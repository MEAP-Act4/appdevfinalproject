import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/protocol/leak_protocol.dart';
import '../data/ble/hm10_transport.dart';
import '../data/ble/leak_transport.dart';
import '../data/ble/simulated_transport.dart';
import '../data/db/app_database.dart';
import '../data/models/aggregates.dart';
import '../data/models/stored_reading.dart';
import '../data/settings/app_settings.dart';
import '../data/settings/settings_controller.dart';

/// The single source of truth for live monitoring state.
///
/// Sits between the transport, the database and the UI:
///   transport lines -> protocol decode -> live state + downsampled persistence
///                   -> aggregate recompute -> event log
class MonitorController extends ChangeNotifier {
  MonitorController({
    required AppDatabase database,
    required this._settings,
  }) : _db = database {
    _settings.addListener(_onSettingsChanged);
  }

  final AppDatabase _db;
  final SettingsController _settings;

  /// Optional append hook, fired once per logged event AFTER the database write
  /// resolves (whether it succeeds or throws). Lets an alerts store keep an
  /// in-memory head-of-list copy in the same frame as the transition without
  /// this controller taking any dependency on it.
  void Function(LeakEvent event)? onEventLogged;

  // --- Transport ------------------------------------------------------------
  LeakTransport? _transport;
  StreamSubscription<String>? _lineSub;
  StreamSubscription<LinkState>? _stateSub;
  StreamSubscription<String>? _diagSub;
  StreamSubscription<List<DiscoveredDevice>>? _discoverySub;

  LinkState _linkState = LinkState.idle;
  List<DiscoveredDevice> _discovered = const <DiscoveredDevice>[];
  String? _lastError;
  bool _usingSimulator = false;

  // --- Live data ------------------------------------------------------------
  Telemetry? _latest;
  DeviceConfig? _deviceConfig;
  final List<BaselineRow> _baselineDraft = <BaselineRow>[];
  List<BaselineRow> _baseline = const <BaselineRow>[];
  CalibrationUpdate? _calibration;

  /// Rolling live window for the realtime sparkline (about 3 minutes at 1 Hz).
  static const int _liveWindowSize = 180;
  final Queue<Telemetry> _liveWindow = Queue<Telemetry>();

  /// Bounded log of raw traffic for the diagnostics sheet.
  static const int _rawLogSize = 200;
  final Queue<String> _rawLog = Queue<String>();

  // --- Persistence ----------------------------------------------------------
  final List<Telemetry> _pendingSamples = <Telemetry>[];
  DateTime? _lastPersistAt;
  Timer? _aggregateTimer;
  Timer? _staleTimer;
  bool _aggregatesInFlight = false;
  AggregateSnapshot _aggregates = AggregateSnapshot.empty();

  // --- Telemetry UI rate limiting -------------------------------------------
  // The board emits ~1 Hz, but a reconnecting or chatty BLE link can deliver a
  // burst of buffered lines at once. Coalesce UI rebuilds to at most one per
  // [_uiThrottle] so a burst cannot thrash the widget tree; the newest sample
  // is always kept and a trailing timer guarantees the last one is painted.
  static const Duration _uiThrottle = Duration(milliseconds: 250);
  DateTime? _lastUiNotifyAt;
  Timer? _trailingNotifyTimer;

  // --- Alarm bookkeeping ----------------------------------------------------
  LeakStatus _lastStatus = LeakStatus.unknown;
  DateTime? _lastTelemetryAt;
  bool _stale = false;
  bool _alarmAcknowledged = false;

  // --- Reconnect ------------------------------------------------------------
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  String? _targetDeviceId;

  // ===========================================================================
  // Exposed state
  // ===========================================================================

  LinkState get linkState => _linkState;
  /// The connection indicator follows the BLE link lifecycle, NOT telemetry
  /// freshness. A brief gap in telemetry (a BLE hiccup, the board pausing) used
  /// to flip this false and back true within a second, so the UI flickered
  /// between connected and disconnected. Staleness is now a separate, softer
  /// signal ([isStale]): the link stays "connected" until the GATT link is
  /// genuinely lost (the transport moves to reconnecting/idle), and a quiet feed
  /// is surfaced as "no fresh data" rather than as a disconnect.
  bool get isConnected => _linkState.grantsAccess;
  bool get usingSimulator => _usingSimulator;
  String? get lastError => _lastError;
  List<DiscoveredDevice> get discovered => _discovered;
  DiscoveredDevice? get connectedDevice => _transport?.connectedDevice;
  String get transportKind => _transport?.kind ?? '—';

  Telemetry? get latest => _latest;
  DeviceConfig? get deviceConfig => _deviceConfig;
  List<BaselineRow> get baseline => _baseline;
  CalibrationUpdate? get calibration => _calibration;
  AggregateSnapshot get aggregates => _aggregates;
  List<Telemetry> get liveWindow => _liveWindow.toList(growable: false);
  List<String> get rawLog => _rawLog.toList(growable: false);

  /// True when the link is up but the board has gone quiet.
  bool get isStale => _stale;

  bool get alarmAcknowledged => _alarmAcknowledged;

  bool _historyOnly = false;

  /// Set when the user deliberately enters without a live link. Only reachable
  /// when the connection gate has been turned off in settings.
  bool get historyOnly => _historyOnly;

  void enterHistoryOnlyMode() {
    _historyOnly = true;
    notifyListeners();
  }

  void leaveHistoryOnlyMode() {
    _historyOnly = false;
    notifyListeners();
  }

  /// The gate's verdict: does the user get the dashboard?
  bool grantsAccess({required bool requireConnection}) {
    if (_linkState.grantsAccess) return true;
    if (!requireConnection && _historyOnly) return true;
    return false;
  }

  LeakStatus get status => _latest?.status ?? LeakStatus.unknown;

  /// Seconds since the last telemetry line, or null if none yet.
  int? get secondsSinceLastSample {
    final at = _lastTelemetryAt;
    if (at == null) return null;
    return DateTime.now().difference(at).inSeconds;
  }

  /// Live flow for one sensor, or 0 before the first sample.
  double flowFor(int sensorIndex) {
    final t = _latest;
    if (t == null) return 0;
    return t.flowLpm[sensorIndex.clamp(0, t.flowLpm.length - 1)];
  }

  double volumeFor(int sensorIndex) {
    final t = _latest;
    if (t == null) return 0;
    return t.volumeL[sensorIndex.clamp(0, t.volumeL.length - 1)];
  }

  /// Recent live values for one sensor, oldest first.
  List<double> liveSeries(int sensorIndex) => _liveWindow
      .map((t) => t.flowLpm[sensorIndex.clamp(0, t.flowLpm.length - 1)])
      .toList(growable: false);

  // ===========================================================================
  // Lifecycle
  // ===========================================================================

  Future<void> initialise() async {
    await _refreshAggregates();
    _aggregateTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshAggregates(),
    );
    _staleTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkStaleness(),
    );

    if (_settings.settings.autoPrune) {
      await _pruneIfNeeded();
    }
  }

  void _onSettingsChanged() {
    // Nothing to recompute eagerly; the UI reads settings directly. Persistence
    // cadence is read per-sample from settings.
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _aggregateTimer?.cancel();
    _staleTimer?.cancel();
    _reconnectTimer?.cancel();
    _trailingNotifyTimer?.cancel();
    _lineSub?.cancel();
    _stateSub?.cancel();
    _diagSub?.cancel();
    _discoverySub?.cancel();
    _transport?.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Transport wiring
  // ===========================================================================

  Future<void> _attach(LeakTransport transport) async {
    await _detach();
    _transport = transport;
    _usingSimulator = transport is SimulatedTransport;

    _stateSub = transport.stateStream.listen((state) {
      _linkState = state;
      if (state == LinkState.reconnecting) {
        _scheduleReconnect();
      }
      if (state == LinkState.idle || state == LinkState.unavailable) {
        _latest = null;
        _stale = false;
      }
      notifyListeners();
    });

    _lineSub = transport.lines.listen(_onLine, onError: (Object error) {
      _lastError = '$error';
      notifyListeners();
    });

    _diagSub = transport.diagnostics.listen((message) {
      _pushRaw('· $message');
      notifyListeners();
    });

    _discoverySub = transport.discoveries.listen((devices) {
      _discovered = devices;
      notifyListeners();
    });

    _linkState = transport.state;
    notifyListeners();
  }

  Future<void> _detach() async {
    await _lineSub?.cancel();
    await _stateSub?.cancel();
    await _diagSub?.cancel();
    await _discoverySub?.cancel();
    _lineSub = null;
    _stateSub = null;
    _diagSub = null;
    _discoverySub = null;
    final old = _transport;
    _transport = null;
    await old?.dispose();
  }

  /// Ensures a real BLE transport exists and starts scanning.
  Future<void> startScan() async {
    _lastError = null;
    if (_transport == null || _usingSimulator) {
      final ble = Hm10Transport()..watchAdapter();
      await _attach(ble);
    }
    try {
      await _transport!.startScan();
    } on TransportFailure catch (failure) {
      _lastError = failure.message;
      notifyListeners();
    } on Object catch (error) {
      _lastError = '$error';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await _transport?.stopScan();
  }

  Future<void> connectTo(DiscoveredDevice device) async {
    _lastError = null;
    _targetDeviceId = device.id;
    _reconnectAttempts = 0;
    try {
      await _transport!.connect(device.id);
      _settings.rememberDevice(device.id, device.displayName);
      await _logEvent(
        EventKind.connected,
        'Connected to ${device.displayName}',
      );
    } on TransportFailure catch (failure) {
      _lastError = failure.message;
      notifyListeners();
    } on Object catch (error) {
      _lastError = '$error';
      notifyListeners();
    }
  }

  /// Reconnects to the remembered device without going through the picker.
  Future<bool> connectToRemembered() async {
    final id = _settings.settings.rememberedDeviceId;
    if (id.isEmpty) return false;
    if (_transport == null || _usingSimulator) {
      final ble = Hm10Transport()..watchAdapter();
      await _attach(ble);
    }
    if (!await _transport!.isSupported()) return false;
    if (!await _transport!.ensurePermissions()) return false;

    _targetDeviceId = id;
    try {
      await _transport!.connect(id);
      return true;
    } on Object catch (error) {
      _lastError = error is TransportFailure ? error.message : '$error';
      notifyListeners();
      return false;
    }
  }

  /// Switches to the in-process simulator. Clearly a demo path, never silent.
  Future<void> startSimulator() async {
    _lastError = null;
    await _attach(SimulatedTransport());
    await _transport!.connect(SimulatedTransport.demoDeviceId);
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _targetDeviceId = null;
    await _flushPending(force: true);
    await _transport?.disconnect();
    await _logEvent(EventKind.disconnected, 'Disconnected by user');
    _latest = null;
    _liveWindow.clear();
    _stale = false;
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (!_settings.settings.autoReconnect) return;
    final id = _targetDeviceId;
    if (id == null || _usingSimulator) return;
    if (_reconnectTimer?.isActive ?? false) return;

    // Exponential backoff capped at 30 s so a board that is genuinely off does
    // not keep the radio busy.
    final delaySeconds = <int>[1, 2, 4, 8, 15, 30];
    final delay = Duration(
      seconds: delaySeconds[_reconnectAttempts.clamp(0, delaySeconds.length - 1)],
    );
    _reconnectAttempts++;

    _pushRaw('· Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, () async {
      if (_linkState.grantsAccess) return;
      try {
        await _transport?.connect(id);
      } on Object catch (error) {
        _pushRaw('· Reconnect failed: $error');
        _scheduleReconnect();
      }
    });
  }

  // ===========================================================================
  // Line handling
  // ===========================================================================

  void _onLine(String line) {
    _pushRaw(line);
    final packet = LeakProtocol.parse(line);
    if (packet == null) return;

    switch (packet) {
      case Telemetry telemetry:
        _onTelemetry(telemetry);
      case DeviceConfig config:
        _deviceConfig = config;
        _markTransportReady();
        if (!config.isCompatible) {
          _lastError =
              'Firmware speaks protocol v${config.protocolVersion}, the app '
              'expects v$kProtocolVersion. Re-flash LeakMonitor.ino.';
        }
        _cacheDevice(config);
        notifyListeners();
      case BaselineRow row:
        _baselineDraft.add(row);
      case BaselineEnd _:
        _baseline = List<BaselineRow>.unmodifiable(_baselineDraft);
        _baselineDraft.clear();
        final id = connectedDevice?.id;
        if (id != null) {
          unawaited(
            _db.replaceBaseline(id, _baseline).catchError((Object _) {}),
          );
        }
        notifyListeners();
      case CalibrationUpdate update:
        _calibration = update;
        if (update.phase == CalibrationPhase.done) {
          unawaited(
            _logEvent(
              EventKind.calibration,
              'Calibrated: bias ${update.meanBalanceLpm.toStringAsFixed(3)} L/min '
              'at ${update.meanInletLpm.toStringAsFixed(2)} L/min over '
              '${update.sampleCount} samples',
            ),
          );
          // Pull the refreshed config so the UI shows the stored bias.
          unawaited(send(LeakCommand.hello));
        } else if (update.phase == CalibrationPhase.failed) {
          _lastError = 'Calibration failed: ${update.reason}';
        }
        notifyListeners();
      case CommandAck ack:
        if (!ack.ok) {
          _lastError = 'Device rejected ${ack.command}: ${ack.detail}';
        }
        notifyListeners();
      case DeviceLog _:
        break;
      case UnknownPacket unknown:
        _pushRaw('! ${unknown.reason}');
    }
  }

  void _markTransportReady() {
    final transport = _transport;
    if (transport is Hm10Transport) {
      transport.markReady();
    } else if (transport is SimulatedTransport) {
      transport.markReady();
    }
  }

  void _onTelemetry(Telemetry telemetry) {
    _markTransportReady();

    _latest = telemetry;
    _lastTelemetryAt = DateTime.now();
    if (_stale) {
      _stale = false;
    }
    _reconnectAttempts = 0;

    _liveWindow.addLast(telemetry);
    while (_liveWindow.length > _liveWindowSize) {
      _liveWindow.removeFirst();
    }

    final statusBefore = _lastStatus;
    _handleStatusTransition(telemetry);
    _accumulate(telemetry);

    // An alarm-relevant status change is painted immediately; routine samples
    // are rate-limited so a burst of buffered lines cannot thrash the UI.
    final statusChanged = telemetry.status != statusBefore;
    if (statusChanged) {
      _notifyNow();
    } else {
      _notifyThrottled();
    }
  }

  /// Emit a UI notification now and reset the throttle window.
  void _notifyNow() {
    _trailingNotifyTimer?.cancel();
    _trailingNotifyTimer = null;
    _lastUiNotifyAt = DateTime.now();
    notifyListeners();
  }

  /// Emit at most one UI notification per [_uiThrottle]. If called again inside
  /// the window, schedule a single trailing notification so the latest sample
  /// is never dropped.
  void _notifyThrottled() {
    final now = DateTime.now();
    final last = _lastUiNotifyAt;
    if (last == null || now.difference(last) >= _uiThrottle) {
      _notifyNow();
      return;
    }
    if (_trailingNotifyTimer?.isActive ?? false) return;
    final wait = _uiThrottle - now.difference(last);
    _trailingNotifyTimer = Timer(wait, _notifyNow);
  }

  void _pushRaw(String line) {
    _rawLog.addLast(line);
    while (_rawLog.length > _rawLogSize) {
      _rawLog.removeFirst();
    }
  }

  // ===========================================================================
  // Alarm transitions
  // ===========================================================================

  void _handleStatusTransition(Telemetry telemetry) {
    final previous = _lastStatus;
    final current = telemetry.status;
    if (previous == current) return;
    _lastStatus = current;

    final settings = _settings.settings;

    switch (current) {
      case LeakStatus.leak:
        _alarmAcknowledged = false;
        unawaited(
          _logEvent(
            EventKind.leakRaised,
            'Leak confirmed — losing '
            '${telemetry.balanceLpm.toStringAsFixed(2)} L/min against a '
            '${telemetry.thresholdLpm.toStringAsFixed(2)} L/min threshold',
            balance: telemetry.balanceLpm,
            threshold: telemetry.thresholdLpm,
          ),
        );
        if (settings.alertOnLeak) _fireAlert(settings, heavy: true);
      case LeakStatus.fault:
        _alarmAcknowledged = false;
        unawaited(
          _logEvent(
            EventKind.faultRaised,
            'Sensor fault — the inlet and outlet readings are inconsistent',
            balance: telemetry.balanceLpm,
            threshold: telemetry.thresholdLpm,
          ),
        );
        if (settings.alertOnFault) _fireAlert(settings, heavy: true);
      case LeakStatus.watch:
        unawaited(
          _logEvent(
            EventKind.watchRaised,
            'Watch — imbalance approaching the alarm threshold',
            balance: telemetry.balanceLpm,
            threshold: telemetry.thresholdLpm,
          ),
        );
        if (settings.alertOnWatch) _fireAlert(settings, heavy: false);
      case LeakStatus.ok:
      case LeakStatus.idle:
        if (previous == LeakStatus.leak) {
          unawaited(
            _logEvent(
              EventKind.leakCleared,
              'Leak cleared — balance back in range',
            ),
          );
        } else if (previous == LeakStatus.fault) {
          unawaited(_logEvent(EventKind.faultCleared, 'Sensor fault cleared'));
        }
        _alarmAcknowledged = false;
      case LeakStatus.calibrating:
      case LeakStatus.unknown:
        break;
    }
  }

  void _fireAlert(AppSettings settings, {required bool heavy}) {
    if (settings.hapticsEnabled) {
      if (heavy) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }
    if (settings.audibleAlarm && heavy) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  void acknowledgeAlarm() {
    _alarmAcknowledged = true;
    notifyListeners();
  }

  /// How long telemetry must be silent before the feed is flagged "quiet".
  /// Deliberately longer than [Hm10Transport.staleAfter] (the transport's own
  /// idea of a gap) so a one- or two-second BLE hiccup never trips it. This only
  /// toggles the soft [isStale] note now — it no longer affects [isConnected] —
  /// so a longer, calmer threshold removes the connected/disconnected flicker.
  static const Duration _staleAfter = Duration(seconds: 12);

  void _checkStaleness() {
    if (!_linkState.grantsAccess) {
      // Not on a live link: clear any lingering stale flag quietly.
      if (_stale) {
        _stale = false;
        notifyListeners();
      }
      return;
    }
    final at = _lastTelemetryAt;
    if (at == null) return;
    final gone = DateTime.now().difference(at);
    final nextStale = gone > _staleAfter;
    if (nextStale != _stale) {
      _stale = nextStale;
      if (_stale) _pushRaw('· Feed quiet — no telemetry for ${gone.inSeconds}s');
      notifyListeners();
    } else if (_stale) {
      // Keep the "seconds since" counter ticking in the UI while quiet.
      notifyListeners();
    }
  }

  // ===========================================================================
  // Persistence
  // ===========================================================================

  /// Buffers samples and flushes one aggregated row per logging interval.
  void _accumulate(Telemetry telemetry) {
    _pendingSamples.add(telemetry);

    final interval = _settings.settings.loggingInterval.duration;
    final last = _lastPersistAt;
    if (last != null && DateTime.now().difference(last) < interval) return;

    unawaited(_flushPending());
  }

  Future<void> _flushPending({bool force = false}) async {
    if (_pendingSamples.isEmpty) return;
    final batch = List<Telemetry>.of(_pendingSamples);
    _pendingSamples.clear();
    _lastPersistAt = DateTime.now();

    final deviceId = connectedDevice?.id ?? 'unknown';
    final row = _condense(batch, deviceId);

    try {
      await _db.insertReading(row);
    } on Object catch (error) {
      _pushRaw('! DB write failed: $error');
      return;
    }

    if (force) await _refreshAggregates();
  }

  /// Collapses N one-second samples into one row: mean flow, last cumulative
  /// volume, worst status. `sampleCount` preserves the weighting.
  StoredReading _condense(List<Telemetry> batch, String deviceId) {
    final n = batch.length;
    final sumFlow = <double>[0, 0, 0];
    var sumBalance = 0.0;
    var sumExpected = 0.0;
    var sumThreshold = 0.0;
    var worst = LeakStatus.idle;

    const severity = <LeakStatus, int>{
      LeakStatus.unknown: 0,
      LeakStatus.idle: 1,
      LeakStatus.ok: 2,
      LeakStatus.calibrating: 3,
      LeakStatus.watch: 4,
      LeakStatus.fault: 5,
      LeakStatus.leak: 6,
    };

    for (final t in batch) {
      for (var i = 0; i < 3; i++) {
        sumFlow[i] += t.flowLpm[i];
      }
      sumBalance += t.balanceLpm;
      sumExpected += t.expectedLpm;
      sumThreshold += t.thresholdLpm;
      if ((severity[t.status] ?? 0) > (severity[worst] ?? 0)) worst = t.status;
    }

    final last = batch.last;
    return StoredReading(
      timestampMs: last.receivedAt.toUtc().millisecondsSinceEpoch,
      deviceId: deviceId,
      seq: last.seq,
      flowLpm: <double>[sumFlow[0] / n, sumFlow[1] / n, sumFlow[2] / n],
      volumeL: List<double>.of(last.volumeL),
      balanceLpm: sumBalance / n,
      expectedLpm: sumExpected / n,
      thresholdLpm: sumThreshold / n,
      status: worst,
      sampleCount: n,
    );
  }

  Future<void> _refreshAggregates() async {
    if (_aggregatesInFlight) return;
    _aggregatesInFlight = true;
    try {
      _aggregates = await _db.computeAggregates();
      notifyListeners();
    } on Object catch (error) {
      _pushRaw('! Aggregate query failed: $error');
    } finally {
      _aggregatesInFlight = false;
    }
  }

  /// Public hook for pull-to-refresh.
  Future<void> refreshAggregates() async {
    await _flushPending();
    await _refreshAggregates();
  }

  Future<void> _pruneIfNeeded() async {
    final retention = _settings.settings.retention.duration;
    if (retention == null) return;
    try {
      final removed = await _db.pruneReadings(retention);
      if (removed > 0) _pushRaw('· Pruned $removed old readings');
    } on Object catch (error) {
      _pushRaw('! Prune failed: $error');
    }
  }

  Future<void> _logEvent(
    EventKind kind,
    String message, {
    double? balance,
    double? threshold,
  }) async {
    final event = LeakEvent(
      timestampMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      kind: kind,
      message: message,
      deviceId: connectedDevice?.id ?? '',
      balanceLpm: balance,
      thresholdLpm: threshold,
    );
    try {
      await _db.insertEvent(event);
    } on Object catch (error) {
      _pushRaw('! Event write failed: $error');
    }
    // Fire the append hook after the write resolves, on both the success and
    // failure paths, so an alerts store always gets the in-memory entry even
    // when persistence fails.
    onEventLogged?.call(event);
  }

  void _cacheDevice(DeviceConfig config) {
    final device = connectedDevice;
    if (device == null) return;
    final future = _db.upsertDevice(
      deviceId: device.id,
      name: device.displayName,
      firmware: config.firmwareVersion,
      configJson: jsonEncode(<String, Object?>{
        'protocol': config.protocolVersion,
        'sampleIntervalMs': config.sampleIntervalMs,
        'pulsesPerLitre': config.pulsesPerLitre,
        'toleranceAbs': config.toleranceAbsLpm,
        'tolerancePct': config.tolerancePct,
        'noiseFloor': config.noiseFloorLpm,
        'faultMinFlow': config.faultMinFlowLpm,
        'leakConfirm': config.leakConfirmSamples,
        'leakClear': config.leakClearSamples,
        'faultConfirm': config.faultConfirmSamples,
        'learnedBias': config.learnedBiasLpm,
      }),
    );
    unawaited(future.catchError((Object _) {}));
  }

  // ===========================================================================
  // Commands
  // ===========================================================================

  Future<bool> send(String command) async {
    final transport = _transport;
    if (transport == null) {
      _lastError = 'Not connected.';
      notifyListeners();
      return false;
    }
    try {
      await transport.send(command);
      _pushRaw('> $command');
      return true;
    } on Object catch (error) {
      _lastError = error is TransportFailure ? error.message : '$error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> setTolerance(double absLpm, double pctFraction) async {
    final ok = await send(LeakCommand.tolerance(absLpm, pctFraction));
    if (ok) {
      await _logEvent(
        EventKind.configChanged,
        'Tolerance set to ${absLpm.toStringAsFixed(2)} L/min / '
        '${(pctFraction * 100).toStringAsFixed(0)}%',
      );
      await send(LeakCommand.hello);
    }
    return ok;
  }

  Future<bool> setNoiseFloor(double lpm) async {
    final ok = await send(LeakCommand.noiseFloor(lpm));
    if (ok) await send(LeakCommand.hello);
    return ok;
  }

  Future<bool> setDebounce(int confirm, int clear, int faultConfirm) async {
    final ok = await send(LeakCommand.debounce(confirm, clear, faultConfirm));
    if (ok) await send(LeakCommand.hello);
    return ok;
  }

  Future<bool> setPulsesPerLitre(int sensorIndex, double ppl) async {
    final ok = await send(LeakCommand.pulsesPerLitre(sensorIndex, ppl));
    if (ok) await send(LeakCommand.hello);
    return ok;
  }

  Future<bool> startCalibration({int seconds = 30}) async {
    _calibration = null;
    return send(LeakCommand.calibrate(seconds));
  }

  Future<bool> cancelCalibration() => send(LeakCommand.cancel);

  Future<bool> zeroTotals() => send(LeakCommand.zeroTotals);

  Future<bool> restoreDeviceDefaults() async {
    final ok = await send(LeakCommand.restoreDefaults);
    if (ok) {
      await _logEvent(EventKind.configChanged, 'Device restored to defaults');
    }
    return ok;
  }

  Future<bool> rebootDevice() => send(LeakCommand.reboot);

  Future<bool> pingDevice() => send(LeakCommand.ping);

  // ===========================================================================
  // Data management (exposed to the settings tab)
  // ===========================================================================

  Future<String> exportCsv({Duration? window}) =>
      _db.exportCsv(window: window);

  Future<List<LeakEvent>> recentEvents({int limit = 100}) =>
      _db.events(limit: limit);

  Future<int> readingCount() => _db.countReadings();

  Future<int> databaseSizeBytes() => _db.estimatedSizeBytes();

  Future<void> clearHistory() async {
    _pendingSamples.clear();
    await _db.clearReadings();
    await _db.clearEvents();
    await _db.vacuum();
    await _refreshAggregates();
  }

  Future<int> pruneNow() async {
    final retention = _settings.settings.retention.duration;
    if (retention == null) return 0;
    final removed = await _db.pruneReadings(retention);
    await _refreshAggregates();
    return removed;
  }

  /// Drives the simulator from the diagnostics sheet.
  void forceSimulatorScenario(String scenario) {
    final transport = _transport;
    if (transport is SimulatedTransport) transport.forceScenario(scenario);
  }
}

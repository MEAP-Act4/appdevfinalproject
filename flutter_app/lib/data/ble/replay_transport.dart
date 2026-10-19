import 'dart:async';

import 'leak_evaluator.dart';
import 'leak_transport.dart';

/// Playback speed for a replay session.
///
/// A month of 1 Hz data is ~2.6M samples, so real-time playback is impractical
/// for a demo. Compressed speeds emit many recorded samples per wall-clock
/// second while the detection logic still runs on every one, so a developing
/// leak over a week still crosses the debounce threshold and alarms, just in
/// minutes instead of days.
enum ReplaySpeed {
  realtime('Real-time (1×)', 1),
  fast('Fast (60×)', 60),
  veryFast('Very fast (600×)', 600),
  ultra('Ultra (3600×)', 3600);

  const ReplaySpeed(this.label, this.factor);

  /// Human label for the picker.
  final String label;

  /// How many recorded seconds advance per real second.
  final int factor;
}

/// A single parsed recording sample: a timestamp and the three raw sensor
/// flows. Everything else in the CSV (recorded status/balance/volume) is
/// intentionally ignored — replay recomputes the verdict from the flows.
class _ReplayRow {
  const _ReplayRow(this.tMs, this.inlet, this.outA, this.outB);
  final int tMs;
  final double inlet;
  final double outA;
  final double outB;
}

/// Feeds a real recorded dataset through the live detection pipeline.
///
/// Implements [LeakTransport] so the whole app above the transport layer runs
/// unchanged — the dashboard, alarms, chart and database all behave exactly as
/// they do on a live BLE link. The crucial difference from a dumb replay: only
/// the raw per-sensor flows are taken from the recording; the balance, the
/// envelope and the `IDLE/OK/WATCH/LEAK/FAULT` verdict are computed here by
/// [LeakEvaluator], the same logic the firmware runs. So the app is genuinely
/// *detecting* the leak on real data, not echoing a stored label.
class ReplayTransport implements LeakTransport {
  ReplayTransport({
    required String csv,
    this.speed = ReplaySpeed.fast,
    String? label,
  })  : _rows = _parseCsv(csv),
        _label = label ?? 'Recorded dataset';

  final ReplaySpeed speed;
  final String _label;
  final List<_ReplayRow> _rows;
  final LeakEvaluator _evaluator = LeakEvaluator();

  final StreamController<LinkState> _stateController =
      StreamController<LinkState>.broadcast();
  final StreamController<String> _lineController =
      StreamController<String>.broadcast();
  final StreamController<String> _diagnosticsController =
      StreamController<String>.broadcast();
  final StreamController<List<DiscoveredDevice>> _discoveryController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  static const String replayDeviceId = 'REPLAY:DATASET';

  Timer? _ticker;
  LinkState _state = LinkState.idle;
  DiscoveredDevice? _connected;
  bool _disposed = false;

  int _cursor = 0;
  int _seq = 0;
  int _uptimeMs = 0;
  final List<double> _volume = <double>[0, 0, 0];

  /// Number of samples parsed from the recording.
  int get sampleCount => _rows.length;

  @override
  String get kind => 'Replay';

  @override
  LinkState get state => _state;

  @override
  Stream<LinkState> get stateStream => _stateController.stream;

  @override
  Stream<String> get lines => _lineController.stream;

  @override
  Stream<String> get diagnostics => _diagnosticsController.stream;

  @override
  Stream<List<DiscoveredDevice>> get discoveries => _discoveryController.stream;

  @override
  DiscoveredDevice? get connectedDevice => _connected;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> ensurePermissions() async => true;

  void _setState(LinkState next) {
    if (_disposed || _state == next) return;
    _state = next;
    _stateController.add(next);
  }

  void _emit(String line) {
    if (!_disposed) _lineController.add(line);
  }

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 12)}) async {
    _setState(LinkState.scanning);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_disposed) return;
    _discoveryController.add(<DiscoveredDevice>[_device()]);
    _setState(LinkState.idle);
  }

  DiscoveredDevice _device() => DiscoveredDevice(
        id: replayDeviceId,
        name: _label,
        rssi: -40,
        advertisesLeakService: true,
      );

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId) async {
    if (_rows.isEmpty) {
      _setState(LinkState.failed);
      throw const TransportFailure(
        'The recording has no usable rows. Export a CSV from the app or check '
        'the file has the inlet/outlet flow columns.',
      );
    }

    _setState(LinkState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _connected = _device();
    _setState(LinkState.handshaking);

    _diagnosticsController.add(
      'Replaying $_label — ${_rows.length} recorded samples at ${speed.label}.',
    );
    _emit('L,LeakGuard replay boot');
    _sendHandshake();
    _sendBaseline();

    _cursor = 0;
    _seq = 0;
    _uptimeMs = 0;
    _volume.setAll(0, <double>[0, 0, 0]);
    _evaluator.reset();

    // Emit one wall-clock tick per second; each tick advances the recording by
    // `speed.factor` samples so compressed speeds still evaluate every sample.
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _sendHandshake() {
    _emit(
      'H,2.0.0-replay,2,3,1000,450.0,450.0,450.0,'
      '${LeakEvaluator.toleranceAbs.toStringAsFixed(3)},'
      '${LeakEvaluator.tolerancePct.toStringAsFixed(4)},'
      '${LeakEvaluator.noiseFloor.toStringAsFixed(3)},'
      '${LeakEvaluator.faultMinFlow.toStringAsFixed(3)},'
      '${LeakEvaluator.leakConfirm},${LeakEvaluator.leakClear},'
      '${LeakEvaluator.faultConfirm},0.0000',
    );
  }

  void _sendBaseline() {
    final rows = LeakEvaluator.defaultBaseline;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      _emit(
        'B,$i,${r[0].toStringAsFixed(2)},'
        '${r[1].toStringAsFixed(3)},${r[2].toStringAsFixed(3)}',
      );
    }
    _emit('B,END,${rows.length}');
  }

  void _tick() {
    if (_disposed) return;

    // Advance `speed.factor` recorded samples, evaluating each so the debounce
    // and hysteresis see every sample, then emit telemetry for the last one.
    final step = speed.factor;
    EvaluatorSample? last;
    int processed = 0;
    for (var i = 0; i < step && _cursor < _rows.length; i++, _cursor++) {
      final row = _rows[_cursor];
      last = _evaluator.evaluate(<double>[row.inlet, row.outA, row.outB]);
      for (var s = 0; s < 3; s++) {
        _volume[s] += last.flow[s] / 60.0;
      }
      _seq++;
      _uptimeMs += 1000;
      processed++;
    }

    if (last != null) {
      _emit(
        'D,$_seq,$_uptimeMs,'
        '${last.flow[0].toStringAsFixed(2)},${last.flow[1].toStringAsFixed(2)},'
        '${last.flow[2].toStringAsFixed(2)},'
        '${_volume[0].toStringAsFixed(3)},${_volume[1].toStringAsFixed(3)},'
        '${_volume[2].toStringAsFixed(3)},'
        '${last.balance.toStringAsFixed(3)},${last.expected.toStringAsFixed(3)},'
        '${last.threshold.toStringAsFixed(3)},${last.status},'
        '${last.breachStreak},${last.faultStreak}',
      );
    }

    if (_cursor >= _rows.length) {
      _ticker?.cancel();
      _ticker = null;
      _diagnosticsController.add(
        'Replay complete — reached the end of the recording '
        '($_seq samples processed).',
      );
    } else if (processed == 0) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Future<void> send(String command) async {
    // Replay is a one-way playback; acknowledge commands so the UI stays happy
    // but do not alter the recording.
    final verb = command.trim().toUpperCase().split(',').first;
    switch (verb) {
      case 'PING':
        _emit('A,PING,OK,PONG');
      case 'HELLO':
      case 'CFG?':
        _sendHandshake();
      case 'BASE?':
        _sendBaseline();
      default:
        _emit('A,$verb,OK,replay');
    }
  }

  void markReady() {
    if (_state != LinkState.ready) _setState(LinkState.ready);
  }

  @override
  Future<void> disconnect() async {
    _ticker?.cancel();
    _ticker = null;
    _connected = null;
    _setState(LinkState.idle);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _ticker?.cancel();
    await _stateController.close();
    await _lineController.close();
    await _diagnosticsController.close();
    await _discoveryController.close();
  }

  // ---------------------------------------------------------------------------
  // CSV parsing
  // ---------------------------------------------------------------------------

  /// Parses the app's exported CSV (see `AppDatabase.exportCsv`). Reads the
  /// timestamp and the three `*_lpm` flow columns by header name, so column
  /// order changes do not break it. Rows that do not parse are skipped.
  static List<_ReplayRow> _parseCsv(String csv) {
    final lines = csv
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return const <_ReplayRow>[];

    final header = lines.first.split(',').map((h) => h.trim().toLowerCase()).toList();
    int col(String name, int fallback) {
      final i = header.indexOf(name);
      return i >= 0 ? i : fallback;
    }

    // Default to the known export column positions if the header is absent.
    final tsCol = col('timestamp_utc', 0);
    final inletCol = col('inlet_lpm', 3);
    final outACol = col('outlet_a_lpm', 4);
    final outBCol = col('outlet_b_lpm', 5);

    // If the first line is not a header (no known column names), treat it as
    // data too by falling back to positional parsing.
    final hasHeader = header.contains('inlet_lpm') ||
        header.contains('timestamp_utc');
    final dataLines = hasHeader ? lines.skip(1) : lines;

    final rows = <_ReplayRow>[];
    for (final line in dataLines) {
      final parts = line.split(',');
      final maxCol = <int>[tsCol, inletCol, outACol, outBCol]
          .reduce((a, b) => a > b ? a : b);
      if (parts.length <= maxCol) continue;

      final inlet = double.tryParse(parts[inletCol].trim());
      final outA = double.tryParse(parts[outACol].trim());
      final outB = double.tryParse(parts[outBCol].trim());
      if (inlet == null || outA == null || outB == null) continue;

      final tMs = _parseTimestamp(parts[tsCol].trim());
      rows.add(_ReplayRow(tMs, inlet, outA, outB));
    }
    return rows;
  }

  static int _parseTimestamp(String raw) {
    // Accept an ISO-8601 string (what the export writes) or a raw epoch-ms int.
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    final dt = DateTime.tryParse(raw);
    return dt?.millisecondsSinceEpoch ?? 0;
  }
}

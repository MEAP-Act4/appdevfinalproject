import 'dart:async';
import 'dart:math' as math;

import 'leak_transport.dart';

/// In-process stand-in for the HM-10 link.
///
/// It re-implements the firmware's decision logic (noise floor, interpolated
/// tolerance envelope, debounce, hysteresis) and emits the same v2 protocol
/// lines, so the whole app above the transport layer is exercised identically
/// with or without hardware. Used for the "Demo data" path on the connection
/// gate and for UI work on a desk with no rig attached.
class SimulatedTransport implements LeakTransport {
  SimulatedTransport({math.Random? random})
      : _random = random ?? math.Random(20260929);

  final math.Random _random;

  final StreamController<LinkState> _stateController =
      StreamController<LinkState>.broadcast();
  final StreamController<String> _lineController =
      StreamController<String>.broadcast();
  final StreamController<String> _diagnosticsController =
      StreamController<String>.broadcast();
  final StreamController<List<DiscoveredDevice>> _discoveryController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  /// Stable id so the controller can "connect" without a scan.
  static const String demoDeviceId = 'SIM:LEAKGUARD-DEMO';

  static const DiscoveredDevice _fakeDevice = DiscoveredDevice(
    id: demoDeviceId,
    name: 'LeakGuard Simulator',
    rssi: -48,
    advertisesLeakService: true,
  );

  // Mirrors of the firmware defaults.
  static const List<List<double>> _baseline = <List<double>>[
    <double>[0.00, 0.00, 0.20],
    <double>[0.50, 0.05, 0.25],
    <double>[1.00, 0.08, 0.30],
    <double>[2.00, 0.12, 0.38],
    <double>[4.00, 0.20, 0.55],
    <double>[8.00, 0.35, 0.95],
    <double>[15.00, 0.60, 1.60],
    <double>[30.00, 1.10, 3.00],
  ];

  static const double _noiseFloor = 0.12;
  static const double _toleranceAbs = 0.20;
  static const double _tolerancePct = 0.08;
  static const double _faultMinFlow = 0.50;
  static const int _leakConfirm = 8;
  static const int _leakClear = 5;
  static const int _faultConfirm = 10;

  Timer? _ticker;
  LinkState _state = LinkState.idle;
  DiscoveredDevice? _connected;
  bool _disposed = false;

  int _seq = 0;
  int _uptimeMs = 0;
  final List<double> _volume = <double>[0, 0, 0];
  int _breachStreak = 0;
  int _cleanStreak = 0;
  int _faultStreak = 0;
  String _status = 'IDLE';

  // Scenario driver.
  _Scenario _scenario = _Scenario.idle;
  int _scenarioTicks = 0;
  double _leakSeverity = 0;

  @override
  String get kind => 'Simulator';

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
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_disposed) return;
    _discoveryController.add(<DiscoveredDevice>[_fakeDevice]);
    _setState(LinkState.idle);
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId) async {
    _setState(LinkState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _connected = _fakeDevice;
    _setState(LinkState.handshaking);

    _diagnosticsController.add('Simulator attached — no hardware in use.');
    _emit('L,LeakGuard simulator boot');
    _sendHandshake();

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void markReady() {
    if (_state != LinkState.ready) _setState(LinkState.ready);
  }

  void _sendHandshake() {
    _emit(
      'H,2.0.0-sim,2,3,1000,450.0,450.0,450.0,'
      '${_toleranceAbs.toStringAsFixed(3)},'
      '${_tolerancePct.toStringAsFixed(4)},'
      '${_noiseFloor.toStringAsFixed(3)},'
      '${_faultMinFlow.toStringAsFixed(3)},'
      '$_leakConfirm,$_leakClear,$_faultConfirm,0.0000',
    );
  }

  void _sendBaseline() {
    for (var i = 0; i < _baseline.length; i++) {
      final row = _baseline[i];
      _emit(
        'B,$i,${row[0].toStringAsFixed(2)},'
        '${row[1].toStringAsFixed(3)},${row[2].toStringAsFixed(3)}',
      );
    }
    _emit('B,END,${_baseline.length}');
  }

  @override
  Future<void> send(String command) async {
    final verb = command.trim().toUpperCase().split(',').first;
    switch (verb) {
      case 'PING':
        _emit('A,PING,OK,PONG');
      case 'HELLO':
      case 'CFG?':
        _sendHandshake();
      case 'BASE?':
        _sendBaseline();
      case 'ZERO':
        _volume.setAll(0, <double>[0, 0, 0]);
        _emit('A,ZERO,OK,totals cleared');
      case 'CAL':
        _emit('A,CAL,OK,started');
        _runFakeCalibration();
      case 'CANCEL':
        _emit('A,CANCEL,OK,aborted');
      default:
        _emit('A,$verb,OK,simulated');
    }
  }

  void _runFakeCalibration() {
    _status = 'CAL';
    var remaining = 12;
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      remaining--;
      _emit('C,RUN,$remaining,${12 - remaining},0.0412');
      if (remaining <= 0) {
        timer.cancel();
        _emit('C,DONE,0.0396,2.140,11');
        _status = 'IDLE';
      }
    });
  }

  /// Walks a small state machine so the demo shows every UI state in a couple of
  /// minutes: idle -> normal draw -> heavy draw -> slow leak -> recovery -> fault.
  void _advanceScenario() {
    _scenarioTicks--;
    if (_scenarioTicks > 0) return;

    _scenario = switch (_scenario) {
      _Scenario.idle => _Scenario.normalDraw,
      _Scenario.normalDraw => _Scenario.heavyDraw,
      _Scenario.heavyDraw => _Scenario.singleBranch,
      _Scenario.singleBranch => _Scenario.slowLeak,
      _Scenario.slowLeak => _Scenario.idle,
      _Scenario.sensorFault => _Scenario.idle,
    };

    _scenarioTicks = switch (_scenario) {
      _Scenario.idle => 20,
      _Scenario.normalDraw => 35,
      _Scenario.heavyDraw => 20,
      _Scenario.singleBranch => 25,
      _Scenario.slowLeak => 45,
      _Scenario.sensorFault => 18,
    };

    if (_scenario == _Scenario.slowLeak) {
      _leakSeverity = 0.6 + _random.nextDouble() * 1.4;
    }
  }

  double _noise(double magnitude) => (_random.nextDouble() - 0.5) * magnitude;

  void _tick() {
    if (_disposed) return;
    _advanceScenario();

    // Initialised up front rather than relying on switch exhaustiveness for
    // definite assignment.
    double inlet = 0;
    double outA = 0;
    double outB = 0;

    switch (_scenario) {
      case _Scenario.idle:
        inlet = 0;
        outA = 0;
        outB = 0;
      case _Scenario.normalDraw:
        inlet = 2.2 + _noise(0.3);
        outA = inlet * 0.52 + _noise(0.16);
        outB = inlet - outA + _noise(0.16);
      case _Scenario.heavyDraw:
        inlet = 7.6 + _noise(0.8);
        outA = inlet * 0.48 + _noise(0.3);
        outB = inlet - outA + _noise(0.3);
      case _Scenario.singleBranch:
        // Only branch A is open. The old firmware called this a disconnect; the
        // new logic must report OK.
        inlet = 1.6 + _noise(0.24);
        outA = inlet + _noise(0.2);
        outB = 0;
      case _Scenario.slowLeak:
        inlet = 3.4 + _noise(0.3);
        final missing = _leakSeverity;
        outA = (inlet - missing) * 0.5 + _noise(0.16);
        outB = (inlet - missing) * 0.5 + _noise(0.16);
      case _Scenario.sensorFault:
        inlet = 3.0 + _noise(0.3);
        outA = 0;
        outB = 0;
    }

    final flow = <double>[
      _applyNoiseFloor(math.max(0, inlet)),
      _applyNoiseFloor(math.max(0, outA)),
      _applyNoiseFloor(math.max(0, outB)),
    ];

    for (var i = 0; i < 3; i++) {
      _volume[i] += flow[i] / 60.0;
    }

    final totalOut = flow[1] + flow[2];
    final balance = flow[0] - totalOut;
    final env = _envelope(flow[0]);
    final expected = env.$1;
    final threshold = env.$2;

    _evaluate(flow, totalOut, balance, threshold);

    _seq++;
    _uptimeMs += 1000;

    _emit(
      'D,$_seq,$_uptimeMs,'
      '${flow[0].toStringAsFixed(2)},${flow[1].toStringAsFixed(2)},'
      '${flow[2].toStringAsFixed(2)},'
      '${_volume[0].toStringAsFixed(3)},${_volume[1].toStringAsFixed(3)},'
      '${_volume[2].toStringAsFixed(3)},'
      '${balance.toStringAsFixed(3)},${expected.toStringAsFixed(3)},'
      '${threshold.toStringAsFixed(3)},$_status,$_breachStreak,$_faultStreak',
    );
  }

  static double _applyNoiseFloor(double v) => v < _noiseFloor ? 0 : v;

  /// Returns (expected, threshold) for a given inlet flow — same interpolation
  /// as `baselineEnvelope()` in the firmware.
  (double, double) _envelope(double inlet) {
    double expected;
    double margin;

    if (inlet <= _baseline.first[0]) {
      expected = _baseline.first[1];
      margin = _baseline.first[2];
    } else if (inlet >= _baseline.last[0]) {
      expected = _baseline.last[1];
      margin = _baseline.last[2];
    } else {
      expected = _baseline.last[1];
      margin = _baseline.last[2];
      for (var i = 1; i < _baseline.length; i++) {
        if (inlet <= _baseline[i][0]) {
          final lo = _baseline[i - 1];
          final hi = _baseline[i];
          final span = hi[0] - lo[0];
          final t = span > 0 ? (inlet - lo[0]) / span : 0.0;
          expected = lo[1] + t * (hi[1] - lo[1]);
          margin = lo[2] + t * (hi[2] - lo[2]);
          break;
        }
      }
    }

    var threshold = expected + margin;
    final pctBand = inlet * _tolerancePct;
    if (_toleranceAbs > threshold) threshold = _toleranceAbs;
    if (pctBand > threshold) threshold = pctBand;
    return (expected, threshold);
  }

  void _evaluate(
    List<double> flow,
    double totalOut,
    double balance,
    double threshold,
  ) {
    if (_status == 'CAL') return;

    // Rule 0 — nothing detected.
    if (flow[0] == 0 && flow[1] == 0 && flow[2] == 0) {
      _breachStreak = 0;
      _cleanStreak = 0;
      _faultStreak = 0;
      _status = 'IDLE';
      return;
    }

    // Rule 1 — implausible topology.
    final shapeA = flow[0] >= _faultMinFlow && flow[1] == 0 && flow[2] == 0;
    final shapeB = totalOut >= _faultMinFlow && flow[0] == 0;
    if (shapeA || shapeB) {
      _faultStreak++;
      if (_faultStreak >= _faultConfirm) {
        _status = 'FAULT';
        _breachStreak = 0;
        _cleanStreak = 0;
        return;
      }
      if (_status != 'LEAK') _status = 'WATCH';
      return;
    }
    _faultStreak = 0;

    // Rule 2 — envelope.
    final absBal = balance.abs();
    if (balance > 0 && absBal > threshold) {
      _cleanStreak = 0;
      _breachStreak++;
      _status = _breachStreak >= _leakConfirm
          ? 'LEAK'
          : (_status == 'LEAK' ? 'LEAK' : 'WATCH');
      return;
    }
    if (balance < 0 && absBal > threshold) {
      _breachStreak = 0;
      _cleanStreak = 0;
      if (_status != 'LEAK') _status = 'WATCH';
      return;
    }

    // Rule 3 — inside the envelope, clear with hysteresis.
    _breachStreak = 0;
    _cleanStreak++;
    if (_status == 'LEAK' || _status == 'FAULT') {
      if (_cleanStreak >= _leakClear) _status = 'OK';
    } else {
      _status = 'OK';
    }
  }

  /// Lets the UI force a scenario, used by the diagnostics screen.
  void forceScenario(String name) {
    _scenario = switch (name.toLowerCase()) {
      'idle' => _Scenario.idle,
      'normal' => _Scenario.normalDraw,
      'heavy' => _Scenario.heavyDraw,
      'branch' => _Scenario.singleBranch,
      'leak' => _Scenario.slowLeak,
      'fault' => _Scenario.sensorFault,
      _ => _scenario,
    };
    _scenarioTicks = 30;
    if (_scenario == _Scenario.slowLeak) _leakSeverity = 1.4;
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
}

enum _Scenario {
  idle,
  normalDraw,
  heavyDraw,
  singleBranch,
  slowLeak,
  sensorFault,
}

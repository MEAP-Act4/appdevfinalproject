import 'dart:math' as math;

/// Shared, firmware-mirrored leak-detection logic.
///
/// This is the exact decision pipeline the Arduino firmware runs
/// (`firmware/LeakMonitor/LeakMonitor.ino`): a noise floor, an interpolated
/// tolerance envelope from the standardized baseline table, and debounce +
/// hysteresis over consecutive samples. Pulling it into one place lets both the
/// built-in [SimulatedTransport] (synthetic scenarios) and the [ReplayTransport]
/// (real recorded flows) compute the *same* verdict the hardware would, rather
/// than each re-implementing it or replaying a pre-recorded status.
///
/// The replay path depends on this: it reads only the raw per-sensor flows from
/// a recording and runs them through [LeakEvaluator.evaluate], so the app is
/// genuinely *detecting* the leak on real data, not echoing a stored label.
class LeakEvaluator {
  /// Default firmware baseline: rows of `[inletLpm, expectedBalance, margin]`,
  /// ascending by inlet. Mirrors `BASELINE_TABLE` in the firmware.
  static const List<List<double>> defaultBaseline = <List<double>>[
    <double>[0.00, 0.00, 0.20],
    <double>[0.50, 0.05, 0.25],
    <double>[1.00, 0.08, 0.30],
    <double>[2.00, 0.12, 0.38],
    <double>[4.00, 0.20, 0.55],
    <double>[8.00, 0.35, 0.95],
    <double>[15.00, 0.60, 1.60],
    <double>[30.00, 1.10, 3.00],
  ];

  static const double noiseFloor = 0.12;
  static const double toleranceAbs = 0.20;
  static const double tolerancePct = 0.08;
  static const double faultMinFlow = 0.50;
  static const int leakConfirm = 8;
  static const int leakClear = 5;
  static const int faultConfirm = 10;

  final List<List<double>> baseline;

  int _breachStreak = 0;
  int _cleanStreak = 0;
  int _faultStreak = 0;
  String _status = 'IDLE';

  LeakEvaluator({List<List<double>>? baseline})
      : baseline = baseline ?? defaultBaseline;

  int get breachStreak => _breachStreak;
  int get faultStreak => _faultStreak;
  String get status => _status;

  /// Resets the streak/hysteresis state (e.g. when a new recording starts).
  void reset() {
    _breachStreak = 0;
    _cleanStreak = 0;
    _faultStreak = 0;
    _status = 'IDLE';
  }

  /// Applies the noise floor exactly as the firmware does: anything under it is
  /// reported as a hard zero so quantisation chatter cannot raise an alarm.
  static double applyNoiseFloor(double v) => v < noiseFloor ? 0 : v;

  /// Interpolated `(expected, threshold)` for a given inlet flow — the same
  /// interpolation as `baselineEnvelope()` in the firmware.
  (double expected, double threshold) envelope(double inlet) {
    double expected;
    double margin;

    final first = baseline.first;
    final last = baseline.last;

    if (inlet <= first[0]) {
      expected = first[1];
      margin = first[2];
    } else if (inlet >= last[0]) {
      expected = last[1];
      margin = last[2];
    } else {
      expected = last[1];
      margin = last[2];
      for (var i = 1; i < baseline.length; i++) {
        if (inlet <= baseline[i][0]) {
          final lo = baseline[i - 1];
          final hi = baseline[i];
          final span = hi[0] - lo[0];
          final t = span > 0 ? (inlet - lo[0]) / span : 0.0;
          expected = lo[1] + t * (hi[1] - lo[1]);
          margin = lo[2] + t * (hi[2] - lo[2]);
          break;
        }
      }
    }

    var threshold = expected + margin;
    final pctBand = inlet * tolerancePct;
    if (toleranceAbs > threshold) threshold = toleranceAbs;
    if (pctBand > threshold) threshold = pctBand;
    return (expected, threshold);
  }

  /// One conditioned sample result.
  ///
  /// [flow] is the three noise-floored sensor flows. [balance], [expected] and
  /// [threshold] are the derived figures, and [status] is the debounced verdict
  /// (`IDLE/OK/WATCH/LEAK/FAULT`). Streaks reflect the running debounce state.
  EvaluatorSample evaluate(List<double> rawFlow, {bool calibrating = false}) {
    final flow = <double>[
      applyNoiseFloor(math.max(0, rawFlow[0])),
      applyNoiseFloor(math.max(0, rawFlow[1])),
      applyNoiseFloor(math.max(0, rawFlow[2])),
    ];

    final totalOut = flow[1] + flow[2];
    final balance = flow[0] - totalOut;
    final env = envelope(flow[0]);
    final expected = env.$1;
    final threshold = env.$2;

    if (calibrating) {
      _status = 'CAL';
      return EvaluatorSample(flow, balance, expected, threshold, _status,
          _breachStreak, _faultStreak);
    }

    // Rule 0 — nothing detected.
    if (flow[0] == 0 && flow[1] == 0 && flow[2] == 0) {
      _breachStreak = 0;
      _cleanStreak = 0;
      _faultStreak = 0;
      _status = 'IDLE';
      return EvaluatorSample(flow, balance, expected, threshold, _status,
          _breachStreak, _faultStreak);
    }

    // Rule 1 — implausible topology.
    final shapeA = flow[0] >= faultMinFlow && flow[1] == 0 && flow[2] == 0;
    final shapeB = totalOut >= faultMinFlow && flow[0] == 0;
    if (shapeA || shapeB) {
      _faultStreak++;
      if (_faultStreak >= faultConfirm) {
        _status = 'FAULT';
        _breachStreak = 0;
        _cleanStreak = 0;
      } else if (_status != 'LEAK') {
        _status = 'WATCH';
      }
      return EvaluatorSample(flow, balance, expected, threshold, _status,
          _breachStreak, _faultStreak);
    }
    _faultStreak = 0;

    // Rule 2 — envelope.
    final absBal = balance.abs();
    if (balance > 0 && absBal > threshold) {
      _cleanStreak = 0;
      _breachStreak++;
      _status = _breachStreak >= leakConfirm
          ? 'LEAK'
          : (_status == 'LEAK' ? 'LEAK' : 'WATCH');
      return EvaluatorSample(flow, balance, expected, threshold, _status,
          _breachStreak, _faultStreak);
    }
    if (balance < 0 && absBal > threshold) {
      _breachStreak = 0;
      _cleanStreak = 0;
      if (_status != 'LEAK') _status = 'WATCH';
      return EvaluatorSample(flow, balance, expected, threshold, _status,
          _breachStreak, _faultStreak);
    }

    // Rule 3 — inside the envelope, clear with hysteresis.
    _breachStreak = 0;
    _cleanStreak++;
    if (_status == 'LEAK' || _status == 'FAULT') {
      if (_cleanStreak >= leakClear) _status = 'OK';
    } else {
      _status = 'OK';
    }
    return EvaluatorSample(flow, balance, expected, threshold, _status,
        _breachStreak, _faultStreak);
  }
}

/// The result of one [LeakEvaluator.evaluate] call.
class EvaluatorSample {
  const EvaluatorSample(
    this.flow,
    this.balance,
    this.expected,
    this.threshold,
    this.status,
    this.breachStreak,
    this.faultStreak,
  );

  /// The three noise-floored sensor flows, L/min.
  final List<double> flow;
  final double balance;
  final double expected;
  final double threshold;
  final String status;
  final int breachStreak;
  final int faultStreak;
}

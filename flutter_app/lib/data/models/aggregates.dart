/// The three averaging windows the sensor tab shows under every live reading.
enum AverageWindow {
  day('Per day', '24 h', Duration(days: 1)),
  threeDay('Per 3 days', '72 h', Duration(days: 3)),
  week('Per week', '7 d', Duration(days: 7));

  const AverageWindow(this.label, this.shortLabel, this.duration);

  final String label;
  final String shortLabel;
  final Duration duration;
}

/// Statistics for one sensor over one window, all in canonical units
/// (L/min for rates, litres for volume).
class WindowStats {
  const WindowStats({
    required this.window,
    required this.averageLpm,
    required this.peakLpm,
    required this.totalLitres,
    required this.sampleCount,
    required this.coverage,
    required this.activeFraction,
  });

  const WindowStats.empty(this.window)
      : averageLpm = 0,
        peakLpm = 0,
        totalLitres = 0,
        sampleCount = 0,
        coverage = 0,
        activeFraction = 0;

  final AverageWindow window;

  /// Mean flow across the whole window, including idle time. This is the number
  /// that answers "how much does this branch use per day on average".
  final double averageLpm;

  final double peakLpm;

  /// Integrated volume over the window.
  final double totalLitres;

  /// How many device samples the window is built from.
  final int sampleCount;

  /// 0..1 — what proportion of the window actually has data. Low coverage means
  /// the average is not yet trustworthy, and the UI says so.
  final double coverage;

  /// 0..1 — proportion of samples where this sensor was flowing.
  final double activeFraction;

  bool get hasData => sampleCount > 0;

  /// Below this the UI labels the figure as "building up".
  bool get isReliable => coverage >= 0.25;

  /// Mean flow while actually flowing, which is the more useful figure for a tap
  /// that runs a few minutes a day.
  double get averageWhileActiveLpm =>
      activeFraction <= 0 ? 0 : averageLpm / activeFraction;
}

/// All three windows for one sensor.
class SensorAggregates {
  const SensorAggregates({
    required this.sensorIndex,
    required this.day,
    required this.threeDay,
    required this.week,
  });

  SensorAggregates.empty(this.sensorIndex)
      : day = const WindowStats.empty(AverageWindow.day),
        threeDay = const WindowStats.empty(AverageWindow.threeDay),
        week = const WindowStats.empty(AverageWindow.week);

  final int sensorIndex;
  final WindowStats day;
  final WindowStats threeDay;
  final WindowStats week;

  WindowStats forWindow(AverageWindow w) => switch (w) {
        AverageWindow.day => day,
        AverageWindow.threeDay => threeDay,
        AverageWindow.week => week,
      };

  List<WindowStats> get all => <WindowStats>[day, threeDay, week];

  /// Week-over-day drift. Positive means recent usage is above the weekly norm,
  /// which is a soft signal for a slow developing leak.
  double get trendRatio {
    if (week.averageLpm <= 0.0001) return 0;
    return (day.averageLpm / week.averageLpm) - 1.0;
  }
}

/// One point on the history sparkline.
class TrendPoint {
  const TrendPoint({
    required this.timestampMs,
    required this.valueLpm,
    this.alarm = false,
  });

  final int timestampMs;
  final double valueLpm;
  final bool alarm;

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true).toLocal();
}

/// Rolled-up snapshot for all sensors, recomputed on a timer rather than on
/// every 1 Hz sample.
class AggregateSnapshot {
  const AggregateSnapshot({
    required this.perSensor,
    required this.trends,
    required this.computedAt,
    required this.totalRows,
    required this.oldestTimestampMs,
  });

  AggregateSnapshot.empty()
      : perSensor = List<SensorAggregates>.generate(
          3,
          SensorAggregates.empty,
        ),
        trends = const <List<TrendPoint>>[
          <TrendPoint>[],
          <TrendPoint>[],
          <TrendPoint>[],
        ],
        computedAt = null,
        totalRows = 0,
        oldestTimestampMs = null;

  final List<SensorAggregates> perSensor;

  /// 24 h downsampled trend per sensor, for the sparkline.
  final List<List<TrendPoint>> trends;

  final DateTime? computedAt;
  final int totalRows;
  final int? oldestTimestampMs;

  SensorAggregates forSensor(int index) =>
      perSensor[index.clamp(0, perSensor.length - 1)];

  List<TrendPoint> trendFor(int index) =>
      trends[index.clamp(0, trends.length - 1)];

  Duration? get historySpan {
    final oldest = oldestTimestampMs;
    if (oldest == null) return null;
    return DateTime.now().toUtc().difference(
          DateTime.fromMillisecondsSinceEpoch(oldest, isUtc: true),
        );
  }
}

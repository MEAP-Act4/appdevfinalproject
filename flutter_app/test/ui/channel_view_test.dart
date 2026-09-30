/// Worked examples for the shared per-channel projection (task 7.5).
///
/// These are examples, not the property — task 7.7 writes Property 7 (the
/// carousel and dashboard agree through this one `ChannelView`). What follows
/// builds a synthetic monitor snapshot plus settings and pins that, for a
/// chosen index, `ChannelView.of` returns the expected live flow, live series,
/// window stats, Status, and formatted strings — the same values `SensorPage`
/// derives inline today, so the projection is a faithful single source.
///
/// The twin of the Web_Client `channelView.test.ts` (task 7.6); the two carry
/// the same worked examples so the clients cannot drift (Requirement 13.2).
///
/// **Why the monitor is a plain fake, not `MonitorController`.** `ChannelView`
/// reads a monitor only through the four widget-free getters declared by
/// [MonitorSource] — `flowFor`, `liveSeries`, `aggregates`, `status`. The real
/// controller's constructor opens an `AppDatabase` (sqflite), unavailable under
/// `flutter_test`, so a small hand-built stand-in implementing exactly those
/// four members is the faithful minimal input — the same reasoning
/// `channel_kpi_card_test.dart` records for its fake. No `pumpWidget` here: the
/// projection is pure Dart with no `BuildContext`.
///
/// _Requirements: 4.6, 13.2_
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/units/measurement_units.dart';
import 'package:leakguard/data/models/aggregates.dart';
import 'package:leakguard/data/settings/app_settings.dart';
import 'package:leakguard/ui/sensors/channel_view.dart';

/// A widget-free [MonitorSource] carrying fixed synthetic values.
class _FakeMonitor implements MonitorSource {
  _FakeMonitor({
    required this.flows,
    required this.series,
    required this.aggregates,
    required this.status,
  });

  final List<double> flows;
  final Map<int, List<double>> series;

  @override
  final AggregateSnapshot aggregates;

  @override
  final LeakStatus status;

  @override
  double flowFor(int sensorIndex) => flows[sensorIndex];

  @override
  List<double> liveSeries(int sensorIndex) =>
      series[sensorIndex] ?? const <double>[];
}

WindowStats _window(AverageWindow window, double averageLpm) => WindowStats(
      window: window,
      averageLpm: averageLpm,
      peakLpm: averageLpm * 2,
      totalLitres: averageLpm * 10,
      sampleCount: 500,
      coverage: 0.8,
      activeFraction: 0.5,
    );

/// A snapshot whose channel 1 (Outlet A) carries known, distinct values.
AggregateSnapshot _snapshot() => AggregateSnapshot(
      perSensor: <SensorAggregates>[
        SensorAggregates.empty(0),
        SensorAggregates(
          sensorIndex: 1,
          day: _window(AverageWindow.day, 3.5),
          threeDay: _window(AverageWindow.threeDay, 2.25),
          week: _window(AverageWindow.week, 1.1),
        ),
        SensorAggregates.empty(2),
      ],
      trends: const <List<TrendPoint>>[
        <TrendPoint>[],
        <TrendPoint>[],
        <TrendPoint>[],
      ],
      computedAt: null,
      totalRows: 0,
      oldestTimestampMs: null,
    );

_FakeMonitor _monitor() => _FakeMonitor(
      flows: <double>[12, 4.2, 0],
      series: <int, List<double>>{
        0: <double>[10, 11, 12],
        1: <double>[4.0, 4.1, 4.2],
        2: <double>[0, 0, 0],
      },
      aggregates: _snapshot(),
      status: LeakStatus.watch,
    );

final AppSettings _settings = const AppSettings(
  sensorNames: <String>['Main Inlet', 'Kitchen', 'Outlet B'],
  flowUnit: FlowUnit.litresPerMinute,
  volumeUnit: VolumeUnit.litres,
);

void main() {
  group('ChannelView.of', () {
    test('projects the live/series/status/aggregate fields for a channel', () {
      final view = ChannelView.of(_monitor(), _settings, 1);

      expect(view.sensorIndex, 1);
      expect(view.name, 'Kitchen');
      // live = flowFor(1)
      expect(view.live, 4.2);
      // series = liveSeries(1)
      expect(view.series, <double>[4.0, 4.1, 4.2]);
      // status = monitor.status
      expect(view.status, LeakStatus.watch);
      // windows = day, 3-day, week in order, from perSensor[1]
      expect(
        view.windows.map((w) => w.window).toList(),
        <AverageWindow>[
          AverageWindow.day,
          AverageWindow.threeDay,
          AverageWindow.week,
        ],
      );
      expect(
        view.windows.map((w) => w.averageLpm).toList(),
        <double>[3.5, 2.25, 1.1],
      );
    });

    test('formats every string through the formatter', () {
      final formatter = _settings.formatter;
      final view = ChannelView.of(_monitor(), _settings, 1);

      expect(view.text.liveReading, formatter.flow(4.2));
      expect(view.text.liveReading, '4.20 L/min');
      // The Status token string mirrors the Web `LeakStatus` token.
      expect(view.text.status, 'WATCH');
      expect(view.text.averages, <String>[
        formatter.flow(3.5),
        formatter.flow(2.25),
        formatter.flow(1.1),
      ]);
      expect(
        view.text.averages,
        <String>['3.50 L/min', '2.25 L/min', '1.10 L/min'],
      );
      // Cost_Formatter arrives in task 11.11; the slot is null until then.
      expect(view.text.bsEquivalence, isNull);
    });

    test('respects the flow unit when formatting', () {
      final lph = _settings.copyWith(
        flowUnit: FlowUnit.litresPerHour,
        volumeUnit: VolumeUnit.litres,
      );
      final view = ChannelView.of(_monitor(), lph, 1);
      // 4.2 L/min -> 252 L/h at 1 decimal.
      expect(view.text.liveReading, '252.0 L/h');
      expect(view.text.averages[0], '210.0 L/h');
    });

    test('falls back to zero live flow and empty series when idle', () {
      final idle = _FakeMonitor(
        flows: <double>[0, 0, 0],
        series: const <int, List<double>>{},
        aggregates: AggregateSnapshot.empty(),
        status: LeakStatus.unknown,
      );
      final view = channelViewOf(idle, _settings, 2);

      expect(view.live, 0);
      expect(view.series, isEmpty);
      expect(view.status, LeakStatus.unknown);
      // An empty snapshot still carries three zeroed windows.
      expect(
        view.windows.map((w) => w.window).toList(),
        <AverageWindow>[
          AverageWindow.day,
          AverageWindow.threeDay,
          AverageWindow.week,
        ],
      );
      expect(view.text.liveReading, '0.00 L/min');
      expect(
        view.text.averages,
        <String>['0.00 L/min', '0.00 L/min', '0.00 L/min'],
      );
    });

    test('names an out-of-range channel from the role fallback', () {
      // The Web falls back to the fixed SENSOR_ROLES label when settings has no
      // name for the index; the Dart twin falls back to SensorRole.byIndex.
      final view = ChannelView.of(_monitor(), _settings, 0);
      expect(view.name, 'Main Inlet');
      expect(view.live, 12);
      expect(view.status, LeakStatus.watch);
    });
  });
}

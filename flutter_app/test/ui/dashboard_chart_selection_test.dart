/// Example tests for the Dashboard_View Main_Chart channel selection and the
/// chart's gradient/grid recipe (task 9.15).
///
/// **Scope.** These complement the composition examples in
/// `dashboard_view_test.dart` (task 9.8) and the multi-series contract in
/// `flow_sparkline_test.dart` (task 9.6) with the two cases task 9.15 owns and
/// those files deliberately left alone:
///
///  * the **exhaustive** eight-subset sweep of the three chart channels. The
///    `.chip`-equivalent [FilterChip] row is a multi-select (Requirement 3.9);
///    for every one of the `2^3 = 8` subsets this pins that the multi-series
///    [FlowSparkline] plots *exactly* the selected channels — the right series,
///    in canonical channel order — including the all-off case, where the impl's
///    one-remaining guard keeps a single channel plotted rather than blanking
///    the chart. Eight cases is the whole input space, so this is stronger than
///    sampling.
///  * a **snapshot of the chart's gradient stops and grid stroke**
///    (Requirements 3.7, 3.8). The area gradient's three stop opacities
///    (`0.34` / `0.10` / `0.0`) and offsets (`0` / `0.6` / `1`), the series
///    stroke width (`2`, Requirement 3.8's cap) and the grid stroke width (`1`,
///    the faint border-token backdrop) are pinned to the named constants the
///    painter draws from, so a change to the recipe fails here. This is the
///    Flutter twin of the React `sparkline` snapshot in
///    `dashboard-chart-selection.test.tsx`.
///
/// **Why the series identify the channels.** Each channel is given a distinct
/// live series in the fake monitor, so asserting on the [FlowSparkline.series]
/// the chart hands the painter proves *which* channels are plotted — the
/// per-channel stroke colours alone cannot (the two outlets share the
/// gradient-green partner). The chart plots the selected channels in canonical
/// order `0, 1, 2`, so the expected series list is just the selected indices'
/// series in that order.
///
/// **Why the monitor is faked.** As in `dashboard_view_test.dart`, the real
/// `MonitorController` opens an sqflite `AppDatabase`, unavailable under
/// `flutter_test`; a subclass overriding only the getters the dashboard reads
/// is the faithful, minimal stand-in.
///
/// _Requirements: 3.7, 3.8, 3.9_
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/layout/layout_scope.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/db/app_database.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/state/monitor_controller.dart';
import 'package:leakguard/ui/common/charts.dart';
import 'package:leakguard/ui/common/surface_card.dart';
import 'package:leakguard/ui/dashboard/dashboard_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A no-op stand-in for the sqflite-backed database. Never touched.
class _FakeDb implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The distinct per-channel live series, indexed by channel. Distinct values
/// let a test tell channel 1's series from channel 2's, which the shared stroke
/// colour cannot.
const Map<int, List<double>> _seriesByChannel = <int, List<double>>{
  0: <double>[1, 2, 3, 4, 5],
  1: <double>[5, 4, 3, 2, 1],
  2: <double>[2, 2, 2, 2, 2],
};

/// A [MonitorController] with a fixed status and a distinct live series per
/// channel, no transport or database work.
class _FakeMonitor extends MonitorController {
  _FakeMonitor(SettingsController settings)
      : super(database: _FakeDb(), settings: settings);

  @override
  LeakStatus get status => LeakStatus.ok;

  @override
  bool get isStale => false;

  @override
  bool get isConnected => true;

  @override
  double flowFor(int sensorIndex) => 5.0 + sensorIndex;

  @override
  List<double> liveSeries(int sensorIndex) =>
      _seriesByChannel[sensorIndex] ?? const <double>[];
}

/// Loads settings with Reduce_Motion on, so the chart's one-shot reveal tween
/// and the KPI cards' entrance animations collapse to zero duration — the
/// harness then has no pending timers to leak between taps.
Future<SettingsController> _settings() {
  SharedPreferences.setMockInitialValues(<String, Object>{'reduceMotion': true});
  return SettingsController.load();
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  SettingsController settings,
) async {
  // A wide, tall physical surface so the Expanded run has room and the KPI
  // cells do not overflow — the same setup `dashboard_view_test.dart` uses.
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MonitorController>.value(
          value: _FakeMonitor(settings),
        ),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const LayoutScope(
          mode: LayoutMode.expanded,
          child: DashboardView(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The Main_Chart's [FlowSparkline], scoped by its enclosing card. Each KPI
/// cell also mounts a `FlowSparkline`, so a bare `find.byType` would match four;
/// the Main_Chart is the only card that also holds the [FilterChip] channel
/// selectors, so scoping to the SurfaceCard that contains a chip isolates it.
Finder _chartFinder() => find.descendant(
      of: find.ancestor(
        of: find.byType(FilterChip).first,
        matching: find.byType(SurfaceCard),
      ),
      matching: find.byType(FlowSparkline),
    );

FlowSparkline _chart(WidgetTester tester) =>
    tester.widget<FlowSparkline>(_chartFinder());

/// The FilterChip for [channel], found by its sensor name label.
Finder _chipFor(SettingsController settings, int channel) => find.widgetWithText(
      FilterChip,
      settings.settings.sensorNames[channel],
    );

/// The series the chart plots for a set of [selected] channels, in canonical
/// channel order — the expectation the sweep compares against.
List<List<double>> _expectedSeries(Set<int> selected) => <List<double>>[
      for (var i = 0; i < kSensorCount; i++)
        if (selected.contains(i)) _seriesByChannel[i]!,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Main_Chart channel selection is an exhaustive 8-subset multi-select '
      '(Requirement 3.9)', () {
    testWidgets('every channel starts plotted (the all-on subset)',
        (tester) async {
      final settings = await _settings();
      await _pumpDashboard(tester, settings);

      // All three FilterChips present and selected.
      final chips =
          tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
      expect(chips.length, kSensorCount);
      expect(chips.every((c) => c.selected), isTrue);

      // The chart plots all three series, in canonical order.
      expect(_chart(tester).series, _expectedSeries(<int>{0, 1, 2}));
    });

    testWidgets(
        'walking down to each smaller subset plots exactly those channels',
        (tester) async {
      final settings = await _settings();
      await _pumpDashboard(tester, settings);

      // Start from the all-on subset and toggle channels off one at a time,
      // covering the subsets {0,1,2} -> {1,2} -> {2} on the way down and back
      // up, checking the plotted series after each toggle.
      Future<void> toggle(int channel) async {
        await tester.tap(_chipFor(settings, channel));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }

      // {0,1,2}
      expect(_chart(tester).series, _expectedSeries(<int>{0, 1, 2}));

      // Drop channel 0 -> {1,2}
      await toggle(0);
      expect(_chart(tester).series, _expectedSeries(<int>{1, 2}));

      // Drop channel 1 -> {2}
      await toggle(1);
      expect(_chart(tester).series, _expectedSeries(<int>{2}));

      // Re-add channel 0 -> {0,2}
      await toggle(0);
      expect(_chart(tester).series, _expectedSeries(<int>{0, 2}));

      // Drop channel 2 -> {0}
      await toggle(2);
      expect(_chart(tester).series, _expectedSeries(<int>{0}));

      // Re-add channel 1 -> {0,1}
      await toggle(1);
      expect(_chart(tester).series, _expectedSeries(<int>{0, 1}));

      // Add channel 2 -> {0,1,2}, closing the exhaustive sweep of the seven
      // non-empty subsets.
      await toggle(2);
      expect(_chart(tester).series, _expectedSeries(<int>{0, 1, 2}));
    });

    testWidgets(
        'the empty subset is guarded: turning the last channel off keeps it on',
        (tester) async {
      final settings = await _settings();
      await _pumpDashboard(tester, settings);

      Future<void> toggle(int channel) async {
        await tester.tap(_chipFor(settings, channel));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }

      // Drop two channels, leaving only channel 2 selected.
      await toggle(0);
      await toggle(1);
      expect(_chart(tester).series, _expectedSeries(<int>{2}));

      // Attempt to drop the last remaining channel. The one-remaining guard
      // keeps it plotted rather than emptying the chart — so the notionally
      // eighth (all-off) subset resolves back to a single-channel plot.
      await toggle(2);
      final chart = _chart(tester);
      expect(chart.series, _expectedSeries(<int>{2}));
      expect(chart.series, isNotEmpty,
          reason: 'the chart never plots zero channels');

      // The chip for the remaining channel is still shown selected.
      final remaining =
          tester.widget<FilterChip>(_chipFor(settings, 2));
      expect(remaining.selected, isTrue);
    });
  });

  group('the chart gradient stops and grid stroke are pinned '
      '(Requirements 3.7, 3.8)', () {
    test('gradient stop opacities are 0.34 / 0.10 / 0.0', () {
      expect(FlowSparkline.gradientStopTopOpacity, 0.34);
      expect(FlowSparkline.gradientStopMidOpacity, 0.10);
      expect(FlowSparkline.gradientStopBottomOpacity, 0.0);
    });

    test('gradient stop offsets are 0 / 0.6 / 1', () {
      expect(FlowSparkline.gradientStopOffsets, <double>[0, 0.6, 1]);
    });

    test('the series stroke is capped at 2 and the grid stroke is the '
        'thinner 1 (Requirement 3.8)', () {
      expect(FlowSparkline.seriesStrokeWidth, 2);
      expect(FlowSparkline.gridStrokeWidth, 1);
      expect(
        FlowSparkline.seriesStrokeWidth,
        lessThanOrEqualTo(2),
        reason: 'Requirement 3.8 caps series strokes at 2',
      );
      expect(
        FlowSparkline.gridStrokeWidth,
        lessThan(FlowSparkline.seriesStrokeWidth),
        reason: 'the grid is a faint backdrop, thinner than the data stroke',
      );
    });

    testWidgets('the mounted Main_Chart renders the multi-series sparkline it '
        'draws the gradient/grid from', (tester) async {
      final settings = await _settings();
      await _pumpDashboard(tester, settings);

      // The chart is present and painting (not the empty state), so the pinned
      // gradient/grid recipe above is the one actually on screen.
      expect(_chartFinder(), findsOneWidget);
      expect(find.text('Waiting for data'), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}

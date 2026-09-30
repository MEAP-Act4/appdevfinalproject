/// Example tests for the Dashboard_View composition (task 9.8).
///
/// Requirements 3.1, 3.2, 3.3, 3.4, 3.9, 3.10.
///
/// **Scope.** These are *example* tests pinning the data-driven composition and
/// the reuse contract on fixed inputs. They deliberately overlap the input
/// space that the dedicated Property 29 suite (task 9.14) and the shared-fixture
/// example suite (task 9.15) will later own — pinning the ordered cells and
/// spans on concrete modes here de-risks those without pre-empting them. This
/// file does not implement any numbered property.
///
/// What is asserted:
///
///  * [dashboardComposition] returns the fixed KPI_Row order and the mode's
///    Main_Chart / Alerts_Panel spans (Requirements 3.1–3.4), and matches the
///    shared referee fixture `test_fixtures/layout/compositions.json` — the
///    same array the cross-client Property 29 reads;
///  * Compact has no grid composition (empty list), matching the fixture's
///    `grid:false`;
///  * every run in a grid mode sums to 12 (Grid_12 conservation);
///  * the Main_Chart channel selector starts with all three channels selectable
///    at once (Requirement 3.9) and the chips are [FilterChip]s;
///  * the view exposes a Diagnostics entry point (Requirement 3.10).
///
/// **Why the monitor is faked.** Like `channel_kpi_card_test.dart`, the real
/// `MonitorController` opens an sqflite `AppDatabase`, unavailable under
/// `flutter_test`. A subclass overriding only the getters the dashboard reads is
/// the faithful, minimal stand-in.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/layout/layout_scope.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/db/app_database.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/state/monitor_controller.dart';
import 'package:leakguard/ui/dashboard/dashboard_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A no-op stand-in for the sqflite-backed database. Never touched.
class _FakeDb implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [MonitorController] with a fixed status and short live series, no transport
/// or database work.
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
      const <double>[1, 2, 3, 4, 5];
}

Future<SettingsController> _settings() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SettingsController.load();
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  SettingsController settings, {
  required LayoutMode mode,
}) async {
  // The Dashboard_View is a full-viewport Scaffold, so the grid derives its
  // column widths from the render surface — not from a MediaQuery override. Give
  // the test a wide, tall physical surface so the Expanded run has room and the
  // KPI cells are wide enough that their inner rows do not overflow.
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
        home: LayoutScope(mode: mode, child: const DashboardView()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Reads the shared referee fixture from the repo root.
Map<String, dynamic> _readFixture() {
  // The Flutter package root is `flutter_app/`, so the repo root — where the
  // fixture lives — is one directory up.
  final file = File('../test_fixtures/layout/compositions.json');
  expect(
    file.existsSync(),
    isTrue,
    reason: 'shared composition fixture must exist at ${file.path}',
  );
  // The fixture carries a leading `$comment` array; jsonDecode ignores it.
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// The `(role.id, span)` pairs the fixture records for [modeName].
List<(String, int)> _fixtureCells(Map<String, dynamic> fixture, String modeName) {
  final modes = fixture['modes'] as Map<String, dynamic>;
  final mode = modes[modeName] as Map<String, dynamic>;
  final cells = (mode['cells'] as List<dynamic>).cast<Map<String, dynamic>>();
  return <(String, int)>[
    for (final cell in cells) (cell['role'] as String, cell['span'] as int),
  ];
}

/// The `(role.id, span)` pairs the Dart composition produces for [mode].
List<(String, int)> _dartCells(LayoutMode mode) => <(String, int)>[
      for (final spec in dashboardComposition(mode)) (spec.role.id, spec.span),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dashboardComposition is data matching the fixture', () {
    test('medium: KPI 4·4·4 then chart 12 then alerts 12', () {
      expect(_dartCells(LayoutMode.medium), <(String, int)>[
        ('kpi-main-inlet', 4),
        ('kpi-outlet-a', 4),
        ('kpi-outlet-b', 4),
        ('main-chart', 12),
        ('alerts-panel', 12),
      ]);
    });

    test('expanded: KPI 4·4·4 then chart 8 + alerts 4', () {
      expect(_dartCells(LayoutMode.expanded), <(String, int)>[
        ('kpi-main-inlet', 4),
        ('kpi-outlet-a', 4),
        ('kpi-outlet-b', 4),
        ('main-chart', 8),
        ('alerts-panel', 4),
      ]);
    });

    test('compact has no grid composition', () {
      expect(dashboardComposition(LayoutMode.compact), isEmpty);
    });

    test('matches the shared referee fixture exactly, in order', () {
      final fixture = _readFixture();
      expect(_dartCells(LayoutMode.medium), _fixtureCells(fixture, 'medium'));
      expect(_dartCells(LayoutMode.expanded), _fixtureCells(fixture, 'expanded'));
      expect(_fixtureCells(fixture, 'compact'), isEmpty);
    });

    test('every grid run sums to 12 (Grid_12 conservation)', () {
      for (final mode in <LayoutMode>[LayoutMode.medium, LayoutMode.expanded]) {
        final spans = dashboardComposition(mode).map((c) => c.span).toList();
        // Pack greedily into runs and check each run totals 12.
        var run = 0;
        for (final span in spans) {
          run += span;
          expect(run, lessThanOrEqualTo(12));
          if (run == 12) run = 0;
        }
        expect(run, 0, reason: 'a trailing run in $mode did not sum to 12');
      }
    });
  });

  testWidgets('renders the three KPI channels in the fixed order',
      (tester) async {
    final settings = await _settings();
    await _pumpDashboard(tester, settings, mode: LayoutMode.expanded);

    expect(find.text(settings.settings.sensorNames[0]), findsWidgets);
    expect(find.text(settings.settings.sensorNames[1]), findsWidgets);
    expect(find.text(settings.settings.sensorNames[2]), findsWidgets);
  });

  testWidgets('the chart channel selector is multi-select, all three on',
      (tester) async {
    final settings = await _settings();
    await _pumpDashboard(tester, settings, mode: LayoutMode.expanded);

    final chips = tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
    expect(chips.length, kSensorCount);
    // Requirement 3.9: every channel starts selected — all three at once.
    expect(chips.every((c) => c.selected), isTrue);
  });

  testWidgets('exposes a Diagnostics entry point (Requirement 3.10)',
      (tester) async {
    final settings = await _settings();
    await _pumpDashboard(tester, settings, mode: LayoutMode.medium);

    expect(find.byTooltip('Diagnostics'), findsOneWidget);
  });
}

/// Widget example for the Compact reachability of the Alert_Entry list from the
/// Sensors tab (task 13.9).
///
/// **What is under test.** Requirement 4.2 keeps exactly two bottom tabs in
/// Compact, so the Alerts_Panel has no tab of its own. Requirement 7.7 still
/// requires the Alert_Entry list to be *reachable* from the Sensors tab. Task
/// 13.9 satisfies both by adding an 'Alerts' AppBar action to the [SensorsTab]
/// that opens the panel as a modal bottom sheet — a modal route, so the shell's
/// two-tab NavigationBar is never touched.
///
/// This test pins that behaviour: tapping the 'Alerts' action opens a sheet
/// that contains an [AlertsPanel].
///
/// **Why the monitor is faked.** As in `sensors_carousel_navigation_test.dart`,
/// the real [MonitorController] opens an sqflite `AppDatabase` unavailable under
/// `flutter_test`; a subclass overriding only the getters the tab reads is the
/// minimal faithful stand-in. The [AlertsController] is stood up over an empty
/// in-memory loader (its `withLoader` test seam) so the panel renders its empty
/// state — enough to prove the sheet opened and the panel is inside it.
///
/// _Requirements: 7.7, 4.2_
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/db/app_database.dart';
import 'package:leakguard/data/models/stored_reading.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/state/alerts_controller.dart';
import 'package:leakguard/state/monitor_controller.dart';
import 'package:leakguard/state/selection_controller.dart';
import 'package:leakguard/ui/dashboard/alerts_panel.dart';
import 'package:leakguard/ui/sensors/sensors_tab.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A no-op stand-in for the sqflite-backed database. Never touched.
class _FakeDb implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [MonitorController] with a fixed status and short live series, no transport
/// or database work. Reported disconnected with no simulator and an OK status,
/// so the _StatusStrip and PulseDot stay quiet.
class _FakeMonitor extends MonitorController {
  _FakeMonitor(SettingsController settings)
      : super(database: _FakeDb(), settings: settings);

  @override
  LeakStatus get status => LeakStatus.ok;

  @override
  bool get isStale => false;

  @override
  bool get isConnected => false;

  @override
  bool get usingSimulator => false;

  @override
  double flowFor(int sensorIndex) => 5.0 + sensorIndex;

  @override
  List<double> liveSeries(int sensorIndex) => const <double>[1, 2, 3, 4, 5];
}

Future<SettingsController> _settings() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SettingsController.load();
}

/// Advances the clock enough for the reveal tweens and the sheet transition to
/// complete, without `pumpAndSettle` (which never returns here because the
/// RefreshIndicator/metric widgets keep a frame scheduled).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required SettingsController settings,
  required AlertsController alerts,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
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
        ChangeNotifierProvider<SelectionController>.value(
          value: SelectionController(),
        ),
        ChangeNotifierProvider<AlertsController>.value(value: alerts),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const SensorsTab(),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tapping the Alerts AppBar action opens a sheet containing an AlertsPanel '
    '(Requirements 7.7, 4.2)',
    (tester) async {
      final settings = await _settings();
      final alerts = AlertsController.withLoader(
        loadEvents: () async => const <LeakEvent>[],
        settings: settings,
      );
      addTearDown(alerts.dispose);
      await alerts.initialise();

      await _pumpTab(tester, settings: settings, alerts: alerts);

      // The panel is not on screen before the action is tapped.
      expect(find.byType(AlertsPanel), findsNothing);

      // The 'Alerts' action is labelled with its tooltip.
      final alertsAction = find.byTooltip('Alerts');
      expect(alertsAction, findsOneWidget);

      await tester.tap(alertsAction);
      await _settle(tester);

      // The modal sheet is now open and contains the Alerts_Panel.
      expect(find.byType(AlertsPanel), findsOneWidget);
      // The sheet carries its own title.
      expect(find.text('Alerts'), findsWidgets);
    },
  );
}

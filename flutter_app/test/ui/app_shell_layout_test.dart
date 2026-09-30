/// Example tests for the Layout_Mode-driven Mobile_Client shell (task 9.10).
///
/// Requirements 3.10, 4.1, 4.2, 4.5, 4.7, 4.8.
///
/// **Scope.** These are *example* tests pinning the shell's per-band chrome and
/// its tab-1 presentation swap on fixed modes. They do not implement any
/// numbered property — Property 5/6 (tasks 9.12/9.13) and the shared-fixture
/// example suite (task 9.15) own the broader input space. What is asserted:
///
///  * Compact shows exactly two bottom tabs (a [NavigationBar] with the Sensors
///    and Settings destinations) and no [NavigationRail] (Requirement 4.2);
///  * Medium/Expanded show a left [NavigationRail] with the same two
///    destinations and no bottom [NavigationBar] (Requirements 4.1, 4.2);
///  * tab 1 shows the [SensorsTab] carousel in Compact and swaps to the
///    [DashboardView] in Medium/Expanded (Requirements 4.1, 3.10);
///  * crossing the band back and forth keeps the mounted tab layers alive — the
///    Settings layer's `State` survives a Compact -> Expanded -> Compact walk
///    (Requirement 4.5).
///
/// **Why the monitor is faked.** As in `dashboard_view_test.dart`, the real
/// `MonitorController` opens an sqflite `AppDatabase`, unavailable under
/// `flutter_test`. A subclass overriding only the getters the shell subtree
/// reads is the faithful, minimal stand-in.
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
import 'package:leakguard/state/selection_controller.dart';
import 'package:leakguard/ui/dashboard/dashboard_view.dart';
import 'package:leakguard/ui/sensors/sensors_tab.dart';
import 'package:leakguard/ui/settings/settings_tab.dart';
import 'package:leakguard/ui/shell/app_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A no-op stand-in for the sqflite-backed database. Never touched.
class _FakeDb implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [MonitorController] with a fixed status and short live series, no transport
/// or database work. Overrides the storage-stat getters the Settings tab's data
/// section reads so pumping the offscreen Settings layer does not hit sqflite.
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
  bool get usingSimulator => false;

  @override
  double flowFor(int sensorIndex) => 5.0 + sensorIndex;

  @override
  List<double> liveSeries(int sensorIndex) => const <double>[1, 2, 3, 4, 5];

  @override
  Future<int> readingCount() async => 0;

  @override
  Future<int> databaseSizeBytes() async => 0;
}

Future<SettingsController> _settings() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SettingsController.load();
}

/// A host that publishes a mutable [LayoutMode] to a single [AppShell]
/// instance, mirroring the way `RootView` wraps the shell in a [LayoutScope].
/// The shell instance is captured once so a mode change never remounts it.
class _ShellHost extends StatefulWidget {
  const _ShellHost({super.key, required this.initialMode});

  final LayoutMode initialMode;

  @override
  State<_ShellHost> createState() => _ShellHostState();
}

class _ShellHostState extends State<_ShellHost> {
  late LayoutMode _mode = widget.initialMode;

  // Captured once, exactly as RootView captures the shell before the
  // LayoutBuilder. Reusing this identical instance across mode changes is what
  // keeps the shell's mounted tab layers out of the swap's remount set.
  final Widget _shell = const AppShell();

  void setMode(LayoutMode mode) => setState(() => _mode = mode);

  @override
  Widget build(BuildContext context) {
    return LayoutScope(mode: _mode, child: _shell);
  }
}

Future<_ShellHostState> _pumpShell(
  WidgetTester tester,
  SettingsController settings, {
  required LayoutMode mode,
}) async {
  // A wide, tall physical surface so the Expanded dashboard grid has room and
  // the rail + content Row is not width-clamped.
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final key = GlobalKey<_ShellHostState>();
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
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: _ShellHost(key: key, initialMode: mode),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return key.currentState!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Compact: two bottom tabs, no rail, tab 1 is the carousel '
      '(Requirements 4.1, 4.2)', (tester) async {
    final settings = await _settings();
    await _pumpShell(tester, settings, mode: LayoutMode.compact);

    // Exactly the two-destination bottom NavigationBar, no rail.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, 2);

    // Tab 1 is the Sensor_Carousel, not the Dashboard_View.
    expect(find.byType(SensorsTab), findsOneWidget);
    expect(find.byType(DashboardView), findsNothing);
  });

  testWidgets(
      'Expanded: a left rail with two destinations, no bottom bar, tab 1 is '
      'the dashboard (Requirements 4.1, 4.2, 3.10)', (tester) async {
    final settings = await _settings();
    await _pumpShell(tester, settings, mode: LayoutMode.expanded);

    // The rail replaces the bottom bar, same two destinations.
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations.length, 2);

    // Tab 1 is now the Dashboard_View, which exposes its Diagnostics entry
    // point (Requirement 3.10).
    expect(find.byType(DashboardView), findsOneWidget);
    expect(find.byType(SensorsTab), findsNothing);
    expect(find.byTooltip('Diagnostics'), findsWidgets);
  });

  testWidgets('Medium also uses the rail with two destinations (Requirement 4.2)',
      (tester) async {
    final settings = await _settings();
    await _pumpShell(tester, settings, mode: LayoutMode.medium);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations.length, 2);
    expect(find.byType(DashboardView), findsOneWidget);
  });

  testWidgets(
      'a Compact -> Expanded -> Compact walk keeps both tabs mounted and '
      'retains the selection (Requirement 4.5)', (tester) async {
    final settings = await _settings();
    // Seed the shared selection to channel 2 so we can watch it survive.
    final selection = SelectionController(selectedChannel: 2);

    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey<_ShellHostState>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MonitorController>.value(
            value: _FakeMonitor(settings),
          ),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<SelectionController>.value(value: selection),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: _ShellHost(key: key, initialMode: LayoutMode.compact),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final host = key.currentState!;

    // Both tabs mounted from the start: Compact tab 1 is the carousel, and the
    // Settings layer is mounted (offscreen) alongside it.
    expect(find.byType(SensorsTab), findsOneWidget);
    expect(find.byType(SettingsTab), findsOneWidget);

    // Cross to Expanded: bottom bar -> rail, carousel -> dashboard. The Settings
    // layer must remain mounted through the swap.
    host.setMode(LayoutMode.expanded);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(DashboardView), findsOneWidget);
    expect(find.byType(SettingsTab), findsOneWidget,
        reason: 'the Settings layer must survive the band change, not unmount');

    // Cross back to Compact: rail -> bottom bar, dashboard -> carousel.
    host.setMode(LayoutMode.compact);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(SensorsTab), findsOneWidget);
    expect(find.byType(DashboardView), findsNothing);

    // The shared selection carried across both crossings untouched
    // (Requirement 4.5's "current view selection retained").
    expect(selection.selectedChannel, 2);
  });
}

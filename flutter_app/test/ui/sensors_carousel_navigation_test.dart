/// Example tests for the Compact Sensor_Carousel's three pages and working
/// chevrons (task 9.15).
///
/// **Scope.** `app_shell_layout_test.dart` (task 9.10) already pins that Compact
/// shows the [SensorsTab] carousel behind exactly two bottom tabs; this file
/// complements it with the carousel-internal behaviour task 9.15 owns: that the
/// carousel has **three** per-sensor pages and that the **chevrons work** —
/// tapping "next" and "previous" moves the selected channel across all three
/// pages and disables at the ends (Requirement 4.1).
///
/// Navigation is driven through the shared [SelectionController]: the chevrons
/// are the writers (via `animateToPage` -> `onPageChanged`), so asserting on the
/// controller's `selectedChannel` after each tap proves the chevron actually
/// moved the carousel rather than merely animating. The chevrons are found by
/// their accessible label, which the widget builds from the neighbouring sensor
/// name, so the test also pins that the affordances are labelled
/// (Requirement 10.4-friendly, though 10.4 is not this task's focus).
///
/// **Why the monitor is faked.** As elsewhere in this suite, the real
/// `MonitorController` opens an sqflite `AppDatabase` unavailable under
/// `flutter_test`; a subclass overriding only the getters the carousel reads is
/// the minimal faithful stand-in.
///
/// _Requirements: 4.1_
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/db/app_database.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/state/monitor_controller.dart';
import 'package:leakguard/state/selection_controller.dart';
import 'package:leakguard/ui/sensors/sensors_tab.dart';
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

  // Reported disconnected so the LinkChip's PulseDot is inactive and does not
  // loop forever — that keeps `pumpAndSettle` from timing out. With no
  // simulator, no staleness and an OK status, the _StatusStrip shows nothing.
  @override
  bool get isConnected => false;

  @override
  bool get usingSimulator => false;

  @override
  double flowFor(int sensorIndex) => 5.0 + sensorIndex;

  @override
  List<double> liveSeries(int sensorIndex) => const <double>[1, 2, 3, 4, 5];
}

/// Loads settings with the defaults. Reduce_Motion is left **off** on purpose:
/// the carousel drives navigation through `PageController.animateToPage`, which
/// asserts a non-zero duration, so the page animation must be allowed to run.
/// `pumpAndSettle` then drains it after each chevron tap.
Future<SettingsController> _settings() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SettingsController.load();
}

Future<SelectionController> _pumpCarousel(
  WidgetTester tester,
  SettingsController settings, {
  required SelectionController selection,
}) async {
  // The SensorsTab always renders the carousel regardless of Layout_Mode (it
  // has no LayoutScope dependency), so the surface size is free to be generous.
  // A roomy surface keeps the SensorPage metric rows from overflowing in the
  // test environment's default text metrics.
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
        ChangeNotifierProvider<SelectionController>.value(value: selection),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const SensorsTab(),
      ),
    ),
  );
  await _settle(tester);
  return selection;
}

/// Advances the clock enough for the carousel page animation and the one-shot
/// reveal tweens to complete, without `pumpAndSettle` (which never returns here
/// because the RefreshIndicator/metric widgets keep a frame scheduled).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(seconds: 1));
}

/// The next / previous chevrons, identified by their unambiguous glyphs.
final Finder _nextChevron = find.byIcon(Icons.chevron_right_rounded);
final Finder _prevChevron = find.byIcon(Icons.chevron_left_rounded);

/// A chevron carries its accessible label as a [Semantics] node; this reads the
/// nearest labelled ancestor so the test can pin that the affordance is
/// labelled. Several unlabelled Semantics wrappers sit between the glyph and the
/// `_ArrowButton`'s explicit one, so it walks up to the first with a label.
String _chevronLabel(WidgetTester tester, Finder chevron) {
  final ancestors = find.ancestor(of: chevron, matching: find.byType(Semantics));
  for (final element in ancestors.evaluate()) {
    final label = (element.widget as Semantics).properties.label;
    if (label != null && label.isNotEmpty) return label;
  }
  return '';
}

/// Taps the InkWell wrapping a chevron glyph — the actual gesture target, which
/// is more reliable to hit than the [Icon] itself.
Future<void> _tap(WidgetTester tester, Finder chevron) async {
  final inkWell = find.ancestor(of: chevron, matching: find.byType(InkWell));
  await tester.tap(inkWell.first);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the carousel has three per-sensor pages (Requirement 4.1)',
      (tester) async {
    final settings = await _settings();
    await _pumpCarousel(tester, settings,
        selection: SelectionController());

    // A PageView with exactly three items, one per sensor channel.
    expect(find.byType(PageView), findsOneWidget);
    expect(kSensorCount, 3);

    // The switcher shows the first page's position of three.
    expect(find.text('Sensor 1 of $kSensorCount'), findsOneWidget);
    expect(find.text(settings.settings.sensorNames[0]), findsWidgets);
  });

  testWidgets('the next chevron walks forward through all three pages',
      (tester) async {
    final settings = await _settings();
    final selection = await _pumpCarousel(tester, settings,
        selection: SelectionController());
    final names = settings.settings.sensorNames;

    expect(selection.selectedChannel, 0);
    // The next chevron is labelled with the sensor it leads to.
    expect(_chevronLabel(tester, _nextChevron), 'Next sensor: ${names[1]}');

    // Page 0 -> 1.
    await _tap(tester, _nextChevron);
    expect(selection.selectedChannel, 1);
    expect(find.text('Sensor 2 of $kSensorCount'), findsOneWidget);

    // Page 1 -> 2.
    await _tap(tester, _nextChevron);
    expect(selection.selectedChannel, 2);
    expect(find.text('Sensor 3 of $kSensorCount'), findsOneWidget);
  });

  testWidgets('the previous chevron walks back through the pages',
      (tester) async {
    final settings = await _settings();
    // Start on the last page so the previous chevron has somewhere to go.
    final selection = await _pumpCarousel(tester, settings,
        selection: SelectionController(selectedChannel: 2));
    final names = settings.settings.sensorNames;

    expect(selection.selectedChannel, 2);
    expect(_chevronLabel(tester, _prevChevron), 'Previous sensor: ${names[1]}');

    await _tap(tester, _prevChevron);
    expect(selection.selectedChannel, 1);

    await _tap(tester, _prevChevron);
    expect(selection.selectedChannel, 0);
    expect(find.text('Sensor 1 of $kSensorCount'), findsOneWidget);
  });

  testWidgets('the chevrons disable at the ends of the carousel',
      (tester) async {
    final settings = await _settings();
    final selection = await _pumpCarousel(tester, settings,
        selection: SelectionController());

    // At the first page the "previous" affordance announces the boundary and
    // does not move the selection.
    expect(selection.selectedChannel, 0);
    expect(_chevronLabel(tester, _prevChevron), 'Already at the first sensor');
    await _tap(tester, _prevChevron);
    expect(selection.selectedChannel, 0,
        reason: 'the previous chevron is inert on the first page');

    // Walk to the last page, where the "next" affordance likewise announces the
    // boundary and is inert.
    selection.selectChannel(kSensorCount - 1);
    await _settle(tester);
    expect(selection.selectedChannel, 2);
    expect(_chevronLabel(tester, _nextChevron), 'Already at the last sensor');
    await _tap(tester, _nextChevron);
    expect(selection.selectedChannel, 2,
        reason: 'the next chevron is inert on the last page');
  });
}

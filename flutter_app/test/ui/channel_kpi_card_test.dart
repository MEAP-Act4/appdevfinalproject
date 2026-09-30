/// Widget tests for the extracted [ChannelKpiCard] (task 7.1).
///
/// Requirements 3.5, 4.6, 13.1.
///
/// **Scope.** Task 7.1 is a pure refactor: `_LiveReadingCard` moved out of
/// `sensor_page.dart` into `channel_kpi_card.dart` and became the public
/// `ChannelKpiCard`, gaining a single new degree of freedom — the [dense] flag
/// controlling the KPI numeral size. These examples pin the two things that flag
/// is contracted to do:
///
///   1. the card renders the live reading (the formatted flow value), so the
///      extraction did not drop the hero KPI, and
///   2. `dense: true` produces a strictly smaller KPI numeral than the default
///      (`dense: false`) carousel hero size, with the dense size fixed at the
///      WattVision §4 dashboard-cell value of [Tokens.kpiSize] (32).
///
/// The default is asserted to leave the carousel hero size unchanged
/// ([ChannelKpiCard.kHeroKpiSize] = 44, the historical `_LiveReadingCard`
/// value), which is what keeps this a no-visual-change refactor at phone widths.
///
/// **Why the monitor is faked.** `ChannelKpiCard` reads `MonitorController`
/// through `provider` only for `status`, `isStale` and `isConnected`; the live
/// value, the flowing flag and the series arrive as constructor arguments. The
/// real controller's constructor opens an `AppDatabase` (sqflite), unavailable
/// under `flutter_test`, so a subclass overriding just those three getters is
/// the faithful and minimal stand-in — the same reasoning
/// `root_view_layout_host_test.dart` records for not pumping the real tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/core/theme/design_tokens.dart';
import 'package:leakguard/data/db/app_database.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/state/monitor_controller.dart';
import 'package:leakguard/ui/sensors/widgets/channel_kpi_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A no-op stand-in for the sqflite-backed database. Never touched, because the
/// fake controller below never calls `initialise()`; it exists only to satisfy
/// the `MonitorController` constructor's argument type.
class _FakeDb implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [MonitorController] that reports a fixed link/status without any transport
/// or database work. Only the three getters the card reads are overridden.
class _FakeMonitor extends MonitorController {
  _FakeMonitor(SettingsController settings)
      : super(database: _FakeDb(), settings: settings);

  @override
  LeakStatus get status => LeakStatus.ok;

  @override
  bool get isStale => false;

  @override
  bool get isConnected => true;
}

Future<SettingsController> _settings() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SettingsController.load();
}

Future<void> _pump(
  WidgetTester tester,
  SettingsController settings, {
  required bool dense,
  double liveLpm = 12.5,
  bool flowing = true,
}) async {
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
        home: Scaffold(
          body: ChannelKpiCard(
            sensorIndex: 0,
            accent: AppPalette.dark.accent,
            liveLpm: liveLpm,
            flowing: flowing,
            series: const <double>[1, 2, 3, 4, 5],
            dense: dense,
          ),
        ),
      ),
    ),
  );
  // Advance past the AnimatedMetric tween so the KPI shows its final value.
  // `pumpAndSettle` is unusable here: the status pill's breathing dot is an
  // ambient repeating animation that never settles. A single long pump clears
  // the one-shot value tween instead.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The resolved font size of the KPI numeral — the mono [Text] whose content is
/// the formatted live value. The unit symbol is a separate, smaller [Text], so
/// matching on the numeral string isolates the KPI face itself.
double _kpiFontSize(WidgetTester tester, String numeral) {
  final text = tester.widget<Text>(find.text(numeral));
  final size = text.style?.fontSize;
  expect(size, isNotNull, reason: 'the KPI numeral must carry an explicit size');
  return size!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the live reading', (tester) async {
    final settings = await _settings();
    await _pump(tester, settings, dense: false);

    // Default L/min formatter keeps two decimals, so 12.5 -> "12.50".
    expect(find.text('12.50'), findsOneWidget);
    expect(find.text('L/min'), findsOneWidget);
    // The flowing affordance is present.
    expect(find.text('FLOWING'), findsOneWidget);
  });

  testWidgets('the default (hero) KPI size is the historical carousel size',
      (tester) async {
    final settings = await _settings();
    await _pump(tester, settings, dense: false);

    expect(_kpiFontSize(tester, '12.50'), ChannelKpiCard.kHeroKpiSize);
    // Guards the no-visual-change contract: the carousel call site omits
    // `dense`, so this is the size it renders today.
    expect(ChannelKpiCard.kHeroKpiSize, 44);
  });

  testWidgets('dense uses the WattVision §4 dashboard-cell size of 32',
      (tester) async {
    final settings = await _settings();
    await _pump(tester, settings, dense: true);

    expect(_kpiFontSize(tester, '12.50'), Tokens.kpiSize);
    expect(Tokens.kpiSize, 32);
  });

  testWidgets('dense produces a strictly smaller KPI than the default hero',
      (tester) async {
    final denseSettings = await _settings();
    await _pump(tester, denseSettings, dense: true);
    final denseSize = _kpiFontSize(tester, '12.50');

    final heroSettings = await _settings();
    await _pump(tester, heroSettings, dense: false);
    final heroSize = _kpiFontSize(tester, '12.50');

    expect(denseSize, lessThan(heroSize));
  });
}

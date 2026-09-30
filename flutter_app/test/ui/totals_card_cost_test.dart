/// Widget tests for the `Bs_Equivalence` on the [TotalsCard] (task 11.11).
///
/// Requirements 6.1, 6.5, 6.8.
///
/// The TotalsCard shows three cumulative volume figures — "Since reset",
/// "Last 24 h" and "Last 7 d". Requirement 6.1 asks for a Bs_Equivalence beside
/// *every* cumulative total, so these examples pin all three, plus the
/// disabled-display and default-tariff behaviours the shared [CostLine] carries.
///
/// **Why the monitor is faked.** The real `MonitorController` opens a
/// sqflite `AppDatabase`, unavailable under `flutter_test`. A subclass
/// overriding only the three members the card reads for its volume figures
/// (`volumeFor`, `aggregates`, `isConnected`) is the minimal faithful stand-in,
/// matching the reasoning in `channel_kpi_card_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/data/db/app_database.dart';
import 'package:leakguard/data/models/aggregates.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/state/monitor_controller.dart';
import 'package:leakguard/ui/common/animated_metric.dart';
import 'package:leakguard/ui/sensors/widgets/channel_cards.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A no-op stand-in for the sqflite database; never touched because the fake
/// controller below never calls `initialise()`.
class _FakeDb implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [MonitorController] with fixed volume figures and no transport or database
/// work. `volumeFor`, `aggregates` and `isConnected` are the only members the
/// TotalsCard reads for its volume tiles.
class _FakeMonitor extends MonitorController {
  _FakeMonitor(SettingsController settings)
      : super(database: _FakeDb(), settings: settings);

  static WindowStats _window(AverageWindow w, double litres) => WindowStats(
        window: w,
        averageLpm: 1,
        peakLpm: 2,
        totalLitres: litres,
        sampleCount: 10,
        coverage: 1,
        activeFraction: 0.5,
      );

  @override
  bool get isConnected => false;

  @override
  double volumeFor(int sensorIndex) => 1000; // 1 m³ -> Bs. 5.00 at default.

  @override
  AggregateSnapshot get aggregates => AggregateSnapshot(
        perSensor: <SensorAggregates>[
          for (var i = 0; i < 3; i++)
            SensorAggregates(
              sensorIndex: i,
              day: _window(AverageWindow.day, 2000), // 2 m³ -> Bs. 10.00.
              threeDay: _window(AverageWindow.threeDay, 3000),
              week: _window(AverageWindow.week, 7000), // 7 m³ -> Bs. 35.00.
            ),
        ],
        trends: const <List<TrendPoint>>[[], [], []],
        computedAt: null,
        totalRows: 0,
        oldestTimestampMs: null,
      );
}

Future<SettingsController> _settings(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  return SettingsController.load();
}

Future<void> _pump(WidgetTester tester, SettingsController settings) async {
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
        home: const Scaffold(body: TotalsCard(sensorIndex: 0)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders a Bs. figure beside each of the three volume totals',
      (tester) async {
    // Default settings: cost display on, default tariff (5.0), en locale.
    final settings = await _settings(<String, Object>{});
    await _pump(tester, settings);

    // Since reset: 1000 L -> Bs. 5.00; Last 24 h: 2000 L -> Bs. 10.00;
    // Last 7 d: 7000 L -> Bs. 35.00.
    expect(find.text('Bs. 5.00'), findsOneWidget);
    expect(find.text('Bs. 10.00'), findsOneWidget);
    expect(find.text('Bs. 35.00'), findsOneWidget);
  });

  testWidgets('renders no Bs. figure when cost display is disabled',
      (tester) async {
    final settings =
        await _settings(<String, Object>{'showCostEquivalence': false});
    await _pump(tester, settings);

    expect(find.textContaining('Bs.'), findsNothing);
  });

  testWidgets('shows the default-tariff hint while the Tariff is unconfigured',
      (tester) async {
    final settings = await _settings(<String, Object>{});
    await _pump(tester, settings);

    // The hint appears beside every one of the three volume figures.
    expect(
      find.text(CostLine.defaultTariffHint),
      findsNWidgets(3),
    );
  });

  testWidgets('drops the hint once a Tariff has been committed', (tester) async {
    final settings = await _settings(<String, Object>{
      'tariffBsPerCubicMetre': 5.0,
      'tariffConfiguredByUser': true,
    });
    await _pump(tester, settings);

    expect(find.text(CostLine.defaultTariffHint), findsNothing);
    // The amounts are still present.
    expect(find.text('Bs. 5.00'), findsOneWidget);
  });
}

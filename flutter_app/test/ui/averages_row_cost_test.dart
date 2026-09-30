/// Widget tests for the `Bs_Equivalence` on the averages window detail
/// (task 11.11).
///
/// Requirements 6.2, 6.5, 6.8.
///
/// The averages row expands each window into a detail card whose "Total used"
/// figure is the window's volume. Requirement 6.2 asks for a Bs_Equivalence
/// beside the per-day, per-3-day and per-week volume figures, so this expands a
/// window and pins the amount, the disabled-display suppression, and the
/// default-tariff hint the shared [CostLine] carries.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/core/units/measurement_units.dart';
import 'package:leakguard/data/models/aggregates.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/ui/common/animated_metric.dart';
import 'package:leakguard/ui/sensors/widgets/averages_row.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

WindowStats _window(AverageWindow w, double litres) => WindowStats(
      window: w,
      averageLpm: 1,
      peakLpm: 2,
      totalLitres: litres,
      sampleCount: 10,
      coverage: 1,
      activeFraction: 0.5,
    );

/// A per-sensor aggregate whose per-day total is 2000 L (2 m³ -> Bs. 10.00 at
/// the default 5.0 tariff), with distinct totals for the other windows.
final _aggregates = SensorAggregates(
  sensorIndex: 0,
  day: _window(AverageWindow.day, 2000),
  threeDay: _window(AverageWindow.threeDay, 3000),
  week: _window(AverageWindow.week, 7000),
);

Future<SettingsController> _settings(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  return SettingsController.load();
}

Future<void> _pumpAndExpandDay(
  WidgetTester tester,
  SettingsController settings,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: AveragesRow(
            aggregates: _aggregates,
            formatter: const UnitFormatter(
              flowUnit: FlowUnit.litresPerMinute,
              volumeUnit: VolumeUnit.litres,
            ),
            accent: AppPalette.dark.accent,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  // Expand the "Per day" window to reveal its detail card.
  await tester.tap(find.text(AverageWindow.day.label.toUpperCase()));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders a Bs. figure beside the window total volume',
      (tester) async {
    final settings = await _settings(<String, Object>{});
    await _pumpAndExpandDay(tester, settings);

    // 2000 L = 2 m³ at 5.00 Bs./m³ -> Bs. 10.00.
    expect(find.text('Bs. 10.00'), findsOneWidget);
  });

  testWidgets('renders no Bs. figure when cost display is disabled',
      (tester) async {
    final settings =
        await _settings(<String, Object>{'showCostEquivalence': false});
    await _pumpAndExpandDay(tester, settings);

    expect(find.textContaining('Bs.'), findsNothing);
  });

  testWidgets('shows the default-tariff hint while the Tariff is unconfigured',
      (tester) async {
    final settings = await _settings(<String, Object>{});
    await _pumpAndExpandDay(tester, settings);

    expect(find.text(CostLine.defaultTariffHint), findsOneWidget);
  });
}

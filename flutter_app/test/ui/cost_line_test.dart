/// Widget tests for the shared [CostLine] — the single `Bs_Equivalence`
/// mechanism every volume figure renders through (task 11.11).
///
/// Requirements 6.1, 6.2, 6.5, 6.8, 6.9.
///
/// These pin the behaviour that both call sites (the TotalsCard cumulative
/// figures and the averages "Total used" figure) inherit from one widget:
///
///   * a `Bs.` amount is rendered beside the volume when display is enabled,
///     computed from the *canonical litre* value (Req 6.1, 6.2);
///   * nothing at all is rendered when display is disabled (Req 5.8);
///   * the "default tariff" hint accompanies the amount when the Tariff has not
///     been configured by the user, and is absent once it has (Req 6.8);
///   * the amount is rendered in the secondary text colour at the body type
///     size (Req 6.5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/money/cost_formatter.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/core/theme/design_tokens.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/ui/common/animated_metric.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(
  WidgetTester tester,
  CostFormatter formatter, {
  double litres = 3600,
}) async {
  // AnimatedMetric reads Reduce_Motion from a SettingsController provider.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final settings = await SettingsController.load();
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: CostLine(canonicalLitres: litres, formatter: formatter),
          ),
        ),
      ),
    ),
  );
  // Clear the one-shot AnimatedMetric value tween so the final amount shows.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the Bs. amount beside the volume when enabled',
      (tester) async {
    // 3600 L = 3.6 m³ at 5.00 Bs./m³ -> Bs. 18.00.
    await _pump(
      tester,
      const CostFormatter(
        tariffBsPerCubicMetre: 5,
        locale: 'en',
        enabled: true,
        isDefaultTariff: false,
      ),
    );

    expect(find.text('Bs. 18.00'), findsOneWidget);
  });

  testWidgets('renders nothing when cost display is disabled', (tester) async {
    await _pump(
      tester,
      const CostFormatter(
        tariffBsPerCubicMetre: 5,
        locale: 'en',
        enabled: false,
        isDefaultTariff: false,
      ),
    );

    // No Bs. amount, and the default-tariff hint is likewise absent.
    expect(find.textContaining('Bs.'), findsNothing);
    expect(find.text(CostLine.defaultTariffHint), findsNothing);
  });

  testWidgets('shows the default-tariff hint when the Tariff is unconfigured',
      (tester) async {
    await _pump(
      tester,
      const CostFormatter(
        tariffBsPerCubicMetre: 5,
        locale: 'en',
        enabled: true,
        isDefaultTariff: true,
      ),
    );

    expect(find.text('Bs. 18.00'), findsOneWidget);
    expect(find.text(CostLine.defaultTariffHint), findsOneWidget);
  });

  testWidgets('omits the hint once the Tariff is user-configured',
      (tester) async {
    await _pump(
      tester,
      const CostFormatter(
        tariffBsPerCubicMetre: 5,
        locale: 'en',
        enabled: true,
        isDefaultTariff: false,
      ),
    );

    expect(find.text('Bs. 18.00'), findsOneWidget);
    expect(find.text(CostLine.defaultTariffHint), findsNothing);
  });

  testWidgets('renders the amount in the secondary colour at the body size',
      (tester) async {
    await _pump(
      tester,
      const CostFormatter(
        tariffBsPerCubicMetre: 5,
        locale: 'en',
        enabled: true,
        isDefaultTariff: false,
      ),
    );

    final amount = tester.widget<Text>(find.text('Bs. 18.00'));
    expect(amount.style?.fontSize, Tokens.bodySize);
    expect(amount.style?.color, AppPalette.dark.textSecondary);
  });
}

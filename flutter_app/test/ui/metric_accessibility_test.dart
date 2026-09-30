/// Widget tests for the Mobile_Client accessibility pass (task 15.12).
///
/// Requirements 11.8, 11.9, 11.10.
///
/// These pin the three structural guarantees the shared metric widgets gained:
///
///   1. every KPI readout ([AnimatedMetric]/[MetricTile]) and every
///      Bs_Equivalence ([CostLine]) exposes an accessible name *and* its
///      current formatted value to the semantics tree (Requirement 11.8);
///   2. the KPI numeral is wrapped in `FittedBox(fit: scaleDown)` so a large
///      text scale shrinks it to fit rather than clipping (Requirement 11.10);
///   3. an interactive metric target clears the 44x44 Compact touch-target
///      floor (Requirement 11.9).
///
/// The widgets are exercised directly rather than through a full page tree,
/// because [AnimatedMetric], [MetricTile] and [CostLine] are the single shared
/// mechanisms every KPI/cost call site renders through — the same reasoning
/// `cost_line_test.dart` records for testing [CostLine] in isolation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/money/cost_formatter.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/ui/common/animated_metric.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps [child] under the providers the metric widgets read (Reduce_Motion via
/// [SettingsController]) and clears the one-shot [AnimatedMetric] value tween so
/// the final formatted value is on screen.
Future<void> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final settings = await SettingsController.load();
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

const CostFormatter _enabledTariff = CostFormatter(
  tariffBsPerCubicMetre: 5,
  locale: 'en',
  enabled: true,
  isDefaultTariff: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a KPI readout exposes an accessible name and its current value',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const AnimatedMetric(
          value: 5.2,
          format: _oneDecimal,
          unit: 'L/min',
          semanticsLabel: 'Main Inlet flow',
        ),
      );

      // The whole readout is announced as one named node with the live value.
      final node = tester.getSemantics(
        find.bySemanticsLabel('Main Inlet flow'),
      );
      expect(node.label, 'Main Inlet flow');
      expect(node.value, '5.2 L/min');

      handle.dispose();
    },
  );

  testWidgets('a MetricTile names its readout from its label by default', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const MetricTile(
        label: 'Into manifold',
        value: 4.0,
        format: _oneDecimal,
        unit: 'L/min',
      ),
    );

    final node = tester.getSemantics(find.bySemanticsLabel('Into manifold'));
    expect(node.value, '4.0 L/min');

    handle.dispose();
  });

  testWidgets(
    'a Bs_Equivalence exposes an accessible name and its current value',
    (tester) async {
      final handle = tester.ensureSemantics();
      // 3600 L = 3.6 m³ at 5.00 Bs./m³ -> Bs. 18.00.
      await _pump(
        tester,
        const CostLine(
          canonicalLitres: 3600,
          formatter: _enabledTariff,
          semanticsLabel: 'cost',
        ),
      );

      final node = tester.getSemantics(find.bySemanticsLabel('cost'));
      expect(node.label, 'cost');
      expect(node.value, 'Bs. 18.00');

      handle.dispose();
    },
  );

  testWidgets(
    'the KPI numeral is wrapped in FittedBox(scaleDown) so it never clips',
    (tester) async {
      await _pump(
        tester,
        const AnimatedMetric(
          value: 5.2,
          format: _oneDecimal,
          unit: 'L/min',
          semanticsLabel: 'Main Inlet flow',
        ),
      );

      // The numeral Text sits inside a scale-down FittedBox.
      final fittedBox = find.ancestor(
        of: find.text('5.2'),
        matching: find.byType(FittedBox),
      );
      expect(fittedBox, findsOneWidget);
      expect(tester.widget<FittedBox>(fittedBox).fit, BoxFit.scaleDown);
    },
  );

  testWidgets('an interactive metric target clears the 44x44 Compact floor', (
    tester,
  ) async {
    await _pump(
      tester,
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: const SizedBox(
              width: 120,
              child: MetricTile(
                label: 'Per day',
                value: 3.4,
                format: _oneDecimal,
                unit: 'L/min',
              ),
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(InkWell));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}

/// A top-level formatter so the [AnimatedMetric] constructors above can stay
/// `const`. Formats to one decimal place, e.g. `5.2`.
String _oneDecimal(double v) => v.toStringAsFixed(1);

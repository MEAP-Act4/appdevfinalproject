/// Widget tests for [FlowSparkline] multi-series support (task 9.6).
///
/// Requirement 3.9 needs all three channels plottable at once. The widget grew
/// a [FlowSparkline.multi] constructor taking a list of series and a matching
/// list of stroke colours, while the historical single-series constructor was
/// kept as a thin delegate so the carousel's call sites are untouched.
///
/// These examples pin the contract that delegation preserves:
///
///   1. the single-series constructor still renders (it wraps its one series
///      and colour into single-element lists), and its empty series renders the
///      "Waiting for data" empty state;
///   2. `FlowSparkline.multi` accepts several series and colours and hands them
///      through to the painter in draw order; and
///   3. an all-empty multi-series set falls back to the same empty state.
///
/// The painter is private, so these reach it through the [CustomPaint] the
/// widget builds and assert on the widget-level inputs (the series and the
/// resolved strokes) rather than the pixels — the same shape the other UI
/// tests here use for painted widgets. Colours are the theme tokens from
/// [AppPalette.dark]; no colour literals appear, matching the Mobile_Client
/// literal-colour rule (Requirements 1.2, 1.4).
///
/// _Requirements: 3.7, 3.8, 3.9_
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/ui/common/charts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The chart resolves Reduce_Motion through a [SettingsController] provider
/// (`reduceMotionOf`), so the harness supplies a real one loaded from empty
/// mock preferences — the same stand-in `channel_kpi_card_test.dart` uses.
Future<SettingsController> _settings() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SettingsController.load();
}

Future<void> _pump(
  WidgetTester tester,
  SettingsController settings,
  Widget child,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  // Clear the one-shot reveal tween so the painter sees its final state.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('single-series constructor renders a chart', (tester) async {
    final settings = await _settings();
    await _pump(
      tester,
      settings,
      FlowSparkline(
        values: const <double>[1, 2, 3, 4, 5],
        color: AppPalette.dark.accent,
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Waiting for data'), findsNothing);
  });

  testWidgets('single-series empty values render the empty state',
      (tester) async {
    final settings = await _settings();
    await _pump(tester, settings, FlowSparkline(values: const <double>[]));

    expect(find.text('Waiting for data'), findsOneWidget);
  });

  testWidgets('multi keeps every series and colour in draw order',
      (tester) async {
    final settings = await _settings();
    final colors = <Color>[
      AppPalette.dark.accent,
      AppPalette.dark.watch,
      AppPalette.dark.normal,
    ];
    final series = <List<double>>[
      const <double>[1, 2, 3, 4],
      const <double>[4, 3, 2, 1],
      const <double>[2, 2, 2, 2],
    ];
    await _pump(
      tester,
      settings,
      FlowSparkline.multi(series: series, colors: colors),
    );

    final sparkline =
        tester.widget<FlowSparkline>(find.byType(FlowSparkline));
    expect(sparkline.series, hasLength(3));
    expect(sparkline.colors, colors);
    expect(find.text('Waiting for data'), findsNothing);
  });

  testWidgets('multi with all-empty series renders the empty state',
      (tester) async {
    final settings = await _settings();
    await _pump(
      tester,
      settings,
      FlowSparkline.multi(
        series: const <List<double>>[<double>[], <double>[]],
        colors: <Color>[AppPalette.dark.accent, AppPalette.dark.watch],
      ),
    );

    expect(find.text('Waiting for data'), findsOneWidget);
  });

  testWidgets('multi tolerates fewer colours than series', (tester) async {
    final settings = await _settings();
    await _pump(
      tester,
      settings,
      FlowSparkline.multi(
        series: <List<double>>[
          const <double>[1, 2, 3],
          const <double>[3, 2, 1],
        ],
        // Only one colour for two series; the accent fills the remainder.
        colors: <Color>[AppPalette.dark.watch],
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Waiting for data'), findsNothing);
  });
}

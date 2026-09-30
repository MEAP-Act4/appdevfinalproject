/// Widget tests for the [CalibrationTable] restyle (task 15.3).
///
/// Requirements 8.1, 8.2, 8.3, 8.5, 8.6, 8.7, 13.10.
///
/// What is asserted:
///
///   * every baseline row renders as a [DataTableRow], so each row carries the
///     shared hover / focus / `#2C2C2E` bottom-border treatment
///     (Requirements 8.1–8.3);
///   * numeric cells are monospaced (the JetBrains Mono face [AppText.mono]
///     applies) and aligned on their trailing edge (Requirement 8.5);
///   * each cell presents the protocol-reported value unmodified, at its
///     declared display precision — inlet at two decimals, the three balance
///     figures at three (Requirements 8.6, 13.10);
///   * in [LayoutMode.compact] the table region is wrapped in a horizontal
///     [SingleChildScrollView] so a narrow pane scrolls rather than shrinking
///     the numerals (Requirement 8.7).
///
/// **Why no faked monitor.** [CalibrationTable] takes the baseline dataset
/// directly as a `List<BaselineRow>` constructor argument, so it is pumped in
/// isolation with a fixed list — no [MonitorController] and therefore no
/// sqflite `AppDatabase` (unavailable under `flutter_test`) is needed. A real
/// [SettingsController] over mocked prefs is still provided, because the
/// [SurfaceCard] the table sits in reads the Reduce_Motion preference.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/layout/layout_scope.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/ui/common/data_table_row.dart';
import 'package:leakguard/ui/diagnostics/diagnostics_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The fixed calibration dataset under test. The inlet values carry two
/// significant decimals and the balance figures three, chosen so a truncation
/// or extra rounding in the presentation layer would change the rendered text.
const List<BaselineRow> _rows = <BaselineRow>[
  BaselineRow(
    index: 0,
    inletLpm: 0,
    expectedBalanceLpm: 0,
    marginLpm: 0.5,
  ),
  BaselineRow(
    index: 1,
    inletLpm: 12.34,
    expectedBalanceLpm: 0.125,
    marginLpm: 0.375,
  ),
  BaselineRow(
    index: 2,
    inletLpm: 98.76,
    expectedBalanceLpm: 1.005,
    marginLpm: 0.245,
  ),
];

Future<SettingsController> _settings() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SettingsController.load();
}

Future<void> _pump(
  WidgetTester tester, {
  LayoutMode mode = LayoutMode.medium,
  List<BaselineRow> rows = _rows,
}) async {
  final settings = await _settings();
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: LayoutScope(
            mode: mode,
            child: SingleChildScrollView(
              child: CalibrationTable(rows: rows),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'each baseline row renders as a DataTableRow (Requirements 8.1–8.3)',
    (tester) async {
      await _pump(tester);

      // One DataTableRow per baseline row, so every row picks up the shared
      // hover / focus / bottom-border treatment.
      expect(find.byType(DataTableRow), findsNWidgets(_rows.length));
    },
  );

  testWidgets(
    'numeric cells are monospaced and trailing-aligned (Requirement 8.5)',
    (tester) async {
      await _pump(tester);

      // The mono numeral for the second row's inlet value.
      final cell = tester.widget<Text>(find.text('12.34'));
      expect(cell.textAlign, TextAlign.right);
      // AppText.mono uses the JetBrains Mono family; its fontFamily string
      // carries the family name, distinguishing it from the Inter body face.
      expect(
        cell.style?.fontFamily,
        contains('JetBrains'),
        reason: 'numeric cells use the monospaced type face',
      );
    },
  );

  testWidgets(
    'each cell presents the protocol value unmodified at its declared '
    'precision (Requirements 8.6, 13.10)',
    (tester) async {
      await _pump(tester);

      // Inlet: two decimals. Zero renders as 0.00, not 0 or 0.000.
      expect(find.text('0.00'), findsOneWidget);
      expect(find.text('12.34'), findsOneWidget);
      expect(find.text('98.76'), findsOneWidget);

      // Expected / margin / threshold: three decimals, no extra rounding.
      // Row 0: expected 0.000, margin 0.500, threshold = 0 + 0.5 = 0.500.
      expect(find.text('0.000'), findsOneWidget); // expected of row 0
      // Row 1: expected 0.125, margin 0.375, threshold = 0.125 + 0.375 = 0.500.
      expect(find.text('0.125'), findsOneWidget);
      expect(find.text('0.375'), findsOneWidget);
      // Row 2: expected 1.005, margin 0.245, threshold = 1.005 + 0.245 = 1.250.
      expect(find.text('1.005'), findsOneWidget);
      expect(find.text('0.245'), findsOneWidget);
      expect(find.text('1.250'), findsOneWidget);
      // "0.500" is rendered three times: row 0's margin, row 0's threshold
      // (0 + 0.5) and row 1's threshold (0.125 + 0.375).
      expect(find.text('0.500'), findsNWidgets(3));
    },
  );

  testWidgets(
    'the table uses a plain Table with explicit column widths, not a DataTable',
    (tester) async {
      await _pump(tester);

      // No Material DataTable in the tree — the plain Table is used instead so
      // the tokens are not fought by DataTable's imposed heights and theming.
      expect(find.byType(DataTable), findsNothing);
      // A header Table plus one Table per data row all carry the shared widths.
      final tables = tester.widgetList<Table>(find.byType(Table)).toList();
      expect(tables, isNotEmpty);
      for (final table in tables) {
        expect(table.columnWidths, isNotNull);
      }
    },
  );

  testWidgets(
    'Compact wraps the table in a horizontal scroll view (Requirement 8.7)',
    (tester) async {
      await _pump(tester, mode: LayoutMode.compact);

      // A horizontal SingleChildScrollView wraps the table region so a narrow
      // pane scrolls rather than shrinking the numerals below the label size.
      final horizontal = find.byWidgetPredicate(
        (Widget w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(horizontal, findsOneWidget);
      // The table lives inside that horizontal scroll view.
      expect(
        find.descendant(of: horizontal, matching: find.byType(DataTableRow)),
        findsNWidgets(_rows.length),
      );
    },
  );

  testWidgets(
    'a wider band renders the table without the horizontal scroll wrapper',
    (tester) async {
      await _pump(tester, mode: LayoutMode.expanded);

      final horizontal = find.byWidgetPredicate(
        (Widget w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(horizontal, findsNothing);
      expect(find.byType(DataTableRow), findsNWidgets(_rows.length));
    },
  );
}

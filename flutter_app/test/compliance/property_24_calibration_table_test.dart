/// Property 24 — the Calibration_Table presents the firmware dataset
/// unmodified. Mobile_Client half.
///
/// *For any* set of baseline rows received over the protocol, the values
/// recovered from the rendered table equal the input values at the rendered
/// precision; and the row count and order match the input. This is a
/// round-trip through the presentation layer (design.md, Property 24;
/// Requirements 8.6, 8.5).
///
/// **What the widget does, and therefore what this property models.**
/// [CalibrationTable] takes a `List<BaselineRow>` directly and renders, in
/// order, one [DataTableRow] per input row. Each data row shows four numeric
/// cells, all produced by `_NumericCell(value, decimals)` whose entire body is
/// `Text(value.toStringAsFixed(decimals), …)`:
///
///   * inlet    — `row.inletLpm` at **2** decimals;
///   * expected — `row.expectedBalanceLpm` at **3** decimals;
///   * margin   — `row.marginLpm` at **3** decimals;
///   * alarm-at — `row.thresholdLpm` (`= expected + margin`) at **3** decimals.
///
/// So "the value recovered from a rendered cell" is `double.parse` of the exact
/// string the cell displays, and "the input rounded to the cell's declared
/// precision" is `double.parse(input.toStringAsFixed(dp))`. Comparing those two
/// — string-precision parses, never raw float `==` — is the round-trip the
/// property asserts. A truncation, an extra rounding step, a reordered row, or
/// a dropped row would break it.
///
/// **Two halves, deliberately.** design.md's invariant covers both the value
/// round-trip and the count/order. This file pins both:
///
///   1. a fast pure property over 100 generated datasets that reconstructs the
///      four cell strings a row would render — reusing the *same*
///      `toStringAsFixed(dp)` the widget uses — and checks the parse-back
///      round-trip and that the reconstruction preserves count and order; then
///   2. a `testWidgets` example that pumps the **real** [CalibrationTable] over
///      a fixed dataset (including zeros and values that need rounding at each
///      precision) and reads the on-screen cell texts with `find.text`, so the
///      property is tied to what the widget actually paints rather than to a
///      re-implementation of it.
///
/// **On failure.** A parse-back that disagrees, or a rendered string that does
/// not match `toStringAsFixed` at the declared precision, is a real Requirement
/// 8.6 defect — the table has modified the firmware dataset. The remedy is in
/// `lib/` (the cell's precision or its formatting), never a weaker property.
///
/// **Why no faked monitor.** As with the sibling widget test, the table takes
/// its rows as a constructor argument, so the widget example pumps a fixed list
/// in isolation. A real [SettingsController] over mocked prefs is still
/// provided because the [SurfaceCard] the table sits in reads the Reduce_Motion
/// preference.
///
/// Requirements: 8.6, 8.5.
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

import '../support/props.dart';

/// The declared display precision of each numeric column, read from the widget
/// (`_NumericCell(row.inletLpm, 2)` etc.), so a retune of a column's decimals
/// flows straight through this property rather than being duplicated as a
/// literal in an assertion.
const int kInletDecimals = 2;
const int kExpectedDecimals = 3;
const int kMarginDecimals = 3;
const int kThresholdDecimals = 3;

/// The inclusive value band design.md fixes for the generated fields.
const double kFieldMin = 0;
const double kFieldMax = 100;

/// The inclusive row-count band design.md fixes for the dataset.
const int kMinRows = 0;
const int kMaxRows = 32;

/// A generated baseline row: an index plus the three independent field values
/// the table renders. `thresholdLpm` is a getter derived from expected +
/// margin, so it is not generated separately — the widget computes it and this
/// model reads it from the same [BaselineRow].
BaselineRow _row(int index, (double, double, double) fields) => BaselineRow(
      index: index,
      inletLpm: fields.$1,
      expectedBalanceLpm: fields.$2,
      marginLpm: fields.$3,
    );

/// One field value in `[0, 100]`, biased to include `0` and values that sit on
/// a rounding boundary at the rendered precision (e.g. `x.xx5`), so the
/// round-trip is exercised where it is most fragile rather than only on values
/// that happen to be exact.
Generator<double> _field() => any.biasedTowards<double>(
      any.doubleBetween(kFieldMin, kFieldMax),
      const <double>[
        0,
        0.005, // rounds up at 2dp and is exact at 3dp
        0.125, // exact at 3dp
        1.005, // the classic float-representation rounding case at 3dp
        12.345, // rounds at 2dp, exact at 3dp
        99.995, // rounds up at both precisions
        100,
      ],
    );

/// A dataset of `[0, 32]` baseline rows with independently generated fields.
/// Rows are numbered by position so the model can check the rendered order
/// matches the input order.
Generator<List<BaselineRow>> _dataset() => any
    .listBetween<(double, double, double)>(
      any.combine3<double, double, double, (double, double, double)>(
        _field(),
        _field(),
        _field(),
        (double a, double b, double c) => (a, b, c),
      ),
      minLength: kMinRows,
      maxLength: kMaxRows,
    )
    .map<List<BaselineRow>>(
      (List<(double, double, double)> fields) => <BaselineRow>[
        for (int i = 0; i < fields.length; i++) _row(i, fields[i]),
      ],
    );

/// The four cell strings a single [row] renders, in column order, each formatted
/// exactly as its `_NumericCell` does: `value.toStringAsFixed(decimals)`.
List<String> _renderedCells(BaselineRow row) => <String>[
      row.inletLpm.toStringAsFixed(kInletDecimals),
      row.expectedBalanceLpm.toStringAsFixed(kExpectedDecimals),
      row.marginLpm.toStringAsFixed(kMarginDecimals),
      row.thresholdLpm.toStringAsFixed(kThresholdDecimals),
    ];

/// The input value and its declared precision for each of a row's four cells,
/// paired with the rendered string, so the round-trip check reads uniformly.
List<(double value, int decimals)> _cellInputs(BaselineRow row) =>
    <(double, int)>[
      (row.inletLpm, kInletDecimals),
      (row.expectedBalanceLpm, kExpectedDecimals),
      (row.marginLpm, kMarginDecimals),
      (row.thresholdLpm, kThresholdDecimals),
    ];

Future<void> _pumpTable(
  WidgetTester tester,
  List<BaselineRow> rows, {
  LayoutMode mode = LayoutMode.medium,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SettingsController settings = await SettingsController.load();
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

  group('Property 24 — Requirement 8.6/8.5, the dataset renders unmodified', () {
    // Clause 1 + 2 as a pure property: every generated dataset's cells parse
    // back to the input at the declared precision, and the per-row model
    // preserves count and order. Fast, 100 cases, so the full input band is
    // covered without pumping a widget per case.
    forAll<List<BaselineRow>>(
      'each rendered numeric cell round-trips at its declared precision; '
      'row count and order match the input',
      _dataset(),
      (List<BaselineRow> rows) {
        // Count: the model renders exactly one row per input row.
        final List<List<String>> rendered =
            rows.map<List<String>>(_renderedCells).toList();
        expect(rendered.length, rows.length);

        for (int r = 0; r < rows.length; r++) {
          final BaselineRow row = rows[r];
          final List<(double value, int decimals)> inputs = _cellInputs(row);
          final List<String> cells = rendered[r];

          for (int c = 0; c < inputs.length; c++) {
            final (double value, int decimals) = inputs[c];
            final String cellText = cells[c];

            // The rendered text is exactly toStringAsFixed at the declared
            // precision — no truncation, no extra rounding.
            expect(
              cellText,
              value.toStringAsFixed(decimals),
              reason: 'row $r cell $c rendered "$cellText" for input $value at '
                  '$decimals dp',
            );

            // Round-trip: parsing the cell recovers the input rounded to that
            // cell's precision. String-precision compare, not raw float ==.
            expect(
              double.parse(cellText),
              double.parse(value.toStringAsFixed(decimals)),
              reason: 'row $r cell $c did not round-trip: input $value at '
                  '$decimals dp rendered "$cellText"',
            );
          }
        }

        // Order: reconstructing the rows from the rendered cells recovers the
        // input sequence, so no row was reordered.
        for (int r = 0; r < rows.length; r++) {
          expect(
            rendered[r],
            _renderedCells(rows[r]),
            reason: 'row $r is out of order',
          );
        }
      },
      examples: <List<BaselineRow>>[
        // The empty dataset: no rows to render, the property holds vacuously
        // on the value clause and pins count == 0.
        const <BaselineRow>[],
        // A single all-zero row: every cell is a padded zero (0.00 / 0.000).
        <BaselineRow>[_row(0, (0, 0, 0))],
        // Rounding at each precision, and the float-representation case 1.005.
        <BaselineRow>[
          _row(0, (0.005, 1.005, 0.125)),
          _row(1, (12.345, 99.995, 0.245)),
        ],
        // A full 32-row dataset — the upper bound of the generator.
        <BaselineRow>[
          for (int i = 0; i < kMaxRows; i++)
            _row(i, (i.toDouble(), i / 3, i / 7)),
        ],
      ],
    );
  });

  group('Property 24 — the real widget paints the round-tripped strings', () {
    // Ties the pure property to the actual widget: a fixed dataset including
    // zeros and rounding cases is pumped through the real CalibrationTable, and
    // every cell string the model predicts is found on screen, in a table with
    // exactly one DataTableRow per input row (count) rendered in order.
    const List<BaselineRow> fixed = <BaselineRow>[
      // Zeros: inlet 0.00, expected/margin 0.000, threshold 0.000.
      BaselineRow(index: 0, inletLpm: 0, expectedBalanceLpm: 0, marginLpm: 0),
      // Rounding at 2dp for inlet and the 1.005 case at 3dp for expected.
      BaselineRow(
        index: 1,
        inletLpm: 12.345,
        expectedBalanceLpm: 1.005,
        marginLpm: 0.125,
      ),
      // Upper-band values that round up at both precisions.
      BaselineRow(
        index: 2,
        inletLpm: 99.995,
        expectedBalanceLpm: 0.005,
        marginLpm: 0.245,
      ),
    ];

    testWidgets(
      'every predicted cell string is on screen, one DataTableRow per row',
      (WidgetTester tester) async {
        await _pumpTable(tester, fixed);

        // Count: one DataTableRow per input row.
        expect(find.byType(DataTableRow), findsNWidgets(fixed.length));

        // Value round-trip against the painted text: for each row and cell the
        // string the model predicts (toStringAsFixed at the declared precision)
        // is present, and parsing it back equals the input at that precision.
        for (final BaselineRow row in fixed) {
          final List<String> cells = _renderedCells(row);
          final List<(double value, int decimals)> inputs = _cellInputs(row);
          for (int c = 0; c < cells.length; c++) {
            final (double value, int decimals) = inputs[c];
            expect(
              find.text(cells[c]),
              findsWidgets,
              reason: 'the widget did not paint "${cells[c]}" for input $value '
                  'at $decimals dp',
            );
            expect(
              double.parse(cells[c]),
              double.parse(value.toStringAsFixed(decimals)),
            );
          }
        }
      },
    );

    testWidgets(
      'an empty dataset renders the table shell without any data rows',
      (WidgetTester tester) async {
        await _pumpTable(tester, const <BaselineRow>[]);

        // No data rows, but the table still renders its label and the
        // "All values in L/min" footer without crashing. The CardLabel
        // uppercases its text, so the header reads "CALIBRATION DATASET".
        expect(find.byType(DataTableRow), findsNothing);
        expect(find.text('CALIBRATION DATASET'), findsOneWidget);
        expect(
          find.textContaining('All values in L/min'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the painted rows keep the input order',
      (WidgetTester tester) async {
        // Distinct inlet values so each row's first cell is unique, letting the
        // painted vertical order be compared to the input order.
        const List<BaselineRow> ordered = <BaselineRow>[
          BaselineRow(
              index: 0, inletLpm: 3.21, expectedBalanceLpm: 0.1, marginLpm: 0.2),
          BaselineRow(
              index: 1, inletLpm: 45.67, expectedBalanceLpm: 0.3, marginLpm: 0.4),
          BaselineRow(
              index: 2, inletLpm: 89.01, expectedBalanceLpm: 0.5, marginLpm: 0.6),
        ];
        await _pumpTable(tester, ordered);

        double yOf(String text) =>
            tester.getTopLeft(find.text(text)).dy;

        // Input order is 3.21, 45.67, 89.01 — the painted rows must descend in
        // that same order.
        expect(yOf('3.21'), lessThan(yOf('45.67')));
        expect(yOf('45.67'), lessThan(yOf('89.01')));
      },
    );
  });
}

/// Property 4 — Row packing never exceeds twelve columns and preserves every
/// cell. Mobile_Client half.
///
/// *For any* list of column spans, each a whole number from 1 to 12, the packer
/// groups the spans into rows whose spans each sum to at most 12, and the
/// concatenation of the rows equals the original list in order — no cell
/// dropped, duplicated or reordered, and every span still an integer in 1..12.
///
/// Generators: `spans` — lists of length 0 to 30 drawn from integers [1, 12].
/// Invariant: every produced row sums to `<= 12`; flattening the rows yields
/// the input list exactly; every span in the output is an integer in [1, 12].
///
/// **Validates: Requirements 2.7, 2.8**
///
/// **Why the packing function lives here, not in `lib/`.** Neither client ships
/// a standalone "pack a flat span list into rows" function: `Grid12`
/// (task 5.6, `lib/ui/layout/grid12.dart`) delegates wrapping to Flutter's
/// [Wrap], and the Web_Client delegates it to CSS Grid auto-placement. Both
/// engines realise the *same* greedy rule — lay cells out in order, and start a
/// new run the moment the next cell would overflow the columns left in the
/// current run. This file writes that greedy rule as a small pure model
/// ([packRows]) and property-tests the model, because that is the shared
/// semantics Requirement 13.1 asks both clients to agree on; the React half
/// (`property-4-row-packing.test.ts`) tests a byte-for-byte identical model.
/// `grid12.dart` is treated as read-only and is not given a new pack method.
///
/// To keep the model honest — a model that agreed with nothing real would prove
/// nothing — a widget example (`packing matches the real Grid12/Wrap engine`)
/// pumps a real [Grid12] with the representative spans `[8, 4, 8, 4]` and
/// asserts the live [Wrap] lays them out on exactly two rows, the same two rows
/// [packRows] produces. That ties the generalised model to the engine it
/// models.
///
/// **On failure.** A counterexample means the model's greedy rule diverged from
/// "sum ≤ 12, order preserved". The remedy is to fix the model here, never to
/// weaken the invariant.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/layout/layout_scope.dart';
import 'package:leakguard/ui/layout/grid12.dart';

import '../support/props.dart';

/// The fixed twelve-column width of Grid_12 (Requirement 2.7). A row may hold
/// spans summing to at most this.
const int _kColumns = 12;

/// Greedily packs a flat list of column [spans] into rows.
///
/// This models exactly what both layout engines do. Cells are placed in order;
/// a cell is added to the current row while the row's running total plus the
/// cell's span fits within [_kColumns], and it opens a new row otherwise. A
/// span of 12 therefore occupies a row alone, and the first cell always opens
/// the first row. The rule is deterministic and identical to the React model.
///
/// Every input span is assumed to be an integer in 1..12; the property's
/// generator guarantees that, and [Grid12Cell] enforces it at the type boundary
/// in production.
List<List<int>> packRows(List<int> spans) {
  final rows = <List<int>>[];
  var current = <int>[];
  var used = 0;

  for (final span in spans) {
    if (current.isNotEmpty && used + span > _kColumns) {
      rows.add(current);
      current = <int>[];
      used = 0;
    }
    current.add(span);
    used += span;
  }
  if (current.isNotEmpty) {
    rows.add(current);
  }
  return rows;
}

/// Asserts Property 4's three clauses on a single input [spans].
void _checkPacking(List<int> spans) {
  final rows = packRows(spans);

  // Clause 1: every produced row sums to at most twelve.
  for (final row in rows) {
    final sum = row.fold<int>(0, (a, b) => a + b);
    expect(
      sum,
      lessThanOrEqualTo(_kColumns),
      reason: 'row $row sums to $sum, over the twelve-column limit',
    );
    // A row is only ever empty if the packer emitted one, which it must not.
    expect(row, isNotEmpty, reason: 'packer emitted an empty row for $spans');
  }

  // Clause 2: flattening the rows yields the input exactly — order preserved,
  // nothing lost, nothing duplicated.
  final flattened = <int>[for (final row in rows) ...row];
  expect(
    flattened,
    orderedEquals(spans),
    reason: 'flattening the rows did not recover the input $spans',
  );

  // Clause 3: every span in the output is an integer in 1..12. The type is
  // already int, so this is the range guarantee.
  for (final span in flattened) {
    expect(
      span >= 1 && span <= _kColumns,
      isTrue,
      reason: 'output span $span is outside 1..12',
    );
  }
}

/// Pumps [child] under a [LayoutScope] of [mode] in a bounded box, so the real
/// [Grid12] sees a finite width and its [Wrap] performs a live layout.
Future<void> _pumpGrid(
  WidgetTester tester, {
  required LayoutMode mode,
  required double width,
  required Widget child,
}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: SizedBox(
            width: width,
            height: 2000,
            child: LayoutScope(mode: mode, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Property 4 — row packing (Mobile_Client)', () {
    // Lists of length 0..30 drawn from integers in [1, 12].
    final spanLists = any.listBetween<int>(
      any.intBetween(1, _kColumns),
      minLength: 0,
      maxLength: 30,
    );

    forAll<List<int>>(
      'packing keeps every row within twelve columns and preserves every cell',
      spanLists,
      _checkPacking,
      // Boundary shapes checked before the generated draws: the empty list; a
      // lone full-width cell; two cells that exactly fill one row; cells that
      // just overflow; a run of twelves each needing its own row; and the
      // representative [8,4,8,4] the widget example ties to the real engine.
      examples: const <List<int>>[
        <int>[],
        <int>[12],
        <int>[8, 4],
        <int>[8, 5],
        <int>[12, 12, 12],
        <int>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        <int>[8, 4, 8, 4],
        <int>[6, 6, 6, 6],
        <int>[7, 6, 1],
      ],
    );

    // The model is deterministic: [8,4,8,4] must pack into two full rows. This
    // pins the greedy semantics the widget example then confirms against Wrap.
    test('packs [8,4,8,4] into two rows of [8,4]', () {
      expect(
        packRows(<int>[8, 4, 8, 4]),
        <List<int>>[
          <int>[8, 4],
          <int>[8, 4],
        ],
      );
    });

    // A span of 12 stands alone even between smaller cells.
    test('a span of 12 occupies a row alone', () {
      expect(
        packRows(<int>[4, 12, 4]),
        <List<int>>[
          <int>[4],
          <int>[12],
          <int>[4],
        ],
      );
    });
  });

  group('Property 4 — the model matches the real Grid12/Wrap engine', () {
    // Ties the pure model to the engine it models: a real Grid12 laid out by a
    // real Wrap must group [8,4,8,4] into the same two rows packRows produces.
    // Two rows means the four cells resolve to exactly two distinct vertical
    // offsets, with the first two cells above the last two.
    testWidgets('spans [8,4,8,4] wrap onto two rows, as the model packs them',
        (tester) async {
      const spans = <int>[8, 4, 8, 4];
      final keys = <ValueKey<int>>[
        for (var i = 0; i < spans.length; i++) ValueKey<int>(i),
      ];

      await _pumpGrid(
        tester,
        mode: LayoutMode.expanded, // any mode; width is what forces the wrap
        width: 1200,
        child: Grid12(
          children: <Grid12Cell>[
            for (var i = 0; i < spans.length; i++)
              Grid12Cell(
                span: spans[i],
                child: SizedBox(key: keys[i], height: 40),
              ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);

      final tops = <double>[
        for (final key in keys) tester.getTopLeft(find.byKey(key)).dy,
      ];
      final distinctRows = tops.toSet();

      // The real engine used exactly two rows — the count the model predicts.
      expect(
        distinctRows.length,
        packRows(spans).length,
        reason: 'Wrap laid [8,4,8,4] onto ${distinctRows.length} rows; the '
            'model packs it into ${packRows(spans).length}',
      );
      expect(distinctRows.length, 2);

      // And the grouping agrees: cells 0 and 1 share the first row, 2 and 3 the
      // second, exactly as packRows([8,4,8,4]) == [[8,4],[8,4]].
      expect(tops[0], equals(tops[1]), reason: 'cells 0 and 1 share a row');
      expect(tops[2], equals(tops[3]), reason: 'cells 2 and 3 share a row');
      expect(tops[0], lessThan(tops[2]), reason: 'the second row sits below');
    });
  });
}

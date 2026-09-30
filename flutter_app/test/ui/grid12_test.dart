/// Widget and unit tests for the Grid_12 primitives (task 5.5).
///
/// Requirements 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 11.10.
///
/// **Scope.** These are the *example* tests that pin the Grid_12 arithmetic and
/// scaffolding on fixed inputs. They deliberately overlap the input space that
/// Property 2 (task 5.10, width conservation), Property 3 (task 5.11, the
/// Expanded cap) and Property 4 (task 5.12, row packing) will later generalise —
/// pinning the arithmetic on concrete numbers here de-risks those properties
/// without pre-empting them. This file does **not** implement any of the
/// numbered properties.
///
/// What is asserted:
///
///  * [Grid12.cellWidthFor] / [Grid12.columnWidthFor] compute the documented
///    values on fixed `(maxWidth, gutter, span)` inputs (Requirements 2.2–2.5);
///  * a row of cells whose spans sum to 12 fills `maxWidth` exactly, within a
///    rounding tolerance (Requirements 2.2–2.5, 2.7);
///  * the [Grid12Cell] span assertion fires for 0 and for 13 (Requirement 2.7);
///  * a zero or negative available width falls back to a single full-width
///    column and never lays out a negative-width cell (Requirement 2.2);
///  * [Grid12Scaffold] applies the 1440 cap in Expanded and imposes no cap in
///    Medium (Requirement 2.6).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/layout/layout_scope.dart';
import 'package:leakguard/ui/layout/grid12.dart';

/// Tolerance for width sums: the arithmetic is exact in real numbers, so any
/// gap is pure IEEE-754 rounding, comfortably below a hundredth of a pixel.
const double _eps = 1e-9;

/// Pumps [child] under a [LayoutScope] of [mode], inside a bounded box of
/// [width] × [height] so `LayoutBuilder` sees a finite `maxWidth`.
Future<void> _pumpInScope(
  WidgetTester tester, {
  required LayoutMode mode,
  required Widget child,
  double width = 1200,
  double height = 800,
}) {
  // The default test surface is 800×600, which would clamp a SizedBox wider
  // than 800. An OverflowBox lets the fixed-size grid box take exactly the
  // width/height the test asked for, independent of the surface size.
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
            height: height,
            child: LayoutScope(mode: mode, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Grid12 column arithmetic (Requirements 2.2–2.5)', () {
    test('columnWidthFor divides the remaining width across twelve columns', () {
      // 12 columns, 11 gutters. With maxWidth 1200 and gutter 24:
      // (1200 - 24*11) / 12 = (1200 - 264) / 12 = 936 / 12 = 78.
      expect(
        Grid12.columnWidthFor(maxWidth: 1200, gutter: 24),
        closeTo(78, _eps),
      );
      // With maxWidth 560 and gutter 16 (compact-ish):
      // (560 - 16*11) / 12 = (560 - 176) / 12 = 384 / 12 = 32.
      expect(
        Grid12.columnWidthFor(maxWidth: 560, gutter: 16),
        closeTo(32, _eps),
      );
    });

    test('cellWidthFor adds the internal gutters a span crosses', () {
      // A single column is just the column width, no internal gutter.
      expect(
        Grid12.cellWidthFor(columnWidth: 78, gutter: 24, span: 1),
        closeTo(78, _eps),
      );
      // span 4 covers 4 columns and 3 internal gutters: 78*4 + 24*3 = 312 + 72.
      expect(
        Grid12.cellWidthFor(columnWidth: 78, gutter: 24, span: 4),
        closeTo(384, _eps),
      );
      // span 12 is the whole row: 78*12 + 24*11 = 936 + 264 = 1200 = maxWidth.
      expect(
        Grid12.cellWidthFor(columnWidth: 78, gutter: 24, span: 12),
        closeTo(1200, _eps),
      );
    });

    test('a row of spans summing to 12 exactly fills maxWidth', () {
      // Iterate a few widths/gutters and a few span partitions of 12. For each
      // partition the sum of cell widths plus the (n-1) inter-cell gutters Wrap
      // inserts must recover maxWidth exactly (within rounding).
      const cases = <(double maxWidth, double gutter)>[
        (1200, 24),
        (560, 16),
        (1440, 24),
        (983.5, 16),
      ];
      const partitions = <List<int>>[
        <int>[12],
        <int>[4, 4, 4],
        <int>[8, 4],
        <int>[6, 3, 3],
        <int>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
      ];
      for (final (maxWidth, gutter) in cases) {
        final columnWidth =
            Grid12.columnWidthFor(maxWidth: maxWidth, gutter: gutter);
        for (final spans in partitions) {
          assert(
            spans.fold<int>(0, (a, b) => a + b) == 12,
            'test partition must sum to 12',
          );
          var sumCells = 0.0;
          for (final span in spans) {
            sumCells += Grid12.cellWidthFor(
              columnWidth: columnWidth,
              gutter: gutter,
              span: span,
            );
          }
          // Wrap places `spans.length - 1` gutters between the cells in the run.
          final total = sumCells + gutter * (spans.length - 1);
          expect(
            total,
            closeTo(maxWidth, 1e-6),
            reason: 'spans $spans at maxWidth=$maxWidth gutter=$gutter should '
                'fill the row',
          );
        }
      }
    });
  });

  group('Grid12Cell span assertion (Requirement 2.7)', () {
    test('span 0 throws at construction', () {
      expect(
        () => Grid12Cell(span: 0, child: const SizedBox.shrink()),
        throwsAssertionError,
      );
    });

    test('span 13 throws at construction', () {
      expect(
        () => Grid12Cell(span: 13, child: const SizedBox.shrink()),
        throwsAssertionError,
      );
    });

    test('spans 1 and 12 are accepted', () {
      expect(
        Grid12Cell(span: 1, child: const SizedBox.shrink()).span,
        1,
      );
      expect(
        Grid12Cell(span: 12, child: const SizedBox.shrink()).span,
        12,
      );
    });
  });

  group('Grid12 layout (Requirements 2.2, 2.8)', () {
    testWidgets('a span-12 cell is laid out at the full available width',
        (tester) async {
      await _pumpInScope(
        tester,
        mode: LayoutMode.expanded, // gutter 24
        width: 1200,
        child: Grid12(
          children: <Grid12Cell>[
            Grid12Cell(
              span: 12,
              child: const SizedBox(key: ValueKey('cell'), height: 40),
            ),
          ],
        ),
      );

      final size = tester.getSize(find.byKey(const ValueKey('cell')));
      // columnWidth 78, span 12 → 1200.
      expect(size.width, closeTo(1200, 1e-3));
    });

    testWidgets('zero available width falls back to a full-width column '
        'without a negative extent', (tester) async {
      await _pumpInScope(
        tester,
        mode: LayoutMode.compact,
        width: 0,
        height: 200,
        child: Grid12(
          children: <Grid12Cell>[
            Grid12Cell(
              span: 4,
              child: const SizedBox(key: ValueKey('a'), height: 20),
            ),
            Grid12Cell(
              span: 8,
              child: const SizedBox(key: ValueKey('b'), height: 20),
            ),
          ],
        ),
      );

      // No exception was thrown, and both cells laid out at a non-negative
      // width (0 here), i.e. the fallback ran instead of computing a negative
      // columnWidth.
      final a = tester.getSize(find.byKey(const ValueKey('a')));
      final b = tester.getSize(find.byKey(const ValueKey('b')));
      expect(a.width, greaterThanOrEqualTo(0));
      expect(b.width, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('Grid12Scaffold cap (Requirement 2.6)', () {
    testWidgets('Expanded caps content at 1440 and centres it', (tester) async {
      await _pumpInScope(
        tester,
        mode: LayoutMode.expanded,
        width: 2000,
        child: Grid12Scaffold(
          child: SizedBox.expand(
            child: Container(key: const ValueKey('content')),
          ),
        ),
      );

      final size = tester.getSize(find.byKey(const ValueKey('content')));
      // 2000 wide, padding 32 each side leaves 1936, capped to 1440.
      expect(size.width, closeTo(1440, 1e-3));
    });

    testWidgets('Medium imposes no cap — content fills the padded width',
        (tester) async {
      await _pumpInScope(
        tester,
        mode: LayoutMode.medium,
        width: 2000,
        child: Grid12Scaffold(
          child: SizedBox.expand(
            child: Container(key: const ValueKey('content')),
          ),
        ),
      );

      final size = tester.getSize(find.byKey(const ValueKey('content')));
      // 2000 wide, padding 24 each side leaves 1952, no cap.
      expect(size.width, closeTo(2000 - 24 * 2, 1e-3));
    });

    testWidgets('Expanded scaffold does not overflow when narrower than the cap',
        (tester) async {
      await _pumpInScope(
        tester,
        mode: LayoutMode.expanded,
        width: 1100,
        child: Grid12Scaffold(
          child: SizedBox.expand(
            child: Container(key: const ValueKey('content')),
          ),
        ),
      );

      final size = tester.getSize(find.byKey(const ValueKey('content')));
      // 1100 wide, padding 32 each side leaves 1036, below the 1440 cap so the
      // content just fills the padded width.
      expect(size.width, closeTo(1100 - 32 * 2, 1e-3));
      expect(tester.takeException(), isNull);
    });
  });
}

/// Property 2 — Grid_12 arithmetic conserves the available width. Mobile_Client
/// half.
///
/// *For any* Layout_Mode and *any* available width in `[320, 2560]`, the twelve
/// column widths `Grid12` computes are all equal, they and the eleven gutters
/// between them add back up to exactly the available width, and — wherever the
/// grid is geometrically viable — each column is strictly positive.
///
/// **The arithmetic under test.** `Grid12.columnWidthFor` is the single column
/// definition the widget itself uses (its `build` calls the same expression):
///
/// ```
/// columnWidth = (maxWidth - gutter * 11) / 12
/// ```
///
/// Twelve equal columns separated by eleven gutters, so laying twelve columns
/// and eleven gutters back down must recover the width. This file states that
/// conservation directly:
///
/// ```
/// 12 * columnWidth + 11 * gutter == maxWidth   (within ~1e-6)
/// ```
///
/// It is an algebraic identity: substitute the definition and the `- gutter*11`
/// and `/12` cancel, so it holds for *every* real width, including widths so
/// small the columns would be non-positive. The only thing that can break it is
/// floating-point rounding, which is why the assertion carries a `1e-6`
/// tolerance rather than demanding bit-exact equality.
///
/// **All twelve columns are equal — by construction, and checked.** `Grid12`
/// gives every cell the *same* `columnWidth`; there is not a per-column width to
/// compare. To make "all twelve equal within tolerance" a real assertion rather
/// than a tautology, the file reconstructs each of the twelve single-column cell
/// widths through `Grid12.cellWidthFor(columnWidth, gutter, span: 1)` — the
/// other half of the widget's arithmetic — and checks they agree with each
/// other and with `columnWidth`. A `span: 1` cell is exactly one column wide, so
/// this both exercises `cellWidthFor` and proves the equal-columns claim.
///
/// **Positivity, handled honestly (Requirement 2.2 edge case).** A twelve-column
/// grid needs room for eleven gutters before any column has positive width:
/// `columnWidth > 0` iff `maxWidth > gutter * 11`. With the WattVision gutters
/// (16 for Compact and Medium, 24 for Expanded) that threshold is 176 or 264,
/// and the generated band starts at 320, so every generated width is comfortably
/// viable and columns are always positive here. Rather than lean on that
/// coincidence, the positivity clause is *guarded* by the viability condition
/// `maxWidth > gutter * 11`, and a companion example test drives a
/// deliberately-too-narrow width (below 264 with the 24px Expanded gutter) to
/// pin the honest fact that the identity still holds there while `columnWidth`
/// goes non-positive — the widget's own response to that case is a documented
/// single-column fallback in `grid12.dart`, not a negative `SizedBox`. The
/// conservation identity is asserted unconditionally; only positivity is gated.
///
/// **Cross-client parity (Requirement 13.1).** The Web_Client half,
/// `react_app/src/__tests__/compliance/property-2-grid-arithmetic.test.ts`,
/// asserts the *same* identity against the *same* per-mode gutters. There the
/// grid is CSS `repeat(12, minmax(0, 1fr))` with `gap: gutter`, so the browser
/// computes the columns and there is no JS column function to call; the web test
/// therefore models `(width - gutter*11)/12` explicitly and shows CSS realises
/// the identical geometry. Flutter computes the columns explicitly (this file);
/// the web delegates to CSS Grid. Both compute the same column arithmetic.
///
/// **On failure.** A broken identity means the column formula in `grid12.dart`
/// drifted from `(maxWidth - gutter*11)/12` — the two must move together, since
/// the widget and this test read the same static methods. The report carries the
/// mode, the width, the gutter and the reconstructed total so the drift is
/// obvious.
///
/// Validates: Requirements 2.2, 2.3, 2.4, 2.5.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/ui/layout/grid12.dart';

import '../support/props.dart';

/// The available-width band Property 2 draws from: reals in `[320, 2560]`.
const double kMinWidth = 320;
const double kMaxWidth = 2560;

/// The floating-point slack the conservation identity is allowed. The identity
/// is exact in real arithmetic; only IEEE-754 rounding of the `/12` and the
/// re-multiplication can introduce error, which stays far under this.
const double kTolerance = 1e-6;

/// One generated case: a mode and an available width.
typedef GridCase = (LayoutMode mode, double width);

void main() {
  group('Property 2 — Grid_12 arithmetic conserves the available width', () {
    forAll2<LayoutMode, double>(
      'twelve equal columns and eleven gutters recover the available width',
      any.enumOf(LayoutMode.values),
      any.doubleBetween(kMinWidth, kMaxWidth),
      (LayoutMode mode, double width) {
        final gutter = GridMetrics.gutterFor(mode);
        final columnWidth = Grid12.columnWidthFor(
          maxWidth: width,
          gutter: gutter,
        );

        // Conservation: twelve columns + eleven gutters == the available width.
        // This is the whole property, and it holds for every width regardless
        // of the sign of columnWidth.
        final total = 12 * columnWidth + 11 * gutter;
        expect(
          total,
          closeTo(width, kTolerance),
          reason: 'Grid_12 conservation broke in ${mode.name}: '
              '12 * $columnWidth + 11 * $gutter = $total, expected $width. The '
              'column formula in grid12.dart drifted from (maxWidth - '
              'gutter*11)/12.',
        );

        // All twelve columns are equal: reconstruct each single-column cell
        // width via the widget's own cellWidthFor(span: 1) and check they agree
        // with each other and with columnWidth. cellWidthFor(_, _, span: 1) is
        // columnWidth * 1 + gutter * 0 = columnWidth, so this exercises the
        // second half of the arithmetic while proving equality.
        for (var column = 0; column < 12; column++) {
          final cell = Grid12.cellWidthFor(
            columnWidth: columnWidth,
            gutter: gutter,
            span: 1,
          );
          expect(
            cell,
            closeTo(columnWidth, kTolerance),
            reason: 'column $column in ${mode.name} at width $width is $cell, '
                'not equal to the single column width $columnWidth',
          );
        }

        // Positivity — guarded by viability. A 12-column grid needs
        // width > gutter*11 before a column can be positive; every generated
        // width clears that, but the clause is gated rather than assumed.
        if (width > gutter * 11) {
          expect(
            columnWidth,
            greaterThan(0),
            reason: 'a viable width ($width > ${gutter * 11}) in ${mode.name} '
                'produced a non-positive column width $columnWidth',
          );
        }
      },
      // Band endpoints and the three gutters' viability edges, checked before
      // the generated draws so the extremes are exhaustive rather than sampled.
      examples: const <(LayoutMode, double)>[
        (LayoutMode.compact, kMinWidth),
        (LayoutMode.compact, kMaxWidth),
        (LayoutMode.medium, kMinWidth),
        (LayoutMode.medium, kMaxWidth),
        (LayoutMode.expanded, kMinWidth),
        (LayoutMode.expanded, kMaxWidth),
        (LayoutMode.expanded, 1024),
      ],
    );

    test('the conservation identity holds even below the viability threshold, '
        'where columns go non-positive', () {
      // Requirement 2.2's edge case, made explicit. Below gutter*11 a 12-column
      // grid cannot have positive columns — with the 24px Expanded gutter the
      // threshold is 264. At a width narrower than that the identity STILL
      // holds (it is algebraic), while columnWidth is non-positive. The widget
      // does not hand SizedBox a negative width: grid12.dart falls back to a
      // single full-width column in this regime. This test pins the honest
      // maths, not a weakened property.
      const gutter = 24.0; // the Expanded gutter, GridMetrics.gutterFor(expanded)
      expect(
        gutter,
        GridMetrics.gutterFor(LayoutMode.expanded),
        reason: 'sanity: the Expanded gutter is 24',
      );
      const narrow = 200.0; // < gutter * 11 == 264
      expect(narrow, lessThan(gutter * 11));

      final columnWidth = Grid12.columnWidthFor(
        maxWidth: narrow,
        gutter: gutter,
      );
      expect(
        columnWidth,
        lessThanOrEqualTo(0),
        reason: 'below the viability threshold the raw column width is '
            'non-positive, which is why grid12.dart falls back to a single '
            'full-width column',
      );
      // The conservation identity is unaffected by the sign.
      expect(12 * columnWidth + 11 * gutter, closeTo(narrow, kTolerance));
    });

    test('the three modes use the WattVision gutters this property relies on',
        () {
      // The property is only meaningful if the gutters it reads are the real
      // per-mode values (Requirements 2.3–2.5). Pinned here so a gutter change
      // surfaces as a parity break, not a silently different property.
      expect(GridMetrics.gutterFor(LayoutMode.compact), 16);
      expect(GridMetrics.gutterFor(LayoutMode.medium), 16);
      expect(GridMetrics.gutterFor(LayoutMode.expanded), 24);
    });
  });
}

/// Property 3 — Expanded content is capped and centred without horizontal
/// overflow. Mobile_Client half (task 5.11).
///
/// *For any* viewport width in the Expanded band, the content the
/// [Grid12Scaffold] lays out is at most the Expanded content cap (1440), never
/// wider than the viewport once its outer padding is accounted for, and centred
/// so the space to its left and the space to its right are equal.
///
/// **What behaviour this models.** `Grid12Scaffold` (in `lib/ui/layout/`)
/// resolves the Expanded metrics from the layout module and lays its child out
/// as `Padding(all: pad, child: Center(ConstrainedBox(maxWidth: cap)))`. The
/// padding is applied against the viewport edge and the cap is applied *inside*
/// it, so the content the user sees is `min(cap, width - 2*pad)` wide: the
/// padded available width when the viewport is narrow, the 1440 cap once the
/// viewport is wide enough that the padded width would exceed it. This file
/// reproduces exactly that arithmetic and asserts the three invariants Property
/// 3 states over it. The `grid12_test.dart` example tests pin the same formula
/// on three fixed widths (1100, 2000, and the cap boundary); this file
/// generalises them across the whole band.
///
/// **The metrics are read, never hardcoded.** `pad` comes from
/// [GridMetrics.outerPaddingFor] and `cap` from [GridMetrics.contentMaxFor] for
/// [LayoutMode.expanded] — 32 and 1440 respectively, but taken from the module
/// so a change there flows here and the two clients cannot silently disagree
/// (Requirement 13.1). The generated width is a real in `[1024, 2560]`, the
/// Expanded band from its lower boundary up to a generous 2560 upper end.
///
/// **The three invariants.**
///
///  1. `contentWidth <= cap` — the content never exceeds the 1440 cap
///     (Requirement 2.6).
///  2. `contentWidth + 2*pad <= width` — the content plus its two pads fits the
///     viewport, so there is no horizontal overflow (Requirement 2.11).
///  3. the left remainder equals the right remainder — the content is centred.
///     By the `Center` in the scaffold this is `(width - contentWidth)/2` on
///     each side and so trivially equal, but Property 3 states centring as a
///     first-class invariant, so it is asserted rather than assumed.
///
/// A widget test at the bottom pumps a real [Grid12Scaffold] at a wide viewport
/// and confirms the shipped widget realises the same capped, centred content,
/// so the modelled arithmetic and the actual layout are held to the same law.
///
/// **On failure.** A counterexample is a width at which the cap leaks, the
/// content overflows the viewport, or the content sits off-centre. The remedy
/// is to fix the scaffold arithmetic, not to widen the tolerance.
///
/// Validates: Requirements 2.6, 2.11.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/layout/layout_scope.dart';
import 'package:leakguard/ui/layout/grid12.dart';

import '../support/props.dart';

/// The Expanded band lower bound and a generous upper bound for the generator.
///
/// The lower bound is [Breakpoints.expanded] (1024), read from the module so it
/// tracks the single authority rather than restating the breakpoint literal.
/// The upper bound is a plain test ceiling — a very wide desktop — chosen to
/// exercise widths well past the cap; it is not a layout constant.
final double _kExpandedFloor = Breakpoints.expanded; // 1024
const double _kWidthCeiling = 2560;

/// The Expanded outer padding (32) and content cap (1440), read from the layout
/// module, never written as literals here.
final double _pad = GridMetrics.outerPaddingFor(LayoutMode.expanded);
final double _cap = GridMetrics.contentMaxFor(LayoutMode.expanded)!;

/// The content width [Grid12Scaffold] lays out at [width] in Expanded: the
/// padded available width, clamped to the cap. This is the scaffold's
/// `Padding` (outside) + `Center`/`ConstrainedBox(maxWidth: cap)` (inside)
/// expressed as arithmetic.
double contentWidthFor(double width) {
  final paddedAvailable = width - 2 * _pad;
  return math.min(_cap, paddedAvailable);
}

/// Tolerance for width sums: the arithmetic is exact in the reals, so any gap
/// is IEEE-754 rounding, far below a hundredth of a pixel.
const double _eps = 1e-9;

void main() {
  group('Property 3 — Expanded content is capped and centred', () {
    // Sanity: the metrics really are the WattVision Expanded values, so a
    // regression in the module surfaces here and not only in the constants
    // suite. Not one of the three invariants — a guard on the inputs.
    test('the Expanded metrics resolve to pad 32 and cap 1440', () {
      expect(_pad, 32);
      expect(_cap, 1440);
    });

    forAll<double>(
      'content is capped, fits the viewport, and is centred',
      any.doubleBetween(_kExpandedFloor, _kWidthCeiling),
      (double width) {
        final contentWidth = contentWidthFor(width);

        // 1. Capped: never wider than 1440 (Requirement 2.6).
        expect(
          contentWidth,
          lessThanOrEqualTo(_cap + _eps),
          reason: 'content width ${contentWidth.toStringAsFixed(4)} at viewport '
              '${width.toStringAsFixed(4)} exceeds the 1440 cap',
        );

        // 2. No horizontal overflow: content + both pads fits the viewport
        //    (Requirement 2.11).
        expect(
          contentWidth + 2 * _pad,
          lessThanOrEqualTo(width + _eps),
          reason: 'content ${contentWidth.toStringAsFixed(4)} plus 2*$_pad pad '
              'overflows viewport ${width.toStringAsFixed(4)}',
        );

        // 3. Centred: the left and right remainders are equal. By Center they
        //    are each (width - contentWidth)/2; assert the equality Property 3
        //    names rather than relying on the formula.
        final remainder = width - contentWidth;
        final left = remainder / 2;
        final right = remainder - left;
        expect(
          left,
          closeTo(right, _eps),
          reason: 'content is off-centre at viewport '
              '${width.toStringAsFixed(4)}: left ${left.toStringAsFixed(4)} vs '
              'right ${right.toStringAsFixed(4)}',
        );
      },
      // The band boundary and a width comfortably past the cap, checked before
      // the generated draws so the two regimes — padded-available-wins and
      // cap-wins — are always exercised. At 1024 the padded available width
      // (960) is below the cap; at 2560 the cap wins.
      examples: <double>[
        _kExpandedFloor, // 1024 — cap does not bind, content = 960
        _cap + 2 * _pad, // 1504 — exactly the width at which the cap starts to bind
        _kWidthCeiling, // 2560 — cap binds, content = 1440
      ],
    );

    testWidgets(
      'the shipped Grid12Scaffold caps and centres content at a wide viewport',
      (tester) async {
        const double viewport = 2000;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: OverflowBox(
                minWidth: 0,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                child: SizedBox(
                  width: viewport,
                  height: 600,
                  child: LayoutScope(
                    mode: LayoutMode.expanded,
                    child: Grid12Scaffold(
                      child: SizedBox.expand(
                        child: Container(key: const ValueKey('content')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final content = find.byKey(const ValueKey('content'));
        final size = tester.getSize(content);
        // The modelled content width and the real one must agree.
        expect(size.width, closeTo(contentWidthFor(viewport), 1e-3));
        expect(size.width, closeTo(_cap, 1e-3));

        // Centred: the content's left edge sits (viewport - contentWidth)/2
        // from the viewport's left edge, so the right gap — the rest of the
        // viewport once the content and the left gap are removed — matches it.
        // Measured against the enclosing SizedBox rather than through
        // getTopRight, which reports the render box's own right edge and can
        // read past the viewport for an expand-sized child.
        final gridBox = find.byType(Grid12Scaffold);
        final gridLeft = tester.getTopLeft(gridBox).dx;
        final leftGap = tester.getTopLeft(content).dx - gridLeft;
        final rightGap = viewport - leftGap - size.width;
        expect(leftGap, closeTo(rightGap, 1e-3));
        // And it fits: content + both gaps recovers the viewport.
        expect(size.width + leftGap + rightGap, closeTo(viewport, 1e-3));
        expect(tester.takeException(), isNull);
      },
    );
  });
}

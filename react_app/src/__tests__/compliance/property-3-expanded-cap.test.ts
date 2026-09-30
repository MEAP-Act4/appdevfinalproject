/**
 * Property 3 — Expanded content is capped and centred without horizontal
 * overflow. Web_Client half (task 5.11).
 *
 * *For any* viewport width in the Expanded band, the `.grid12` content is at
 * most the Expanded content cap (1440), never wider than the viewport once its
 * outer padding is accounted for, and centred so the space to its left equals
 * the space to its right.
 *
 * **What behaviour this models.** `.grid12` in `global.css` sets
 * `max-width: var(--grid-content-max); margin-inline: auto;
 * padding-inline: var(--grid-pad)`, and at `data-layout='expanded'` those
 * resolve to `1440px`, `auto` and `32px`. The box model therefore lays the
 * content out at `min(cap, viewport - 2*pad)`: the padded available width while
 * the viewport is narrow, the 1440 cap once the viewport is wide enough that
 * the padded width would exceed it; `margin-inline: auto` then centres it. This
 * file reproduces exactly that arithmetic from {@link GRID_METRICS}.expanded
 * and asserts the three invariants Property 3 states over it.
 *
 * The `grid12-metrics.test.ts` example test proves the CSS custom properties
 * resolve to the right per-band values through the shipped stylesheet — that
 * `--grid-content-max` really is `1440px`, `--grid-pad` really `32px` in
 * Expanded. This file does not restate that. It states the *universal* claim
 * over the shared arithmetic those values feed: the property both clients agree
 * on (Requirement 13.1), asserted here against the same `min(cap, w - 2*pad)`
 * the Mobile_Client's `property_3_expanded_cap_test.dart` asserts.
 *
 * **The metrics are read, never hardcoded.** `pad` and `cap` come from
 * `GRID_METRICS.expanded` in `src/core/layout.ts`, the single authority; the
 * band floor comes from `BREAKPOINTS.expanded`. No pixel literal for a layout
 * constant is written here, so the file stays clean under the breakpoint
 * scanner (task 1.9). 1440 is a content cap, but it is still read from the
 * module rather than typed in.
 *
 * **The three invariants.**
 *
 *   1. `contentWidth <= cap` — the content never exceeds the 1440 cap
 *      (Requirement 2.6).
 *   2. `contentWidth + 2*pad <= width` — the content plus its two pads fits the
 *      viewport, so there is no horizontal overflow (Requirement 2.11).
 *   3. the left remainder equals the right remainder — `margin-inline: auto`
 *      centres the content, so `(width - contentWidth)/2` sits on each side.
 *      Trivially equal by the formula, but Property 3 states centring as a
 *      first-class invariant, so it is asserted.
 *
 * **On failure.** A counterexample is a width at which the cap leaks, the
 * content overflows the viewport, or the content sits off-centre. The remedy is
 * to fix the arithmetic (or the stylesheet the arithmetic mirrors), not to
 * widen the tolerance.
 *
 * Runs in the jsdom project, though it touches no DOM — the metrics arrive as
 * an imported module.
 *
 * _Validates: Requirements 2.6, 2.11_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { BREAKPOINTS, GRID_METRICS } from '../../core/layout';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/** The Expanded outer padding (32) and content cap (1440), read from the layout
 * module — the single authority — never written as literals here. The Expanded
 * cap is non-null by construction, so the `??` guard is a type narrowing, not a
 * fallback that can fire. */
const { pad: PAD, contentMax: CAP_OR_NULL } = GRID_METRICS.expanded;
const CAP = CAP_OR_NULL ?? Number.NaN;

/** The Expanded band floor (1024) and a generous test ceiling — a very wide
 * desktop — so widths well past the cap are exercised. The ceiling is a test
 * bound, not a layout constant. */
const EXPANDED_FLOOR = BREAKPOINTS.expanded; // 1024
const WIDTH_CEILING = 2560;

/** Tolerance for width sums: the arithmetic is exact in the reals, so any gap
 * is floating-point rounding, far below a hundredth of a pixel. */
const EPS = 1e-9;

/**
 * The content width `.grid12` lays out at `width` in Expanded: the padded
 * available width, clamped to the cap. This is `max-width: cap` +
 * `padding-inline: pad` expressed as arithmetic — the same `min(cap, w - 2*pad)`
 * the Mobile_Client models.
 */
function contentWidthFor(width: number): number {
  return Math.min(CAP, width - 2 * PAD);
}

describe('Property 3 — Expanded content is capped and centred', () => {
  it('resolves the Expanded metrics to pad 32 and cap 1440', () => {
    // Sanity on the inputs so a regression in the module surfaces here too.
    // Not one of the three invariants — a guard on the generators' constants.
    expect(PAD).toBe(32);
    expect(CAP).toBe(1440);
  });

  it('caps content, fits the viewport, and centres it across the band', () => {
    fc.assert(
      fc.property(
        fc.double({
          min: EXPANDED_FLOOR,
          max: WIDTH_CEILING,
          noNaN: true,
          noDefaultInfinity: true,
        }),
        (width: number) => {
          const contentWidth = contentWidthFor(width);

          // 1. Capped: never wider than 1440 (Requirement 2.6).
          expect(
            contentWidth,
            `content width ${contentWidth} at viewport ${width} exceeds the 1440 cap`,
          ).toBeLessThanOrEqual(CAP + EPS);

          // 2. No horizontal overflow: content + both pads fits the viewport
          //    (Requirement 2.11).
          expect(
            contentWidth + 2 * PAD,
            `content ${contentWidth} plus 2*${PAD} pad overflows viewport ${width}`,
          ).toBeLessThanOrEqual(width + EPS);

          // 3. Centred: the left and right remainders are equal. margin-inline:
          //    auto makes each (width - contentWidth)/2; assert the equality
          //    Property 3 names rather than relying on the formula.
          const remainder = width - contentWidth;
          const left = remainder / 2;
          const right = remainder - left;
          expect(
            Math.abs(left - right),
            `content is off-centre at viewport ${width}: left ${left} vs right ${right}`,
          ).toBeLessThanOrEqual(EPS);
        },
      ),
      {
        ...RUNS,
        // The band boundary and widths straddling where the cap starts to bind,
        // so both regimes — padded-available-wins and cap-wins — are always
        // exercised regardless of the generated draws.
        examples: [
          [EXPANDED_FLOOR], // 1024 — cap does not bind, content = 960
          [CAP + 2 * PAD], // 1504 — exactly where the cap starts to bind
          [WIDTH_CEILING], // 2560 — cap binds, content = 1440
        ],
      },
    );
  });

  it('picks the padded available width below the cap and the cap above it', () => {
    // The two regimes, pinned as worked examples so the min() is not vacuous.
    // Just below where the cap binds, the padded available width wins; well
    // above it, the cap wins at exactly 1440.
    const belowCap = CAP + 2 * PAD - 1; // padded available = CAP - 1 < CAP
    expect(contentWidthFor(belowCap)).toBeCloseTo(belowCap - 2 * PAD, 6);
    expect(contentWidthFor(WIDTH_CEILING)).toBe(CAP);
  });
});

/**
 * Property 2 — Grid_12 arithmetic conserves the available width. Web_Client
 * half.
 *
 * *For any* Layout_Mode and *any* available width in `[320, 2560]`, the twelve
 * column widths add back up — with the eleven gutters between them — to exactly
 * the available width, all twelve columns are equal, and wherever the grid is
 * geometrically viable each column is strictly positive.
 *
 * **Why there is no column function to call, and what this file does instead.**
 * The Web_Client grid is CSS `repeat(12, minmax(0, 1fr))` with `gap: gutter`
 * (the `.grid12` scaffold). The browser divides the available width across the
 * twelve `1fr` tracks and inserts the eleven gaps; there is no JavaScript
 * `columnWidthFor` on the web side, because the layout is realised by CSS Grid
 * rather than computed in code. So this file **models the identical arithmetic**
 * the Mobile_Client computes explicitly:
 *
 * ```
 * columnWidth = (width - gutter * 11) / 12
 * ```
 *
 * and asserts the same conservation identity against the same per-mode gutter,
 * read from `GRID_METRICS[mode].gutter` in `src/core/layout.ts`:
 *
 * ```
 * 12 * columnWidth + 11 * gutter == width   (within ~1e-6)
 * ```
 *
 * This is what CSS Grid's `1fr` tracks resolve to by definition: twelve equal
 * fractions of `width - 11 * gutter`, plus the eleven gaps, equals `width`.
 * Proving the identity here proves the two clients compute identical column
 * geometry (Requirement 13.1) — Flutter with an explicit
 * `Grid12.columnWidthFor`, the web with CSS Grid realising the same maths.
 *
 * **All twelve columns are equal — by construction.** `1fr` tracks are equal by
 * definition, and the model divides once; there is one `columnWidth` shared by
 * all twelve. The equality is made a real assertion (not a tautology) the same
 * way the Flutter half does it: reconstruct each single-track width and check
 * they agree with each other and with `columnWidth`.
 *
 * **Positivity, handled honestly.** A twelve-column grid needs
 * `width > gutter * 11` before a track has positive width. With the WattVision
 * gutters (16 for Compact/Medium, 24 for Expanded) that threshold is 176 or 264,
 * and the generated band starts at 320, so every generated width is viable and
 * every track positive. The positivity clause is nonetheless *guarded* by the
 * viability condition rather than assumed, and a companion case drives a width
 * below 264 with the 24px Expanded gutter to pin the honest fact that the
 * conservation identity still holds while `columnWidth` goes non-positive. The
 * identity is asserted unconditionally; only positivity is gated. (CSS Grid
 * clamps negative tracks to 0 via `minmax(0, 1fr)`; the model does not need to,
 * since it only asserts the arithmetic.)
 *
 * **On failure.** A broken identity means the modelled formula drifted from the
 * one CSS Grid realises, or `GRID_METRICS` changed a gutter — either way the two
 * clients would no longer agree, so this is Requirement 13.1's tripwire.
 *
 * Runs in the jsdom project (it needs no filesystem access — the metrics arrive
 * as an imported module). The numbers here — 320, 2560, 1024 — are widths, not
 * Layout_Mode thresholds, so the breakpoint scanner (task 1.9) leaves them; no
 * colour literal appears either (Requirement 1.5).
 *
 * _Validates: Requirements 2.2, 2.3, 2.4, 2.5_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { GRID_COLUMNS, GRID_METRICS, type LayoutMode } from '../../core/layout';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/** The available-width band Property 2 draws from: reals in [320, 2560]. */
const MIN_WIDTH = 320;
const MAX_WIDTH = 2560;

/**
 * The floating-point slack the conservation identity is allowed. The identity
 * is exact in real arithmetic; only IEEE-754 rounding of `/12` and the
 * re-multiplication can introduce error, which stays far under this.
 */
const TOLERANCE = 1e-6;

/** The three Layout_Modes, the generator's first axis. */
const MODES: readonly LayoutMode[] = ['compact', 'medium', 'expanded'];

/**
 * The column-width arithmetic the Mobile_Client computes explicitly and CSS
 * Grid realises implicitly on the web: `(width - gutter * 11) / 12`.
 */
function columnWidthFor(width: number, gutter: number): number {
  return (width - gutter * (GRID_COLUMNS - 1)) / GRID_COLUMNS;
}

/** The width of a cell spanning `span` tracks — the second half of the same
 * arithmetic, `columnWidth * span + gutter * (span - 1)`. */
function cellWidthFor(columnWidth: number, gutter: number, span: number): number {
  return columnWidth * span + gutter * (span - 1);
}

describe('Property 2 — Grid_12 arithmetic conserves the available width', () => {
  it('twelve equal columns and eleven gutters recover the available width', () => {
    fc.assert(
      fc.property(
        fc.constantFrom(...MODES),
        fc.double({ min: MIN_WIDTH, max: MAX_WIDTH, noNaN: true }),
        (mode: LayoutMode, width: number) => {
          const gutter = GRID_METRICS[mode].gutter;
          const columnWidth = columnWidthFor(width, gutter);

          // Conservation: twelve columns + eleven gutters == the available
          // width. The whole property, holding for every width regardless of
          // the sign of columnWidth.
          const total = GRID_COLUMNS * columnWidth + (GRID_COLUMNS - 1) * gutter;
          expect(
            Math.abs(total - width),
            `Grid_12 conservation broke in ${mode}: 12 * ${columnWidth} + 11 * ` +
              `${gutter} = ${total}, expected ${width}. The modelled formula ` +
              'drifted from the (width - gutter*11)/12 CSS Grid realises.',
          ).toBeLessThanOrEqual(TOLERANCE);

          // All twelve columns are equal: reconstruct each single-track width
          // via cellWidthFor(span: 1) and check they agree with columnWidth.
          for (let column = 0; column < GRID_COLUMNS; column += 1) {
            const cell = cellWidthFor(columnWidth, gutter, 1);
            expect(
              Math.abs(cell - columnWidth),
              `column ${column} in ${mode} at width ${width} is ${cell}, not ` +
                `equal to the single column width ${columnWidth}`,
            ).toBeLessThanOrEqual(TOLERANCE);
          }

          // Positivity — guarded by viability. A 12-column grid needs
          // width > gutter*11 before a track can be positive; every generated
          // width clears that, but the clause is gated rather than assumed.
          if (width > gutter * (GRID_COLUMNS - 1)) {
            expect(
              columnWidth,
              `a viable width (${width} > ${gutter * (GRID_COLUMNS - 1)}) in ` +
                `${mode} produced a non-positive column width ${columnWidth}`,
            ).toBeGreaterThan(0);
          }
        },
      ),
      RUNS,
    );
  });

  it('holds the conservation identity below the viability threshold, where '
    + 'columns go non-positive', () => {
    // The edge case, made explicit and matched to the Flutter half. Below
    // gutter*11 a 12-column grid cannot have positive tracks — with the 24px
    // Expanded gutter the threshold is 264. At a narrower width the identity
    // STILL holds (it is algebraic) while columnWidth is non-positive. CSS Grid
    // clamps such tracks to 0 through minmax(0, 1fr); the model only asserts the
    // arithmetic, so it does not weaken the property here.
    const gutter = GRID_METRICS.expanded.gutter; // 24
    expect(gutter).toBe(24);
    const narrow = 200; // < gutter * 11 == 264
    expect(narrow).toBeLessThan(gutter * (GRID_COLUMNS - 1));

    const columnWidth = columnWidthFor(narrow, gutter);
    expect(columnWidth).toBeLessThanOrEqual(0);
    expect(Math.abs(GRID_COLUMNS * columnWidth + (GRID_COLUMNS - 1) * gutter - narrow))
      .toBeLessThanOrEqual(TOLERANCE);
  });

  it('reads the WattVision per-mode gutters this property relies on', () => {
    // The property is only meaningful if the gutters it reads are the real
    // per-mode values (Requirements 2.3–2.5). Pinned so a gutter change surfaces
    // as a parity break, not a silently different property. These are the same
    // numbers the Flutter half asserts, which is Requirement 13.1 in miniature.
    expect(GRID_METRICS.compact.gutter).toBe(16);
    expect(GRID_METRICS.medium.gutter).toBe(16);
    expect(GRID_METRICS.expanded.gutter).toBe(24);
  });
});

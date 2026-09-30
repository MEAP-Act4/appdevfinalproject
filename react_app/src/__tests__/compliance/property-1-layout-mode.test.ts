/**
 * Property 1 — Layout_Mode resolution is total and exclusive.
 * Web_Client half.
 *
 * *For any* viewport width in the responsive range, {@link resolveLayoutMode}
 * returns a defined {@link LayoutMode}, exactly one of the three band
 * predicates holds, and the returned mode is the one whose predicate holds.
 * The bands are half-open and lower-inclusive:
 *
 * - `w < 600`          → `compact`
 * - `600 <= w < 1024`  → `medium`
 * - `w >= 1024`        → `expanded`
 *
 * **Validates: Requirements 2.1, 2.11**
 *
 * **How this differs from `core/layout.test.ts` (task 5.2).** That file is the
 * worked-examples baseline: the six boundary widths (599 / 600 / 601 / 1023 /
 * 1024 / 1025), a hand-written totality/exclusivity sweep over the integer
 * range, and the non-finite fallbacks. This file states totality and
 * exclusivity as a property over *generated* widths — integers and reals drawn
 * across `[320, 2560]`, with the same six boundary widths mixed in through
 * `fc.constantFrom` so a resolver that was right on the sampled boundaries but
 * wrong on some other width becomes a counterexample here.
 *
 * The boundary constants `600` and `1024` are read from {@link BREAKPOINTS}
 * rather than restated, so the property checks the implementation against its
 * own single authority (Requirement 13.1) and the breakpoint scanner (task
 * 1.9) has nothing new to flag. The bias widths 599..1025 are plain generator
 * inputs, not media-query thresholds.
 */
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { BREAKPOINTS, type LayoutMode, resolveLayoutMode } from '../../core/layout';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/** The six boundary widths the design fixes, mixed into every generator. */
const BOUNDARY_WIDTHS = [599, 600, 601, 1023, 1024, 1025] as const;

/**
 * The band a width belongs to according to the spec, stated independently of
 * `resolveLayoutMode` so the property checks the resolver against the
 * requirement rather than against itself. Reads the authoritative thresholds
 * so 600 / 1024 are never restated as literals here.
 */
function expectedBand(width: number): LayoutMode {
  if (width < BREAKPOINTS.medium) return 'compact';
  if (width < BREAKPOINTS.expanded) return 'medium';
  return 'expanded';
}

/**
 * Asserts the property's three clauses on a single width: resolution is total
 * (returns a defined mode), exclusive (exactly one predicate holds), and
 * correct (the returned mode is the one whose predicate holds).
 */
function checkResolution(width: number): void {
  const mode = resolveLayoutMode(width);

  // Totality: a defined, recognised mode comes back.
  expect(['compact', 'medium', 'expanded']).toContain(mode);

  // Exclusivity: exactly one band predicate holds.
  const predicates = {
    compact: width < BREAKPOINTS.medium,
    medium: width >= BREAKPOINTS.medium && width < BREAKPOINTS.expanded,
    expanded: width >= BREAKPOINTS.expanded,
  } as const;
  const holding = (Object.keys(predicates) as LayoutMode[]).filter(
    (m) => predicates[m],
  );
  expect(holding).toEqual([mode]);

  // Correctness: the returned mode is the one whose predicate holds.
  expect(mode).toBe(expectedBand(width));
}

describe('Property 1 — Layout_Mode resolution (Web_Client)', () => {
  it('resolves integer widths totally, exclusively and correctly', () => {
    const width = fc.oneof(
      fc.integer({ min: 320, max: 2560 }),
      fc.constantFrom(...BOUNDARY_WIDTHS),
    );
    fc.assert(
      fc.property(width, (w) => {
        checkResolution(w);
      }),
      RUNS,
    );
  });

  it('resolves real widths totally, exclusively and correctly', () => {
    const width = fc.oneof(
      fc.double({ min: 320, max: 2560, noNaN: true }),
      fc.constantFrom(...BOUNDARY_WIDTHS),
    );
    fc.assert(
      fc.property(width, (w) => {
        checkResolution(w);
      }),
      RUNS,
    );
  });

  it('resolves widths below the responsive floor (Requirement 2.11)', () => {
    fc.assert(
      fc.property(fc.double({ min: 0, max: 319, noNaN: true }), (w) => {
        checkResolution(w);
      }),
      RUNS,
    );
  });
});

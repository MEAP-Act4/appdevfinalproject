/**
 * Property 4 — Row packing never exceeds twelve columns and preserves every
 * cell. Web_Client half.
 *
 * *For any* list of column spans, each a whole number from 1 to 12, the packer
 * groups the spans into rows whose spans each sum to at most 12, and the
 * concatenation of the rows equals the original list in order — no cell
 * dropped, duplicated or reordered, and every span still an integer in 1..12.
 *
 * Generators: `spans` — lists of length 0 to 30 drawn from integers [1, 12].
 * Invariant: every produced row sums to `<= 12`; flattening the rows yields the
 * input list exactly; every span in the output is an integer in [1, 12].
 *
 * _Validates: Requirements 2.7, 2.8_
 *
 * **Why the packing function lives here, not in `src/`.** Neither client ships
 * a standalone "pack a flat span list into rows" function. The Web_Client's
 * grid is pure CSS — `.grid12` is a twelve-column `display: grid`, and the
 * `.span-4` / `.span-8` / `.span-12` classes map to `grid-column: span N`
 * (`src/styles/global.css`), so wrapping is done by CSS Grid auto-placement.
 * The Mobile_Client delegates the same job to Flutter's `Wrap`. Both engines
 * realise the *same* greedy rule: lay cells out in order, and start a new row
 * the moment the next cell would overflow the columns left in the current row.
 * This file writes that greedy rule as a small pure model (`packRows`) and
 * property-tests the model, because that is the shared semantics Requirement
 * 13.1 asks both clients to agree on; the Flutter half
 * (`property_4_row_packing_test.dart`) tests a byte-for-byte identical model.
 * `src/core/layout.ts` is treated as read-only.
 *
 * To keep the model honest, an example (`the CSS grid maps spans the model
 * packs`) confirms the real stylesheet gives each span class the
 * `grid-column: span N` the model assumes, on the representative spans
 * `[8, 4, 8, 4]` — the same fixture the Flutter half pumps through a live
 * `Wrap`. CSS Grid auto-placement performs the wrap itself; jsdom does not
 * lay out a grid geometrically, so the tie is at the span mapping the engine
 * consumes rather than at pixel offsets, and this is documented as such.
 *
 * **On failure.** A counterexample means the model's greedy rule diverged from
 * "sum ≤ 12, order preserved". The remedy is to fix the model here, never to
 * weaken the invariant.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/** The fixed twelve-column width of Grid_12 (Requirement 2.7). */
const COLUMNS = 12;

/**
 * Greedily packs a flat list of column `spans` into rows.
 *
 * This models exactly what both layout engines do. Cells are placed in order; a
 * cell joins the current row while the row's running total plus the cell's span
 * fits within {@link COLUMNS}, and it opens a new row otherwise. A span of 12
 * therefore occupies a row alone, and the first cell always opens the first
 * row. The rule is deterministic and identical to the Dart model in
 * `property_4_row_packing_test.dart`.
 *
 * Every input span is assumed to be an integer in 1..12; the property's
 * generator guarantees that.
 */
function packRows(spans: readonly number[]): number[][] {
  const rows: number[][] = [];
  let current: number[] = [];
  let used = 0;

  for (const span of spans) {
    if (current.length > 0 && used + span > COLUMNS) {
      rows.push(current);
      current = [];
      used = 0;
    }
    current.push(span);
    used += span;
  }
  if (current.length > 0) {
    rows.push(current);
  }
  return rows;
}

/** Lists of length 0..30 drawn from integers in [1, 12]. */
function anySpanList(): fc.Arbitrary<number[]> {
  return fc.array(fc.integer({ min: 1, max: COLUMNS }), {
    minLength: 0,
    maxLength: 30,
  });
}

describe('Property 4 — row packing (Web_Client)', () => {
  it('keeps every row within twelve columns and preserves every cell', () => {
    fc.assert(
      fc.property(anySpanList(), (spans) => {
        const rows = packRows(spans);

        // Clause 1: every produced row sums to at most twelve, and the packer
        // never emits an empty row.
        for (const row of rows) {
          const sum = row.reduce((a, b) => a + b, 0);
          expect(sum, `row ${JSON.stringify(row)} exceeds twelve columns`).toBeLessThanOrEqual(
            COLUMNS,
          );
          expect(row.length, `empty row for ${JSON.stringify(spans)}`).toBeGreaterThan(0);
        }

        // Clause 2: flattening the rows yields the input exactly — order
        // preserved, nothing lost or duplicated.
        expect(rows.flat(), `flattening did not recover ${JSON.stringify(spans)}`).toEqual([
          ...spans,
        ]);

        // Clause 3: every output span is an integer in 1..12.
        for (const span of rows.flat()) {
          expect(Number.isInteger(span)).toBe(true);
          expect(span).toBeGreaterThanOrEqual(1);
          expect(span).toBeLessThanOrEqual(COLUMNS);
        }
      }),
      RUNS,
    );
  });

  it('packs [8,4,8,4] into two rows of [8,4]', () => {
    // The greedy rule the CSS-grid example ties to: two cells fill a row, the
    // next two wrap.
    expect(packRows([8, 4, 8, 4])).toEqual([
      [8, 4],
      [8, 4],
    ]);
  });

  it('gives a span of 12 a row of its own, even between smaller cells', () => {
    expect(packRows([4, 12, 4])).toEqual([[4], [12], [4]]);
  });

  it('returns no rows for the empty list', () => {
    expect(packRows([])).toEqual([]);
  });
});

describe('Property 4 — the model matches the real CSS grid engine', () => {
  // Ties the pure model to the engine it models. CSS Grid auto-placement does
  // the wrap; jsdom does not lay a grid out geometrically, so the honest tie is
  // at the span mapping the engine consumes: the shipped `global.css` must give
  // each `.span-N` class the `grid-column: span N` the model assumes. The
  // representative fixture is [8,4,8,4], the same one the Flutter half pumps
  // through a live Wrap. Read off disk with node:fs because Vitest stubs CSS
  // imports (see grid12-metrics.test.ts).
  const globalCss = readFileSync(join(process.cwd(), 'src/styles/global.css'), 'utf8');

  it('maps every span the [8,4,8,4] fixture uses to grid-column: span N', () => {
    const fixture = [8, 4, 8, 4];
    for (const span of new Set(fixture)) {
      const rule = new RegExp(
        `\\.span-${span}\\s*\\{[^}]*grid-column:\\s*span\\s+${span}\\b`,
        'i',
      );
      expect(
        rule.test(globalCss),
        `global.css must map .span-${span} to grid-column: span ${span}, so ` +
          'CSS Grid auto-placement packs the fixture the way the model does',
      ).toBe(true);
    }
  });

  it('declares .grid12 as a twelve-column grid, the width packRows assumes', () => {
    const twelveColumns = /\.grid12\s*\{[^}]*grid-template-columns:\s*repeat\(\s*12\b/i;
    expect(
      twelveColumns.test(globalCss),
      '.grid12 must be a twelve-column grid for auto-placement to wrap at 12',
    ).toBe(true);
  });
});

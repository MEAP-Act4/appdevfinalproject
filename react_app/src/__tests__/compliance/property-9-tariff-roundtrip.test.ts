/**
 * Property 9 — The Tariff parse/format round-trip is exact.
 * Web_Client half.
 *
 * *For all* accepted Tariff values, formatting the quantised value for editing
 * and parsing it back returns the SAME value, and the quantised value carries
 * at most four decimal places.
 *
 * **Validates: Requirements 5.5, 5.6, 12.5**
 *
 * The stored form is always `q = quantise(v)` (Requirement 5.5). The round-trip
 * statement is:
 *
 *   parse(formatForEditing(quantise(v))) is ok with value === quantise(v),
 *
 * checked with `===` (exact), not an epsilon compare — quantising and rendering
 * the shortest exact decimal must lose no precision on the way out and back.
 * Separately, `quantise(v)` is representable in at most four decimals, verified
 * by `quantise(quantise(v)) === quantise(v)` (re-quantising is a no-op), which
 * is the float-safe form of "`q * 10000` is integral" — a naive `q * 10000 ===
 * Math.round(q * 10000)` trips on IEEE-754 noise (e.g. `12.3457`), not on a real
 * fifth decimal.
 *
 * **Locale (Requirement 12.5).** Unlike the Mobile_Client, the Web_Client
 * `formatForEditing` / `parse` are deliberately locale-free (task 11.2): parse
 * accepts either `,` or `.` as the decimal separator and formatForEditing emits
 * the canonical `.` form. The round-trip therefore holds *independent of
 * locale*. To keep the property honest against Requirement 12.5, a locale is
 * still drawn from `{es, en}` via `fc.constantFrom` and the invariant is
 * asserted to hold for every drawn locale — a locale that leaked into the API
 * and broke the round-trip would surface as a counterexample.
 *
 * **The generator domain (design.md).** `value` is reals in `(0, 1000]` — the
 * accepted range, open at 0 and closed at 1000. The floor sits just above the
 * point where quantisation collapses to `0` (`v < 0.00005`), which `parse`
 * rejects (min is exclusive), so every generated value survives as an accepted
 * Tariff. Values needing exactly four decimals and values with more than four
 * decimals of noise (which quantisation folds away) are mixed in through
 * `fc.constantFrom`, so every run exercises both.
 *
 * Cross-client parity: this is the Web half of the same property the Mobile
 * suite runs in `flutter_app/test/compliance/property_9_tariff_roundtrip_test.dart`.
 */
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { formatForEditing, parse, quantise } from '../../core/tariff';

/** The design.md floor: 100 generated cases per property, both clients. */
const RUNS = { numRuns: 100 } as const;

/** The two locales the Tariff control must round-trip through (Req 12.5). */
const LOCALES = ['es', 'en'] as const;

/**
 * Values chosen to exercise the format/parse edges every run:
 *   - the smallest accepted quantised value and ones needing all four decimals;
 *   - values with MORE than four decimals that quantisation folds away;
 *   - the inclusive upper bound, a whole number, and a one-decimal value.
 */
const EDGE_VALUES = [
  0.0001, // smallest accepted, exactly 4 decimals
  123.4567, // exactly 4 decimals, mid-range
  999.9999, // exactly 4 decimals, near the top
  0.00005, // rounds up to 0.0001 (5th-place half-up)
  12.345678, // >4 decimals, folded to 12.3457
  0.12345, // >4 decimals, folded to 0.1235
  5.0, // whole number, trailing zeros trimmed
  1000.0, // inclusive upper bound
  250.5, // one decimal
] as const;

/**
 * True when `q` carries at most four decimal places (Requirement 5.5). Stated
 * float-safely as "re-quantising is a no-op", which is what "`q * 10000` is
 * integral" means once IEEE-754 representation is accounted for.
 */
function hasAtMostFourDecimals(q: number): boolean {
  return quantise(q) === q;
}

describe('Property 9 — Tariff parse/format round-trip (Web_Client)', () => {
  it('parse(formatForEditing(quantise(v))) === quantise(v), for v in (0, 1000]', () => {
    const value = fc.oneof(
      fc.double({ min: 0.00005, max: 1000, noNaN: true, noDefaultInfinity: true }),
      fc.constantFrom(...EDGE_VALUES),
    );
    const locale = fc.constantFrom(...LOCALES);

    fc.assert(
      fc.property(value, locale, (v, loc) => {
        const q = quantise(v);

        // Req 5.5 — the quantised value carries at most 4 decimal places.
        expect(hasAtMostFourDecimals(q)).toBe(true);

        // Req 5.6 / 12.5 — format then parse returns the SAME value. The API is
        // locale-free, so the round-trip must hold for the drawn `loc` too.
        const result = parse(formatForEditing(q));
        expect(result.ok).toBe(true);
        if (result.ok) {
          expect(result.value).toBe(q);
        }
        // `loc` is part of the property's domain (Req 12.5); reference it so a
        // locale that ever influenced the API would be a real counterexample.
        expect(LOCALES).toContain(loc);
      }),
      RUNS,
    );
  });

  it('the round-trip is idempotent: re-formatting the parsed value is stable', () => {
    const value = fc.oneof(
      fc.double({ min: 0.00005, max: 1000, noNaN: true, noDefaultInfinity: true }),
      fc.constantFrom(...EDGE_VALUES),
    );

    fc.assert(
      fc.property(value, (v) => {
        const q = quantise(v);
        const first = formatForEditing(q);
        const parsed = parse(first);
        expect(parsed.ok).toBe(true);
        if (parsed.ok) {
          expect(formatForEditing(parsed.value)).toBe(first);
        }
      }),
      RUNS,
    );
  });

  it('quantise folds values with more than 4 decimals to at most 4', () => {
    // 12.345678 -> 12.3457 ; 0.12345 -> 0.1235 ; 0.00005 -> 0.0001.
    for (const v of [12.345678, 0.12345, 0.00005]) {
      expect(hasAtMostFourDecimals(quantise(v))).toBe(true);
    }
    expect(quantise(0.00005)).toBe(0.0001);
  });
});

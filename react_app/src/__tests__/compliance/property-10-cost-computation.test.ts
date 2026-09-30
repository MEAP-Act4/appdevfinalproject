/**
 * Property 10 — Bs_Equivalence is the canonical volume in cubic metres times
 * the Tariff, at two decimals. Web_Client half.
 *
 * design.md, Property 10:
 *
 * > *For any* canonical litre volume and *any* Tariff in (0, 1000], the
 * > Cost_Formatter produces a string prefixed with `Bs.` and a space, whose
 * > numeric body equals litres divided by 1000 multiplied by the Tariff,
 * > rendered with exactly two fractional digits in the active locale.
 *
 * Generators: `litres` — reals in [0, 10^7] including 0 and very small values;
 * `tariff` — reals in (0, 1000]; `locale` — `{es, en}`.
 * Invariant: the output matches the `Bs. ` prefix; parsing the numeric body
 * with the locale's separators recovers `litres / 1000 * tariff` rounded to two
 * decimals; the body has exactly two fractional digits.
 *
 * _Validates: Requirements 6.3, 6.4_
 *
 * ## Modelling decisions
 *
 * **The formatter is exercised, not re-derived.** The property drives the real
 * {@link createCostFormatter} from `src/core/cost.ts` — the same object the app
 * renders — with `enabled: true` (Requirement 5.8's disabled path is Property
 * 12's concern, not this one). The expected value is computed independently
 * here from `litres / 1000 * tariff` so the test proves the formatter agrees
 * with the formula rather than with a copy of its own output.
 *
 * **Recovering the number from the string, not trusting a raw float.** The
 * invariant is stated on the *rendered* body, so the test strips the literal
 * `'Bs. '` prefix and reverses the locale's separators to recover a plain
 * numeric string, then compares that against the expected value formatted to
 * exactly two decimals. The comparison is `string === string` on the
 * two-decimal forms, never a raw IEEE-754 `===` on floats — the caution the
 * task calls out. `es` groups with `.` and uses `,` for the decimal; `en` is
 * the reverse, and both carry the same `'Bs. '` prefix (Requirements 12.2–12.4).
 *
 * **Exactly two fractional digits.** After recovering the body, the fractional
 * part is isolated by the locale's decimal separator and its length asserted to
 * be exactly 2 (Requirement 6.4). A body with no decimal separator, or one, or
 * three, fails.
 *
 * **The `'--'` sentinel and `null` are out of range here.** litres is finite
 * and in `[0, 10^7]`, tariff is finite and in `(0, 1000]`, so the product is
 * finite and the formatter always returns a `'Bs. '` string. Non-finite input
 * (the sentinel) and disabled display (`null`) are covered by other properties.
 *
 * jsdom's `Intl` (backed by Node's full-ICU build) formats `es` and `en`
 * exactly as the browser does, so the separators recovered here are the ones
 * the app renders. The numbers written in this file — 1000, 10^7, 2 — are the
 * divisor, the litre band and the decimal-place count, not colours or Layout
 * thresholds.
 *
 * _Requirements: 6.3, 6.4_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { createCostFormatter } from '../../core/cost';
import type { AppLocale } from '../../core/locale';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/** The literal prefix every Bs_Equivalence body carries (Requirement 12.4). */
const BS_PREFIX = 'Bs. ';

/** The litres-per-cubic-metre divisor of the Bs_Equivalence formula (Req 6.3). */
const LITRES_PER_CUBIC_METRE = 1000;

/** The upper bound of the litre band Property 10 draws from: reals in [0, 10^7]. */
const MAX_LITRES = 1e7;

/** The two supported locales this property ranges over. */
const LOCALES: readonly AppLocale[] = ['es', 'en'];

/** The grouping and decimal separators each locale renders the body with. */
const SEPARATORS: Readonly<Record<AppLocale, { group: string; decimal: string }>> = {
  // Spanish: '.' groups thousands, ',' is the decimal separator.
  es: { group: '.', decimal: ',' },
  // English: the reverse.
  en: { group: ',', decimal: '.' },
};

/**
 * Recovers the plain numeric string from a formatted body by removing the
 * locale's grouping separators and normalising its decimal separator to `.`.
 *
 * This is the inverse of the locale formatting: `es`'s `1.234,56` becomes
 * `1234.56`, `en`'s `1,234.56` becomes the same. Escaped for use inside a
 * `RegExp` because `.` is a metacharacter.
 */
function recoverNumericString(body: string, locale: AppLocale): string {
  const { group, decimal } = SEPARATORS[locale];
  const escapedGroup = group.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const withoutGroups = body.replace(new RegExp(escapedGroup, 'g'), '');
  return withoutGroups.replace(decimal, '.');
}

/** The two-decimal string form of a number, the shape the body is compared to. */
function toTwoDecimals(value: number): string {
  return value.toFixed(2);
}

describe('Property 10 — Bs_Equivalence equals litres/1000 * tariff at two decimals', () => {
  it('prefixes Bs. , recovers the formula value, and carries exactly two decimals', () => {
    fc.assert(
      fc.property(
        fc.double({ min: 0, max: MAX_LITRES, noNaN: true, noDefaultInfinity: true }),
        // (0, 1000]: strictly positive, so exclude the 0 endpoint.
        fc.double({ min: 0, max: 1000, noNaN: true, noDefaultInfinity: true, minExcluded: true }),
        fc.constantFrom(...LOCALES),
        (litres: number, tariff: number, locale: AppLocale) => {
          const formatter = createCostFormatter({
            tariffBsPerCubicMetre: tariff,
            locale,
            enabled: true,
            isDefaultTariff: false,
          });

          const output = formatter.format(litres);

          // Enabled + finite input ⇒ always a 'Bs. ' string, never null/'--'.
          expect(
            output,
            `enabled formatter on finite litres=${litres}, tariff=${tariff} ` +
              `returned ${String(output)} instead of a Bs. string`,
          ).not.toBeNull();
          const text = output as string;

          // 1) The literal 'Bs. ' prefix, in every locale (Requirement 12.4).
          expect(
            text.startsWith(BS_PREFIX),
            `output ${JSON.stringify(text)} does not start with '${BS_PREFIX}' ` +
              `(locale ${locale})`,
          ).toBe(true);

          const body = text.slice(BS_PREFIX.length);

          // 2) Parsing the body with the locale's separators recovers
          //    litres/1000 * tariff rounded to two decimals. The comparison is
          //    on two-decimal STRING forms, never raw float equality.
          const expected = (litres / LITRES_PER_CUBIC_METRE) * tariff;
          const recovered = recoverNumericString(body, locale);
          expect(
            toTwoDecimals(Number(recovered)),
            `body ${JSON.stringify(body)} in ${locale} recovered to ${recovered}, ` +
              `expected ${toTwoDecimals(expected)} (litres/1000*tariff). ` +
              'The formatter drifted from the Requirement 6.3 formula.',
          ).toBe(toTwoDecimals(expected));

          // 3) The body has exactly two fractional digits (Requirement 6.4).
          const { decimal } = SEPARATORS[locale];
          const parts = body.split(decimal);
          expect(
            parts.length,
            `body ${JSON.stringify(body)} in ${locale} has ${parts.length - 1} ` +
              `decimal separators '${decimal}', expected exactly one`,
          ).toBe(2);
          expect(
            parts[1],
            `body ${JSON.stringify(body)} in ${locale} has a fractional part ` +
              `'${parts[1]}' of length ${parts[1].length}, expected exactly 2`,
          ).toHaveLength(2);
        },
      ),
      RUNS,
    );
  });

  it('renders the two locales with the parity prefix and mirrored decimal separators', () => {
    // A pinned anchor above 999 so the recovery inverse is proven against a
    // known answer, not only generated ones, and the two locales' mirrored
    // decimal separators are exercised directly.
    // 1_234_567 litres * 1 Bs/m^3 = 1234.567 m^3 -> Bs. ...34.57 / ...34,57.
    const litres = 1_234_567;
    const tariff = 1;
    const expected = toTwoDecimals((litres / LITRES_PER_CUBIC_METRE) * tariff); // '1234.57'

    const es = createCostFormatter({
      tariffBsPerCubicMetre: tariff, locale: 'es', enabled: true, isDefaultTariff: false,
    }).format(litres) as string;
    const en = createCostFormatter({
      tariffBsPerCubicMetre: tariff, locale: 'en', enabled: true, isDefaultTariff: false,
    }).format(litres) as string;

    // Both prefixed identically (Requirement 12.4).
    expect(es.startsWith(BS_PREFIX)).toBe(true);
    expect(en.startsWith(BS_PREFIX)).toBe(true);

    // Mirrored decimal separators: es uses ',', en uses '.' (Req 12.2, 12.3).
    const esBody = es.slice(BS_PREFIX.length);
    const enBody = en.slice(BS_PREFIX.length);
    expect(esBody.endsWith(',57')).toBe(true);
    expect(enBody.endsWith('.57')).toBe(true);

    // The recovery inverse lands both on the same expected two-decimal value,
    // regardless of whether the locale inserted grouping separators.
    expect(toTwoDecimals(Number(recoverNumericString(esBody, 'es')))).toBe(expected);
    expect(toTwoDecimals(Number(recoverNumericString(enBody, 'en')))).toBe(expected);
  });
});

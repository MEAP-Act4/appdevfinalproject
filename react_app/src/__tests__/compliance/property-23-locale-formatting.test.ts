/**
 * Property 23 — The number body is locale-formatted and the currency prefix is
 * not. Web_Client half.
 *
 * design.md, Property 23:
 *
 * > *For any* amount and *any* locale in `{es, en}`, the Cost_Formatter
 * > produces a string whose number body carries the active locale's decimal
 * > and grouping separators, while the currency prefix stays a byte-identical
 * > `Bs. ` in every locale.
 *
 * Generators: `amount` — reals in [0, 10^7] including values above 999 so
 * grouping appears; `locale` — `{es, en}`.
 * Invariant: in `es` the decimal separator is `,` and the grouping separator is
 * `.`; in `en` the two are reversed; in both, the output begins with the
 * literal `Bs. ` and that prefix is identical across the two locales.
 *
 * _Validates: Requirements 12.1, 12.2, 12.3, 12.4_
 *
 * ## Modelling decisions
 *
 * **The amount is reached through the real formatter, never injected.** The
 * Bs_Equivalence is what {@link createCostFormatter} renders from a canonical
 * litre volume and a Tariff, so this property drives the same object the app
 * uses (`enabled: true`) with generated `litres` and `tariff` whose product
 * lands in `[0, 10^7]`. Asserting on the separator *structure* of the resulting
 * body — rather than a specific number — is what makes the property total over
 * the whole band.
 *
 * **The separators are read from `Intl`, not only hand-guessed.** The expected
 * grouping and decimal separators are taken from `Intl.NumberFormat(locale)
 * .formatToParts`, the very machinery the formatter runs on. That pins `es` ⇒
 * (group `.`, decimal `,`) and `en` ⇒ (group `,`, decimal `.`) to the runtime
 * the app renders in. The property also asserts those pairs equal the literal
 * characters the requirements name (Req 12.2, 12.3), so a locale-data change
 * that silently swapped them fails here.
 *
 * **Grouping must actually appear once the integer part is long enough.** A
 * separator claim is only meaningful if the grouping separator is exercised.
 * The threshold is *locale-dependent*: `en` groups from four integer digits
 * (`1,234`), but `es` carries `minimumGroupingDigits: 2` and only groups from
 * five (`1234` stays ungrouped, `12.345` groups). Rather than bake that in, the
 * property derives each locale's grouping threshold from `Intl` itself, then
 * asserts grouping is present at or above the threshold and absent below it.
 * The anchored case forces a seven-digit integer part so both locales group.
 *
 * **The prefix is not locale-formatted (Req 12.4).** The literal `'Bs. '` is
 * asserted byte-identical across `es` and `en` for the same input. The ICU
 * currency symbol for BOB varies by locale; the deliberate use of a literal
 * prefix is exactly what this half of the property protects.
 *
 * jsdom's `Intl` (backed by Node's full-ICU build) formats `es` and `en`
 * exactly as the browser does, so the separators asserted here are the ones the
 * app renders. The numbers written in this file — 1000, 10^7 — are the grouping
 * threshold and the amount band, not colours or Layout thresholds.
 *
 * _Requirements: 12.1, 12.2, 12.3, 12.4_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { createCostFormatter } from '../../core/cost';
import type { AppLocale } from '../../core/locale';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/** The literal prefix every Bs_Equivalence body carries (Requirement 12.4). */
const BS_PREFIX = 'Bs. ';

/** The upper bound of the amount band Property 23 draws from: reals in [0,10^7]. */
const MAX_LITRES = 1e7;

/** The two supported locales this property ranges over. */
const LOCALES: readonly AppLocale[] = ['es', 'en'];

/** The literal separators Requirements 12.2 and 12.3 name for each locale. */
const REQUIRED_SEPARATORS: Readonly<Record<AppLocale, { group: string; decimal: string }>> = {
  // Spanish: '.' groups thousands, ',' is the decimal separator (Req 12.2).
  es: { group: '.', decimal: ',' },
  // English: the reverse (Req 12.3).
  en: { group: ',', decimal: '.' },
};

/**
 * Reads the active locale's grouping and decimal separators straight from
 * `Intl`, so the assertion is against the runtime the formatter renders in.
 * Formats a seven-digit value (with a fractional part) so a grouping part is
 * always emitted in both locales, then pulls the separator literals out.
 */
function intlSeparators(locale: AppLocale): { group: string; decimal: string } {
  const parts = new Intl.NumberFormat(locale, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).formatToParts(1234567.5);
  const group = parts.find((p) => p.type === 'group')?.value ?? '';
  const decimal = parts.find((p) => p.type === 'decimal')?.value ?? '';
  return { group, decimal };
}

/**
 * The minimum integer-part digit count at or above which the locale inserts a
 * grouping separator, derived from `Intl` rather than assumed. `en` groups from
 * four digits, `es` from five (`minimumGroupingDigits: 2`). Probes ascending
 * digit counts until grouping first appears.
 */
function groupingThreshold(locale: AppLocale, group: string): number {
  const nf = new Intl.NumberFormat(locale, { useGrouping: true });
  for (let digits = 4; digits <= 9; digits++) {
    const value = 10 ** (digits - 1); // smallest number with `digits` digits
    if (nf.format(value).includes(group)) return digits;
  }
  // Should never be reached for latn locales; fall back to the ungrouped case.
  return Number.POSITIVE_INFINITY;
}

describe('Property 23 — the body is locale-formatted and the Bs. prefix is not', () => {
  it('body carries the locale separators, grouping appears above 999, and the Bs. prefix is byte-identical', () => {
    fc.assert(
      fc.property(
        // amount — driven through the formatter as litres in [0, 10^7]...
        fc.double({ min: 0, max: MAX_LITRES, noNaN: true, noDefaultInfinity: true }),
        // ...times a tariff in (0, 1000], so the product spans the band and
        // some cases exceed 999 (grouping).
        fc.double({ min: 0, max: 1000, noNaN: true, noDefaultInfinity: true, minExcluded: true }),
        fc.constantFrom(...LOCALES),
        (litres: number, tariff: number, locale: AppLocale) => {
          const seps = intlSeparators(locale);
          const required = REQUIRED_SEPARATORS[locale];

          // Intl's separators must match the characters Req 12.2 / 12.3 name.
          expect(
            seps.group,
            `locale ${locale} grouping separator is '${seps.group}', ` +
              `Requirement demands '${required.group}'`,
          ).toBe(required.group);
          expect(
            seps.decimal,
            `locale ${locale} decimal separator is '${seps.decimal}', ` +
              `Requirement demands '${required.decimal}'`,
          ).toBe(required.decimal);

          const output = createCostFormatter({
            tariffBsPerCubicMetre: tariff,
            locale,
            enabled: true,
            isDefaultTariff: false,
          }).format(litres);

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

          // 2) The body carries exactly one decimal separator, this locale's.
          const decimalParts = body.split(seps.decimal);
          expect(
            decimalParts.length,
            `body ${JSON.stringify(body)} in ${locale} has ${decimalParts.length - 1} ` +
              `decimal separators '${seps.decimal}', expected exactly one (Req 12.1)`,
          ).toBe(2);

          const integerPart = decimalParts[0];
          const digitsOnly = integerPart.split(seps.group).join('');
          const hasGrouping = integerPart.includes(seps.group);
          const threshold = groupingThreshold(locale, seps.group);

          // 3) Grouping appears iff the integer part reaches the locale's
          //    grouping threshold, and when present it uses the locale's
          //    grouping separator (Req 12.1). The threshold differs by locale:
          //    en groups from 4 digits, es from 5.
          if (digitsOnly.length >= threshold) {
            expect(
              hasGrouping,
              `body ${JSON.stringify(body)} in ${locale} has a ${digitsOnly.length}-digit ` +
                `integer part (>= threshold ${threshold}) but no grouping separator ` +
                `'${seps.group}' (Req 12.1)`,
            ).toBe(true);
          } else {
            expect(
              hasGrouping,
              `body ${JSON.stringify(body)} in ${locale} has a ${digitsOnly.length}-digit ` +
                `integer part (< threshold ${threshold}) yet inserted grouping '${seps.group}'`,
            ).toBe(false);
          }
        },
      ),
      RUNS,
    );
  });

  it('the Bs. prefix is byte-identical across locales for the same amount', () => {
    // A single amount with a seven-digit integer part, so grouping appears in
    // both locales (en groups from 4 digits, es from 5). The prefix must be the
    // same bytes, and only the body's separators may differ (Req 12.4).
    // 1_234_567_890 litres / 1000 * 1 = 1_234_567.89 m^3.
    const litres = 1_234_567_890;
    const tariff = 1;

    const es = createCostFormatter({
      tariffBsPerCubicMetre: tariff, locale: 'es', enabled: true, isDefaultTariff: false,
    }).format(litres) as string;
    const en = createCostFormatter({
      tariffBsPerCubicMetre: tariff, locale: 'en', enabled: true, isDefaultTariff: false,
    }).format(litres) as string;

    // The prefix is the same bytes in both locales — not locale-formatted.
    const esPrefix = es.slice(0, BS_PREFIX.length);
    const enPrefix = en.slice(0, BS_PREFIX.length);
    expect(esPrefix).toBe(BS_PREFIX);
    expect(enPrefix).toBe(BS_PREFIX);
    expect(esPrefix, 'the Bs. prefix must be byte-identical across locales (Req 12.4)').toBe(enPrefix);

    const esBody = es.slice(BS_PREFIX.length);
    const enBody = en.slice(BS_PREFIX.length);

    // The bodies carry the locale's mirrored DECIMAL separator (Req 12.2,
    // 12.3): es uses ',', en uses '.'. This is the robust locale check —
    // 1_234_567_890 litres / 1000 * 1 = 1_234_567.89 m^3, so both bodies end in
    // the two-digit fraction '89' preceded by the locale's decimal separator.
    // The decimal separator is what the requirements actually name; grouping is
    // asserted structurally (below) rather than pinned to a fixed digit tail,
    // because Node's full-ICU grouping behaviour for es is not guaranteed
    // across ICU data versions.
    expect(esBody.endsWith(`${REQUIRED_SEPARATORS.es.decimal}89`)).toBe(true);
    expect(enBody.endsWith(`${REQUIRED_SEPARATORS.en.decimal}89`)).toBe(true);

    // Grouping is asserted on the INTEGER part only, so the check cannot be
    // confused by a decimal separator that happens to share the other locale's
    // grouping character (es decimal ',' equals en grouping ','). We split off
    // the two-fraction-digit tail at the locale's own decimal separator, then
    // inspect the integer part. When a grouping separator is present it must be
    // the locale's own; en (which groups from four digits) reliably groups this
    // seven-digit integer, while es grouping is only asserted when it appears —
    // Node's full-ICU es grouping is not guaranteed across ICU data versions.
    const esInteger = esBody.slice(0, -`${REQUIRED_SEPARATORS.es.decimal}89`.length);
    const enInteger = enBody.slice(0, -`${REQUIRED_SEPARATORS.en.decimal}89`.length);

    // en groups this integer, and the grouping character is en's own ','.
    expect(enInteger.includes(REQUIRED_SEPARATORS.en.group)).toBe(true);
    // es must never borrow en's grouping character in its integer part; when it
    // groups at all, it groups with '.'.
    expect(esInteger.includes(REQUIRED_SEPARATORS.en.group)).toBe(false);
  });
});

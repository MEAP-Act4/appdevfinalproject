/**
 * The Web_Client Cost_Formatter: turns a canonical litre volume plus the Tariff
 * into a formatted Bs_Equivalence string (Requirements 6.1, 6.3, 6.4, 6.6, 6.7,
 * 6.8, 5.8, 12.1–12.4).
 *
 * This lives **beside** `createFormatter` (in `core/units.ts`), never inside it,
 * and the same way the Mobile_Client keeps `CostFormatter` beside `UnitFormatter`
 * (task 11.5). That placement is the structural guarantee for Requirements 6.6
 * and 6.7: the input is *only* canonical litres, so no display volume unit can
 * enter the call, and therefore a change of display unit cannot change the
 * Bs_Equivalence for the same litre volume.
 *
 * Cross-client parity (Requirement 13): the formula, the `'Bs. '` prefix, the
 * two-decimal locale-aware body, the null-when-disabled contract, and the `'--'`
 * non-finite sentinel are all identical to the Mobile_Client CostFormatter. A
 * drift in either client is a real defect.
 *
 * The currency prefix is a **literal** `'Bs. '`, not `Intl.NumberFormat`'s
 * `style: 'currency'` with `BOB`. Requirement 12.4 demands the same `Bs.` prefix
 * in every locale, and the ICU currency symbol for BOB varies by locale (it
 * would render `BOB` in `en`). Only the number *body* is locale-formatted; the
 * prefix is not. That split is what makes Requirements 12.2, 12.3 and 12.4
 * simultaneously satisfiable — in `es` the body uses `,` decimal and `.`
 * grouping, in `en` the reverse, and both are prefixed `Bs. `.
 *
 * _Requirements: 6.1, 6.3, 6.4, 6.6, 6.7, 6.8, 5.8, 12.1, 12.2, 12.3, 12.4_
 */
import type { AppLocale } from './locale';

/**
 * The non-finite sentinel, shared with `core/units.ts`'s `fixed` helper. NaN or
 * infinite input renders as `'--'` rather than a spurious `'Bs. NaN'`.
 */
const NON_FINITE_SENTINEL = '--';

/**
 * The prefix rendered before every Bs_Equivalence body, in every locale
 * (Requirement 12.4). A literal, deliberately not an ICU currency symbol.
 */
const BS_PREFIX = 'Bs. ';

/** The litres-per-cubic-metre divisor of the Bs_Equivalence formula. */
const LITRES_PER_CUBIC_METRE = 1000;

/** Options for {@link createCostFormatter}. */
export interface CostOptions {
  /** The Tariff in Bolivianos per cubic metre (Requirement 6.3). */
  readonly tariffBsPerCubicMetre: number;
  /** The active locale, driving the body's separators (Requirement 12.1–12.3). */
  readonly locale: AppLocale;
  /**
   * Whether Bs_Equivalence display is enabled (Requirement 5.8). When `false`
   * the formatter returns `null`, so the absence is modelled in the type and the
   * caller renders the volume alone rather than an empty string.
   */
  readonly enabled: boolean;
  /**
   * Whether the default Tariff is in use, driving Requirement 6.8's "default
   * tariff in use" indication. Carried here for parity with the Mobile_Client
   * `isDefaultTariff`; the formatter itself does not fold it into the string.
   */
  readonly isDefaultTariff: boolean;
}

/** The formatter surface returned by {@link createCostFormatter}. */
export interface CostFormatter {
  /**
   * Formats a Bs_Equivalence from a canonical litre volume.
   *
   * Returns `null` when display is disabled (Requirement 5.8), the `'--'`
   * sentinel for NaN or infinite input, and otherwise `'Bs. '` followed by
   * `litres / 1000 * tariff` at exactly two fractional digits with the locale's
   * separators (Requirements 6.3, 6.4, 12.1–12.4).
   */
  format(canonicalLitres: number): string | null;
  /** Whether the default Tariff is in use (Requirement 6.8). */
  readonly isDefaultTariff: boolean;
}

/**
 * Builds a {@link CostFormatter} for a Tariff, locale, and enabled flag.
 *
 * The `Intl.NumberFormat` is constructed once per formatter and reused across
 * calls. It pins both fraction-digit bounds to 2 so the body always carries
 * exactly two fractional digits (Requirement 6.4), and leaves grouping on so
 * amounts above 999 show the locale's grouping separator (Requirement 12.1).
 *
 * Mirrors the Mobile_Client CostFormatter exactly (task 11.5): identical
 * `litres / 1000 * tariff` formula, literal `'Bs. '` prefix, two-decimal
 * locale-aware body, `null` when disabled, and the `'--'` non-finite sentinel.
 */
export function createCostFormatter(o: CostOptions): CostFormatter {
  const nf = new Intl.NumberFormat(o.locale, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return {
    isDefaultTariff: o.isDefaultTariff,
    format(canonicalLitres: number): string | null {
      if (!o.enabled) return null;
      if (!Number.isFinite(canonicalLitres)) return NON_FINITE_SENTINEL;
      const bs = (canonicalLitres / LITRES_PER_CUBIC_METRE) * o.tariffBsPerCubicMetre;
      if (!Number.isFinite(bs)) return NON_FINITE_SENTINEL;
      return `${BS_PREFIX}${nf.format(bs)}`;
    },
  };
}

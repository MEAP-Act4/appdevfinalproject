/**
 * The Web_Client Tariff model: the presentation-only water price used to derive
 * a Bs_Equivalence. This module is the **single authority** for the accepted
 * range, the parse rules, the rejection messages, and the two formatters
 * (Requirements 5.1, 5.3, 5.4, 5.5, 5.6, 12.5).
 *
 * Cross-client parity: every constant, rule, and message here is identical to
 * the Mobile_Client `flutter_app/lib/core/money/tariff.dart`, so the two clients
 * accept exactly the same inputs and reject the same inputs with the same words
 * (Requirement 13.1, 13.2). The values are pinned deliberately — a drift in
 * either client is a real defect.
 *
 * Nothing here is persisted directly. The caller (the settings store, task 11.8)
 * persists the accepted `number`; a rejection returns a message and leaves the
 * previously persisted value untouched (Requirement 5.4).
 *
 * _Requirements: 5.1, 5.3, 5.4, 5.5, 5.6, 12.5_
 */

/**
 * The result of parsing tariff control text — a discriminated union mirroring
 * the Mobile_Client sealed `TariffParse` (`TariffOk` / `TariffInvalid`).
 *
 * On success `ok` is `true` and `value` carries the accepted, quantised price.
 * On rejection `ok` is `false` and `message` states the accepted range or the
 * ambiguity, verbatim; the caller retains its persisted value (Requirement 5.4).
 */
export type TariffParse =
  | { ok: true; value: number }
  | { ok: false; message: string };

/** The exclusive lower bound of the accepted range (Requirement 5.3). */
export const TARIFF_MIN = 0;

/** The inclusive upper bound of the accepted range (Requirement 5.3). */
export const TARIFF_MAX = 1000;

/**
 * The default Tariff applied on first run, an editable placeholder rather than a
 * billed figure (Requirement 5.2).
 */
export const TARIFF_DEFAULT = 5.0;

/** The maximum stored precision, in decimal places (Requirement 5.5). */
export const TARIFF_DECIMALS = 4;

/**
 * The out-of-range / non-numeric rejection message, stating the accepted range
 * (Requirement 5.4). Exported so the Settings tab and its tests reference the
 * one canonical string, and so it can be compared byte-for-byte with the
 * Mobile_Client.
 */
export const TARIFF_RANGE_MESSAGE =
  'Enter a tariff between 0 and 1000 Bs. per cubic metre.';

/**
 * The rejection message for input containing both a comma and a period, which
 * is ambiguous because either could be the decimal separator (Requirement 12.5,
 * read generously).
 */
export const TARIFF_AMBIGUOUS_SEPARATOR_MESSAGE = 'Use only one decimal separator.';

/**
 * Rounds a value to at most {@link TARIFF_DECIMALS} decimal places
 * (Requirement 5.5). Half-away-from-zero via `Math.round`, matching the
 * Mobile_Client `(v * 10000).round() / 10000`.
 */
export function quantise(v: number): number {
  const scaled = Math.round(v * 10000) / 10000;
  // Normalise -0 to 0 so formatting never emits a leading minus for zero.
  return scaled === 0 ? 0 : scaled;
}

/**
 * Parses tariff control text into a {@link TariffParse}.
 *
 * Accepts `,` OR `.` as the decimal separator regardless of locale, because a
 * user on a hardware keyboard may produce either (Requirement 12.5). Rejects, in
 * order:
 * - text containing BOTH separators, as ambiguous;
 * - empty or whitespace-only text;
 * - non-numeric text;
 * - zero, negatives, and values greater than {@link TARIFF_MAX}.
 *
 * A rejection returns a non-empty message and does not mutate any persisted
 * value — that is the caller's responsibility (Requirement 5.4). On success the
 * value is quantised to at most 4 decimals (Requirement 5.5).
 */
export function parse(text: string): TariffParse {
  const trimmed = text.trim();

  if (trimmed.length === 0) {
    return { ok: false, message: TARIFF_RANGE_MESSAGE };
  }

  const hasComma = trimmed.includes(',');
  const hasPeriod = trimmed.includes('.');
  if (hasComma && hasPeriod) {
    return { ok: false, message: TARIFF_AMBIGUOUS_SEPARATOR_MESSAGE };
  }

  // Normalise the single decimal separator to a period for numeric parsing.
  const normalised = hasComma ? trimmed.replace(',', '.') : trimmed;

  // Reject anything that is not a bare decimal number: optional leading sign,
  // digits, an optional single decimal point with digits. This excludes
  // thousands separators, exponents, hex, `NaN`, `Infinity`, and stray letters.
  if (!/^[+-]?(\d+(\.\d+)?|\.\d+)$/.test(normalised)) {
    return { ok: false, message: TARIFF_RANGE_MESSAGE };
  }

  const value = Number.parseFloat(normalised);
  if (!Number.isFinite(value)) {
    return { ok: false, message: TARIFF_RANGE_MESSAGE };
  }

  // min is exclusive, max is inclusive (Requirement 5.3).
  if (value <= TARIFF_MIN || value > TARIFF_MAX) {
    return { ok: false, message: TARIFF_RANGE_MESSAGE };
  }

  return { ok: true, value: quantise(value) };
}

/**
 * Formats a value for the editing text field: ungrouped, with trailing zeros
 * trimmed (`5.0 → "5"`, `5.5000 → "5.5"`). This is the representation over which
 * Requirement 5.6's round-trip holds — `parse(formatForEditing(quantise(v)))`
 * yields `quantise(v)`.
 */
export function formatForEditing(v: number): string {
  const q = quantise(v);
  if (!Number.isFinite(q)) return '';
  // Fixed to 4 decimals, then trim trailing zeros and any bare decimal point.
  const fixed = q.toFixed(TARIFF_DECIMALS);
  return fixed.replace(/\.?0+$/, '');
}

/**
 * Formats a value for read-only display: grouped with thousands separators
 * (`1234.5 → "1,234.5"`), trailing zeros trimmed. Unlike
 * {@link formatForEditing}, this is not intended to be re-parsed — grouping
 * separators are for the reader, not the round-trip.
 */
export function formatForDisplay(v: number): string {
  const q = quantise(v);
  if (!Number.isFinite(q)) return '';
  return new Intl.NumberFormat('en-US', {
    useGrouping: true,
    minimumFractionDigits: 0,
    maximumFractionDigits: TARIFF_DECIMALS,
  }).format(q);
}

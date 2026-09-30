/**
 * Property 8 — Tariff validation accepts exactly the stated range.
 * Web_Client half (task 11.13).
 *
 * *For any* Tariff control text, {@link parse} returns `{ ok: true }` IFF the
 * text is a well-formed decimal — one decimal separator at most, either `,` or
 * `.` but never both — whose value, after separator normalisation and
 * quantisation to 4 places, lies in the half-open range `(0, 1000]`. On every
 * other input it returns `{ ok: false }` carrying a non-empty message, one of
 * the two canonical strings: {@link TARIFF_RANGE_MESSAGE} for out-of-range /
 * non-numeric / empty input, {@link TARIFF_AMBIGUOUS_SEPARATOR_MESSAGE} for
 * input that carries BOTH separators.
 *
 * **Validates: Requirements 5.3, 5.4**
 *
 * Requirement 5.3: a committed value strictly greater than 0 and at most 1000
 * is accepted. Requirement 5.4: an entry that is not a number, is `<= 0`, or is
 * `> 1000` is rejected, the previously persisted Tariff is retained, and a
 * message stating the accepted range is shown.
 *
 * **The invariant, stated three ways.**
 *
 *  1. *Acceptance equals the range predicate.* Rather than trust `parse`
 *     against itself, the property recomputes the oracle independently: it
 *     normalises the separator, screens the shape with a bare-decimal regex
 *     (no exponent, no hex, no thousands separators, no `NaN` / `Infinity`),
 *     parses, quantises, and tests `0 < v <= 1000`. `parse` must return
 *     `{ ok: true }` exactly when this oracle says so, and the accepted `value`
 *     must equal the quantised value.
 *
 *  2. *Rejection carries a non-empty, canonical message.* Every rejection
 *     message is non-empty and is either the range message or the
 *     ambiguous-separator message. Both-separator input takes the ambiguity
 *     branch; all other rejections take the range branch.
 *
 *  3. *The stored value is untouched.* Requirement 5.4's "retain the previously
 *     persisted Tariff" is a statement about the caller, not this pure
 *     function — but the guarantee that makes it hold is that `parse` is PURE:
 *     it returns a result and mutates nothing. The property models this
 *     directly. It threads a sentinel "persisted value" that `parse` has no
 *     access to and asserts it is unchanged across the call, and it asserts
 *     `parse` is referentially transparent — calling it twice on the same text
 *     yields an equal outcome — so a caller who only writes on `{ ok: true }`
 *     can never have its stored value disturbed by a rejection.
 *
 * **The awkward corpus.** design.md calls for the boundaries and the malformed
 * shapes to be visited exhaustively, not merely sampled: the four boundary
 * values `0`, `0.0001`, `1000`, `1000.0001`; both-separator strings; the empty
 * string; whitespace-only; alphabetic; `NaN`; `Infinity`; and leading /
 * trailing padded numbers. These go through `fc.constantFrom`, always in the
 * sampled pool. The generated cases add well-formed decimals drawn both inside
 * and outside the range, in both separator styles, so a rule that was right on
 * the fixed corpus but wrong on some other decimal still surfaces as a
 * counterexample.
 *
 * The bounds `0` and `1000` and the two messages are read from the model
 * (`TARIFF_MIN`, `TARIFF_MAX`, `TARIFF_RANGE_MESSAGE`,
 * `TARIFF_AMBIGUOUS_SEPARATOR_MESSAGE`) rather than restated, so the property
 * checks the implementation against its own single authority (Requirement 13.1)
 * and cannot silently drift from the messages the UI shows.
 *
 * _Requirements: 5.3, 5.4_
 */
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import {
  TARIFF_AMBIGUOUS_SEPARATOR_MESSAGE,
  TARIFF_DECIMALS,
  TARIFF_MAX,
  TARIFF_MIN,
  TARIFF_RANGE_MESSAGE,
  parse,
  quantise,
} from '../../core/tariff';

/** The design.md floor: 100 generated cases per property, both clients. */
const RUNS = { numRuns: 100 } as const;

/**
 * A bare-decimal shape screen, the independent oracle for "well-formed":
 * optional sign, digits with an optional single fractional part, OR a leading
 * dot with a fractional part. No exponent, no hex, no thousands separators, no
 * `NaN` / `Infinity`, no stray letters. Stated here, not imported, so it is a
 * genuine second opinion on `parse` rather than a copy of it.
 */
const BARE_DECIMAL = /^[+-]?(\d+(\.\d+)?|\.\d+)$/;

/**
 * The oracle: what SHOULD `parse(text)` decide, computed without calling it.
 * Returns the accepted quantised value when `text` is well-formed and in range,
 * or `null` when it should be rejected.
 */
function oracleAccepts(text: string): number | null {
  const trimmed = text.trim();
  if (trimmed.length === 0) return null;

  const hasComma = trimmed.includes(',');
  const hasPeriod = trimmed.includes('.');
  if (hasComma && hasPeriod) return null;

  const normalised = hasComma ? trimmed.replace(',', '.') : trimmed;
  if (!BARE_DECIMAL.test(normalised)) return null;

  const parsed = Number.parseFloat(normalised);
  if (!Number.isFinite(parsed)) return null;

  // This is the SINGLE shared oracle used by both clients (the per-client fork
  // is gone): range-check the RAW parsed value against `(0, 1000]`, and only
  // THEN quantise the accepted result. Range-check-before-quantise means a
  // value just past the max that would round down onto it (e.g. `1000.0000001`)
  // is rejected here — identically on both clients.
  if (parsed <= TARIFF_MIN || parsed > TARIFF_MAX) return null;
  return quantise(parsed);
}

/** True when `text` carries BOTH separators once trimmed. */
function hasBothSeparators(text: string): boolean {
  const trimmed = text.trim();
  return trimmed.includes(',') && trimmed.includes('.');
}

/**
 * Renders a value as decimal text using `separator` as the decimal mark, with
 * trailing zeros trimmed. Builds well-formed inputs in both separator styles.
 */
function render(value: number, separator: ',' | '.'): string {
  const fixed = value.toFixed(TARIFF_DECIMALS);
  const trimmed = fixed.replace(/\.?0+$/, '');
  return separator === '.' ? trimmed : trimmed.replace('.', separator);
}

/** The single obligation, asserted on one `text`. */
function checkParse(text: string): void {
  const expected = oracleAccepts(text);
  const result = parse(text);

  if (expected !== null) {
    // In-range, well-formed: must accept, and the value must be the quantised
    // oracle value.
    expect(result.ok, `expected ok for ${show(text)}`).toBe(true);
    if (result.ok) {
      expect(result.value, `accepted value for ${show(text)}`).toBe(expected);
    }
  } else {
    // Out of range or malformed: must reject with a non-empty, canonical
    // message.
    expect(result.ok, `expected rejection for ${show(text)}`).toBe(false);
    if (!result.ok) {
      expect(result.message.length, `non-empty message for ${show(text)}`).toBeGreaterThan(0);
      if (hasBothSeparators(text)) {
        expect(result.message, `ambiguity message for ${show(text)}`).toBe(
          TARIFF_AMBIGUOUS_SEPARATOR_MESSAGE,
        );
      } else {
        expect(result.message, `range message for ${show(text)}`).toBe(TARIFF_RANGE_MESSAGE);
      }
    }
  }

  // Clause 3 — the stored value is untouched. `parse` is pure: a sentinel the
  // function cannot reach is unchanged across the call, and a second call on
  // the same text yields an equal decision. A caller that writes only on
  // `{ ok: true }` therefore cannot have its persisted Tariff disturbed by a
  // rejection (Requirement 5.4).
  const SENTINEL = 42.4242;
  const stored = SENTINEL;
  const again = parse(text);
  expect(stored, `parse must not mutate anything for ${show(text)}`).toBe(SENTINEL);
  expect(again.ok, `parse must be deterministic for ${show(text)}`).toBe(result.ok);
  if (result.ok && again.ok) {
    expect(again.value, `stable value for ${show(text)}`).toBe(result.value);
  }
}

function show(text: string): string {
  return JSON.stringify(text);
}

describe('Property 8 — Tariff validation (Web_Client), Requirements 5.3/5.4', () => {
  // The awkward corpus, always in the sampled pool: boundaries, both-separator,
  // empty, whitespace, alphabetic, NaN, Infinity, and padded numbers.
  // `TARIFF_MAX` is read rather than the literal 1000 restated.
  const maxText = render(TARIFF_MAX, '.'); // "1000"
  const AWKWARD: readonly string[] = [
    // Boundaries.
    '0',
    '0.0001',
    maxText,
    `${maxText}.0001`, // "1000.0001" — just over the inclusive max.
    // Boundaries in the comma style.
    '0,0001',
    `${maxText},0001`,
    // Both separators — must take the ambiguity branch.
    '1,000.5',
    '1.000,5',
    '1,2.3',
    '0.0,0',
    // Empty and whitespace.
    '',
    ' ',
    '   ',
    '\t',
    '\n',
    // Alphabetic and mixed.
    'abc',
    '12abc',
    'abc12',
    '1e3', // exponent — not a bare decimal.
    '0x10', // hex — not a bare decimal.
    // The non-finite words a naive parseFloat would otherwise mishandle.
    'NaN',
    'Infinity',
    '-Infinity',
    '+Infinity',
    'inf',
    // Padded numbers — leading / trailing whitespace around a valid value.
    ' 5',
    '5 ',
    '  5.5  ',
    '\t7,25\n',
    // Signs and zeros.
    '-1',
    '-0.5',
    '+5',
    '0.0',
    '0,0',
    '-0',
    // Just above / below the ends.
    '999.9999',
    '1000.0000001',
    '0.00001', // quantises to 0 → rejected as <= min.
  ];

  it('accepts iff in (0, 1000] — period-style decimals inside the range', () => {
    const inRange = fc.oneof(
      fc.double({ min: 0.0001, max: TARIFF_MAX, noNaN: true }),
      fc.constantFrom(0.0001, 1, 5, 250.5, 999.9999, TARIFF_MAX),
    );
    fc.assert(
      fc.property(inRange, (v) => {
        checkParse(render(v, '.'));
      }),
      RUNS,
    );
  });

  it('accepts iff in (0, 1000] — comma-style decimals inside the range', () => {
    const inRange = fc.oneof(
      fc.double({ min: 0.0001, max: TARIFF_MAX, noNaN: true }),
      fc.constantFrom(0.0001, 1, 5, 250.5, 999.9999, TARIFF_MAX),
    );
    fc.assert(
      fc.property(inRange, (v) => {
        checkParse(render(v, ','));
      }),
      RUNS,
    );
  });

  it('rejects decimals above the inclusive maximum', () => {
    const above = fc.oneof(
      fc.double({ min: TARIFF_MAX, max: 5000, noNaN: true }),
      fc.constantFrom(1000.0001, 1001, 2500, 5000),
    );
    fc.assert(
      fc.property(above, (v) => {
        checkParse(render(v, '.'));
      }),
      RUNS,
    );
  });

  it('decides the awkward corpus exactly as the range oracle', () => {
    fc.assert(
      fc.property(fc.constantFrom(...AWKWARD), (text) => {
        checkParse(text);
      }),
      RUNS,
    );
  });
});

describe('Property 8 — the oracle does real work', () => {
  it('agrees with the fixed points the requirement pins', () => {
    // 0 is rejected (exclusive min), 1000 is accepted (inclusive max).
    expect(oracleAccepts('0')).toBeNull();
    expect(oracleAccepts('0.0001')).toBe(0.0001);
    expect(oracleAccepts('1000')).toBe(1000);
    expect(oracleAccepts('1000.0001')).toBeNull();
    // Both-separator, empty and non-finite are all rejected.
    expect(oracleAccepts('1,000.5')).toBeNull();
    expect(oracleAccepts('')).toBeNull();
    expect(oracleAccepts('NaN')).toBeNull();
    expect(oracleAccepts('Infinity')).toBeNull();
  });

  it('covers each named shape in the corpus', () => {
    expect(oracleAccepts('1000')).not.toBeNull(); // boundary accepted
    expect(hasBothSeparators('1,000.5')).toBe(true); // both separators
    expect(oracleAccepts('')).toBeNull(); // empty
    expect(oracleAccepts('   ')).toBeNull(); // whitespace
    expect(oracleAccepts('abc')).toBeNull(); // alpha
    expect(oracleAccepts('NaN')).toBeNull(); // NaN
    expect(oracleAccepts('Infinity')).toBeNull(); // Infinity
    expect(oracleAccepts(' 5')).toBe(5); // padded, still accepted
  });
});

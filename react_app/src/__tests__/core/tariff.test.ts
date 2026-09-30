/**
 * Worked examples for the Web_Client Tariff model (task 11.2).
 *
 * These pin the constants, the parse boundaries, the two rejection messages,
 * and the two formatters so a stray edit fails here. The exhaustive validation
 * and round-trip PROPERTIES are tasks 11.13 and 11.14 (separate); this file is
 * the example layer beneath them.
 *
 * _Requirements: 5.1, 5.3, 5.4, 5.5, 5.6, 12.5_
 */
import { describe, expect, it } from 'vitest';

import {
  TARIFF_AMBIGUOUS_SEPARATOR_MESSAGE,
  TARIFF_DECIMALS,
  TARIFF_DEFAULT,
  TARIFF_MAX,
  TARIFF_MIN,
  TARIFF_RANGE_MESSAGE,
  formatForDisplay,
  formatForEditing,
  parse,
  quantise,
} from '../../core/tariff';

describe('tariff constants', () => {
  it('pins the shared cross-client values', () => {
    expect(TARIFF_MIN).toBe(0);
    expect(TARIFF_MAX).toBe(1000);
    expect(TARIFF_DEFAULT).toBe(5.0);
    expect(TARIFF_DECIMALS).toBe(4);
  });

  it('pins the two rejection messages verbatim', () => {
    expect(TARIFF_RANGE_MESSAGE).toBe(
      'Enter a tariff between 0 and 1000 Bs. per cubic metre.',
    );
    expect(TARIFF_AMBIGUOUS_SEPARATOR_MESSAGE).toBe('Use only one decimal separator.');
  });
});

describe('parse — acceptance', () => {
  it('accepts a period decimal separator', () => {
    expect(parse('5.5')).toEqual({ ok: true, value: 5.5 });
  });

  it('accepts a comma decimal separator regardless of locale', () => {
    expect(parse('5,5')).toEqual({ ok: true, value: 5.5 });
  });

  it('accepts the inclusive maximum', () => {
    expect(parse('1000')).toEqual({ ok: true, value: 1000 });
  });

  it('accepts a value just above the exclusive minimum', () => {
    expect(parse('0.0001')).toEqual({ ok: true, value: 0.0001 });
  });

  it('quantises to at most 4 decimals on acceptance', () => {
    expect(parse('5.123456')).toEqual({ ok: true, value: 5.1235 });
  });

  it('accepts surrounding whitespace', () => {
    expect(parse('  12.5  ')).toEqual({ ok: true, value: 12.5 });
  });
});

describe('parse — rejection with the range message', () => {
  for (const text of ['', '   ', 'abc', '0', '-1', '1000.0001', '5e2', '12.', 'NaN', 'Infinity']) {
    it(`rejects ${JSON.stringify(text)}`, () => {
      const result = parse(text);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.message).toBe(TARIFF_RANGE_MESSAGE);
    });
  }
});

describe('parse — ambiguous separator', () => {
  it('rejects text containing both separators', () => {
    const result = parse('1.234,5');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.message).toBe(TARIFF_AMBIGUOUS_SEPARATOR_MESSAGE);
  });
});

describe('quantise', () => {
  it('rounds to at most 4 decimals', () => {
    expect(quantise(5.123456)).toBe(5.1235);
    expect(quantise(5.0)).toBe(5);
    expect(quantise(1000)).toBe(1000);
  });
});

describe('formatForEditing — ungrouped, trailing zeros trimmed', () => {
  it('trims trailing zeros', () => {
    expect(formatForEditing(5.0)).toBe('5');
    expect(formatForEditing(5.5)).toBe('5.5');
    expect(formatForEditing(1234.5)).toBe('1234.5');
  });

  it('round-trips through parse', () => {
    for (const v of [5, 5.5, 0.0001, 1000, 12.3456, 999.9999]) {
      const q = quantise(v);
      expect(parse(formatForEditing(q))).toEqual({ ok: true, value: q });
    }
  });
});

describe('formatForDisplay — grouped', () => {
  it('adds thousands separators', () => {
    expect(formatForDisplay(1234.5)).toBe('1,234.5');
    expect(formatForDisplay(5)).toBe('5');
    expect(formatForDisplay(1000)).toBe('1,000');
  });
});

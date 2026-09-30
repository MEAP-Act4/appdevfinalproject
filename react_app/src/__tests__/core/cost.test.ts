/**
 * Worked examples for the Web_Client Cost_Formatter (task 11.6).
 *
 * These pin the Bs_Equivalence formula, the literal `'Bs. '` prefix, the
 * exactly-two-decimal locale-aware body, the null-when-disabled contract, and
 * the `'--'` non-finite sentinel, so a stray edit fails here. The dedicated
 * PROPERTIES are tasks 11.15/11.16/11.17 (separate); this file is the example
 * layer beneath them.
 *
 * _Requirements: 6.1, 6.3, 6.4, 6.6, 6.7, 6.8, 5.8, 12.1, 12.2, 12.3, 12.4_
 */
import { describe, expect, it } from 'vitest';

import { createCostFormatter } from '../../core/cost';

describe('createCostFormatter formula and prefix', () => {
  it('computes litres / 1000 * tariff at two decimals with the Bs. prefix', () => {
    // 3600 L = 3.6 m³, at 5.25 Bs./m³ → 18.90 Bs.
    const f = createCostFormatter({
      tariffBsPerCubicMetre: 5.25,
      locale: 'en',
      enabled: true,
      isDefaultTariff: false,
    });
    expect(f.format(3600)).toBe('Bs. 18.90');
  });

  it('always renders exactly two fractional digits', () => {
    const f = createCostFormatter({
      tariffBsPerCubicMetre: 5,
      locale: 'en',
      enabled: true,
      isDefaultTariff: false,
    });
    // 200 L = 0.2 m³ * 5 = 1 Bs. → padded to two decimals.
    expect(f.format(200)).toBe('Bs. 1.00');
    expect(f.format(0)).toBe('Bs. 0.00');
  });
});

describe('createCostFormatter locale separators (Req 12.1–12.4)', () => {
  it('formats the body with en separators and the Bs. prefix', () => {
    const f = createCostFormatter({
      tariffBsPerCubicMetre: 1000,
      locale: 'en',
      enabled: true,
      isDefaultTariff: false,
    });
    // 1234567 L = 1234.567 m³ * 1000 = 1234567 Bs.
    const out = f.format(1234567);
    expect(out).toBe('Bs. 1,234,567.00');
    expect(out?.startsWith('Bs. ')).toBe(true);
  });

  it('formats the body with es separators and the same Bs. prefix', () => {
    const f = createCostFormatter({
      tariffBsPerCubicMetre: 1000,
      locale: 'es',
      enabled: true,
      isDefaultTariff: false,
    });
    const out = f.format(1234567);
    // es reverses the roles: '.' groups, ',' is the decimal separator.
    expect(out).toBe('Bs. 1.234.567,00');
    expect(out?.startsWith('Bs. ')).toBe(true);
  });

  it('uses the same Bs. prefix in every locale for a small amount', () => {
    const en = createCostFormatter({
      tariffBsPerCubicMetre: 5,
      locale: 'en',
      enabled: true,
      isDefaultTariff: false,
    });
    const es = createCostFormatter({
      tariffBsPerCubicMetre: 5,
      locale: 'es',
      enabled: true,
      isDefaultTariff: false,
    });
    expect(en.format(3600)).toBe('Bs. 18.00');
    expect(es.format(3600)).toBe('Bs. 18,00');
  });
});

describe('createCostFormatter disabled and non-finite (Req 5.8)', () => {
  it('returns null when display is disabled', () => {
    const f = createCostFormatter({
      tariffBsPerCubicMetre: 5,
      locale: 'en',
      enabled: false,
      isDefaultTariff: false,
    });
    expect(f.format(3600)).toBeNull();
    expect(f.format(0)).toBeNull();
    expect(f.format(NaN)).toBeNull();
  });

  it('returns the -- sentinel for NaN and infinite input', () => {
    const f = createCostFormatter({
      tariffBsPerCubicMetre: 5,
      locale: 'en',
      enabled: true,
      isDefaultTariff: false,
    });
    expect(f.format(Number.NaN)).toBe('--');
    expect(f.format(Number.POSITIVE_INFINITY)).toBe('--');
    expect(f.format(Number.NEGATIVE_INFINITY)).toBe('--');
  });
});

describe('createCostFormatter display-unit invariance (Req 6.7) and 6.8 flag', () => {
  it('produces the same Bs_Equivalence for the same litre volume regardless of caller unit choice', () => {
    // The formatter only ever sees canonical litres — there is no unit param —
    // so the same litre volume can only ever produce the same output.
    const f = createCostFormatter({
      tariffBsPerCubicMetre: 7.5,
      locale: 'en',
      enabled: true,
      isDefaultTariff: false,
    });
    expect(f.format(5000)).toBe(f.format(5000));
    expect(f.format(5000)).toBe('Bs. 37.50');
  });

  it('carries the isDefaultTariff flag for the Req 6.8 indication', () => {
    const f = createCostFormatter({
      tariffBsPerCubicMetre: 5,
      locale: 'en',
      enabled: true,
      isDefaultTariff: true,
    });
    expect(f.isDefaultTariff).toBe(true);
  });
});

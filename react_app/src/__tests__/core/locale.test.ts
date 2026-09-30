/**
 * Worked examples for the Web_Client locale resolution chain (task 11.4).
 *
 * These are examples, not the property. Task 11.18 writes Property 22 —
 * "Locale resolution is total and falls back to English" — over the tag set
 * `es`, `es-BO`, `es-419`, `en`, `en-US`, `pt-BR`, `qq`, empty and whitespace.
 * What follows pins the resolution order of Requirement 12.6 (override, then
 * platform language subtag, then `en`), the subtag reduction that makes
 * `es-BO` / `es-419` resolve to `es`, and the totality of {@link resolveLocale}
 * on the awkward inputs the property will also hit, so a stray edit to the
 * chain fails here rather than surfacing as silent mis-formatting.
 *
 * `resolveActiveLocale` is covered for its override wiring and its
 * construction-failure downgrade via the injectable diagnostic hook; the `Intl`
 * probe is exercised without touching a real render.
 *
 * _Requirements: 12.6_
 */
import { describe, expect, it, vi } from 'vitest';

import {
  FALLBACK_LOCALE,
  resolveActiveLocale,
  resolveLocale,
  SUPPORTED_LOCALES,
} from '../../core/locale';

describe('resolveLocale order (Requirement 12.6)', () => {
  it('takes a supported explicit override ahead of the platform tag', () => {
    expect(resolveLocale('es', 'en-US')).toBe('es');
    expect(resolveLocale('en', 'es-BO')).toBe('en');
  });

  it('ignores an unsupported or empty override and falls through', () => {
    expect(resolveLocale('pt', 'es-BO')).toBe('es');
    expect(resolveLocale('qq', 'en-US')).toBe('en');
    expect(resolveLocale('', 'es')).toBe('es');
    expect(resolveLocale(null, 'es')).toBe('es');
    expect(resolveLocale(undefined, 'en')).toBe('en');
  });

  it('normalises a supported override that is mixed case or padded', () => {
    expect(resolveLocale('ES', 'en')).toBe('es');
    expect(resolveLocale('  en  ', 'es')).toBe('en');
  });
});

describe('resolveLocale platform subtag reduction', () => {
  const cases: ReadonlyArray<readonly [string, 'es' | 'en']> = [
    ['es', 'es'],
    ['es-BO', 'es'],
    ['es-419', 'es'],
    ['es_BO', 'es'],
    ['ES-bo', 'es'],
    ['en', 'en'],
    ['en-US', 'en'],
    ['pt-BR', 'en'],
    ['qq', 'en'],
  ];

  for (const [tag, expected] of cases) {
    it(`resolves platform tag "${tag}" to ${expected}`, () => {
      expect(resolveLocale(null, tag)).toBe(expected);
    });
  }
});

describe('resolveLocale is total on awkward input', () => {
  const awkward = ['', '   ', '-', '_', '--', 'es-', '-es', '@@', '123', 'e', 's'];

  for (const tag of awkward) {
    it(`never throws and returns a supported locale for ${JSON.stringify(tag)}`, () => {
      const result = resolveLocale(null, tag);
      expect(SUPPORTED_LOCALES).toContain(result);
    });
  }

  it('falls back to English when nothing matches', () => {
    expect(resolveLocale(null, '')).toBe(FALLBACK_LOCALE);
    expect(resolveLocale(null, 'pt-BR')).toBe(FALLBACK_LOCALE);
    expect(FALLBACK_LOCALE).toBe('en');
  });
});

describe('resolveActiveLocale', () => {
  it('resolves from an explicit platformTag hook without touching the DOM', () => {
    expect(resolveActiveLocale('es', { platformTag: 'en-US' })).toBe('es');
    expect(resolveActiveLocale(null, { platformTag: 'es-BO' })).toBe('es');
    expect(resolveActiveLocale(null, { platformTag: 'pt-BR' })).toBe('en');
  });

  it('does not fire the diagnostic when Intl formatters construct', () => {
    const onDiagnostic = vi.fn();
    const result = resolveActiveLocale(null, { platformTag: 'es', onDiagnostic });
    expect(result).toBe('es');
    expect(onDiagnostic).not.toHaveBeenCalled();
  });

  it('downgrades to English and records a diagnostic on Intl failure', () => {
    const onDiagnostic = vi.fn();
    const original = Intl.NumberFormat;
    // Force the single-point Intl construction failure Requirement 12.6 guards.
    vi.spyOn(Intl, 'NumberFormat').mockImplementation(() => {
      throw new Error('no ICU data');
    });
    try {
      const result = resolveActiveLocale(null, { platformTag: 'es', onDiagnostic });
      expect(result).toBe(FALLBACK_LOCALE);
      expect(onDiagnostic).toHaveBeenCalledTimes(1);
      expect(onDiagnostic.mock.calls[0]?.[0]).toContain('downgrading');
    } finally {
      Intl.NumberFormat = original;
    }
  });
});

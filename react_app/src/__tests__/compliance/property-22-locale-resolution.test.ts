/**
 * Property 22 — Locale resolution is total and falls back to English.
 * Web_Client half (task 11.18).
 *
 * *For any* locale tag string, resolution returns a member of the supported
 * locale set `{es, en}`, and returns `es` iff the effective language subtag is
 * `es`, otherwise `en`. Resolution never throws for any input.
 *
 * **Validates: Requirements 12.6**
 *
 * The surface under test is the pure `resolveLocale(override, platformTag)` in
 * `core/locale.ts` — no DOM, no `Intl` probe (that lives in the
 * `resolveActiveLocale` wrapper and is out of this property's scope). The order
 * it must honour is override → platform language subtag → `en`, which this file
 * exercises through *both* argument positions: the override path and the
 * platformTag path each get their own property, plus a combined property that
 * pins the precedence between them.
 *
 * **The generators (design.md).** The `tag` domain is a corpus of the named
 * cases — `es`, `es-BO`, `es-419`, `en`, `en-US`, `pt-BR`, `qq`, `''`,
 * whitespace, and malformed values — *plus* fast garbage: random unicode,
 * punctuation, mixed case, and padded strings. The corpus guarantees the
 * boundary tags appear every run; the garbage keeps the totality claim honest
 * against inputs no one wrote by hand. `override` also draws `null`/`undefined`
 * (the "not provided" cases), so the fall-through to the platform tag is
 * exercised.
 *
 * **The oracle.** The expected result is derived independently of the
 * implementation: take the effective tag, cut it at the first `-`/`_`, trim and
 * lower-case, and check whether that subtag is `es`. This is the same rule the
 * design states, re-derived here rather than imported, so a bug in the
 * implementation's subtag extraction would surface as a mismatch.
 *
 * Cross-client parity: this is the Web half of the same property the Mobile
 * suite runs in
 * `flutter_app/test/compliance/property_22_locale_resolution_test.dart`.
 *
 * Runs in the default jsdom project — it needs no filesystem access.
 */
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import {
  FALLBACK_LOCALE,
  resolveLocale,
  SUPPORTED_LOCALES,
  type AppLocale,
} from '../../core/locale';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/**
 * The named tags Property 22 must always see: the two supported languages in
 * bare, regioned and script/extended forms, an unsupported language with a
 * region, an unsupported bare language, and the empty/whitespace edges.
 */
const CORPUS_TAGS = [
  'es',
  'es-BO',
  'es-419',
  'en',
  'en-US',
  'pt-BR',
  'qq',
  '',
  '   ',
  '\t',
  '\n ',
  // malformed / hand-adversarial values
  'es_BO', // underscore separator
  '-es', // leading separator: empty primary subtag -> en
  'ES', // upper-case supported
  'Es-bo', // mixed case supported
  '  es  ', // padded supported
  '  en-US ', // padded regioned
  'esperanto', // starts with es- but subtag is "esperanto", not "es"
  'e', // single char
  'español', // unicode
  '123', // digits
  'es-', // trailing separator
  '_en', // leading underscore
] as const;

/**
 * The effective tag domain: the corpus, biased in, plus fast garbage — random
 * unicode strings, punctuation, mixed case and padded variants. `fc.oneof`
 * mixes them so every run sees corpus tags and never-seen-before junk.
 */
function anyTag(): fc.Arbitrary<string> {
  return fc.oneof(
    { weight: 3, arbitrary: fc.constantFrom<string>(...CORPUS_TAGS) },
    // Fast garbage: arbitrary strings, including separators, digits and spaces.
    { weight: 2, arbitrary: fc.string() },
    // Fast garbage over the full unicode range (emoji, CJK, combining marks).
    { weight: 1, arbitrary: fc.string({ unit: 'grapheme' }) },
    // Padded / mixed-case variants of arbitrary short tokens.
    {
      weight: 1,
      arbitrary: fc
        .tuple(
          fc.constantFrom('', ' ', '  ', '\t'),
          fc.constantFrom('es', 'EN', 'Es', 'pT', 'qq', 'xx'),
          fc.constantFrom('', '-BO', '_419', '-US', '.', '!!'),
          fc.constantFrom('', ' ', '  '),
        )
        .map(([lead, lang, tail, trail]) => `${lead}${lang}${tail}${trail}`),
    },
  );
}

/** `override` also draws the "not provided" cases so fall-through is covered. */
function anyOverride(): fc.Arbitrary<string | null | undefined> {
  return fc.oneof(
    { weight: 4, arbitrary: anyTag() },
    { weight: 1, arbitrary: fc.constantFrom(null, undefined) },
  );
}

/**
 * The oracle: the language subtag of `tag`, trimmed and lower-cased, is the run
 * of characters before the first `-` or `_`. Derived independently of the
 * implementation so it can catch a bug in it.
 */
function languageSubtagOracle(tag: string): string {
  const trimmed = tag.trim();
  if (trimmed === '') return '';
  const separator = trimmed.search(/[-_]/);
  const primary = separator === -1 ? trimmed : trimmed.slice(0, separator);
  return primary.trim().toLowerCase();
}

/** The expected resolution for a supported-or-not effective tag. */
function expectedFor(effectiveTag: string | null | undefined): AppLocale {
  const subtag = languageSubtagOracle(effectiveTag ?? '');
  return subtag === 'es' ? 'es' : 'en';
}

/**
 * Whether an override string counts as a supported override, computed EXACTLY
 * as `resolveLocale` does: the override is accepted only when its whole
 * trimmed, lower-cased value is exactly `'es'` or `'en'`. Unlike a platform
 * tag, the override is NOT split on `-`/`_`, so `'es-BO'`, `'es-419'` and
 * `'  es-US '` are unsupported overrides and fall through to the platform tag.
 */
function overrideResolvesTo(override: string | null | undefined): AppLocale | null {
  if (typeof override !== 'string') return null;
  const normalised = override.trim().toLowerCase();
  return normalised === 'es' || normalised === 'en' ? (normalised as AppLocale) : null;
}

describe('Property 22 — locale resolution is total and falls back to English', () => {
  it('is total: resolveLocale never throws and always returns a member of {es, en}', () => {
    fc.assert(
      fc.property(anyOverride(), anyTag(), (override, platformTag) => {
        let result: AppLocale;
        // Totality: any pair of strings resolves without throwing.
        expect(() => {
          result = resolveLocale(override, platformTag);
        }).not.toThrow();
        expect(SUPPORTED_LOCALES).toContain(result!);
      }),
      RUNS,
    );
  });

  it('resolves via the platformTag when no override is given: es iff its subtag is es', () => {
    fc.assert(
      fc.property(fc.constantFrom(null, undefined), anyTag(), (override, platformTag) => {
        const result = resolveLocale(override, platformTag);
        const expected = expectedFor(platformTag);
        expect(result).toBe(expected);
      }),
      RUNS,
    );
  });

  it('resolves via the override when it names a supported locale: es iff its subtag is es', () => {
    // A supported override wins over the platform tag; an unsupported override
    // is ignored and the platform tag decides. The oracle expresses exactly
    // that precedence. Unlike the platform tag, the override is accepted only
    // when its whole trimmed, lower-cased value is exactly 'es' or 'en' — it is
    // not split on '-'/'_', so 'es-BO' is an unsupported override.
    fc.assert(
      fc.property(anyTag(), anyTag(), (override, platformTag) => {
        const result = resolveLocale(override, platformTag);

        const overrideLocale = overrideResolvesTo(override);
        const expected = overrideLocale ?? expectedFor(platformTag);

        expect(result).toBe(expected);
      }),
      RUNS,
    );
  });

  it('lands es exactly when the effective language subtag is es, else en', () => {
    // The core invariant stated directly over the effective tag (override when
    // supported, otherwise platform), independent of which argument carried it.
    fc.assert(
      fc.property(anyOverride(), anyTag(), (override, platformTag) => {
        const result = resolveLocale(override, platformTag);

        // The override is accepted only as a whole exact 'es'/'en' (never
        // split on a separator); otherwise the platform tag's subtag decides.
        const overrideLocale = overrideResolvesTo(override);
        const effectiveSubtag = overrideLocale ?? languageSubtagOracle(platformTag);

        if (effectiveSubtag === 'es') {
          expect(result).toBe('es');
        } else {
          expect(result).toBe('en');
        }
      }),
      RUNS,
    );
  });

  it('covers the named corpus tags every run', () => {
    // The corpus is the boundary set design.md names; pin that it resolves as
    // the oracle says, so a regression in any named case fails here directly.
    for (const tag of CORPUS_TAGS) {
      expect(resolveLocale(undefined, tag)).toBe(expectedFor(tag));
    }
    // Sanity anchors on the fallback and the supported set.
    expect(resolveLocale(undefined, 'pt-BR')).toBe(FALLBACK_LOCALE);
    expect(resolveLocale(undefined, 'es-419')).toBe('es');
    expect(FALLBACK_LOCALE).toBe('en');
  });
});

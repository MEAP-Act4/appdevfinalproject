/**
 * The Web_Client locale resolution and fallback chain (Requirement 12.6).
 *
 * This module is the **single authority** for which of the two supported
 * locales — `es` or `en` — the client formats numbers, currency and dates in.
 * The Mobile_Client holds the identical chain in
 * `flutter_app/lib/core/locale/app_locale.dart` (task 11.3); the two clients
 * resolve in the same order and always land on the same result for the same
 * inputs, which is what keeps the cross-client parity of Requirement 13.
 *
 * The resolution order (Requirement 12.6) is:
 *   1. an explicit user override in settings, if one is set and supported;
 *   2. the platform locale's language subtag from `navigator.language`, if it
 *      is one of the supported set `{es, en}`;
 *   3. `en`.
 *
 * Only number, currency and date *formatting* is localised — full Spanish
 * interface copy is out of scope (requirements open decision 2). The formatters
 * this feeds are `Intl.NumberFormat` and `Intl.DateTimeFormat`, both platform
 * built-ins; a construction failure in either is caught here, at resolution
 * time, and downgraded to `en` with a recorded diagnostic, so it can never
 * surface inside a render.
 *
 * The core resolver {@link resolveLocale} is pure — `(override, platformTag) =>
 * 'es' | 'en'` — takes no DOM and never throws for any input string. That is
 * the surface Property 22 (task 11.18) exercises over well-formed, malformed,
 * empty and whitespace tags. {@link resolveActiveLocale} is the thin,
 * DOM-reading wrapper the app calls at startup.
 *
 * _Requirements: 12.6_
 */

/** The two locales the clients format in (Requirement 12.6). */
export type AppLocale = 'es' | 'en';

/** The safe fallback locale, used whenever resolution finds nothing better. */
export const FALLBACK_LOCALE: AppLocale = 'en';

/** The supported locale set, in resolution-independent form. */
export const SUPPORTED_LOCALES: readonly AppLocale[] = ['es', 'en'];

/**
 * Extracts the lower-cased primary language subtag from a BCP-47-ish tag.
 *
 * Total: any string — including `''`, whitespace, `es-419`, `pt-BR`, `qq` and
 * malformed values — maps to a (possibly empty) subtag string, never throwing.
 * The subtag is the run of characters before the first `-` or `_`, trimmed and
 * lower-cased; everything after the separator (region, script, variant) is
 * discarded, so `es-BO`, `es-419` and `es` all reduce to `es`.
 */
function languageSubtag(tag: string): string {
  if (typeof tag !== 'string') return '';
  const trimmed = tag.trim();
  if (trimmed === '') return '';
  const separator = trimmed.search(/[-_]/);
  const primary = separator === -1 ? trimmed : trimmed.slice(0, separator);
  return primary.trim().toLowerCase();
}

/** Narrows an arbitrary string to an {@link AppLocale}, or `null`. */
function asSupportedLocale(value: string): AppLocale | null {
  return value === 'es' || value === 'en' ? value : null;
}

/**
 * Resolves the active locale from an explicit override and a platform tag.
 *
 * The pure heart of Requirement 12.6, directly testable without the DOM. The
 * order is override, then platform language subtag, then `en`:
 *
 * 1. `override`, when it is exactly `'es'` or `'en'`. An override outside the
 *    supported set (or `null`/`undefined`) is ignored rather than trusted.
 * 2. the language subtag of `platformTag`, when it is `'es'` or `'en'`.
 * 3. `en`.
 *
 * Total and never throwing for any input (Property 22, task 11.18): the result
 * is always in `{es, en}`, and it is `es` iff the effective language subtag is
 * `es`, otherwise `en`. Only the primary subtag is consulted, so `es-BO`,
 * `es-419` and `es` all resolve to `es`, while `pt-BR`, `qq`, `''` and
 * whitespace fall through to `en`.
 */
export function resolveLocale(
  override: string | null | undefined,
  platformTag: string | null | undefined,
): AppLocale {
  const fromOverride = typeof override === 'string' ? asSupportedLocale(override.trim().toLowerCase()) : null;
  if (fromOverride !== null) return fromOverride;

  const fromPlatform = asSupportedLocale(languageSubtag(platformTag ?? ''));
  if (fromPlatform !== null) return fromPlatform;

  return FALLBACK_LOCALE;
}

/**
 * Probes that `Intl.NumberFormat` and `Intl.DateTimeFormat` can be constructed
 * for a locale, returning `true` when both succeed.
 *
 * This is the single point where an `Intl` construction failure is caught
 * (Requirement 12.6). A runtime whose `Intl` implementation cannot build a
 * formatter for the resolved locale would otherwise throw the first time a
 * value is formatted inside a render; catching it here lets the caller
 * downgrade to `en` and record a diagnostic instead.
 */
function intlFormattersConstruct(locale: AppLocale): boolean {
  try {
    // Both are the formatters the client actually uses at render time; building
    // them here mirrors that usage rather than probing a proxy.
    new Intl.NumberFormat(locale);
    new Intl.DateTimeFormat(locale);
    return true;
  } catch {
    return false;
  }
}

/** Optional hook for recording the construction-failure diagnostic. */
export interface LocaleResolutionHooks {
  /** The platform tag read from the environment, for diagnostics. */
  readonly platformTag?: string | null | undefined;
  /** Called once with a human-readable line when a downgrade to `en` occurs. */
  readonly onDiagnostic?: (message: string) => void;
}

/**
 * Resolves the active locale for the running client, reading the platform tag
 * from `navigator.language` and verifying the result can drive `Intl`.
 *
 * The thin DOM-reading wrapper around {@link resolveLocale}. It applies the
 * same override → platform → `en` chain, then confirms the resolved locale can
 * construct both `Intl` formatters. If it cannot, it downgrades to `en` — the
 * single fallback point of Requirement 12.6 — and records a diagnostic through
 * {@link LocaleResolutionHooks.onDiagnostic} rather than letting the failure
 * reach a render. Should `en` itself somehow fail to construct, the diagnostic
 * still fires and `en` is returned; formatting then falls back to the runtime's
 * own default, which is the most graceful outcome available.
 *
 * `navigator` is read defensively so this is safe to call in a non-DOM context
 * (tests, server prerender): a missing `navigator.language` is treated as an
 * empty platform tag and flows to the `en` fallback.
 */
export function resolveActiveLocale(
  override?: string | null | undefined,
  hooks?: LocaleResolutionHooks,
): AppLocale {
  const platformTag =
    hooks?.platformTag ??
    (typeof navigator !== 'undefined' ? navigator.language : undefined);

  const resolved = resolveLocale(override, platformTag);

  if (intlFormattersConstruct(resolved)) return resolved;

  hooks?.onDiagnostic?.(
    `Locale "${resolved}" could not construct Intl formatters; ` +
      `downgrading to "${FALLBACK_LOCALE}".`,
  );
  return FALLBACK_LOCALE;
}

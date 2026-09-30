/**
 * Example tests for the Appearance → `data-theme` resolution in `App.tsx`
 * (task 3.6).
 *
 * Worked examples, not the properties. Task 3.12 writes Property 26 — the
 * contrast relationship between High_Contrast_Dark and Dark — and task 3.13
 * writes Property 25 over persistence. What is asserted here is the resolution
 * itself: four appearances onto three stylesheet blocks, the `system` listener,
 * and the `theme-color` meta tag following the resolved background.
 *
 * Three things make these tests real rather than circular:
 *
 * 1. **The stylesheet is the actual one.** `tokens.css` is read off disk and
 *    injected into the document, so `getComputedStyle` resolves the same
 *    `data-theme` blocks the app ships. jsdom does cascade custom properties,
 *    which is what makes the meta-tag assertions observable at all.
 *
 *    It is read with `node:fs` rather than imported as text, even though this
 *    file runs under jsdom and the suite's convention is that disk-reading tests
 *    are named `*.node.test.ts`. Vitest stubs CSS imports by default — `?raw`
 *    included — so an import yields an empty string, and the Node project has no
 *    DOM to cascade anything into. This test genuinely needs both, and `node:fs`
 *    is available under jsdom because only the globals change, not the runtime.
 * 2. **The expected values come from the registry**, not from this file. No
 *    colour literal appears here, so the file stays subject to the Requirement
 *    1.5 scan like any other.
 * 3. **`matchMedia` is stubbed, deliberately.** jsdom does not implement it, and
 *    even where it does it never changes, so a fake that can be flipped is the
 *    only way to observe the `system` listener doing its job.
 *
 * _Requirements: 9.1, 9.2, 9.6_
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import {
  APPEARANCE_THEMES,
  PREFERS_DARK_QUERY,
  applyAppearance,
  resolveTheme,
  syncThemeColor,
  type ThemeName,
} from '../../App';
import { APPEARANCES, type Appearance } from '../../state/settingsStore';
import {
  lightAppearanceExtensions,
  normaliseCssValue,
  tokens,
} from '../compliance/registry-model';

/**
 * `src/styles/tokens.css`, verbatim.
 *
 * Resolved from the Vitest root, which is `react_app/`, because `import.meta.url`
 * is not a `file:` URL under jsdom. A wrong path throws here rather than passing
 * vacuously, so the dependency is loud.
 */
const tokensCss = readFileSync(join(process.cwd(), 'src/styles/tokens.css'), 'utf8');

/** The dark background, from the registry rather than from a literal here. */
const DARK_BG = tokens['--bg'].value;

/** The light background, likewise. */
const LIGHT_BG = lightAppearanceExtensions['--bg'].value;

// --- the matchMedia stub -----------------------------------------------------

/** A `MediaQueryList` whose `matches` can be flipped, firing `change`. */
class FakeMediaQuery {
  readonly listeners = new Set<(event: MediaQueryListEvent) => void>();

  constructor(
    readonly media: string,
    public matches: boolean,
  ) {}

  addEventListener(type: string, listener: (event: MediaQueryListEvent) => void): void {
    if (type === 'change') this.listeners.add(listener);
  }

  removeEventListener(
    type: string,
    listener: (event: MediaQueryListEvent) => void,
  ): void {
    if (type === 'change') this.listeners.delete(listener);
  }

  /** Flips the preference and notifies, the way a platform theme change does. */
  flip(matches: boolean): void {
    this.matches = matches;
    const event = { matches, media: this.media } as MediaQueryListEvent;
    for (const listener of [...this.listeners]) listener(event);
  }
}

let query: FakeMediaQuery;
/** Every media string `applyAppearance` asked about, in order. */
let asked: string[];

function stubMatchMedia(prefersDark: boolean): void {
  query = new FakeMediaQuery(PREFERS_DARK_QUERY, prefersDark);
  asked = [];
  (window as unknown as { matchMedia: (media: string) => MediaQueryList }).matchMedia = (
    media: string,
  ) => {
    asked.push(media);
    return query as unknown as MediaQueryList;
  };
}

// --- the document ------------------------------------------------------------

const STYLE_ID = 'tokens-under-test';

/** Injects the real `tokens.css`, so custom properties resolve per theme. */
function loadTokensCss(): void {
  const style = document.createElement('style');
  style.id = STYLE_ID;
  style.textContent = tokensCss;
  document.head.append(style);
}

function themeColorMeta(): HTMLMetaElement {
  const meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
  expect(meta, 'the theme-color meta tag is missing').not.toBeNull();
  return meta as HTMLMetaElement;
}

/** What the meta tag currently advertises. */
function themeColor(): string {
  return themeColorMeta().getAttribute('content') ?? '';
}

/** A placeholder the production code must overwrite. Not a colour. */
const UNSET = 'unset-by-the-test';

beforeEach(() => {
  const meta = document.createElement('meta');
  meta.setAttribute('name', 'theme-color');
  meta.setAttribute('content', UNSET);
  document.head.append(meta);
  stubMatchMedia(false);
});

afterEach(() => {
  document.querySelectorAll('meta[name="theme-color"]').forEach((meta) => meta.remove());
  document.getElementById(STYLE_ID)?.remove();
  const root = document.documentElement;
  delete root.dataset.theme;
  delete root.dataset.reduceMotion;
  root.removeAttribute('style');
  delete (window as unknown as { matchMedia?: unknown }).matchMedia;
});

// --- the mapping -------------------------------------------------------------

describe('resolveTheme (Requirements 9.1, 9.2, 9.6)', () => {
  const explicit: readonly [Exclude<Appearance, 'system'>, ThemeName][] = [
    ['dark', 'dark'],
    ['hc-dark', 'hc-dark'],
    ['light', 'light'],
  ];

  for (const [appearance, theme] of explicit) {
    it(`maps ${appearance} onto data-theme='${theme}' whatever the platform says`, () => {
      expect(resolveTheme(appearance, false)).toBe(theme);
      expect(resolveTheme(appearance, true)).toBe(theme);
    });
  }

  it('does not fold hc-dark into dark', () => {
    // The whole appearance is two overrides under `:root[data-theme='hc-dark']`.
    // Resolving it to `dark` would drop both and leave it indistinguishable.
    expect(resolveTheme('hc-dark', false)).not.toBe(resolveTheme('dark', false));
  });

  it('resolves system to dark when the platform prefers dark', () => {
    expect(resolveTheme('system', true)).toBe('dark');
  });

  it('resolves system to light when the platform does not', () => {
    expect(resolveTheme('system', false)).toBe('light');
  });

  it('never resolves system to hc-dark', () => {
    // `prefers-color-scheme` carries no contrast signal, so High_Contrast_Dark
    // can only ever be an explicit choice.
    for (const prefersDark of [true, false]) {
      expect(resolveTheme('system', prefersDark)).not.toBe('hc-dark');
    }
  });

  it('resolves every appearance the store offers, and nothing else', () => {
    const mapped = [...Object.keys(APPEARANCE_THEMES), 'system'].sort();

    expect(mapped).toEqual([...APPEARANCES].sort());
  });

  it('resolves only onto data-theme values tokens.css declares', () => {
    const declared = new Set(
      [...tokensCss.matchAll(/\[data-theme='([^']+)'\]/g)].map((match) => match[1]),
    );

    for (const appearance of APPEARANCES) {
      for (const prefersDark of [true, false]) {
        const theme = resolveTheme(appearance, prefersDark);
        expect(declared, `tokens.css has no block for '${theme}'`).toContain(theme);
      }
    }
  });
});

// --- applying it to the document --------------------------------------------

describe('applyAppearance (Requirements 9.1, 9.2, 9.6)', () => {
  it('writes the resolved theme and the reduce-motion flag onto the root', () => {
    const cleanup = applyAppearance('hc-dark', true);

    expect(document.documentElement.dataset.theme).toBe('hc-dark');
    expect(document.documentElement.dataset.reduceMotion).toBe('true');
    cleanup();
  });

  it('asks only about the colour-scheme preference', () => {
    applyAppearance('dark', false)();

    expect(asked).toEqual([PREFERS_DARK_QUERY]);
  });

  it('follows the platform while the appearance is system', () => {
    stubMatchMedia(true);
    const cleanup = applyAppearance('system', false);
    expect(document.documentElement.dataset.theme).toBe('dark');

    query.flip(false);
    expect(document.documentElement.dataset.theme).toBe('light');

    query.flip(true);
    expect(document.documentElement.dataset.theme).toBe('dark');
    cleanup();
  });

  it('stops following the platform once cleaned up', () => {
    const cleanup = applyAppearance('system', false);
    expect(query.listeners.size).toBe(1);

    cleanup();

    expect(query.listeners.size).toBe(0);
    query.flip(true);
    expect(document.documentElement.dataset.theme).toBe('light');
  });

  it('ignores the platform for every appearance other than system', () => {
    for (const appearance of ['dark', 'hc-dark', 'light'] as const) {
      const cleanup = applyAppearance(appearance, false);

      expect(query.listeners.size, `${appearance} subscribed`).toBe(0);
      query.flip(true);
      expect(document.documentElement.dataset.theme).toBe(appearance);
      cleanup();
    }
  });
});

// --- the theme-color meta tag ------------------------------------------------

describe('theme-color follows the resolved background (Requirement 9.1)', () => {
  beforeEach(loadTokensCss);

  const expected: readonly [Appearance, string][] = [
    ['dark', DARK_BG],
    ['hc-dark', DARK_BG],
    ['light', LIGHT_BG],
  ];

  for (const [appearance, background] of expected) {
    it(`advertises the ${appearance} background`, () => {
      applyAppearance(appearance, false)();

      expect(normaliseCssValue(themeColor())).toBe(normaliseCssValue(background));
    });
  }

  it('advertises the same background for both dark appearances', () => {
    // Requirement 9.2: High_Contrast_Dark stays inside the dark family. It
    // overrides secondary text and the hairline, never the background.
    applyAppearance('dark', false)();
    const dark = themeColor();
    applyAppearance('hc-dark', false)();

    expect(themeColor()).toBe(dark);
  });

  it('advertises a different background for light', () => {
    applyAppearance('dark', false)();
    const dark = themeColor();
    applyAppearance('light', false)();

    expect(themeColor()).not.toBe(dark);
  });

  it('follows the platform for system, tag included', () => {
    stubMatchMedia(true);
    const cleanup = applyAppearance('system', false);
    expect(normaliseCssValue(themeColor())).toBe(normaliseCssValue(DARK_BG));

    query.flip(false);

    expect(normaliseCssValue(themeColor())).toBe(normaliseCssValue(LIGHT_BG));
    cleanup();
  });

  it('reports what it wrote, read back off the document', () => {
    document.documentElement.dataset.theme = 'light';

    expect(normaliseCssValue(syncThemeColor(document.documentElement) ?? '')).toBe(
      normaliseCssValue(LIGHT_BG),
    );
  });
});

describe('theme-color edge cases', () => {
  it('leaves the markup value alone when no background resolves', () => {
    // No tokens.css in this block, so `--bg` resolves to nothing. Writing an
    // empty content attribute would be worse than leaving index.html's value.
    applyAppearance('dark', false)();

    expect(themeColor()).toBe(UNSET);
    expect(syncThemeColor(document.documentElement)).toBeNull();
  });

  it('does nothing when the page has no theme-color tag', () => {
    loadTokensCss();
    themeColorMeta().remove();
    document.documentElement.dataset.theme = 'dark';

    expect(syncThemeColor(document.documentElement)).toBeNull();
  });

  it('still sets the theme attribute when there is no tag to update', () => {
    themeColorMeta().remove();

    applyAppearance('light', false)();

    expect(document.documentElement.dataset.theme).toBe('light');
  });
});

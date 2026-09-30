/**
 * Property 26 — High_Contrast_Dark strictly improves contrast without leaving
 * the dark family. Web_Client half.
 *
 * Requirement 9.2.
 *
 * design.md states the property in two clauses, and this file asserts both:
 *
 *   1. **Monotone non-decreasing contrast.** For every text or border token,
 *      its contrast ratio against each surface it is rendered on in
 *      High_Contrast_Dark is greater than or equal to its ratio in Dark.
 *      Strictly greater for the secondary text and border tokens; equal is
 *      allowed for the rest, because primary text and the text accent are not
 *      overridden and so measure identically.
 *   2. **The dark family is intact.** `--bg`, `--surface` and `--surface-raised`
 *      are pixel-identical between Dark and High_Contrast_Dark.
 *
 * **This is a relationship between two appearances, not an absolute bar.** It
 * says nothing about whether any token clears 4.5:1 or 3:1 — that is Property 16
 * (`property-16-*`). Property 26 only compares hc-dark against dark, so no
 * threshold is read here; the whole content is `ratio(hcDark) >= ratio(dark)`,
 * tightened to `>` for the two tokens the appearance actually changes.
 *
 * **The generator is the token set, not a hand-listed pair.** The property
 * ranges over every text-and-border token crossed with every surface, drawn
 * from the registry. The strict-improvement set is likewise derived — it is
 * exactly the text-and-border tokens the `highContrastDarkExtensions` group
 * overrides — rather than the literal names `--text-secondary` and `--border`.
 * So if the override set ever changes (a third token is raised, or one stops
 * being raised), the property keeps holding without an edit here: a newly
 * overridden token must strictly improve, and a no-longer-overridden one need
 * only not regress.
 *
 * **How the two appearances are modelled.** `tokens.css` reaches hc-dark by
 * redeclaring two custom properties in the more specific `:root[data-theme=
 * 'hc-dark']` block; everything else is inherited from the grouped dark block,
 * `:root[data-theme='dark'], :root[data-theme='hc-dark']`. `resolve()` mirrors
 * that cascade exactly: the dark value of a token is its base declaration, and
 * the hc-dark value is the base overlaid with any `highContrastDarkExtensions`
 * entry of the same name. That the override group holds exactly the two entries
 * Requirement 9.2 raises is asserted by the `flag does real work` block, so the
 * property cannot pass vacuously by the group being empty.
 *
 * Runs in the jsdom project; it needs no filesystem, the registry arrives as an
 * imported module. No colour literal is written here, per Requirement 1.5 —
 * every colour comes out of the registry through `resolve()`.
 *
 * _Requirements: 9.2_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { contrastRatio, roundRatio } from './contrast';
import {
  extensions,
  highContrastDarkExtensions,
  tokens,
  type RegistryEntry,
} from './registry-model';

/** The design.md floor: 100 generated cases per property, both clients. */
const RUNS = { numRuns: 100 } as const;

/**
 * The colour role a custom property plays where it is rendered.
 *
 * Property 26 ranges over the tokens that are drawn as **text** or as a
 * **border line** — the things whose contrast against a surface is a
 * legibility concern — so the role, not the name, decides membership. Surfaces
 * are the backdrops those tokens sit on and are handled separately by clause 2.
 */
type Role = 'text' | 'border' | 'surface' | 'other';

/**
 * The role of each custom property this property cares about, read off what the
 * token *is* rather than off a threshold. `--accent-text` is the accent in its
 * text-and-icon use (Requirement 11.4), so it is text; `--accent` proper is a
 * graphical colour and is not in scope here.
 */
const ROLES: Readonly<Record<string, Role>> = {
  '--text-primary': 'text',
  '--text-secondary': 'text',
  '--accent-text': 'text',
  '--border': 'border',
  '--bg': 'surface',
  '--surface': 'surface',
  '--surface-raised': 'surface',
};

/** The two appearances this property compares. */
type Appearance = 'dark' | 'hc-dark';

/**
 * Resolves a custom property to a concrete hex string in the given appearance,
 * following the same cascade `tokens.css` uses.
 *
 * The base value is the token's own declaration (from `tokens`, or from the
 * shared `extensions` group for `--accent-text`). In `hc-dark` a
 * `highContrastDarkExtensions` entry of the same name, if present, overrides it.
 * `--accent-text` is authored as `var(--accent)`, so a `var(--x)` value is
 * chased to the property it aliases.
 */
function resolve(name: string, appearance: Appearance): string {
  if (appearance === 'hc-dark') {
    const override = highContrastDarkExtensions[name];
    if (override !== undefined) {
      return resolveValue(name, override, appearance);
    }
  }
  const base = tokens[name] ?? extensions[name];
  if (base === undefined) {
    throw new Error(`no registry entry for ${name}`);
  }
  return resolveValue(name, base, appearance);
}

/** Reads an entry's value, chasing a single `var(--x)` alias if present. */
function resolveValue(name: string, entry: RegistryEntry, appearance: Appearance): string {
  const alias = /^var\(\s*(--[a-z0-9-]+)\s*\)$/i.exec(entry.value.trim());
  if (alias !== null) {
    if (alias[1] === name) {
      throw new Error(`${name} aliases itself`);
    }
    return resolve(alias[1], appearance);
  }
  return entry.value;
}

/** Every text-and-border token, in registry order. */
const TEXT_AND_BORDER = Object.keys(ROLES).filter(
  (name) => ROLES[name] === 'text' || ROLES[name] === 'border',
);

/** The three surface tokens a text or border colour is rendered against. */
const SURFACES = Object.keys(ROLES).filter((name) => ROLES[name] === 'surface');

/**
 * The text-and-border tokens the High_Contrast_Dark group actually overrides.
 * Derived, so the strict-improvement clause tracks the override set rather than
 * a hardcoded pair.
 */
const STRICTLY_IMPROVED = TEXT_AND_BORDER.filter(
  (name) => highContrastDarkExtensions[name] !== undefined,
);

/** A (token, surface) pair — one comparison of the property. */
interface Pairing {
  readonly token: string;
  readonly surface: string;
}

const PAIRINGS: Pairing[] = TEXT_AND_BORDER.flatMap((token) =>
  SURFACES.map((surface) => ({ token, surface })),
);

function anyOf<T>(values: readonly T[]): fc.Arbitrary<T> {
  if (values.length === 0) {
    throw new Error('the generated set is empty, so the property is vacuous');
  }
  return fc.constantFrom(...values);
}

describe('Property 26 — Requirement 9.2, hc-dark never lowers text or border contrast', () => {
  it('has each hc-dark ratio at least its dark ratio, strict where overridden', () => {
    fc.assert(
      fc.property(anyOf(PAIRINGS), ({ token, surface }: Pairing) => {
        // Surfaces are identical between the appearances (clause 2), so the
        // only thing that can move a ratio is the text/border colour itself.
        const surfaceDark = resolve(surface, 'dark');
        const surfaceHc = resolve(surface, 'hc-dark');

        const dark = contrastRatio(resolve(token, 'dark'), surfaceDark);
        const hc = contrastRatio(resolve(token, 'hc-dark'), surfaceHc);

        // Rounded to two places, the precision design.md quotes ratios at, so a
        // sub-perceptual float wobble cannot fail an otherwise-equal pair.
        const darkR = roundRatio(dark);
        const hcR = roundRatio(hc);

        expect(
          hcR,
          `${token} on ${surface}: hc-dark ${hcR}:1 is below dark ${darkR}:1 — ` +
            'High_Contrast_Dark must never reduce a text or border contrast ratio',
        ).toBeGreaterThanOrEqual(darkR);

        if (STRICTLY_IMPROVED.includes(token)) {
          expect(
            hcR,
            `${token} on ${surface}: hc-dark ${hcR}:1 does not beat dark ` +
              `${darkR}:1 — an overridden token has to strictly improve, or the ` +
              'high-contrast appearance is not worth offering',
          ).toBeGreaterThan(darkR);
        }
      }),
      RUNS,
    );
  });
});

describe('Property 26 — Requirement 9.2, the dark family is intact', () => {
  it('keeps every surface pixel-identical between the two appearances', () => {
    fc.assert(
      fc.property(anyOf(SURFACES), (surface: string) => {
        expect(
          resolve(surface, 'hc-dark'),
          `${surface} differs between Dark and High_Contrast_Dark — the ` +
            'high-contrast appearance must stay inside the WattVision §2 dark family',
        ).toBe(resolve(surface, 'dark'));
      }),
      RUNS,
    );
  });
});

describe('Property 26 — the model does real work', () => {
  // Without this block the property above could pass vacuously: an empty
  // override set makes STRICTLY_IMPROVED empty, and the strict clause would
  // never fire.
  it('overrides exactly the two text-and-border tokens Requirement 9.2 raises', () => {
    // Every override in the group is a text or border token — the group holds
    // no surface override, which is clause 2 stated from the other side.
    for (const name of Object.keys(highContrastDarkExtensions)) {
      expect(
        ROLES[name] === 'text' || ROLES[name] === 'border',
        `${name} is overridden by hc-dark but is not a text or border token`,
      ).toBe(true);
    }
    expect(
      STRICTLY_IMPROVED,
      'the strict-improvement set is empty, so the strict clause never fires',
    ).not.toHaveLength(0);
    expect([...STRICTLY_IMPROVED].sort()).toEqual(['--border', '--text-secondary']);
  });

  it('leaves primary text and the text accent unchanged, so they compare equal', () => {
    for (const name of ['--text-primary', '--accent-text']) {
      expect(
        highContrastDarkExtensions[name],
        `${name} is expected to be inherited unchanged by hc-dark`,
      ).toBeUndefined();
      expect(resolve(name, 'hc-dark')).toBe(resolve(name, 'dark'));
    }
  });

  it('generates a non-empty set of token/surface pairings', () => {
    expect(PAIRINGS).not.toHaveLength(0);
    expect(SURFACES).toHaveLength(3);
    // Four text-and-border tokens × three surfaces.
    expect(PAIRINGS).toHaveLength(TEXT_AND_BORDER.length * SURFACES.length);
  });

  it('pins the design.md measurements for the two raised tokens on the surface', () => {
    // design.md records the improvement on --surface: secondary text 5.81 →
    // 9.90, border 1.20 → 1.83. Pinned so a change to either palette value that
    // silently preserved the >= relationship would still be caught.
    const surface = resolve('--surface', 'dark');
    expect(roundRatio(contrastRatio(resolve('--text-secondary', 'dark'), surface))).toBe(5.81);
    expect(roundRatio(contrastRatio(resolve('--text-secondary', 'hc-dark'), surface))).toBe(9.9);
    expect(roundRatio(contrastRatio(resolve('--border', 'dark'), surface))).toBe(1.2);
    expect(roundRatio(contrastRatio(resolve('--border', 'hc-dark'), surface))).toBe(1.83);
  });
});

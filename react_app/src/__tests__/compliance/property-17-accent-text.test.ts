/**
 * Property 17 — the accent is never used as text where it fails 4.5:1.
 * Web_Client half.
 *
 * Requirements 11.3, 11.4.
 *
 * **The property, stated as design.md states it.** For any appearance,
 * *either* the accent-as-text token clears 4.5:1 against every surface it is
 * rendered on, *or* no text token in that appearance resolves to the raw
 * graphical accent. It is a disjunction per appearance, and writing it as a
 * disjunction — rather than collapsing it to one ratio check — is the point:
 * the two branches are independently checkable and the three appearances
 * satisfy the invariant by different branches.
 *
 *  - **dark** and **hc-dark** satisfy branch A. The `--accent-text` custom
 *    property is declared in the base `:root` block as an alias of `--accent`,
 *    so in both dark appearances it resolves to the graphical accent, which
 *    measures 10.84:1 on the card surface and clears 4.5:1 on every dark
 *    surface. The text token *is* the raw accent here, so branch B is false,
 *    and branch A carries the disjunction alone.
 *  - **light** satisfies both branches, and needs both to be checkable to prove
 *    the split did its job. Branch A: the light block overrides `--accent-text`
 *    to a darker value that clears 4.5:1 on all three light surfaces. Branch B:
 *    no text token resolves to the raw light accent, which measures only
 *    3.74:1 on the card surface and would fail as text. Banishing the raw
 *    accent from text is the whole reason `--accent-text` exists (Requirement
 *    11.4).
 *
 * **Where the values come from.** Every colour is read out of
 * `src/styles/token-registry.json`, never written as a literal — Requirement
 * 1.5 forbids colour literals outside `tokens.css` and the declared fixture
 * quarantine, and this file honours that. The dark surfaces and the graphical
 * `--accent` are WattVision `tokens`; the dark alias of `--accent-text` is an
 * `extensions` entry whose value is `var(--accent)`; the light surfaces, the
 * light graphical accent and the light `--accent-text` are
 * `lightAppearanceExtensions` entries.
 *
 * **What "the surfaces it appears on" means.** Task 3.2 switched
 * `.section__title` and `.row__value` from `var(--accent)` to
 * `var(--accent-text)` — the two places the accent was rendered as text. Those
 * sit on the appearance's three background surfaces (`--bg`, `--surface`,
 * `--surface-raised`), so branch A quantifies over exactly those three.
 *
 * **What "text token" means for branch B.** `--accent-text` is the one custom
 * property that is *the accent, used as text*. Branch B asks whether it (and
 * any future accent-derived text token) resolves to the raw graphical
 * `--accent`. In the dark appearances it does, by design; in light it must not.
 * The graphical `--accent` itself is not a text token — it is chart strokes,
 * fills and button fills — so its own contrast is Property 16's concern at the
 * 3:1 graphical threshold, not this property's 4.5:1 text threshold.
 *
 * **Cross-client parity.** `flutter_app/test/compliance/
 * property_17_accent_text_test.dart` states the identical disjunction over the
 * same three appearances and the same values, so Requirement 13.1 holds.
 *
 * Runs in the jsdom project; it needs no DOM, only the imported registry.
 *
 * _Requirements: 11.3, 11.4_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import registry from '../../styles/token-registry.json';
import { contrastRatio, roundRatio, type Rgb } from './contrast';

/** The design.md floor: 100 generated cases per property, both clients. */
const RUNS = { numRuns: 100 } as const;

/** The WCAG 2.1 body-text threshold Requirement 11.3 pins for accent-as-text. */
const ACCENT_TEXT_THRESHOLD = 4.5;

/**
 * The measured ratios design.md pins, quoted so the identity tests below fail
 * loudly if the registry's values drift off the figures the design records.
 * These are ratios, not colours, so they are not literals the scan is about.
 */
const DARK_ACCENT_TEXT_ON_SURFACE = 10.84;
const RAW_LIGHT_ACCENT_ON_SURFACE = 3.74;

/** The three appearances Property 17 quantifies over. */
const APPEARANCES = ['dark', 'hc-dark', 'light'] as const;
type Appearance = (typeof APPEARANCES)[number];

/** A named surface an accent-as-text colour is rendered on. */
interface Surface {
  readonly name: string;
  readonly value: string;
}

type TokenGroup = Readonly<Record<string, { readonly value: string }>>;

const tokens = registry.tokens as unknown as TokenGroup;
const extensions = registry.extensions as unknown as TokenGroup;
const lightExtensions =
  registry.lightAppearanceExtensions as unknown as TokenGroup;

/**
 * Reads a custom property's declared value from a group, or throws — a missing
 * token is a registry drift the property must not paper over.
 */
function read(group: TokenGroup, name: string): string {
  const entry = group[name];
  if (entry === undefined || typeof entry.value !== 'string') {
    throw new Error(`token-registry.json has no string value for ${name}`);
  }
  return entry.value;
}

/**
 * Resolves `var(--accent)`-style aliases to a concrete colour. `--accent-text`
 * in the dark block is declared as an alias of `--accent`, exactly as CSS
 * resolves it, so the alias is followed here rather than treated as opaque.
 */
function resolve(value: string): string {
  const alias = /^var\(\s*(--[\w-]+)\s*\)$/.exec(value.trim());
  if (alias === null) {
    return value;
  }
  // Only `--accent` is ever aliased in this property's inputs; follow it.
  if (alias[1] === '--accent') {
    return read(tokens, '--accent');
  }
  throw new Error(`unexpected alias ${value} in an accent-text resolution`);
}

/** The concrete accent-as-text colour that renders in an appearance. */
function accentTextOf(appearance: Appearance): string {
  return appearance === 'light'
    ? read(lightExtensions, '--accent-text')
    : resolve(read(extensions, '--accent-text'));
}

/** The raw *graphical* accent for an appearance — what text must not become. */
function rawAccentOf(appearance: Appearance): string {
  return appearance === 'light'
    ? read(lightExtensions, '--accent')
    : read(tokens, '--accent');
}

/** The three background surfaces the accent-as-text colour is rendered on. */
function surfacesOf(appearance: Appearance): Surface[] {
  const group = appearance === 'light' ? lightExtensions : tokens;
  return [
    { name: '--bg', value: read(group, '--bg') },
    { name: '--surface', value: read(group, '--surface') },
    { name: '--surface-raised', value: read(group, '--surface-raised') },
  ];
}

/**
 * The text-role colours the appearance carries that are made of the accent.
 * Today that is exactly `--accent-text`; a list so a future accent-derived text
 * token is caught by branch B automatically.
 */
function accentTextTokensOf(
  appearance: Appearance,
): { readonly name: string; readonly value: string }[] {
  return [{ name: '--accent-text', value: accentTextOf(appearance) }];
}

/** Case-insensitive hex equality, so upper- and lower-case hex compare equal. */
function sameColour(a: string, b: string): boolean {
  return a.trim().toLowerCase() === b.trim().toLowerCase();
}

interface BranchResult {
  readonly holds: boolean;
  readonly detail: string;
}

/** Branch A: `--accent-text` clears 4.5:1 on every surface it appears on. */
function branchA(appearance: Appearance): BranchResult {
  const accentText = accentTextOf(appearance);
  const failures: string[] = [];
  let worst = Number.POSITIVE_INFINITY;
  for (const surface of surfacesOf(appearance)) {
    const ratio = contrastRatio(accentText, surface.value);
    worst = Math.min(worst, ratio);
    if (ratio < ACCENT_TEXT_THRESHOLD) {
      failures.push(`${surface.name} at ${roundRatio(ratio)}:1`);
    }
  }
  return {
    holds: failures.length === 0,
    detail:
      failures.length === 0
        ? `--accent-text clears ${ACCENT_TEXT_THRESHOLD}:1 on every surface (worst ${roundRatio(worst)}:1)`
        : `--accent-text fails ${ACCENT_TEXT_THRESHOLD}:1 on ${failures.join(', ')}`,
  };
}

/** Branch B: no text token resolves to the raw graphical accent. */
function branchB(appearance: Appearance): BranchResult {
  const rawAccent = rawAccentOf(appearance);
  const offenders = accentTextTokensOf(appearance)
    .filter((token) => sameColour(token.value, rawAccent))
    .map((token) => token.name);
  return {
    holds: offenders.length === 0,
    detail:
      offenders.length === 0
        ? 'no text token resolves to the raw accent'
        : `${offenders.join(', ')} resolve(s) to the raw graphical accent`,
  };
}

/** The worst (lowest) contrast a colour gets across an appearance's surfaces. */
function worstRatioOn(colour: string | Rgb, appearance: Appearance): number {
  return surfacesOf(appearance)
    .map((surface) => contrastRatio(colour, surface.value))
    .reduce((lowest, ratio) => Math.min(lowest, ratio), Number.POSITIVE_INFINITY);
}

describe('Property 17 — the accent is never used as text where it fails 4.5:1', () => {
  it('holds the disjunction for every appearance', () => {
    fc.assert(
      fc.property(fc.constantFrom(...APPEARANCES), (appearance: Appearance) => {
        const a = branchA(appearance);
        const b = branchB(appearance);
        // The disjunction itself. A violation would take *both* an
        // --accent-text that fails contrast *and* a text token still resolving
        // to the raw accent — reporting both branches makes that legible.
        expect(
          a.holds || b.holds,
          `Property 17 violated for ${appearance}: neither branch holds.\n` +
            `  branch A (contrast): ${a.detail}\n` +
            `  branch B (no raw accent as text): ${b.detail}`,
        ).toBe(true);
      }),
      RUNS,
    );
  });

  // The branches are independently checkable — the point of the disjunction.
  // These pin *which* branch each appearance satisfies, so a regression that
  // silently flipped an appearance from one branch to the other (light losing
  // its --accent-text override and falling back to the raw accent, say) is
  // caught even while the disjunction as a whole still passes.

  it('dark satisfies branch A — --accent-text aliases the accent at 10.84:1', () => {
    const a = branchA('dark');
    const b = branchB('dark');
    expect(a.holds, a.detail).toBe(true);
    // Branch B is false here, on purpose: the text accent is the raw accent.
    expect(b.holds, 'in dark the text accent is the raw accent by design').toBe(
      false,
    );
    expect(sameColour(accentTextOf('dark'), rawAccentOf('dark'))).toBe(true);
    // The measured value design.md pins for the accent on the card surface.
    expect(
      roundRatio(contrastRatio(accentTextOf('dark'), read(tokens, '--surface'))),
    ).toBe(DARK_ACCENT_TEXT_ON_SURFACE);
  });

  it('hc-dark satisfies branch A the same way as dark', () => {
    const a = branchA('hc-dark');
    const b = branchB('hc-dark');
    expect(a.holds, a.detail).toBe(true);
    expect(b.holds, 'hc-dark inherits the accent-as-text alias').toBe(false);
    // hc-dark shares the dark surfaces, so the alias resolves the same way.
    expect(sameColour(accentTextOf('hc-dark'), rawAccentOf('hc-dark'))).toBe(true);
    expect(
      roundRatio(
        contrastRatio(accentTextOf('hc-dark'), read(tokens, '--surface')),
      ),
    ).toBe(DARK_ACCENT_TEXT_ON_SURFACE);
  });

  it('light satisfies both branches — and needs both to prove the split', () => {
    const a = branchA('light');
    const b = branchB('light');

    // Branch A: the darkened text accent clears 4.5:1 on all three surfaces.
    expect(a.holds, a.detail).toBe(true);

    // Branch B: no text token is the raw graphical light accent — the value
    // that measures 3.74:1 on the card surface and would fail as text.
    expect(b.holds, b.detail).toBe(true);
    expect(sameColour(accentTextOf('light'), rawAccentOf('light'))).toBe(false);

    // And the raw light accent genuinely fails as text — a sanity bound so
    // branch B is not vacuous.
    expect(
      worstRatioOn(rawAccentOf('light'), 'light'),
      'the raw light accent must fail as text for Property 17 to have ' +
        'anything to protect against',
    ).toBeLessThan(ACCENT_TEXT_THRESHOLD);
    // The pinned figure design.md records for the raw light accent on the
    // light card surface.
    expect(
      roundRatio(
        contrastRatio(rawAccentOf('light'), read(lightExtensions, '--surface')),
      ),
    ).toBe(RAW_LIGHT_ACCENT_ON_SURFACE);
  });
});

/**
 * Property 16 — every text token meets its contrast threshold on every surface
 * in every appearance. Web_Client half.
 *
 * design.md, Property 16:
 *
 * > *For any* appearance, *any* text token and *any* surface token it is
 * > rendered on, the WCAG 2.1 contrast ratio meets the threshold required for
 * > that text role: 4.5:1 for body and secondary text, 3:1 for KPI and title
 * > text, and 3:1 for focus indicators against the adjacent background.
 *
 * Generators: `appearance` — Dark, High_Contrast_Dark, Light; `textToken` —
 * the text and accent-text tokens with their declared roles; `surfaceToken` —
 * background, surface and surface-raised.
 * Invariant: `contrastRatio(text, surface) >= thresholdFor(role)`, using the
 * shared linearised-sRGB maths in `contrast.ts`.
 *
 * _Validates: Requirements 11.1, 11.2, 11.7, 9.5_
 *
 * ## Modelling decisions
 *
 * **The three appearances only.** design.md names Dark, High_Contrast_Dark and
 * Light. `system` is not a fourth case: `App.tsx` resolves it to `dark` or
 * `light` via `prefers-color-scheme` and it owns no palette, so testing it
 * would test one of the other three twice. Palettes are resolved from
 * `token-registry.json` through `registry-model.ts` — the same registry
 * `tokens.css` mirrors — rather than restated here, so no colour literal is
 * written in this file (Requirement 1.5).
 *
 * **Which text token maps to which role, and therefore which threshold.**
 * The criterion gives three roles and two thresholds:
 *
 * - body text and secondary/label text — 4.5:1 (Requirement 11.1);
 * - text at the KPI type size and the title type size — 3:1, as large text
 *   (Requirement 11.2);
 * - focus indicators — 3:1 (Requirement 11.7).
 *
 * The three text tokens are `--text-primary`, `--text-secondary` and
 * `--accent-text`. Their roles:
 *
 * - `--text-secondary` is *secondary/label* text by definition. Role:
 *   body-grade, **4.5:1** (Requirement 11.1).
 * - `--text-primary` sets body copy *and* KPI numerals and titles, spanning a
 *   4.5:1 use and a 3:1 use. The strictest use wins — a colour that clears
 *   4.5:1 clears 3:1 too, whereas asserting the looser 3:1 on a token that
 *   also sets body text would let a body-failing colour through. Role:
 *   body-grade, **4.5:1**.
 * - `--accent-text` is the accent used as text: `.section__title` and
 *   `.row__value` in `global.css`. Requirement 11.4 and the design's
 *   accent-as-text measurements are stated against the 4.5:1 body threshold,
 *   not the 3:1 large-text one, so accent-as-text is held to **4.5:1**. This is
 *   the conservative reading: the light `--accent-text` was chosen precisely so
 *   it clears 4.5:1 on all three light surfaces (5.79 / 5.31 / 4.99), and
 *   holding it to 3:1 would hide a regression that dropped it below 4.5:1.
 *
 * The mapping is recorded as an explicit role per token in {@link TEXT_TOKENS};
 * the threshold comes from {@link thresholdFor}, so no magic number is attached
 * to a token. The 3:1 KPI/title and focus thresholds are pinned in the
 * role/threshold block so the looser branch of {@link thresholdFor} is not dead
 * code.
 *
 * **Which (text, surface) pairs are realisable.** The realisability policy is:
 * assert every text token against all three surfaces. Every text colour is
 * rendered on the page background, on card surfaces and on the raised surface
 * (`--surface-raised` is the table row hover and focus background, where the
 * same row text sits, including `.row__value`). No pair among these three
 * tokens is genuinely impossible, so nothing is over-narrowed and a real
 * failure on any surface is caught.
 *
 * **Requirement 9.5** requires the light appearance to meet the same criteria
 * as the dark ones, which is why Light is one of the three generated
 * appearances.
 *
 * If a real token/surface/appearance combination fails, this property reports
 * the counterexample with its measured ratio. It must not be made to pass by
 * weakening a threshold or a role — that would mask an accessibility defect
 * that needs a colour decision.
 *
 * Runs in the jsdom project: it needs no filesystem access, only the imported
 * registry module. The numbers written here — 4.5, 3, cardinalities and the
 * pinned reference ratios — are thresholds and measurements, not colours.
 *
 * _Requirements: 11.1, 11.2, 11.7, 9.5_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { contrastRatio, roundRatio } from './contrast';
import {
  extensions,
  highContrastDarkExtensions,
  lightAppearanceExtensions,
  tokens,
  type RegistryEntry,
} from './registry-model';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

// --- appearances -------------------------------------------------------------

/** The three appearances Property 16 ranges over; `system` is excluded. */
type AppearanceId = 'dark' | 'hc-dark' | 'light';

const APPEARANCES: readonly AppearanceId[] = ['dark', 'hc-dark', 'light'] as const;

// --- roles and thresholds ----------------------------------------------------

/** A text role and the WCAG threshold the criterion assigns it. */
type Role = 'body' | 'kpiTitle' | 'focus';

const ROLE_THRESHOLD: Readonly<Record<Role, number>> = {
  // body and secondary/label text — Requirement 11.1
  body: 4.5,
  // KPI numerals and titles, as large text — Requirement 11.2
  kpiTitle: 3,
  // focus indicators against the adjacent background — Requirement 11.7
  focus: 3,
};

/**
 * The threshold a role must clear — a function over the role, so the mapping is
 * `token -> role -> threshold` and no number is hardcoded per token.
 */
function thresholdFor(role: Role): number {
  return ROLE_THRESHOLD[role];
}

// --- resolving a hex value from the registry --------------------------------

/**
 * The `value` of a registry entry, or the entry it aliases.
 *
 * `--accent-text` in the shared dark extensions is a `color-alias` whose value
 * is `var(--accent)`; it is resolved to the accent token's own hex so the dark
 * appearances measure the colour they actually render. Every other entry
 * carries a hex string directly.
 */
function hexOf(entry: RegistryEntry): string {
  const value = entry.value.trim();
  const alias = /^var\(\s*(--[\w-]+)\s*\)$/.exec(value);
  if (alias !== null) {
    const target = alias[1];
    // The only alias in play is --accent-text -> --accent, which lives in the
    // base :root tokens block.
    const resolved = tokens[target];
    if (resolved === undefined) {
      throw new Error(`alias ${value} points at unknown token ${target}`);
    }
    return resolved.value.trim();
  }
  if (!value.startsWith('#')) {
    throw new Error(`entry value ${JSON.stringify(value)} is not a hex colour`);
  }
  return value;
}

// --- palette resolution per appearance --------------------------------------

/**
 * The text and surface colours an appearance actually renders, resolved from
 * the registry in the same way the cascade resolves them:
 *
 * - **dark** — text and surfaces from the base `tokens` block; `--accent-text`
 *   from the shared `extensions` block, aliasing `--accent`.
 * - **hc-dark** — as dark, but `--text-secondary` is overridden by the
 *   High_Contrast_Dark block; surfaces and primary text are inherited from the
 *   grouped dark block unchanged (Requirement 9.2), and `--accent-text` still
 *   aliases the accent.
 * - **light** — every value from the light block, including its own
 *   `--accent-text` override.
 */
interface ResolvedPalette {
  readonly textPrimary: string;
  readonly textSecondary: string;
  readonly accentText: string;
  readonly background: string;
  readonly surface: string;
  readonly surfaceRaised: string;
}

function paletteFor(appearance: AppearanceId): ResolvedPalette {
  switch (appearance) {
    case 'dark':
      return {
        textPrimary: hexOf(tokens['--text-primary']),
        textSecondary: hexOf(tokens['--text-secondary']),
        accentText: hexOf(extensions['--accent-text']),
        background: hexOf(tokens['--bg']),
        surface: hexOf(tokens['--surface']),
        surfaceRaised: hexOf(tokens['--surface-raised']),
      };
    case 'hc-dark':
      return {
        textPrimary: hexOf(tokens['--text-primary']),
        // The one override that changes contrast, per Requirement 9.2.
        textSecondary: hexOf(highContrastDarkExtensions['--text-secondary']),
        accentText: hexOf(extensions['--accent-text']),
        // Inherited from the grouped dark block — the family constraint.
        background: hexOf(tokens['--bg']),
        surface: hexOf(tokens['--surface']),
        surfaceRaised: hexOf(tokens['--surface-raised']),
      };
    case 'light':
      return {
        textPrimary: hexOf(lightAppearanceExtensions['--text-primary']),
        textSecondary: hexOf(lightAppearanceExtensions['--text-secondary']),
        accentText: hexOf(lightAppearanceExtensions['--accent-text']),
        background: hexOf(lightAppearanceExtensions['--bg']),
        surface: hexOf(lightAppearanceExtensions['--surface']),
        surfaceRaised: hexOf(lightAppearanceExtensions['--surface-raised']),
      };
  }
}

// --- text tokens and surfaces ------------------------------------------------

interface TextTokenSpec {
  readonly name: string;
  readonly role: Role;
  readonly colour: (palette: ResolvedPalette) => string;
}

/** The three text tokens, each with its declared role. */
const TEXT_TOKENS: readonly TextTokenSpec[] = [
  { name: '--text-primary', role: 'body', colour: (p) => p.textPrimary },
  { name: '--text-secondary', role: 'body', colour: (p) => p.textSecondary },
  { name: '--accent-text', role: 'body', colour: (p) => p.accentText },
] as const;

interface SurfaceTokenSpec {
  readonly name: string;
  readonly colour: (palette: ResolvedPalette) => string;
}

/** The three surfaces: background, surface, surface-raised. */
const SURFACES: readonly SurfaceTokenSpec[] = [
  { name: '--bg', colour: (p) => p.background },
  { name: '--surface', colour: (p) => p.surface },
  { name: '--surface-raised', colour: (p) => p.surfaceRaised },
] as const;

/** The contrast ratio of a text token on a surface in an appearance. */
function ratioOf(
  appearance: AppearanceId,
  token: TextTokenSpec,
  surface: SurfaceTokenSpec,
): number {
  const palette = paletteFor(appearance);
  return contrastRatio(token.colour(palette), surface.colour(palette));
}

/** Every realisable (appearance, token, surface) triple. */
interface Combination {
  readonly appearance: AppearanceId;
  readonly token: TextTokenSpec;
  readonly surface: SurfaceTokenSpec;
}

const COMBINATIONS: readonly Combination[] = APPEARANCES.flatMap((appearance) =>
  TEXT_TOKENS.flatMap((token) =>
    SURFACES.map((surface) => ({ appearance, token, surface })),
  ),
);

// --- tests -------------------------------------------------------------------

describe('Property 16 — text contrast across appearances', () => {
  it('every text token clears its threshold on every surface', () => {
    fc.assert(
      fc.property(fc.constantFrom(...COMBINATIONS), ({ appearance, token, surface }) => {
        const ratio = ratioOf(appearance, token, surface);
        const threshold = thresholdFor(token.role);
        expect(
          ratio,
          `${token.name} (${token.role}) on ${surface.name} in ${appearance} ` +
            `measures ${roundRatio(ratio)}:1, below the required ${threshold}:1. ` +
            'This is a real accessibility defect — do not weaken the threshold ' +
            'to pass it.',
        ).toBeGreaterThanOrEqual(threshold);
      }),
      RUNS,
    );
  });

  it('holds for every realisable pair, exhaustively', () => {
    // The sampled property cannot guarantee coverage of a 27-triple grid, so
    // the full grid is walked here — this is the assertion that actually
    // proves no realisable triple falls short.
    const failures: string[] = [];
    for (const { appearance, token, surface } of COMBINATIONS) {
      const ratio = ratioOf(appearance, token, surface);
      const threshold = thresholdFor(token.role);
      if (ratio < threshold) {
        failures.push(
          `${token.name} (${token.role}) on ${surface.name} in ${appearance}: ` +
            `${roundRatio(ratio)}:1 < ${threshold}:1`,
        );
      }
    }
    expect(failures, `contrast failures:\n${failures.join('\n')}`).toHaveLength(0);
  });
});

describe('Property 16 — role/threshold mapping is sound', () => {
  it('matches the criterion thresholds', () => {
    expect(thresholdFor('body'), 'Requirement 11.1').toBe(4.5);
    expect(thresholdFor('kpiTitle'), 'Requirement 11.2').toBe(3);
    expect(thresholdFor('focus'), 'Requirement 11.7').toBe(3);
  });

  it('declares a role per token and a full 3x3x3 grid', () => {
    expect(TEXT_TOKENS).toHaveLength(3);
    expect(SURFACES).toHaveLength(3);
    expect(APPEARANCES).toHaveLength(3);
    expect(COMBINATIONS).toHaveLength(27);
    for (const token of TEXT_TOKENS) {
      expect(ROLE_THRESHOLD[token.role]).toBeGreaterThan(0);
    }
  });

  it('keeps High_Contrast_Dark inside the dark surface family', () => {
    // Requirement 9.2: surfaces are inherited from dark, only text/border rise.
    const dark = paletteFor('dark');
    const hc = paletteFor('hc-dark');
    expect(hc.background).toBe(dark.background);
    expect(hc.surface).toBe(dark.surface);
    expect(hc.surfaceRaised).toBe(dark.surfaceRaised);
  });
});

describe('Property 16 — known-good anchors, computed independently', () => {
  // Recomputed from the registry rather than copied, so the shared maths is
  // pinned against known answers that also appear on the Flutter side.
  const accentText = TEXT_TOKENS.find((t) => t.name === '--accent-text')!;
  const textSecondary = TEXT_TOKENS.find((t) => t.name === '--text-secondary')!;
  const surface = SURFACES.find((s) => s.name === '--surface')!;
  const background = SURFACES.find((s) => s.name === '--bg')!;
  const raised = SURFACES.find((s) => s.name === '--surface-raised')!;

  it('accent-text on the dark card surface is 10.84:1', () => {
    expect(roundRatio(ratioOf('dark', accentText, surface))).toBe(10.84);
  });

  it('hc-dark secondary text on the card surface is 9.90:1', () => {
    expect(roundRatio(ratioOf('hc-dark', textSecondary, surface))).toBe(9.9);
  });

  it('light accent-text clears 4.5:1 on all three light surfaces', () => {
    expect(roundRatio(ratioOf('light', accentText, surface))).toBe(5.79);
    expect(roundRatio(ratioOf('light', accentText, background))).toBe(5.31);
    expect(roundRatio(ratioOf('light', accentText, raised))).toBe(4.99);
  });
});

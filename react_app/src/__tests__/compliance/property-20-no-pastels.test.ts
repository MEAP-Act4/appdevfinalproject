/**
 * Property 20 — no appearance contains a pastel colour. Web_Client half.
 *
 * *For any* colour in *any* appearance's palette, it is not the case that HSL
 * lightness exceeds 0.8 while HSL saturation falls below 0.5, with white and
 * pure black excluded as achromatic and near-neutral greys excluded by the
 * registry's carve-out.
 *
 * **What this file proves, and what it does not restate.** `contrast.test.ts`
 * (task 1.5) pins the predicate itself — the two thresholds, the achromatic
 * exclusion, the near-neutral carve-out, and the resolution of the four
 * light-palette values phase 1 flagged. This file does not duplicate that. It
 * states the *universal* claim the predicate was built to support: run the
 * pastel predicate over every colour custom property in every shipped
 * appearance and nothing is flagged. Every threshold is read from
 * `pastelRule` in the registry through `contrast.ts`; no colour literal is
 * written here, per Requirement 1.5 — palette values come from
 * `token-registry.json`.
 *
 * **The generators.** The appearance is one of the three that resolve to a
 * palette — `dark`, `hc-dark`, `light`. The colour is every colour custom
 * property that appearance renders, enumerated from the registry via
 * `registry-model.ts`: for the two dark appearances that is the WattVision
 * colour tokens plus the shared dark colour extensions, with the
 * High_Contrast_Dark overrides applied on top for `hc-dark`; for `light` it is
 * the light-appearance colour extensions. A property added to any of those
 * groups becomes an input here by existing. The two generators are combined, so
 * the property runs over the full appearance × colour grid.
 *
 * **The carve-out is made to earn its place.** A rule that exempted everything
 * would also pass this property, so a worked example of a genuine pastel — a
 * light colour that is weakly *but really* saturated, saturation strictly
 * between the 0.2 neutral floor and the 0.5 pastel ceiling — is asserted to be
 * flagged. If a future edit widened `neutral.saturationAtMost` towards 0.5,
 * that example would stop being flagged and this file would fail, which is the
 * guard that keeps the carve-out from quietly swallowing the rule. The approach
 * mirrors the `chalky`/`offWhite` anchors in `contrast.test.ts` on a distinct
 * value; the file is not duplicated.
 *
 * **On failure.** A real palette colour reading as a pastel means a value
 * regressed or the carve-out is mis-set. The remedy is not to loosen the
 * thresholds; it is to fix the colour. The counterexample carries the offending
 * property's lightness and saturation.
 *
 * Runs in the jsdom project because it needs no filesystem access — the
 * registry arrives as an imported module.
 *
 * _Validates: Requirements 9.8_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import {
  NEUTRAL_SATURATION_AT_MOST,
  PASTEL_LIGHTNESS_ABOVE,
  PASTEL_SATURATION_BELOW,
  hslLightness,
  hslSaturation,
  isNeutral,
  isPastel,
} from './contrast';
import {
  extensions,
  highContrastDarkExtensions,
  lightAppearanceExtensions,
  tokens,
  type RegistryEntry,
} from './registry-model';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/** The three appearances that resolve to a palette. `system` renders one of
 * these three and contributes no palette of its own, so it is not one of them —
 * design.md's Property 20 names exactly these three. */
type PaletteAppearance = 'dark' | 'hc-dark' | 'light';
const PALETTE_APPEARANCES: readonly PaletteAppearance[] = ['dark', 'hc-dark', 'light'];

/** One appearance × one named colour: the shape the property generates over. */
interface PaletteColour {
  readonly appearance: PaletteAppearance;
  readonly name: string;
  readonly value: string;
}

/**
 * A hex colour value from a registry entry, or `null` when the entry carries no
 * resolvable hex value.
 *
 * Only `type === 'color'` entries hold a hex literal. `color-alias`
 * (`--accent-text` → `var(--accent)`), `shadow` and the `rgba()` `--scrim` are
 * deliberately skipped: an alias contributes the value it points at, which is
 * already enumerated under its own name, and a shadow or scrim is not a palette
 * colour the pastel rule is about.
 */
function hexValueOf(entry: RegistryEntry): string | null {
  if (entry.type !== 'color') {
    return null;
  }
  return entry.value.startsWith('#') ? entry.value : null;
}

/** Every `--name` → hex pair in a registry group whose entries are colours. */
function colourEntries(
  group: Readonly<Record<string, RegistryEntry>>,
): Array<readonly [string, string]> {
  return Object.entries(group).flatMap(([name, entry]) => {
    const hex = hexValueOf(entry);
    return hex === null ? [] : [[name, hex] as const];
  });
}

/**
 * The colour custom properties an appearance renders, as a `--name` → hex map.
 *
 * The two dark appearances start from the shared WattVision colour tokens and
 * the shared dark colour extensions. `hc-dark` then applies the
 * High_Contrast_Dark overrides on top, which is how CSS reaches that appearance:
 * the same custom-property names redeclared in a more specific block. The light
 * appearance is its own extension group.
 */
function paletteColours(appearance: PaletteAppearance): Map<string, string> {
  const colours = new Map<string, string>();

  if (appearance === 'light') {
    for (const [name, hex] of colourEntries(lightAppearanceExtensions)) {
      colours.set(name, hex);
    }
    return colours;
  }

  // dark and hc-dark share the §2/§3 tokens and the shared dark extensions.
  for (const [name, hex] of colourEntries(tokens)) {
    colours.set(name, hex);
  }
  for (const [name, hex] of colourEntries(extensions)) {
    colours.set(name, hex);
  }

  if (appearance === 'hc-dark') {
    // Requirement 9.2: the overrides redeclare existing property names, so a
    // set() overwrites the dark value the same way the more specific CSS block
    // does at run time.
    for (const [name, hex] of colourEntries(highContrastDarkExtensions)) {
      colours.set(name, hex);
    }
  }

  return colours;
}

/** The full appearance × colour grid, enumerated from the registry. */
function allPaletteColours(): PaletteColour[] {
  return PALETTE_APPEARANCES.flatMap((appearance) =>
    [...paletteColours(appearance).entries()].map(([name, value]) => ({
      appearance,
      name,
      value,
    })),
  );
}

const ALL = allPaletteColours();

/** Uniform choice over the grid, so the registry is the generator. */
function anyPaletteColour(): fc.Arbitrary<PaletteColour> {
  if (ALL.length === 0) {
    throw new Error('the palette grid is empty, so the property is vacuous');
  }
  return fc.constantFrom(...ALL);
}

describe('Property 20 — no appearance contains a pastel colour', () => {
  it('flags no colour in any appearance palette', () => {
    fc.assert(
      fc.property(anyPaletteColour(), ({ appearance, name, value }: PaletteColour) => {
        const l = hslLightness(value);
        const s = hslSaturation(value);
        expect(
          isPastel(value),
          `the ${name} colour in ${appearance} reads as a pastel: HSL ` +
            `lightness ${l.toFixed(4)} (> ${PASTEL_LIGHTNESS_ABOVE}) and ` +
            `saturation ${s.toFixed(4)} (< ${PASTEL_SATURATION_BELOW}), and it ` +
            'is not neutral. A palette value regressed or the carve-out is ' +
            'mis-set — fix the colour, do not loosen the thresholds.',
        ).toBe(false);
      }),
      RUNS,
    );
  });

  it('covers all three appearances, drawing from a non-empty palette each', () => {
    // A property that generated over an empty or partial grid would pass
    // vacuously, so the grid it draws from is pinned.
    for (const appearance of PALETTE_APPEARANCES) {
      const forAppearance = ALL.filter((entry) => entry.appearance === appearance);
      expect(
        forAppearance.length,
        `${appearance} contributes no colours to the grid`,
      ).toBeGreaterThan(0);
    }
    // hc-dark inherits the whole dark palette, so the two dark appearances hold
    // the same number of colours; light is its own group.
    const darkCount = ALL.filter((e) => e.appearance === 'dark').length;
    const hcCount = ALL.filter((e) => e.appearance === 'hc-dark').length;
    expect(hcCount).toBe(darkCount);
  });

  it('does not swallow the rule: a genuine pastel is still flagged', () => {
    // A light colour that is weakly *but genuinely* saturated: saturation
    // strictly between the 0.2 neutral floor and the 0.5 pastel ceiling, and
    // lightness above 0.8. This is exactly the shape WattVision §6 is about, so
    // the predicate must flag it. If a future edit widened
    // neutral.saturationAtMost towards 0.5, this colour would fall inside the
    // carve-out and stop being flagged — and this assertion would fail, before
    // any real palette value could slip through unnoticed. Built from channels
    // rather than a hex literal so no colour literal appears here (Requirement
    // 1.5); the value mirrors the `chalky` anchor in contrast.test.ts on a
    // distinct colour.
    const genuinePastel = { r: 242, g: 222, b: 230, a: 1 };
    const l = hslLightness(genuinePastel);
    const s = hslSaturation(genuinePastel);
    expect(l).toBeGreaterThan(PASTEL_LIGHTNESS_ABOVE);
    expect(s, 'above the neutral carve-out, so it is a real tint').toBeGreaterThan(
      NEUTRAL_SATURATION_AT_MOST,
    );
    expect(s, 'below the pastel saturation ceiling').toBeLessThan(PASTEL_SATURATION_BELOW);
    expect(isNeutral(genuinePastel)).toBe(false);
    expect(
      isPastel(genuinePastel),
      'a light, genuinely-tinted, weakly saturated colour is a pastel; if this ' +
        'stops being flagged the carve-out has been widened too far',
    ).toBe(true);
  });
});

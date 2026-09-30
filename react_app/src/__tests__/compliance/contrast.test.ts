/**
 * Reference tests for the colour maths in `./contrast.ts`.
 *
 * Thirty property tests are going to lean on these functions, so the maths
 * itself is pinned here against values that do not come from this codebase:
 * the 21:1 white-on-black extreme, the 1:1 identity, WebAIM's published
 * boundary grey, pure blue on white, and the 10.84:1 pair Requirement 11.3
 * names. If the linearisation were wrong, the ratios would still be internally
 * consistent — only the published figures catch it.
 *
 * Palette values are read from `src/styles/token-registry.json`, never written
 * as literals. The handful of literals the parser and the published references
 * genuinely need live in `./fixtures/color-literals.ts`.
 *
 * _Requirements: 11.3, 9.8_
 */

import { describe, expect, it } from 'vitest';

import registry from '../../styles/token-registry.json';
import {
  ACHROMATIC_SATURATION_AT_MOST,
  CONTRAST_OFFSET,
  LUMINANCE_WEIGHTS,
  NEUTRAL_SATURATION_AT_MOST,
  PASTEL_LIGHTNESS_ABOVE,
  PASTEL_SATURATION_BELOW,
  contrastRatio,
  hslLightness,
  hslSaturation,
  isAchromatic,
  isNeutral,
  isPastel,
  lineariseChannel,
  parseColor,
  relativeLuminance,
  roundRatio,
  srgb,
} from './contrast';
import {
  BLACK,
  MALFORMED,
  MID_GREY,
  MID_GREY_LEGACY,
  MID_GREY_LEGACY_ALPHA,
  MID_GREY_MODERN,
  MID_GREY_MODERN_ALPHA,
  PURE_BLUE,
  PURE_RED_PERCENT,
  WHITE,
  WHITE_SHORTHAND,
  WHITE_SHORTHAND_HALF_ALPHA,
  WHITE_WITH_ALPHA,
} from './fixtures/color-literals';

/** The §2 primary accent, as the registry records it. */
const ACCENT = registry.tokens['--accent'].value;

/** The §2 card surface, as the registry records it. */
const CARD_SURFACE = registry.tokens['--surface'].value;

/** The dark-appearance OK box fill: a dark, low-lightness green. */
const DARK_NORMAL_FILL = registry.extensions['--normal-fill'].value;

describe('parseColor', () => {
  it('reads the six-digit hex form used throughout tokens.css', () => {
    expect(parseColor(WHITE)).toEqual(srgb(255, 255, 255));
    expect(parseColor(BLACK)).toEqual(srgb(0, 0, 0));
    expect(parseColor(MID_GREY)).toEqual(srgb(118, 118, 118));
  });

  it('expands the three-digit shorthand by doubling each digit', () => {
    expect(parseColor(WHITE_SHORTHAND)).toEqual(parseColor(WHITE));
  });

  it('reads alpha from the four- and eight-digit hex forms', () => {
    expect(parseColor(WHITE_WITH_ALPHA).a).toBeCloseTo(0.5, 2);
    expect(parseColor(WHITE_SHORTHAND_HALF_ALPHA).a).toBeCloseTo(0.533, 3);
  });

  it('reads the functional notation getComputedStyle returns', () => {
    const expected = srgb(118, 118, 118);
    expect(parseColor(MID_GREY_LEGACY)).toEqual(expected);
    expect(parseColor(MID_GREY_MODERN)).toEqual(expected);
  });

  it('reads alpha from both functional syntaxes', () => {
    expect(parseColor(MID_GREY_LEGACY_ALPHA).a).toBeCloseTo(0.5, 6);
    expect(parseColor(MID_GREY_MODERN_ALPHA).a).toBeCloseTo(0.5, 6);
  });

  it('resolves percentage channels against 255', () => {
    const red = parseColor(PURE_RED_PERCENT);
    expect(red.r).toBeCloseTo(255, 6);
    expect(red.g).toBeCloseTo(0, 6);
    expect(red.b).toBeCloseTo(0, 6);
  });

  it('throws rather than guessing at an unparseable value', () => {
    for (const bad of MALFORMED) {
      expect(() => parseColor(bad), `expected ${JSON.stringify(bad)} to throw`).toThrow();
    }
  });
});

describe('sRGB linearisation', () => {
  it('fixes both endpoints', () => {
    expect(lineariseChannel(0)).toBe(0);
    expect(lineariseChannel(1)).toBeCloseTo(1, 12);
  });

  it('uses the linear segment at and below the knee', () => {
    expect(lineariseChannel(0.03928)).toBeCloseTo(0.03928 / 12.92, 12);
  });

  it('is monotonically increasing across the knee', () => {
    let previous = -1;
    for (let step = 0; step <= 255; step += 1) {
      const value = lineariseChannel(step / 255);
      expect(value).toBeGreaterThan(previous);
      previous = value;
    }
  });

  it('weights the green channel most heavily', () => {
    expect(LUMINANCE_WEIGHTS.g).toBeGreaterThan(LUMINANCE_WEIGHTS.r);
    expect(LUMINANCE_WEIGHTS.r).toBeGreaterThan(LUMINANCE_WEIGHTS.b);
    const sum = LUMINANCE_WEIGHTS.r + LUMINANCE_WEIGHTS.g + LUMINANCE_WEIGHTS.b;
    expect(sum).toBeCloseTo(1, 12);
  });
});

describe('relativeLuminance', () => {
  it('spans the full unit interval between black and white', () => {
    expect(relativeLuminance(BLACK)).toBeCloseTo(0, 12);
    expect(relativeLuminance(WHITE)).toBeCloseTo(1, 12);
  });

  it('reproduces the luminances behind the Requirement 11.3 pair', () => {
    // design.md's research note quotes these as "L(accent) ~= 0.6327" and
    // "L(card) ~= 0.0130". The card value is exact to four places; the accent
    // value is a rounding slip in the prose — the WCAG computation gives
    // 0.632586, not 0.6327. The difference is 1.1e-4 of luminance and moves the
    // ratio by 0.002, so the 10.84:1 figure design.md pins is unaffected and
    // stands. Recorded here rather than silently accommodated.
    expect(relativeLuminance(ACCENT)).toBeCloseTo(0.6326, 4);
    expect(relativeLuminance(CARD_SURFACE)).toBeCloseTo(0.013, 4);
  });

  it('ignores alpha, because contrast is defined over composited colours', () => {
    expect(relativeLuminance(parseColor(WHITE_WITH_ALPHA))).toBeCloseTo(
      relativeLuminance(parseColor(WHITE)),
      12,
    );
  });
});

describe('contrastRatio', () => {
  it('gives exactly 21:1 for white on black', () => {
    expect(contrastRatio(WHITE, BLACK)).toBeCloseTo(21, 10);
  });

  it('gives exactly 1:1 for a colour against itself', () => {
    for (const colour of [WHITE, BLACK, ACCENT, CARD_SURFACE, MID_GREY]) {
      expect(contrastRatio(colour, colour)).toBeCloseTo(1, 12);
    }
  });

  it('is symmetric in its arguments', () => {
    const pairs: ReadonlyArray<readonly [string, string]> = [
      [WHITE, BLACK],
      [ACCENT, CARD_SURFACE],
      [MID_GREY, WHITE],
      [PURE_BLUE, WHITE],
      [DARK_NORMAL_FILL, ACCENT],
    ];
    for (const [a, b] of pairs) {
      expect(contrastRatio(a, b)).toBeCloseTo(contrastRatio(b, a), 12);
    }
  });

  it('never leaves the [1, 21] range', () => {
    const palette = [WHITE, BLACK, ACCENT, CARD_SURFACE, MID_GREY, PURE_BLUE];
    for (const a of palette) {
      for (const b of palette) {
        const ratio = contrastRatio(a, b);
        expect(ratio).toBeGreaterThanOrEqual(1);
        expect(ratio).toBeLessThanOrEqual(21);
      }
    }
  });

  it('matches the published figure for the WebAIM boundary grey on white', () => {
    expect(roundRatio(contrastRatio(MID_GREY, WHITE))).toBe(4.54);
  });

  it('matches the published figure for pure blue on white', () => {
    expect(roundRatio(contrastRatio(PURE_BLUE, WHITE))).toBe(8.59);
  });

  it('pins the Requirement 11.3 pair at 10.84:1 and clears 4.5:1', () => {
    const ratio = contrastRatio(ACCENT, CARD_SURFACE);
    expect(roundRatio(ratio)).toBe(10.84);
    expect(ratio).toBeGreaterThanOrEqual(4.5);
  });

  it('offsets both luminances by 0.05, so the floor is 1 and not infinity', () => {
    expect(CONTRAST_OFFSET).toBe(0.05);
    expect(contrastRatio(BLACK, BLACK)).toBeCloseTo(1, 12);
  });
});

describe('HSL lightness and saturation', () => {
  it('reads lightness from the raw channels, not the linearised ones', () => {
    // Mid grey sits at 118/255 of the way up the raw scale but only ~0.18 of
    // the way up the linearised one. Using the wrong one here would be
    // invisible in a contrast ratio and fatal to the pastel rule.
    expect(hslLightness(MID_GREY)).toBeCloseTo(118 / 255, 12);
    expect(relativeLuminance(MID_GREY)).toBeLessThan(0.25);
  });

  it('puts white at lightness 1 and black at lightness 0', () => {
    expect(hslLightness(WHITE)).toBe(1);
    expect(hslLightness(BLACK)).toBe(0);
  });

  it('reports zero saturation when the three channels are equal', () => {
    for (const grey of [WHITE, BLACK, MID_GREY]) {
      expect(hslSaturation(grey)).toBe(0);
      expect(isAchromatic(grey)).toBe(true);
    }
  });

  it('reports full saturation for a pure hue at mid lightness', () => {
    expect(hslSaturation(PURE_BLUE)).toBeCloseTo(1, 12);
    expect(hslLightness(PURE_BLUE)).toBeCloseTo(0.5, 12);
    expect(isAchromatic(PURE_BLUE)).toBe(false);
  });

  it('switches denominators either side of lightness 0.5', () => {
    // Two colours with the same chroma spread (0.2), mirrored about mid
    // lightness: one at L = 0.8, one at L = 0.2. HSL saturation is symmetric
    // under that reflection and both come out at 0.5, which only holds if the
    // (2 - max - min) branch is wired up correctly. Using the (max + min)
    // denominator for both would give 0.25 and 0.5 instead.
    const light = srgb(0.9 * 255, 0.7 * 255, 0.7 * 255);
    const dark = srgb(0.3 * 255, 0.1 * 255, 0.1 * 255);
    expect(hslLightness(light)).toBeCloseTo(0.8, 12);
    expect(hslLightness(dark)).toBeCloseTo(0.2, 12);
    expect(hslSaturation(light)).toBeCloseTo(0.5, 12);
    expect(hslSaturation(dark)).toBeCloseTo(0.5, 12);
  });
});

describe('the pastel rule', () => {
  it('takes its thresholds from the registry rather than restating them', () => {
    expect(PASTEL_LIGHTNESS_ABOVE).toBe(registry.pastelRule.lightnessAbove);
    expect(PASTEL_SATURATION_BELOW).toBe(registry.pastelRule.saturationBelow);
    expect(ACHROMATIC_SATURATION_AT_MOST).toBe(
      registry.pastelRule.achromatic.saturationAtMost,
    );
    expect(NEUTRAL_SATURATION_AT_MOST).toBe(
      registry.pastelRule.neutral.saturationAtMost,
    );
  });

  it('keeps the two pastel thresholds where they were', () => {
    // The task 3.2 carve-out narrows what the rule is asked about. It must not
    // have loosened what the rule demands of a colour that really is tinted, so
    // the predicate string is pinned alongside the numbers.
    expect(registry.pastelRule.predicate).toBe(
      'isPastel(c) = !isNeutral(c) && hslLightness(c) > 0.8 && hslSaturation(c) < 0.5',
    );
    expect(PASTEL_LIGHTNESS_ABOVE).toBeLessThan(1);
    expect(NEUTRAL_SATURATION_AT_MOST).toBeLessThan(PASTEL_SATURATION_BELOW);
    expect(ACHROMATIC_SATURATION_AT_MOST).toBeLessThan(NEUTRAL_SATURATION_AT_MOST);
  });

  it('excludes achromatic colours, so white is not a pastel', () => {
    expect(isPastel(WHITE)).toBe(false);
    expect(isPastel(BLACK)).toBe(false);
    expect(isPastel(MID_GREY)).toBe(false);
  });

  it('flags a light, weakly saturated colour', () => {
    const pale = srgb(245, 230, 235);
    expect(hslLightness(pale)).toBeGreaterThan(PASTEL_LIGHTNESS_ABOVE);
    expect(hslSaturation(pale)).toBeLessThan(PASTEL_SATURATION_BELOW);
    expect(isPastel(pale)).toBe(true);
  });

  it('clears a light colour that is strongly saturated', () => {
    const vivid = srgb(255, 200, 200);
    expect(hslLightness(vivid)).toBeGreaterThan(PASTEL_LIGHTNESS_ABOVE);
    expect(hslSaturation(vivid)).toBeGreaterThanOrEqual(PASTEL_SATURATION_BELOW);
    expect(isPastel(vivid)).toBe(false);
  });

  it('clears a weakly saturated colour that is not light', () => {
    const muted = srgb(120, 130, 125);
    expect(hslLightness(muted)).toBeLessThan(PASTEL_LIGHTNESS_ABOVE);
    expect(hslSaturation(muted)).toBeLessThan(PASTEL_SATURATION_BELOW);
    expect(isPastel(muted)).toBe(false);
  });

  it('clears the dark-appearance palette values it is handed', () => {
    for (const colour of [ACCENT, CARD_SURFACE, DARK_NORMAL_FILL]) {
      expect(isPastel(colour), `${colour} should not read as pastel`).toBe(false);
    }
  });
});

describe('the near-neutral carve-out', () => {
  // Task 3.2's user decision. `isAchromatic` stays as it was — a distinct,
  // stricter fact — and `isNeutral` is the wider exclusion the pastel rule now
  // uses. The threshold itself is not restated in this file; it is read from the
  // registry, so the only way to move it is to move it there.

  it('is wider than the achromatic exclusion and contains it', () => {
    for (const grey of [WHITE, BLACK, MID_GREY]) {
      expect(isAchromatic(grey)).toBe(true);
      expect(isNeutral(grey), 'every achromatic colour is neutral').toBe(true);
    }
  });

  it('admits a faintly cast grey that is not achromatic', () => {
    // One blue point away from a pure grey: hueless to any eye, but saturation
    // strictly above zero, which is the whole reason the carve-out exists.
    const faint = srgb(200, 200, 204);
    expect(isAchromatic(faint)).toBe(false);
    expect(hslSaturation(faint)).toBeGreaterThan(ACHROMATIC_SATURATION_AT_MOST);
    expect(hslSaturation(faint)).toBeLessThanOrEqual(NEUTRAL_SATURATION_AT_MOST);
    expect(isNeutral(faint)).toBe(true);
  });

  it('stops short of a colour with a nameable hue', () => {
    const tinted = srgb(245, 220, 220);
    expect(hslSaturation(tinted)).toBeGreaterThan(NEUTRAL_SATURATION_AT_MOST);
    expect(isNeutral(tinted)).toBe(false);
  });

  it('turns a light near-neutral from pastel into not-pastel', () => {
    // The behavioural change, stated on a synthetic value so it does not depend
    // on any particular palette entry. Both pastel thresholds are still met;
    // only the exclusion has moved.
    const offWhite = srgb(244, 245, 247);
    expect(hslLightness(offWhite)).toBeGreaterThan(PASTEL_LIGHTNESS_ABOVE);
    expect(hslSaturation(offWhite)).toBeLessThan(PASTEL_SATURATION_BELOW);
    expect(isAchromatic(offWhite)).toBe(false);
    expect(isNeutral(offWhite)).toBe(true);
    expect(isPastel(offWhite)).toBe(false);
  });

  it('records the decision and the reasoning behind the threshold', () => {
    const { neutral } = registry.pastelRule;
    expect(neutral.definition.trim()).toBeTruthy();
    expect(neutral.reason.trim()).toBeTruthy();
    expect(neutral.decidedBy).toContain('user');
    expect(registry.pastelRule.thresholdProvenance).toContain('neutral.saturationAtMost');
  });
});

describe('the four light-palette rule hits, after task 3.2', () => {
  // Task 1.7 recorded four near-neutral values in the light palette that the
  // predicate, as literally defined, flagged as pastels. Task 3.2 cleared all
  // four — but by two different means, and the distinction is the substance of
  // the resolution rather than a detail of it:
  //
  // - three are greys with a faint cast, and the rule was wrong about them: they
  //   are now excluded by the neutral carve-out, and their values did not move;
  // - one, `--normal-fill`, was a genuinely pale weakly-saturated green at
  //   saturation 0.429 — far above the carve-out — so the rule was right about
  //   it and the value moved instead.
  //
  // These assertions replace the ones that pinned all four as pastel. They pin
  // the new behaviour and, more importantly, pin *which mechanism* cleared each
  // one, so loosening the carve-out to absorb the fourth would fail here.

  /** Light-appearance values by custom-property name, skipping the `_about` note. */
  const lightPalette = new Map<string, string>();
  for (const [name, spec] of Object.entries(
    registry.lightAppearanceExtensions as Record<string, { value?: string }>,
  )) {
    if (typeof spec.value === 'string') {
      lightPalette.set(name, spec.value);
    }
  }

  const valueOf = (name: string): string => {
    const value = lightPalette.get(name);
    if (value === undefined) {
      throw new Error(`${name} is not a light-palette key`);
    }
    return value;
  };

  /** The three cleared by the carve-out, still at their original values. */
  const CLEARED_BY_CARVE_OUT = ['--bg', '--surface-raised', '--border'] as const;

  /** The one cleared by retuning the value. */
  const CLEARED_BY_RETUNE = '--normal-fill';

  it('records no remaining rule hits', () => {
    const { knownLiteralRuleHits } = registry.pastelRule;
    expect(knownLiteralRuleHits.values).toEqual([]);
    expect(knownLiteralRuleHits.clearedBy).toContain('3.2');
    // Kept as a field with its history rather than deleted, so a reader can see
    // what the four were and how each one went away.
    expect(knownLiteralRuleHits.note).toContain('--normal-fill');
    expect(knownLiteralRuleHits.appearance).toBe('light');
  });

  it.each(CLEARED_BY_CARVE_OUT)(
    '%s is cleared by the carve-out, on both pastel thresholds still being met',
    (name: string) => {
      const value = valueOf(name);
      // Still light and still weakly saturated — the thresholds were not
      // loosened. It is the neutral exclusion that takes it out of scope.
      expect(hslLightness(value), `${name} lightness`).toBeGreaterThan(
        PASTEL_LIGHTNESS_ABOVE,
      );
      expect(hslSaturation(value), `${name} saturation`).toBeLessThan(
        PASTEL_SATURATION_BELOW,
      );
      expect(isAchromatic(value), `${name} was never achromatic`).toBe(false);
      expect(isNeutral(value), `${name} neutral`).toBe(true);
      expect(isPastel(value), `${name} pastel`).toBe(false);
    },
  );

  it('clears --normal-fill on saturation, not by carve-out', () => {
    const value = valueOf(CLEARED_BY_RETUNE);
    // The retuned green is still a light colour, so the lightness threshold is
    // no help. It clears the rule because it is genuinely saturated, which is
    // the same footing its two siblings were always on.
    expect(hslLightness(value)).toBeGreaterThan(PASTEL_LIGHTNESS_ABOVE);
    expect(isNeutral(value), 'the carve-out must not be what saves it').toBe(false);
    expect(hslSaturation(value)).toBeGreaterThanOrEqual(PASTEL_SATURATION_BELOW);
    expect(isPastel(value)).toBe(false);
  });

  it('brings --normal-fill onto the same footing as the other two box fills', () => {
    // The reason the value moved: the alert and watch fills were already
    // strongly saturated and the green was the washed-out odd one out.
    const siblings = ['--alert-fill', '--watch-fill'].map(valueOf);
    for (const sibling of siblings) {
      expect(hslSaturation(sibling)).toBeGreaterThanOrEqual(PASTEL_SATURATION_BELOW);
      expect(isPastel(sibling)).toBe(false);
    }
  });

  it('leaves no pastel anywhere in the light palette', () => {
    // The point of the whole exercise, asserted over the palette rather than
    // over the four names that used to fail. Property 20 generalises this.
    const offenders = [...lightPalette.entries()]
      .filter(([, value]) => value.startsWith('#'))
      .filter(([, value]) => isPastel(value))
      .map(([name, value]) => `${name} ${value}`);
    expect(offenders).toEqual([]);
  });
});


describe('Requirement 11.4 — the accent split into graphical and text tokens', () => {
  // Requirement 11.4 is conditional on a measurement, so the measurement is the
  // test. Every value is read from the registry; the ratios are recomputed here
  // rather than copied from the `measured` fields the registry records.
  const light = registry.lightAppearanceExtensions;
  const surfaces = [
    ['--bg', light['--bg'].value],
    ['--surface', light['--surface'].value],
    ['--surface-raised', light['--surface-raised'].value],
  ] as const;

  /** Requirement 11.1: body and secondary text. */
  const TEXT_THRESHOLD = 4.5;

  /** Requirement 11.2: KPI and title text, and graphical elements. */
  const GRAPHICAL_THRESHOLD = 3;

  it('confirms the light graphical accent really does fail as text', () => {
    // The premise of the whole split. If this ever passes 4.5:1, the extra token
    // is no longer justified and should be revisited rather than kept out of
    // habit.
    const onCard = contrastRatio(light['--accent'].value, light['--surface'].value);
    expect(roundRatio(onCard)).toBe(3.74);
    expect(onCard).toBeLessThan(TEXT_THRESHOLD);
    expect(onCard).toBeGreaterThanOrEqual(GRAPHICAL_THRESHOLD);
  });

  it.each(surfaces)(
    'clears 4.5:1 for the light accent-as-text on %s',
    (_name: string, surface: string) => {
      const ratio = contrastRatio(light['--accent-text'].value, surface);
      expect(ratio).toBeGreaterThanOrEqual(TEXT_THRESHOLD);
      // Strictly better than the graphical accent it replaces, on every surface.
      expect(ratio).toBeGreaterThan(contrastRatio(light['--accent'].value, surface));
    },
  );

  it('pins the light card-surface figure design.md computes at 5.79:1', () => {
    expect(
      roundRatio(contrastRatio(light['--accent-text'].value, light['--surface'].value)),
    ).toBe(5.79);
  });

  it('needs no override in the dark appearances, because the accent already passes', () => {
    // The dark text token aliases the accent, so the ratio it inherits is the
    // Requirement 11.3 pair itself.
    expect(registry.extensions['--accent-text'].value).toBe('var(--accent)');
    expect(roundRatio(contrastRatio(ACCENT, CARD_SURFACE))).toBe(10.84);
    expect(contrastRatio(ACCENT, CARD_SURFACE)).toBeGreaterThanOrEqual(TEXT_THRESHOLD);
  });
});

describe('Requirement 9.2 — High_Contrast_Dark improves on Dark', () => {
  // The full invariant is Property 26 (task 3.12). What is asserted here is the
  // narrower claim task 3.2 is responsible for: the two values it chose really do
  // raise contrast on every dark surface, and the surfaces themselves are shared
  // rather than restated.
  const overrides = registry.highContrastDarkExtensions;
  const dark = registry.tokens;
  const surfaces = [
    ['--bg', dark['--bg'].value],
    ['--surface', dark['--surface'].value],
    ['--surface-raised', dark['--surface-raised'].value],
  ] as const;

  it.each(surfaces)(
    'raises secondary-text contrast on %s',
    (_name: string, surface: string) => {
      const before = contrastRatio(dark['--text-secondary'].value, surface);
      const after = contrastRatio(overrides['--text-secondary'].value, surface);
      expect(after).toBeGreaterThan(before);
      // Requirement 11.1 held before the override and has to keep holding.
      expect(before).toBeGreaterThanOrEqual(4.5);
      expect(after).toBeGreaterThanOrEqual(4.5);
    },
  );

  it.each(surfaces)('raises border contrast on %s', (_name: string, surface: string) => {
    expect(contrastRatio(overrides['--border'].value, surface)).toBeGreaterThan(
      contrastRatio(dark['--border'].value, surface),
    );
  });

  it('pins the card-surface figures the registry records', () => {
    expect(
      roundRatio(
        contrastRatio(overrides['--text-secondary'].value, dark['--surface'].value),
      ),
    ).toBe(9.9);
    expect(
      roundRatio(contrastRatio(overrides['--border'].value, dark['--surface'].value)),
    ).toBe(1.83);
  });

  it('keeps the two overrides out of the pastel region', () => {
    // Requirement 9.8 applies to every appearance, including this one. The
    // `_about` preamble is documentation and carries no value, so it is skipped
    // by having a value rather than by name.
    const values = Object.entries(
      overrides as Record<string, { value?: string }>,
    ).flatMap(([name, entry]) =>
      typeof entry.value === 'string' ? [[name, entry.value] as const] : [],
    );
    expect(values).toHaveLength(2);
    for (const [name, value] of values) {
      expect(isPastel(value), `${name} reads as pastel`).toBe(false);
    }
  });
});

describe('Requirement 9.5 / 11.1 — text on the retuned light OK fill', () => {
  // Task 3.2 moved `--normal-fill` in the light palette to clear the pastel rule.
  // Requirement 9.5 keeps the light appearance bound by the Requirement 11
  // contrast criteria, so the retune has to be checked against the text that
  // sits on it rather than assumed harmless.
  const light = registry.lightAppearanceExtensions;
  const fill = light['--normal-fill'].value;

  it.each([
    ['--text-primary', light['--text-primary'].value],
    ['--text-secondary', light['--text-secondary'].value],
    ['--accent-text', light['--accent-text'].value],
  ])('clears 4.5:1 for %s on the fill', (_name: string, text: string) => {
    expect(contrastRatio(text, fill)).toBeGreaterThanOrEqual(4.5);
  });

  it('keeps the OK status colour at the 3:1 headline threshold', () => {
    // `--normal` on the OK fill is a status headline, not body text, so
    // Requirement 11.2's 3:1 is the applicable threshold. It was already below
    // 4.5:1 at the previous value, so the retune does not change which criterion
    // the pair satisfies — recorded rather than glossed over.
    const ratio = contrastRatio(light['--normal'].value, fill);
    expect(ratio).toBeGreaterThanOrEqual(3);
    expect(ratio).toBeLessThan(4.5);
  });
});

/**
 * The fixed WattVision constants, asserted against the Design_Token_Registry.
 *
 * Requirement 1.6 enumerates eleven exact colours and Requirement 1.7 six exact
 * numerics. This file pins both, plus the §5 grid and spacing constants, the
 * Requirement 1.9 documentation obligation on every Token_Extension, and the
 * Requirement 1.10 amber WATCH rationale.
 *
 * **What the pin actually is.** No colour value is written here — Requirement
 * 1.5 forbids that outside `styles/tokens.css` and the declared
 * `fixtures/color-literals.ts` quarantine, and a suite that enforces the rule
 * has to keep it. So the eleven colours are pinned by *agreement across three
 * independent encodings of the same value*:
 *
 * 1. `value`, the CSS hex as written in the registry;
 * 2. `argb`, the `0xAARRGGBB` form the Flutter registry mirrors (this file);
 * 3. the declaration in `styles/tokens.css` (`stylesheet-agreement.node.test.ts`).
 *
 * Changing a colour therefore takes three coordinated edits across two files
 * and two notations, and any one of them alone fails the suite. The six
 * numerics are pinned outright, because integers are not colour literals.
 *
 * _Requirements: 1.6, 1.7, 1.9, 1.10_
 */

import { describe, expect, it } from 'vitest';

import {
  alphaFromArgb,
  allTokenExtensions,
  extensions,
  hexesIn,
  highContrastDarkAbout,
  highContrastDarkExtensions,
  lightAppearanceAbout,
  lightAppearanceExtensions,
  namedTokens,
  registry,
  requirement16Tokens,
  requirement17Tokens,
  rgbFromArgb,
  tokens,
  type NamedEntry,
  type RegistryEntry,
} from './registry-model';

/** Six-digit opaque hex, the only colour form `tokens.css` uses. */
const OPAQUE_HEX = /^#[0-9a-f]{6}$/;

/** The eleven colour tokens Requirement 1.6 enumerates, in registry order. */
const REQUIREMENT_16_NAMES = [
  '--bg',
  '--surface',
  '--accent',
  '--alert',
  '--normal',
  '--gradient-green',
  '--surface-raised',
  '--border',
  '--text-primary',
  '--text-secondary',
  '--alert-fill',
] as const;

/**
 * The four of the eleven that WattVision specifies in §3 rather than §2.
 * Requirement 1.6 calls the whole set "§2 colour tokens"; the registry records
 * the section each value actually comes from, which is why the set is selected
 * by the `requirement16` flag and never by a section string.
 */
const REQUIREMENT_16_NAMES_FROM_SECTION_3 = [
  '--gradient-green',
  '--surface-raised',
  '--border',
  '--alert-fill',
] as const;

/** One of the six Requirement 1.7 numerics, paired with the value it must hold. */
interface PinnedNumeric {
  readonly name: string;
  readonly expected: number;
}

/** The six numerics Requirement 1.7 enumerates, with their exact values. */
const REQUIREMENT_17_VALUES: PinnedNumeric[] = [
  { name: '--radius-card', expected: 16 },
  { name: '--card-padding', expected: 20 },
  { name: '--hairline', expected: 1 },
  { name: '--size-title', expected: 24 },
  { name: '--size-kpi', expected: 32 },
  { name: '--size-body', expected: 14 },
];

/** WattVision §5: a twelve-column grid on a multiple-of-eight spacing base. */
const GRID_COLUMNS = 12;
const SPACING_BASE = 8;
const ENUMERATED_STEPS = [8, 16, 24, 32];

/**
 * The whole registry holds twenty-five WattVision tokens: eleven colours, three
 * §3 geometry numerics, five §4 type entries and six §5 spacing steps.
 */
const TOKEN_COUNT = 25;

describe('Requirement 1.6 — the eleven enumerated colour tokens', () => {
  const eleven = requirement16Tokens();

  it('flags exactly eleven tokens, and exactly the enumerated ones', () => {
    expect(eleven.map(({ name }) => name)).toEqual([...REQUIREMENT_16_NAMES]);
  });

  it('is selected by the requirement16 flag, because the section labels differ', () => {
    // Four of the eleven are honestly labelled §3, since that is where
    // WattVision puts them. Selecting on the section string would silently
    // return seven of the eleven and the criterion would go under-asserted.
    const bySection = namedTokens().filter(({ entry }) => entry.section === '§2');
    expect(bySection).toHaveLength(7);
    expect(bySection.length).toBeLessThan(eleven.length);

    const fromSectionThree = eleven
      .filter(({ entry }) => entry.section === '§3')
      .map(({ name }) => name);
    expect(fromSectionThree).toEqual([...REQUIREMENT_16_NAMES_FROM_SECTION_3]);
    expect(bySection.length + fromSectionThree.length).toBe(eleven.length);
  });

  it('records the section-label decision, so the flag is not an unexplained field', () => {
    const decision = registry.meta.resolvedAmbiguities.find(
      ({ id }) => id === 'section-labels',
    );
    expect(decision).toBeDefined();
    expect(decision?.resolution).toContain('requirement16');
  });

  it.each(eleven)(
    '$name is an opaque colour whose argb mirror equals its own value',
    (named: NamedEntry) => {
      const { entry } = named;
      expect(entry.type).toBe('color');
      expect(entry.value).toMatch(OPAQUE_HEX);
      expect(entry.argb).toBeDefined();
      // The second encoding of the same value. These are transcribed
      // independently — one for CSS, one for the Dart mirror — so a typo in
      // either shows up here.
      expect(rgbFromArgb(entry.argb as string)).toBe(entry.value);
      expect(alphaFromArgb(entry.argb as string)).toBe(255);
    },
  );

  it('gives eleven pairwise distinct values', () => {
    const values = eleven.map(({ entry }) => entry.value);
    expect(new Set(values).size).toBe(values.length);
  });

  it('cites the WattVision text each value was transcribed from', () => {
    for (const { name, entry } of eleven) {
      expect(entry.spec?.trim(), `${name} records no spec text`).toBeTruthy();
    }
  });

  it('holds all eleven as WattVision tokens, never as Token_Extensions', () => {
    for (const { name, entry } of eleven) {
      // A rationale is the marker of a Token_Extension: it records why a value
      // is absent from WattVision. These eleven are in WattVision, so none of
      // them may carry one.
      expect(entry.rationale, `${name} carries an extension rationale`).toBeUndefined();
      expect(Object.keys(extensions)).not.toContain(name);
    }
  });
});

describe('Requirement 1.7 — the six enumerated numeric tokens', () => {
  const six = requirement17Tokens();

  it('flags exactly six tokens, and exactly the enumerated ones', () => {
    expect(six.map(({ name }) => name)).toEqual(
      REQUIREMENT_17_VALUES.map(({ name }) => name),
    );
  });

  it.each(REQUIREMENT_17_VALUES)('$name equals $expected', (pinned: PinnedNumeric) => {
    const { name, expected } = pinned;
    const entry = tokens[name];
    expect(entry, `${name} is missing from the registry`).toBeDefined();
    expect(entry.numeric).toBe(expected);
    // The string form has to agree with the numeric form, because the
    // stylesheet check compares against `value`, not against `numeric`.
    expect(entry.type).toBe('length');
    expect(entry.unit).toBe('px');
    expect(entry.value).toBe(`${expected}px`);
  });

  it('draws the card geometry from §3 and the type sizes from §4', () => {
    const sections = new Map(six.map(({ name, entry }) => [name, entry.section]));
    expect(sections.get('--radius-card')).toBe('§3');
    expect(sections.get('--card-padding')).toBe('§3');
    expect(sections.get('--hairline')).toBe('§3');
    expect(sections.get('--size-title')).toBe('§4');
    expect(sections.get('--size-kpi')).toBe('§4');
    expect(sections.get('--size-body')).toBe('§4');
  });
});

describe('the WattVision token set', () => {
  it('holds twenty-five tokens, decomposed by section', () => {
    const all = namedTokens();
    expect(all).toHaveLength(TOKEN_COUNT);

    const colours = all.filter(({ entry }) => entry.type === 'color');
    const geometry = all.filter(
      ({ entry }) => entry.section === '§3' && entry.type !== 'color',
    );
    const type = all.filter(({ entry }) => entry.section === '§4');
    const spacing = all.filter(({ entry }) => entry.section === '§5');

    expect(colours).toHaveLength(11);
    expect(geometry).toHaveLength(3);
    expect(type).toHaveLength(5);
    expect(spacing).toHaveLength(6);
    expect(
      colours.length + geometry.length + type.length + spacing.length,
    ).toBe(TOKEN_COUNT);
  });

  it('marks every colour token as one of the Requirement 1.6 eleven', () => {
    const colours = namedTokens().filter(({ entry }) => entry.type === 'color');
    expect(colours.map(({ name }) => name).sort()).toEqual(
      [...REQUIREMENT_16_NAMES].sort(),
    );
  });
});

describe('the two greens stay distinct', () => {
  // WattVision §2 names one green as the secondary accent; §3 names a different
  // green for the chart area gradient. Both are WattVision values, so both are
  // plain tokens and neither is a Token_Extension.
  const secondaryAccent = tokens['--normal'];
  const gradientPartner = tokens['--gradient-green'];

  it('registers both as plain tokens', () => {
    expect(secondaryAccent).toBeDefined();
    expect(gradientPartner).toBeDefined();
    expect(secondaryAccent.type).toBe('color');
    expect(gradientPartner.type).toBe('color');
    expect(Object.keys(extensions)).not.toContain('--normal');
    expect(Object.keys(extensions)).not.toContain('--gradient-green');
  });

  it('gives neither a rationale, because neither is absent from WattVision', () => {
    expect(secondaryAccent.rationale).toBeUndefined();
    expect(gradientPartner.rationale).toBeUndefined();
  });

  it('keeps the two values different', () => {
    expect(gradientPartner.value).not.toBe(secondaryAccent.value);
    expect(gradientPartner.argb).not.toBe(secondaryAccent.argb);
  });

  it('sources them from the sections that specify them', () => {
    expect(secondaryAccent.section).toBe('§2');
    expect(gradientPartner.section).toBe('§3');
  });

  it('records the decision, so a future reader does not collapse them', () => {
    const decision = registry.meta.resolvedAmbiguities.find(
      ({ id }) => id === 'two-greens',
    );
    expect(decision).toBeDefined();
    expect(decision?.resolution).toContain('--gradient-green');
    expect(decision?.resolution).toContain('Neither is a Token_Extension');
  });
});

describe('WattVision §5 — twelve columns on a multiple-of-eight scale', () => {
  const { layout } = registry;

  it('records twelve columns and a spacing base of eight', () => {
    expect(layout.section).toBe('§5');
    expect(layout.columns).toBe(GRID_COLUMNS);
    expect(layout.spacingBase).toBe(SPACING_BASE);
  });

  it('enumerates the four steps WattVision names', () => {
    expect([...layout.enumeratedSteps]).toEqual(ENUMERATED_STEPS);
  });

  it('puts every enumerated step on the base', () => {
    for (const step of layout.enumeratedSteps) {
      expect(step % layout.spacingBase, `${step} is off the scale`).toBe(0);
    }
  });

  it('holds every enumerated step as a real spacing token', () => {
    // The enumerated steps are not free-floating numbers: each one has to exist
    // as a §5 token, or the scale is documentation rather than a token set.
    const spacingValues = namedTokens()
      .filter(({ entry }) => entry.section === '§5')
      .map(({ entry }) => entry.numeric);
    for (const step of layout.enumeratedSteps) {
      expect(spacingValues, `no §5 token has the value ${step}`).toContain(step);
    }
  });
});

describe('Requirement 1.9 — every Token_Extension is documented', () => {
  const allExtensions = allTokenExtensions();

  it('has extensions to check in every appearance', () => {
    // Three groups since task 3.2: the shared dark extensions, the two
    // High_Contrast_Dark overrides and the light palette. The obligation is the
    // union of all three, so an entry added to any one of them has to arrive
    // here.
    const groups = [extensions, highContrastDarkExtensions, lightAppearanceExtensions];
    for (const group of groups) {
      expect(Object.keys(group).length).toBeGreaterThan(0);
    }
    expect(allExtensions).toHaveLength(
      groups.reduce((total, group) => total + Object.keys(group).length, 0),
    );
  });

  it.each(allExtensions)(
    '$group $name records a rationale and a consumer',
    (named: NamedEntry) => {
      const { entry } = named;
      expect(entry.rationale?.trim()).toBeTruthy();
      expect(entry.consumedBy?.trim()).toBeTruthy();
    },
  );

  it('documents the light palette as a whole, not only entry by entry', () => {
    // WattVision §6 forbids white backgrounds, so no light value can be
    // sourced from §2 and the entire palette is one extension. The shared
    // reason lives on the `_about` preamble.
    expect(lightAppearanceAbout.rationale.trim()).toBeTruthy();
    expect(lightAppearanceAbout.consumedBy.trim()).toBeTruthy();
    expect(lightAppearanceAbout.constraint.trim()).toBeTruthy();
    expect(lightAppearanceAbout.selector).toContain('light');
  });

  it('never marks a WattVision token as an extension', () => {
    for (const { name, entry } of namedTokens()) {
      expect(entry.rationale, `${name} is a WattVision value`).toBeUndefined();
      expect(entry.consumedBy, `${name} is a WattVision value`).toBeUndefined();
    }
  });
});

describe('Requirement 1.10 — the amber WATCH Token_Extension', () => {
  const watch = extensions['--watch'];

  it('is registered as an extension and not as a WattVision token', () => {
    expect(watch).toBeDefined();
    expect(watch.type).toBe('color');
    expect(watch.value).toMatch(OPAQUE_HEX);
    expect(rgbFromArgb(watch.argb as string)).toBe(watch.value);
    expect(Object.keys(tokens)).not.toContain('--watch');
  });

  it('names Requirement 1.10 as the criterion that requires it', () => {
    expect(watch.requirement).toBe('1.10');
  });

  it('records that WattVision supplies no intermediate advisory colour', () => {
    const rationale = watch.rationale as string;
    expect(rationale).toContain('§2');
    expect(rationale).toContain('no intermediate advisory colour');
    expect(rationale).toContain('secondary accent');
    expect(rationale).toContain('alert accent');
  });

  it('brackets the gap with the registry\'s own two colours', () => {
    // The rationale quotes the pair the amber sits between. Those two values
    // have to be the registry's secondary accent and alert accent, or the
    // recorded reason describes a gap that does not exist.
    const quoted = hexesIn(watch.rationale as string);
    expect(quoted).toHaveLength(2);
    expect(quoted).toContain(tokens['--normal'].value);
    expect(quoted).toContain(tokens['--alert'].value);
  });

  it('names what consumes it', () => {
    expect(watch.consumedBy).toContain('WATCH');
  });
});

describe('Requirement 11.4 — the accent split into graphical and text tokens', () => {
  // Until task 3.2 these assertions read the other way round: they pinned
  // `--accent-text` and the High_Contrast_Dark overrides as *absent*, and named
  // task 3.2 as their owner in `meta.excluded`. That is now history, so they pin
  // presence and correctness instead, and the `meta.excluded` entries are gone.
  const graphical = tokens['--accent'];
  const asText = extensions['--accent-text'];
  const asTextInLight = lightAppearanceExtensions['--accent-text'];

  it('registers the text variant as a Token_Extension, not as a WattVision token', () => {
    // WattVision §2 names one accent and draws no line between graphical and
    // text use, so the token that draws that line is an extension by definition.
    expect(asText).toBeDefined();
    expect(Object.keys(tokens)).not.toContain('--accent-text');
    expect(asText.requirement).toBe('11.4');
  });

  it('leaves the graphical accent exactly as WattVision specifies it', () => {
    // The point of the split is that the accent itself does not move. If this
    // ever fails, the fix was applied to the wrong token.
    expect(graphical.requirement16).toBe(true);
    expect(graphical.rationale).toBeUndefined();
  });

  it('aliases the accent in the dark appearances rather than copying it', () => {
    // An alias is what makes "identical in every dark appearance" true by
    // construction instead of by transcription. A copied hex would be a second
    // encoding of the same value that nothing keeps in step.
    expect(asText.type).toBe('color-alias');
    expect(asText.value).toBe('var(--accent)');
    expect(asText.selector).toBe(':root');
    expect(asText.argb).toBeUndefined();
  });

  it('overrides the text variant in the light appearance, where the accent fails', () => {
    expect(asTextInLight).toBeDefined();
    expect(asTextInLight.type).toBe('color');
    expect(asTextInLight.value).toMatch(OPAQUE_HEX);
    expect(rgbFromArgb(asTextInLight.argb as string)).toBe(asTextInLight.value);
    expect(alphaFromArgb(asTextInLight.argb as string)).toBe(255);
    expect(asTextInLight.requirement).toBe('11.4');

    // It has to actually differ from the light graphical accent, or the override
    // is ceremony. Both are darkened cyans; only one of them clears 4.5:1.
    expect(asTextInLight.value).not.toBe(
      lightAppearanceExtensions['--accent'].value,
    );
    expect(asTextInLight.derivedFrom).toBe(
      '--accent, darkened at the same hue and full saturation',
    );
  });

  it('records the measured ratios on both entries', () => {
    // Requirement 11.4 is conditional on a measurement, so the measurement is
    // part of the record. `contrast.test.ts` recomputes the figures; this pins
    // that the reason is written down rather than folklore.
    for (const [label, entry] of [
      ['dark', asText],
      ['light', asTextInLight],
    ] as const) {
      expect(entry.measured?.trim(), `${label} records no measurement`).toBeTruthy();
    }
    expect(asText.rationale).toContain('11.4');
    expect(asTextInLight.rationale).toContain('11.4');
  });

  it('names what consumes it, which is the two text uses it was added for', () => {
    for (const entry of [asText, asTextInLight]) {
      expect(entry.consumedBy).toContain('.section__title');
      expect(entry.consumedBy).toContain('.row__value');
    }
  });
});

describe('Requirement 9.2 — the High_Contrast_Dark overrides', () => {
  const overrides = highContrastDarkExtensions;

  it('registers exactly two overrides', () => {
    // A high-contrast appearance is a pair of overrides, not a palette. Anything
    // more here means the appearance has started to diverge from Dark.
    expect(Object.keys(overrides).sort()).toEqual(['--border', '--text-secondary']);
  });

  it.each(Object.entries(overrides))(
    '%s is an opaque colour whose argb mirror equals its own value',
    (name: string, entry: RegistryEntry) => {
      expect(entry.type, name).toBe('color');
      expect(entry.value).toMatch(OPAQUE_HEX);
      expect(rgbFromArgb(entry.argb as string)).toBe(entry.value);
      expect(alphaFromArgb(entry.argb as string)).toBe(255);
      expect(entry.requirement).toBe('9.2');
      expect(entry.measured?.trim(), `${name} records no measurement`).toBeTruthy();
      expect(entry.derivedFrom, `${name} records no source token`).toBe(
        `${name}, lightened along the same neutral ramp`,
      );
    },
  );

  it('overrides names the dark appearance already declares, never new ones', () => {
    // This is the mechanism, and it is why nothing downstream has to know which
    // appearance is active: every consumer keeps reading var(--text-secondary).
    for (const name of Object.keys(overrides)) {
      expect(Object.keys(tokens), `${name} has no Dark counterpart`).toContain(name);
    }
  });

  it('is not spelled as --hc-* in CSS, and records why', () => {
    // The `--hc-*` spelling exists only on the Flutter side, which has no
    // selector mechanism and needs distinct field names. Asserting the absence
    // keeps a future contributor from adding a parallel set of CSS properties
    // that no component reads.
    for (const [group, entries] of Object.entries({
      tokens,
      extensions,
      highContrastDarkExtensions,
      lightAppearanceExtensions,
    })) {
      const prefixed = Object.keys(entries).filter((name) => name.startsWith('--hc-'));
      expect(prefixed, `${group} invents --hc-* custom properties`).toEqual([]);
    }

    expect(registry.meta.highContrastNaming).toContain('hcTextSecondary');
    expect(registry.meta.highContrastNaming).toContain('hcBorder');
    expect(overrides['--text-secondary'].flutterName).toBe('hcTextSecondary');
    expect(overrides['--border'].flutterName).toBe('hcBorder');
  });

  it('documents the appearance as a whole, not only override by override', () => {
    expect(highContrastDarkAbout.rationale.trim()).toBeTruthy();
    expect(highContrastDarkAbout.consumedBy.trim()).toBeTruthy();
    expect(highContrastDarkAbout.constraint.trim()).toBeTruthy();
    expect(highContrastDarkAbout.selector).toContain('hc-dark');
  });

  it('no longer records either addition as owned by a later task', () => {
    const { excluded } = registry.meta;
    expect(Object.keys(excluded)).not.toContain('--accent-text');
    expect(Object.keys(excluded)).not.toContain('--hc-*');
    // The one genuine exclusion survives: `color-scheme` is a standard property.
    expect(Object.keys(excluded)).toEqual(['color-scheme']);
  });
});

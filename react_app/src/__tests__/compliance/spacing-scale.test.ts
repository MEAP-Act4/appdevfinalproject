/**
 * Property 21 — every spacing token is a multiple of eight and every
 * Token_Extension is documented. Web_Client half.
 *
 * Requirements 1.8 and 1.9.
 *
 * **How this differs from `token-constants.test.ts` (task 1.11).** That file
 * pins the registry *as it stands today*: `it.each` over the current extension
 * list for the Requirement 1.9 rationale-and-consumer obligation, and the fixed
 * §5 constants — twelve columns, a spacing base of eight, the four enumerated
 * steps. Example tests over a fixed table, which is the right shape for a
 * criterion that names exact values.
 *
 * This file is the **property** form of the same two obligations. The generator
 * is the registry itself — the layout-spacing set and the Token_Extension set —
 * so the invariant is stated over *whatever those sets contain* rather than over
 * today's membership. Phase 2 adds `--accent-text` and the High_Contrast_Dark
 * overrides, phases 3 and 5 add layout values; each new entry becomes an input
 * here by existing, with no edit to this file. The two forms are complementary:
 * the example test catches a changed value, the property catches an added entry
 * that does not satisfy the rule.
 *
 * **The multiple-of-8 filter is data-driven, not an exception list.** The
 * registry carries `layoutSpacing` for exactly this purpose: it marks the values
 * Requirement 1.8 is about — layout gaps, gutters and outer padding — and leaves
 * everything else out of scope. Two length entries are deliberately not
 * selected, and neither is a multiple of eight:
 *
 * - `--s1` (4px) — an intra-component inset, a half-step below the §5 scale;
 * - `--card-padding` (20px) — a WattVision §3 component value, not a layout gap.
 *
 * A filter is only trustworthy if it is doing work, so the `the layoutSpacing
 * flag does real work` block asserts that both of those exist, that both really
 * do fail the modulo test, and that both are excluded — and that the selected
 * set is non-empty and covers every enumerated §5 step. Without that, dropping
 * the flag from every entry would leave this property passing vacuously.
 *
 * The bidirectional registry/stylesheet clause of Property 21 is not restated
 * here: `stylesheet-agreement.node.test.ts` already pins it exhaustively over
 * the finite declaration set, in both directions, and a generated sample of a
 * finite set is strictly weaker than walking all of it. What this file adds is
 * the Web_Client half of the cross-client mapping — every selected entry must
 * carry the `flutterName` its Dart counterpart is keyed by.
 *
 * Runs in the jsdom project because it needs no filesystem access; the registry
 * arrives as an imported module. No colour value is written here, per
 * Requirement 1.5 — the numbers that appear are the spacing base and the two
 * excluded lengths, which are not colours.
 *
 * _Requirements: 1.8, 1.9_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import {
  allEntries,
  allTokenExtensions,
  extensions,
  highContrastDarkExtensions,
  lightAppearanceExtensions,
  namedTokens,
  registry,
  type NamedEntry,
} from './registry-model';

/**
 * The design.md floor: 100 generated cases per property, for both clients.
 *
 * Left unannotated deliberately. `fc.Parameters` is generic in the property's
 * tuple type and defaults to `void`, so annotating it here would make one
 * shared constant unusable across properties with different inputs.
 */
const RUNS = { numRuns: 100 } as const;

/** WattVision §5 puts layout spacing on whole multiples of this. */
const SPACING_BASE = registry.layout.spacingBase;

/** The two lengths the flag deliberately leaves outside Requirement 1.8. */
const EXCLUDED_LENGTH_NAMES = ['--s1', '--card-padding'] as const;

/** `--s1`: the intra-component half-step. */
const S1_VALUE = 4;

/** `--card-padding`: the §3 card inset. */
const CARD_PADDING_VALUE = 20;

/**
 * The entries Requirement 1.8 applies to, selected by the `layoutSpacing` flag
 * and by nothing else.
 *
 * Drawn from {@link allEntries} rather than from `tokens`, because the §5 steps
 * are WattVision tokens today while the per-Layout_Mode gutters and outer
 * padding of phase 3 arrive as Token_Extensions.
 */
function layoutSpacingEntries(): NamedEntry[] {
  return allEntries().filter(({ entry }) => entry.layoutSpacing === true);
}

/**
 * Every px length the flag leaves out of scope. Durations, easings, shadows and
 * colours are not lengths at all, so they are not candidates either way.
 */
function nonLayoutLengths(): NamedEntry[] {
  return allEntries().filter(
    ({ entry }) =>
      entry.layoutSpacing !== true && entry.unit === 'px' && entry.numeric !== undefined,
  );
}

/** A registry entry by custom-property name, across all three groups. */
function entryNamed(name: string): NamedEntry {
  const found = allEntries().find((candidate) => candidate.name === name);
  if (found === undefined) {
    throw new Error(`no registry entry named ${name}`);
  }
  return found;
}

function isMultipleOfBase(value: number): boolean {
  return value % SPACING_BASE === 0;
}

/** Uniform choice over a registry set, so the registry is the generator. */
function anyOf(entries: readonly NamedEntry[]): fc.Arbitrary<NamedEntry> {
  // Guarded rather than left to throw inside `constantFrom`, so an empty set
  // reports as the vacuity it is instead of as an arbitrary-construction error.
  if (entries.length === 0) {
    throw new Error('the generated set is empty, so the property is vacuous');
  }
  return fc.constantFrom(...entries);
}

describe('Property 21 — Requirement 1.8, layout spacing is on the eight scale', () => {
  const spacing = layoutSpacingEntries();

  it('puts every layoutSpacing entry on a whole multiple of the base', () => {
    fc.assert(
      fc.property(anyOf(spacing), ({ name, group, entry }: NamedEntry) => {
        expect(
          entry.numeric,
          `${name} is flagged layoutSpacing but carries no numeric value, so ` +
            'Requirement 1.8 cannot be checked on it',
        ).toBeDefined();
        const value = entry.numeric as number;

        expect(value, `${name} is a layout spacing value`).toBeGreaterThan(0);
        expect(
          Number.isInteger(value),
          `${name} is ${value}; a multiple of ${SPACING_BASE} is a whole number`,
        ).toBe(true);
        expect(
          isMultipleOfBase(value),
          `${name} (${group}) is ${value}, which is not a whole multiple of ` +
            `${SPACING_BASE} — Requirement 1.8 constrains every layout gap, ` +
            'gutter and outer padding to the WattVision §5 scale',
        ).toBe(true);
      }),
      RUNS,
    );
  });

  it('declares px and a Flutter-side mirror on every layoutSpacing entry', () => {
    fc.assert(
      fc.property(anyOf(spacing), ({ name, entry }: NamedEntry) => {
        expect(entry.type, `${name} is a length`).toBe('length');
        expect(
          entry.unit,
          `${name} is a layout spacing value, so its unit has to be px for the ` +
            'multiple-of-eight rule to mean anything',
        ).toBe('px');
        // The numeric and string forms have to agree, since the stylesheet
        // check compares against `value` while this property reads `numeric`.
        expect(entry.value).toBe(`${entry.numeric as number}px`);
        // The Web_Client half of the cross-client mapping. The bidirectional
        // registry/stylesheet check itself lives in
        // `stylesheet-agreement.node.test.ts`.
        expect(entry.flutterName?.trim(), `${name} records no Dart mirror`).toBeTruthy();
      }),
      RUNS,
    );
  });
});

describe('Property 21 — the layoutSpacing flag does real work', () => {
  // Without this block the property above could pass vacuously: drop the flag
  // from every entry and an empty selected set satisfies any invariant.
  it('selects a non-empty set', () => {
    expect(
      layoutSpacingEntries(),
      'no entry is flagged layoutSpacing, so Requirement 1.8 would be asserted over nothing',
    ).not.toHaveLength(0);
  });

  it('covers every enumerated §5 step', () => {
    const selected = layoutSpacingEntries().map(({ entry }) => entry.numeric);
    for (const step of registry.layout.enumeratedSteps) {
      expect(selected, `WattVision §5 enumerates ${step}, but no entry holds it`).toContain(
        step,
      );
    }
  });

  it('excludes --s1, the 4px intra-component inset', () => {
    const { entry } = entryNamed('--s1');

    expect(entry.numeric).toBe(S1_VALUE);
    expect(entry.unit).toBe('px');
    expect(
      isMultipleOfBase(S1_VALUE),
      'if --s1 became a multiple of eight this exclusion would be pointless',
    ).toBe(false);
    // Recorded as `false` outright on this entry; the Dart mirror leaves the
    // field at its `false` default. Either way the filter selects on `=== true`.
    expect(entry.layoutSpacing).not.toBe(true);
    expect(
      layoutSpacingEntries().map(({ name }) => name),
      '--s1 is an intra-component inset — pill padding, value/unit spacing — and ' +
        'Requirement 1.8 constrains layout gaps, gutters and outer padding only',
    ).not.toContain('--s1');
  });

  it('excludes --card-padding, the §3 component value', () => {
    const { entry } = entryNamed('--card-padding');

    expect(entry.numeric).toBe(CARD_PADDING_VALUE);
    expect(entry.unit).toBe('px');
    expect(
      isMultipleOfBase(CARD_PADDING_VALUE),
      'that 20 is off the eight scale is exactly why the flag has to ' +
        'distinguish a §3 component value from a layout gap',
    ).toBe(false);
    expect(entry.layoutSpacing).not.toBe(true);
    expect(
      layoutSpacingEntries().map(({ name }) => name),
      '--card-padding is a WattVision §3 card inset, not a layout gap, gutter ' +
        'or outer padding',
    ).not.toContain('--card-padding');
  });

  it('leaves px lengths outside the Requirement 1.8 scope', () => {
    // The flag is a filter, not a blanket. Both exclusions above are px lengths
    // the property would reject, so the excluded set has to be non-empty too —
    // a flag that is true everywhere is as useless as one that is true nowhere.
    const excluded = nonLayoutLengths();
    const names = excluded.map(({ name }) => name);
    expect(names).toEqual(expect.arrayContaining([...EXCLUDED_LENGTH_NAMES]));
    expect(
      excluded.filter(({ entry }) => !isMultipleOfBase(entry.numeric as number)),
      'at least one excluded length is off the eight scale, so the flag is ' +
        'genuinely narrowing the set rather than selecting all of it',
    ).not.toHaveLength(0);
  });
});

describe('Property 21 — Requirement 1.9, every Token_Extension is documented', () => {
  const allExtensions = allTokenExtensions();

  it('records a rationale and a consumer on every extension', () => {
    fc.assert(
      fc.property(anyOf(allExtensions), ({ name, group, entry }: NamedEntry) => {
        expect(
          entry.rationale?.trim(),
          `${group} ${name} records no reason for being absent from WattVision`,
        ).toBeTruthy();
        expect(
          entry.consumedBy?.trim(),
          `${group} ${name} records no state or surface that consumes it`,
        ).toBeTruthy();
      }),
      RUNS,
    );
  });

  it('has extensions to check, in every appearance', () => {
    const groups = [extensions, highContrastDarkExtensions, lightAppearanceExtensions];
    for (const group of groups) {
      expect(Object.keys(group).length).toBeGreaterThan(0);
    }
    expect(
      allExtensions,
      'the extension set is the union of the shared dark extensions, the ' +
        'High_Contrast_Dark overrides and the light palette, so an entry added ' +
        'to any of them has to reach this property',
    ).toHaveLength(
      groups.reduce((total, group) => total + Object.keys(group).length, 0),
    );
  });

  it('never lets a WattVision token masquerade as an extension', () => {
    // Compared against the shared dark extension keys only. The light palette
    // and the High_Contrast_Dark overrides deliberately reuse the same
    // custom-property names — `--bg`, `--surface`, `--text-secondary`,
    // `--border` — because the appearances are separated by CSS selector, not by
    // property name, so a name collision there is the design rather than a
    // drift.
    const darkExtensionNames = Object.keys(extensions);
    fc.assert(
      fc.property(anyOf(namedTokens()), ({ name, entry }: NamedEntry) => {
        // The inverse of the obligation: a rationale records why a value is
        // *absent* from WattVision, so a §2–§5 value carries neither field.
        expect(entry.rationale, `${name} comes from WattVision`).toBeUndefined();
        expect(entry.consumedBy, `${name} comes from WattVision`).toBeUndefined();
        expect(
          darkExtensionNames,
          `${name} comes from WattVision ${entry.section ?? ''}, so it is not a ` +
            'Token_Extension',
        ).not.toContain(name);
      }),
      RUNS,
    );
  });
});

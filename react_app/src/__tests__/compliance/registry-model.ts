/**
 * A typed, queryable view over `src/styles/token-registry.json`.
 *
 * The registry is authored as JSON because CSS cannot carry structured
 * metadata, which means TypeScript infers a different object shape for every
 * key (only some entries carry `numeric`, only some carry `rationale`, and so
 * on). Every consumer would otherwise repeat the same widening cast, so the
 * cast happens exactly once, here, behind named accessors.
 *
 * This module holds **no values**. Every colour, length, duration and family
 * comes out of the registry at run time. Requirement 1.5 forbids literal
 * colours anywhere under `react_app/src` outside `styles/tokens.css` and the
 * declared `fixtures/color-literals.ts` quarantine, and the compliance suite
 * has to obey the rule it enforces. The numbers that do appear literally in the
 * tests — 11, 6, 25, 12, 8 — are cardinalities and the two §5 layout constants,
 * not token values.
 *
 * _Requirements: 1.1, 1.6, 1.7, 1.9, 1.10_
 */

import rawRegistry from '../../styles/token-registry.json';

/**
 * One registry entry, flattened across the four groups. Every field beyond
 * `type` and `value` is optional because the groups carry different metadata:
 * WattVision tokens record a `section`, Token_Extensions record a `rationale`
 * and a `consumedBy`, and only length/duration entries record a `numeric`.
 */
export interface RegistryEntry {
  /** Name of the mirroring field in `token_registry.dart`. */
  readonly flutterName?: string;
  /** `color`, `length`, `duration`, `duration-alias`, `easing`, `shadow`, `font-family`. */
  readonly type: string;
  /** The WattVision section the value is sourced from, for tokens only. */
  readonly section?: string;
  /** The `tokens.css` block this declaration lives in. */
  readonly selector?: string;
  /** The declaration value, verbatim as written in `tokens.css`. */
  readonly value: string;
  /** The Flutter-side `0xAARRGGBB` form, for colours only. */
  readonly argb?: string;
  /** The numeric part of a length or duration. */
  readonly numeric?: number;
  /** The unit of a length or duration. */
  readonly unit?: string;
  /** What WattVision says about the value. */
  readonly spec?: string;
  /** Requirement 1.9: why the value is absent from WattVision. */
  readonly rationale?: string;
  /** Requirement 1.9: the state or surface that consumes the value. */
  readonly consumedBy?: string;
  /** The acceptance criterion an extension is named by, where one names it. */
  readonly requirement?: string;
  /** Recorded contrast measurements, for values chosen to satisfy a ratio. */
  readonly measured?: string;
  /** Marks one of the eleven colours Requirement 1.6 enumerates. */
  readonly requirement16?: boolean;
  /** Marks one of the six numerics Requirement 1.7 enumerates. */
  readonly requirement17?: boolean;
  /** Requirement 1.8 applicability: a layout gap, gutter or outer padding. */
  readonly layoutSpacing?: boolean;
  /** For the `--t-*` aliases: the Reduce_Motion override block. */
  readonly reduceMotionSelector?: string;
  /** For the `--t-*` aliases: the value that block redefines them to. */
  readonly reduceMotionValue?: string;
  readonly note?: string;
  readonly derivedFrom?: string;
}

/** The `layout` block: the WattVision §5 grid and spacing constants. */
export interface RegistryLayout {
  readonly section: string;
  readonly columns: number;
  readonly spacingBase: number;
  readonly enumeratedSteps: readonly number[];
  readonly rule: string;
}

/**
 * The `_about` preamble an appearance-scoped extension group carries.
 *
 * Both the light palette and the High_Contrast_Dark overrides are extensions of
 * a whole appearance rather than of one surface, so each records its shared
 * reason, its shared consumer, the selector its block uses and the constraint
 * the appearance has to keep, once, on a preamble key rather than repeated on
 * every entry.
 */
export interface AppearanceGroupAbout {
  readonly rationale: string;
  readonly consumedBy: string;
  readonly selector: string;
  readonly constraint: string;
}

/** Retained name for the light palette's preamble. */
export type LightAppearanceAbout = AppearanceGroupAbout;

/** The whole registry, widened to a uniform shape. */
export interface Registry {
  readonly meta: {
    readonly stylesheet: string;
    readonly mirroredBy: string;
    readonly groupedSelectors: string;
    readonly highContrastNaming: string;
    readonly resolvedAmbiguities: readonly {
      readonly id: string;
      readonly summary: string;
      readonly resolution: string;
    }[];
    readonly excluded: Readonly<Record<string, string>>;
  };
  readonly tokens: Readonly<Record<string, RegistryEntry>>;
  readonly layout: RegistryLayout;
  readonly extensions: Readonly<Record<string, RegistryEntry>>;
  readonly highContrastDarkExtensions: Readonly<Record<string, RegistryEntry>>;
  readonly lightAppearanceExtensions: Readonly<Record<string, RegistryEntry>>;
}

/**
 * The one widening cast in the suite. `as unknown as` rather than a plain
 * assertion because the inferred JSON type is a union of ~60 distinct object
 * shapes and is not assignable to the uniform one.
 */
export const registry = rawRegistry as unknown as Registry;

/** The `_about` preamble key, which is documentation rather than a token. */
export const LIGHT_ABOUT_KEY = '_about';

/** Drops the `_about` preamble, leaving only real custom properties. */
function realEntries(
  group: Readonly<Record<string, RegistryEntry>>,
): Readonly<Record<string, RegistryEntry>> {
  return Object.fromEntries(
    Object.entries(group).filter(([name]) => name !== LIGHT_ABOUT_KEY),
  );
}

/** Reads an appearance group's `_about` preamble. */
function aboutOf(
  group: Readonly<Record<string, RegistryEntry>>,
): AppearanceGroupAbout {
  return group[LIGHT_ABOUT_KEY] as unknown as AppearanceGroupAbout;
}

/** WattVision tokens: the §2 colours and the §3/§4/§5 numerics. */
export const tokens = registry.tokens;

/** Token_Extensions shared by both dark appearances. */
export const extensions = registry.extensions;

/**
 * Token_Extensions the High_Contrast_Dark appearance overrides, with the
 * `_about` preamble removed.
 *
 * Exactly the two properties Requirement 9.2 raises. They reuse the custom
 * property names the dark block already declares — CSS reaches a high-contrast
 * palette by redeclaring in a more specific block, not by inventing `--hc-*`
 * names — so these entries are distinguished from their dark counterparts by
 * selector, never by name. See `meta.highContrastNaming`.
 */
export const highContrastDarkExtensions = realEntries(
  registry.highContrastDarkExtensions,
);

/**
 * Token_Extensions for the light appearance, with the `_about` preamble
 * removed. Every remaining key is a real custom property.
 */
export const lightAppearanceExtensions = realEntries(
  registry.lightAppearanceExtensions,
);

/** The light-palette preamble, which carries the shared selector. */
export const lightAppearanceAbout = aboutOf(registry.lightAppearanceExtensions);

/** The High_Contrast_Dark preamble, which carries the shared selector. */
export const highContrastDarkAbout = aboutOf(registry.highContrastDarkExtensions);

/** The four registry groups, labelled, in the order the JSON declares them. */
export const REGISTRY_GROUPS = [
  { group: 'tokens', entries: tokens },
  { group: 'extensions', entries: extensions },
  { group: 'highContrastDarkExtensions', entries: highContrastDarkExtensions },
  { group: 'lightAppearanceExtensions', entries: lightAppearanceExtensions },
] as const;

/** A registry group name, used in failure messages. */
export type RegistryGroup = (typeof REGISTRY_GROUPS)[number]['group'];

/** A registry entry paired with its custom-property name and its group. */
export interface NamedEntry {
  readonly name: string;
  readonly group: RegistryGroup;
  readonly entry: RegistryEntry;
}

/** Every entry across all four groups, `_about` excluded. */
export function allEntries(): NamedEntry[] {
  return REGISTRY_GROUPS.flatMap(({ group, entries }) =>
    Object.entries(entries).map(([name, entry]) => ({ name, group, entry })),
  );
}

/** Every Token_Extension, dark and light. Requirement 1.9 applies to these. */
export function allTokenExtensions(): NamedEntry[] {
  return allEntries().filter(({ group }) => group !== 'tokens');
}

/** The WattVision tokens, paired with their names. */
export function namedTokens(): NamedEntry[] {
  return Object.entries(tokens).map(([name, entry]) => ({
    name,
    group: 'tokens' as const,
    entry,
  }));
}

/** The eleven colours Requirement 1.6 enumerates, selected by flag. */
export function requirement16Tokens(): NamedEntry[] {
  return namedTokens().filter(({ entry }) => entry.requirement16 === true);
}

/** The six numerics Requirement 1.7 enumerates, selected by flag. */
export function requirement17Tokens(): NamedEntry[] {
  return namedTokens().filter(({ entry }) => entry.requirement17 === true);
}

/**
 * The selector whose block a registry entry's declaration lives in.
 *
 * Tokens, dark extensions and the two High_Contrast_Dark overrides record it per
 * entry; the light palette records it once, on `_about`, because every light
 * value shares one block.
 *
 * Note that a selector here is a *block prelude*, not necessarily a single
 * selector. The dark block's prelude names two appearances, and entries
 * declared in it record that grouped prelude verbatim — see
 * `meta.groupedSelectors`.
 */
export function selectorFor(named: NamedEntry): string {
  if (named.group === 'lightAppearanceExtensions') {
    return lightAppearanceAbout.selector;
  }
  const { selector } = named.entry;
  if (selector === undefined) {
    throw new Error(
      `Registry entry ${named.name} in ${named.group} records no selector, ` +
        'so its declaration cannot be located in tokens.css.',
    );
  }
  return selector;
}

/**
 * Collapses whitespace runs and lowercases, so a declaration read out of
 * `tokens.css` compares equal to the registry's record of it.
 *
 * Case is folded because `meta.hexCase` makes comparison case-insensitive by
 * policy: WattVision writes hex uppercase, `tokens.css` writes it lowercase.
 * Folding also covers the font-family names, where both sides carry the same
 * casing anyway.
 */
export function normaliseCssValue(value: string): string {
  return value.trim().replace(/\s+/g, ' ').toLowerCase();
}

/** True when two declaration values agree under {@link normaliseCssValue}. */
export function valuesAgree(a: string, b: string): boolean {
  return normaliseCssValue(a) === normaliseCssValue(b);
}

/**
 * The 24-bit RGB body of an `0xAARRGGBB` string, lowercased and `#`-prefixed,
 * so a registry entry's `argb` mirror can be compared against its `value`
 * without either being restated in a test.
 */
export function rgbFromArgb(argb: string): string {
  const match = /^0x([0-9a-f]{8})$/i.exec(argb.trim());
  if (match === null) {
    throw new Error(
      `Malformed argb ${JSON.stringify(argb)}: expected 0x followed by 8 hex digits.`,
    );
  }
  return `#${match[1].slice(2).toLowerCase()}`;
}

/** The alpha byte of an `0xAARRGGBB` string, 0..255. */
export function alphaFromArgb(argb: string): number {
  const match = /^0x([0-9a-f]{2})[0-9a-f]{6}$/i.exec(argb.trim());
  if (match === null) {
    throw new Error(
      `Malformed argb ${JSON.stringify(argb)}: expected 0x followed by 8 hex digits.`,
    );
  }
  return parseInt(match[1], 16);
}

/**
 * Every hex literal appearing inside a prose field such as a `rationale`.
 *
 * Used to check that a recorded rationale quotes the colours it claims to sit
 * between, and that those quoted values are the registry's own. The pattern
 * itself contains no hex digits after the `#`, so this module stays clean under
 * the Requirement 1.5 scan.
 */
export function hexesIn(prose: string): string[] {
  return (prose.match(/#[0-9a-f]{6}\b/gi) ?? []).map((hex) => hex.toLowerCase());
}

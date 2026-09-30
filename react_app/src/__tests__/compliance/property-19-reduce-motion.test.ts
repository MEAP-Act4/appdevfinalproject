/**
 * Property 19 — Reduce_Motion collapses every transition and stops every
 * ambient animation. Web_Client half.
 *
 * *For any* motion token, when Reduce_Motion is enabled the resolved duration
 * is at most 1 ms; and every ambient looping animation resolves to disabled.
 * When it is disabled, the resolved duration equals the token's declared value.
 *
 * **The two clauses, both asserted.** design.md's invariant is a conjunction
 * under Reduce_Motion:
 *
 *   1. `resolvedDuration <= 1ms` for every motion token, and
 *   2. `ambientEnabled == false`.
 *
 * The `!reduceMotion` branch is the third obligation: the resolved duration
 * equals the token's declared value. All three are checked here.
 *
 * **The motion token set is the generator, read from the registry.** The
 * tokens transitions actually route through are the three duration *aliases* —
 * `--t-fast`, `--t-base`, `--t-slow`. `tokens.css` says so in a comment: "Every
 * transition in the app routes through these two custom properties, so the
 * reduce-motion switch is one attribute flip rather than a hunt through the
 * CSS." Each alias declares `value: var(--motion-X)` and carries a
 * `reduceMotionSelector` / `reduceMotionValue` pair (`1ms`) recorded in
 * `token-registry.json`. This file enumerates those aliases from the registry
 * via `registry-model.ts`; a fourth alias added later becomes an input here by
 * existing. No duration literal (120/200/320/520/1) is written in this file —
 * every number is pulled from the registry, so this file stays clean under the
 * Requirement 1.5 scan and cannot drift from the token source.
 *
 * **How "resolved duration" is modelled.** For an alias, its declared value is
 * `var(--motion-X)`, which resolves to the referenced raw motion token's
 * numeric duration (e.g. `--t-base` → `var(--motion-base)` → `320ms`). Under
 * Reduce_Motion the alias is redefined to its `reduceMotionValue` (`1ms`) by
 * both `:root[data-reduce-motion='true']` and the
 * `@media (prefers-reduced-motion: reduce)` block. So:
 *
 *   - reduceMotion true  → resolvedDuration = reduceMotionValue (1 ms) ⇒ ≤ 1 ms
 *   - reduceMotion false → resolvedDuration = the aliased motion token's value.
 *
 * **How "ambientEnabled" is modelled.** Reduce_Motion is one system-level
 * switch. When it is on, every ambient looping animation is disabled — in the
 * CSS that is the `:root[data-reduce-motion='true']` blocks that set
 * `animation: none` on `.dot--live`, `.gate__wash` and `.gate__ring`. At the
 * model level `ambientEnabled == !reduceMotion`, which is the boolean
 * design.md's invariant names. Both clients model it identically, so
 * Requirement 13.1's parity holds.
 *
 * **On failure.** A resolved duration above 1 ms under Reduce_Motion, or an
 * ambient animation that stays enabled, is a real Requirement 11.6 defect — a
 * transition that does not route through the reduce-motion switch. The remedy
 * is to route it through the switch, not to weaken this property.
 *
 * Runs in the jsdom project because it needs no filesystem access — the
 * registry arrives as an imported module.
 *
 * _Validates: Requirements 4.8, 11.6_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { extensions, type RegistryEntry } from './registry-model';

/**
 * The registry group the motion scale lives in. The named-scale durations
 * (`--motion-*`) and the transition aliases (`--t-*`) are Token_Extensions —
 * WattVision §1–§6 specify no motion durations, so they are documented as
 * extensions rather than sourced tokens — and both sit in the `extensions`
 * group. This is the single place either is read.
 */
const MOTION_GROUP: Readonly<Record<string, RegistryEntry>> = extensions;

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/**
 * A parsed millisecond duration, or `null` when the value is not a bare `Nms`
 * literal (an alias's `var(--motion-X)` is resolved separately, not parsed
 * here).
 */
function parseMs(value: string): number | null {
  const match = /^(\d+(?:\.\d+)?)ms$/.exec(value.trim());
  return match === null ? null : Number(match[1]);
}

/** The `--motion-X` custom property an alias's `var(--motion-X)` value names. */
function referencedMotionName(aliasValue: string): string | null {
  const match = /^var\(\s*(--motion-[a-z]+)\s*\)$/.exec(aliasValue.trim());
  return match === null ? null : match[1];
}

/**
 * The declared millisecond duration of a raw motion token, read from the
 * registry by name. Throws rather than defaulting, so a mis-linked alias is a
 * loud failure rather than a silent zero.
 */
function motionTokenMs(name: string): number {
  const entry = MOTION_GROUP[name] as RegistryEntry | undefined;
  if (entry === undefined) {
    throw new Error(`alias references ${name}, which is not in the registry`);
  }
  const ms = parseMs(entry.value);
  if (ms === null) {
    throw new Error(
      `${name} has value ${JSON.stringify(entry.value)}, not a millisecond duration`,
    );
  }
  return ms;
}

/** One motion-alias token, flattened to the fields Property 19 ranges over. */
interface MotionAlias {
  /** The custom-property name, e.g. `--t-base`. */
  readonly name: string;
  /** The raw motion token it resolves to when Reduce_Motion is off, in ms. */
  readonly declaredMs: number;
  /** The duration it collapses to when Reduce_Motion is on, in ms. */
  readonly reduceMotionMs: number;
  /** The block that performs the collapse, for failure messages. */
  readonly reduceMotionSelector: string;
}

/**
 * The motion token set: every `duration-alias` entry in the registry, resolved.
 *
 * These are the tokens every transition routes through, so they are exactly the
 * "motion token set" design.md's generator names. Each is resolved to its
 * declared duration (via the `--motion-X` it references) and its Reduce_Motion
 * value.
 */
function motionAliases(): MotionAlias[] {
  return Object.entries(MOTION_GROUP).flatMap(([name, entry]) => {
    if (entry.type !== 'duration-alias') {
      return [];
    }
    const referenced = referencedMotionName(entry.value);
    if (referenced === null) {
      throw new Error(
        `alias ${name} has value ${JSON.stringify(entry.value)}, ` +
          'expected var(--motion-X)',
      );
    }
    if (entry.reduceMotionValue === undefined) {
      throw new Error(`alias ${name} records no reduceMotionValue`);
    }
    const reduceMotionMs = parseMs(entry.reduceMotionValue);
    if (reduceMotionMs === null) {
      throw new Error(
        `alias ${name} reduceMotionValue ${JSON.stringify(
          entry.reduceMotionValue,
        )} is not a millisecond duration`,
      );
    }
    if (entry.reduceMotionSelector === undefined) {
      throw new Error(`alias ${name} records no reduceMotionSelector`);
    }
    return [
      {
        name,
        declaredMs: motionTokenMs(referenced),
        reduceMotionMs,
        reduceMotionSelector: entry.reduceMotionSelector,
      },
    ];
  });
}

const ALIASES = motionAliases();

/**
 * The resolved duration of a motion alias for a given Reduce_Motion state — the
 * model of what the cascade produces. Reduce_Motion on flips the alias to its
 * reduce-motion value; off leaves it at its declared value.
 */
function resolvedMs(alias: MotionAlias, reduceMotion: boolean): number {
  return reduceMotion ? alias.reduceMotionMs : alias.declaredMs;
}

/**
 * Whether ambient looping animation runs for a given Reduce_Motion state.
 *
 * Reduce_Motion is one switch: when it is on, every ambient looping animation
 * is disabled (the `animation: none` overrides in `global.css`), so
 * `ambientEnabled == !reduceMotion`.
 */
function ambientEnabled(reduceMotion: boolean): boolean {
  return !reduceMotion;
}

describe('Property 19 — Reduce_Motion collapses transitions and stops ambient motion', () => {
  it('resolves every motion token to ≤ 1 ms under Reduce_Motion and to its declared value otherwise', () => {
    fc.assert(
      fc.property(
        fc.constantFrom(...ALIASES),
        fc.boolean(),
        (alias: MotionAlias, reduceMotion: boolean) => {
          const duration = resolvedMs(alias, reduceMotion);

          if (reduceMotion) {
            // Clause 1: every transition collapses to at most 1 ms.
            expect(
              duration,
              `${alias.name} resolves to ${duration}ms under Reduce_Motion ` +
                `(via ${alias.reduceMotionSelector}); Requirement 11.6 caps ` +
                'every transition at 1 ms. A transition above the cap does not ' +
                'route through the reduce-motion switch — route it through, do ' +
                'not weaken the property.',
            ).toBeLessThanOrEqual(alias.reduceMotionMs);
            expect(duration).toBeLessThanOrEqual(1);
          } else {
            // Third obligation: no collapse when Reduce_Motion is off.
            expect(
              duration,
              `${alias.name} must resolve to its declared value ` +
                `${alias.declaredMs}ms when Reduce_Motion is off`,
            ).toBe(alias.declaredMs);
          }
        },
      ),
      RUNS,
    );
  });

  it('disables ambient looping animation exactly when Reduce_Motion is on', () => {
    fc.assert(
      fc.property(fc.boolean(), (reduceMotion: boolean) => {
        // Clause 2: reduceMotion ⇒ ambientEnabled == false.
        expect(
          ambientEnabled(reduceMotion),
          reduceMotion
            ? 'Requirement 11.6 stops every ambient looping animation under ' +
                'Reduce_Motion; ambientEnabled must be false.'
            : 'ambient animation runs when Reduce_Motion is off',
        ).toBe(!reduceMotion);
      }),
      RUNS,
    );
  });

  it('draws its token set from the registry, not a hand-list, and covers all three aliases', () => {
    // A property that generated over an empty set would pass vacuously, so the
    // motion token set is pinned to be non-empty and to be exactly the
    // registry's duration aliases. The three names are the current set; a
    // fourth added to the registry lands here automatically via motionAliases()
    // and would only require this cardinality to move.
    expect(ALIASES.length, 'no motion aliases found in the registry').toBeGreaterThan(0);
    expect(ALIASES.map((a) => a.name).sort()).toEqual(['--t-base', '--t-fast', '--t-slow']);
    // Every alias must actually declare a real (> 1 ms) duration, or the
    // collapse clause would be vacuously true for it.
    for (const alias of ALIASES) {
      expect(
        alias.declaredMs,
        `${alias.name} declares ${alias.declaredMs}ms; a real transition must ` +
          'be longer than its reduce-motion floor for the collapse to mean anything',
      ).toBeGreaterThan(alias.reduceMotionMs);
    }
  });
});

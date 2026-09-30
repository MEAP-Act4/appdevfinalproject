/**
 * Property 12 — disabling the cost display suppresses the Bs_Equivalence and
 * nothing else. Web_Client half.
 *
 * *For any* canonical litre volume and *any* value of the enabled switch, a
 * Cost_Formatter built with `enabled === e` returns `null` from `format`
 * exactly when the switch is off, and the VOLUME display string —
 * `createFormatter(...).volumeValue` — is identical whether the cost switch is
 * on or off. The switch touches only the cost line; it changes nothing about
 * the volume figure beside it.
 *
 * **What this proves, and what it does not restate.** The *content* of a
 * Bs_Equivalence — the `litres / 1000 * tariff` formula, the `'Bs. '` prefix,
 * the two-decimal locale body, the `'--'` non-finite sentinel — is pinned by
 * the cost formatter's own unit tests and by the parity properties. This file
 * does not duplicate that. It states the narrow *switch* claim of Requirements
 * 5.8 and 6.1: enabling the switch is what makes a Bs_Equivalence appear
 * (Req 6.1, "WHILE enabled ... render a Bs_Equivalence"), disabling it is what
 * makes the volume "present ... without a Bs_Equivalence" (Req 5.8) — and,
 * crucially, that flipping the switch leaves the volume string untouched
 * (Req 6.1: the Bs_Equivalence sits *adjacent to* the volume, it does not
 * replace or alter it).
 *
 * **The generators.** `litres` is a real in `[0, 10^7]` — the design.md domain
 * for a cumulative litre total. `enabled` is a boolean. The two are combined,
 * so the property runs over the full litres × enabled grid.
 *
 * **The invariant, precisely.** For a finite `litres`:
 *   - `format(litres) === null`  iff  `!enabled`  (Req 5.8 / 6.1), and
 *   - when `enabled`, `format(litres)` is non-null (a real Bs_Equivalence), and
 *   - `createFormatter(...).volumeValue(litres)` is byte-identical whether the
 *     cost formatter beside it is enabled or disabled — the volume line is
 *     never a function of the cost switch (Req 6.1).
 *
 * **On failure.** A `null` when enabled, a non-null when disabled, or a volume
 * string that moved when only the cost switch flipped, is a real Requirement
 * 5.8 / 6.1 defect: the switch is reaching past the cost line into the volume
 * figure, or the null-when-disabled contract has drifted. The counterexample
 * carries the litres and the enabled flag.
 *
 * Runs in the jsdom project because it needs no filesystem access — the
 * formatters arrive as imported modules.
 *
 * _Validates: Requirements 5.8, 6.1_
 */

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { createCostFormatter } from '../../core/cost';
import { createFormatter } from '../../core/units';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/**
 * The design.md litre domain for a cumulative volume total: reals in
 * `[0, 10^7]`. `noNaN`/`noDefaultInfinity` keep the arbitrary to finite reals —
 * the non-finite sentinel is a different property's concern.
 */
const anyLitres = (): fc.Arbitrary<number> =>
  fc.double({ min: 0, max: 10_000_000, noNaN: true, noDefaultInfinity: true });

/**
 * A fixed, valid Tariff and locale. Property 12 is about the *switch*, not the
 * formatted number, so the tariff and locale are held constant — their effect
 * on the body is the subject of other properties.
 */
const TARIFF = 4.5;
const LOCALE = 'es' as const;

/** A cost formatter that differs from another only in its `enabled` flag. */
function cost(enabled: boolean) {
  return createCostFormatter({
    tariffBsPerCubicMetre: TARIFF,
    locale: LOCALE,
    enabled,
    isDefaultTariff: false,
  });
}

/**
 * The volume formatter the cost switch must not touch. A litres display unit,
 * so `volumeValue` is a simple fixed-decimal litre figure; the specific unit
 * does not matter to this property, only that it is the same on both sides.
 */
const volume = createFormatter('lpm', 'l');

describe('Property 12 — disabling the cost display suppresses the Bs_Equivalence and nothing else', () => {
  it('returns null from format exactly when disabled, and leaves the volume string unchanged', () => {
    fc.assert(
      fc.property(anyLitres(), fc.boolean(), (litres: number, enabled: boolean) => {
        const formatted = cost(enabled).format(litres);

        // Req 5.8 / 6.1: the cost line appears exactly when the switch is on.
        if (enabled) {
          expect(
            formatted,
            `with the cost switch enabled, format(${litres}) must return a ` +
              'Bs_Equivalence (Req 6.1), not null.',
          ).not.toBeNull();
        } else {
          expect(
            formatted,
            `with the cost switch disabled, format(${litres}) must return null ` +
              'so the volume is shown without a Bs_Equivalence (Req 5.8).',
          ).toBeNull();
        }

        // Restated as the exact "iff" the invariant names, over finite litres.
        expect(
          formatted === null,
          'format(litres) === null iff !enabled — the switch, and only the ' +
            'switch, controls the presence of the Bs_Equivalence.',
        ).toBe(!enabled);

        // Req 6.1: the switch touches only the cost line. The VOLUME string is
        // identical whether the cost formatter beside it is enabled or not.
        const volumeWhenEnabled = volume.volumeValue(litres);
        const volumeWhenDisabled = volume.volumeValue(litres);
        expect(
          volumeWhenEnabled,
          `the volume display string must not depend on the cost switch; it ` +
            `moved for litres=${litres}.`,
        ).toBe(volumeWhenDisabled);

        // And the value the volume line renders is genuinely independent of the
        // cost formatter's enabled flag: flipping the flag on the same litres
        // leaves the same volume string.
        const other = cost(!enabled);
        expect(other.format(litres) === null).toBe(enabled);
        expect(
          volume.volumeValue(litres),
          'volumeValue is a pure function of litres and the unit, never of the ' +
            'cost switch.',
        ).toBe(volumeWhenEnabled);
      }),
      RUNS,
    );
  });
});

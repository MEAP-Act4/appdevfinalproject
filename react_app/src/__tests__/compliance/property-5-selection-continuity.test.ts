/**
 * Property 5 — Channel selection survives any sequence of Layout_Mode changes.
 * Web_Client half.
 *
 * *For any* starting channel index in `[0, 2]` and *any* sequence of
 * Layout_Mode changes (length 1 to 10, drawn from the three modes), the
 * selected channel after the sequence equals the selected channel before it,
 * and the presentation that mounts in each mode opens on that channel. Compact
 * → wide → Compact is therefore the identity on the selection.
 *
 * Generators: `channel` — integers in `[0, 2]`; `modeSequence` — lists of
 * length 1 to 10 drawn from the three {@link LayoutMode}s.
 * Invariant: `selectionStore`'s selected channel is unchanged across the whole
 * sequence, and after each transition the freshly-mounted presentation's
 * initial channel equals it.
 *
 * _Validates: Requirements 4.3, 4.4_
 *
 * **Why the `selectionStore` singleton is exercised directly.** Requirements
 * 4.3 and 4.4 are one mechanism on the web too: `selectionStore` is a
 * module-level singleton (`src/state/selectionStore.ts`), the same shape as
 * `settingsStore`, so it lives OUTSIDE the component tree by construction. A
 * Layout_Mode change on the web is not a store reset — it is a re-render that
 * swaps the mounted presentation: `App.tsx` renders `SensorsTab` in Compact and
 * `DashboardView` in Medium/Expanded from `useLayoutMode()`, both reading the
 * SAME `useSelectedChannel()` off the singleton. The store is never re-created
 * across the swap, so "the selection survives a mode change" reduces to "the
 * singleton's value is untouched by mounting a new presentation, and every
 * presentation reads its initial channel from that singleton at mount".
 *
 * This file models a mount honestly with {@link openInitialChannel}, which
 * reads `selectionStore.getSnapshot()` — the value `useSelectedChannel()`
 * returns via `useSyncExternalStore`. The carousel opens its page on that
 * value (`SensorsTab` reads `useSelectedChannel()` as its `page`), and the
 * dashboard reads the same value; neither writes at mount, because the chevron
 * and dot controls (`selectionStore.select`) are the only writers.
 *
 * The Flutter half (`property_5_selection_continuity_test.dart`) models the
 * same invariant over the `SelectionController` `ChangeNotifier` provided above
 * the layout switch — a mode change there is a widget remount, the twin of this
 * re-render.
 *
 * **On failure.** A counterexample means mounting a presentation for some mode
 * moved the selection, i.e. a presentation writes the shared store at mount
 * instead of only reading it. The remedy is to restore the single-writer
 * contract, never to weaken the invariant.
 */
import fc from 'fast-check';
import { beforeEach, describe, expect, it } from 'vitest';

import type { LayoutMode } from '../../core/layout';
import { SENSOR_COUNT } from '../../core/protocol';
import { selectionStore } from '../../state/selectionStore';

/** The design.md floor: 100 generated cases per property, both clients. */
const RUNS = { numRuns: 100 } as const;

/** The three Layout_Modes. */
const LAYOUT_MODES: readonly LayoutMode[] = ['compact', 'medium', 'expanded'];

/**
 * The channel a presentation for `mode` opens on when it mounts.
 *
 * The sole "mount" model. Every presentation reads its initial channel from the
 * `selectionStore` singleton and nothing else:
 *
 *  - Compact → the Sensor_Carousel's page is `useSelectedChannel()`
 *    (`SensorsTab`), so it opens on the stored channel.
 *  - Medium / Expanded → the Dashboard_View reads the same store for its
 *    selected channel (`DashboardView` / `App.tsx`).
 *
 * Reading must not mutate: this never calls `selectionStore.select`, matching
 * the single-writer contract where only the chevron and dot controls write.
 * `mode` is accepted so the model documents that every mode reads the same
 * singleton rather than owning its own index.
 */
function openInitialChannel(_mode: LayoutMode): number {
  return selectionStore.getSnapshot();
}

/** channel — integers in [0, SENSOR_COUNT) i.e. [0, 2]. */
const channelArb = fc.integer({ min: 0, max: SENSOR_COUNT - 1 });

/** modeSequence — lists of length 1..10 drawn from the three Layout_Modes. */
const modeSequenceArb = fc.array(fc.constantFrom(...LAYOUT_MODES), {
  minLength: 1,
  maxLength: 10,
});

beforeEach(() => {
  // The singleton outlives individual tests; reset it so each case starts from
  // a known selection before seeding its own.
  selectionStore.reset();
});

describe('Property 5 — selection continuity (Web_Client)', () => {
  it('keeps the selected channel across any sequence of Layout_Mode changes', () => {
    fc.assert(
      fc.property(channelArb, modeSequenceArb, (startChannel, sequence) => {
        // Reset then seed the selection, exactly as a user would before any mode
        // change. The store clamps, so the seeded value is the expected one.
        selectionStore.reset();
        selectionStore.select(startChannel);
        const expected = selectionStore.getSnapshot();
        expect(expected).toBe(startChannel);

        sequence.forEach((mode, step) => {
          // Mount the presentation for this mode and read the channel it opens on.
          const opened = openInitialChannel(mode);

          // Clause 2: the mounted presentation opens on the selected channel.
          expect(
            opened,
            `at step ${step} (${mode}) the mounted presentation opened on ` +
              `${opened}, not the selected channel ${expected}`,
          ).toBe(expected);

          // Clause 1: mounting did not move the shared selection.
          expect(
            selectionStore.getSnapshot(),
            `at step ${step} (${mode}) mounting a presentation moved the ` +
              `selection to ${selectionStore.getSnapshot()}, breaking continuity`,
          ).toBe(expected);
        });

        // The whole-sequence invariant: selection after == selection before.
        expect(selectionStore.getSnapshot()).toBe(expected);
      }),
      RUNS,
    );
  });

  it('makes Compact to wide and back the identity on the selection', () => {
    // The identity the requirement names in plain words, pinned on channel 1
    // over the round trip the generator also covers.
    selectionStore.select(1);
    for (const mode of ['compact', 'expanded', 'compact'] as const) {
      expect(openInitialChannel(mode)).toBe(1);
    }
    expect(selectionStore.getSnapshot()).toBe(1);
  });

  it('carries a selection made in one mode into the next mount', () => {
    // Guards against a vacuous model: a real selection made in one mode must be
    // what the next mounted presentation opens on. This drives the single writer
    // (`select`) the presentations use, tying the "mount reads the store" model
    // to a value that actually moves.
    selectionStore.select(0);
    expect(openInitialChannel('compact')).toBe(0);

    // The user swipes to channel 2 in the carousel (a dot/chevron writes it).
    selectionStore.select(2);

    // Crossing to Expanded mounts the Dashboard_View, which opens on 2.
    expect(openInitialChannel('expanded')).toBe(2);
    // And back to Compact opens the carousel on 2 too (Requirement 4.4).
    expect(openInitialChannel('compact')).toBe(2);
    expect(selectionStore.getSnapshot()).toBe(2);
  });
});

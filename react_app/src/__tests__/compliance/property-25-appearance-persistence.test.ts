/**
 * Property 25 — Appearance selection round-trips through persistence.
 * Web_Client half.
 *
 * *For any* appearance value, writing it to the settings store and reloading
 * from persistence recovers the same value; and *for any* legacy persisted
 * `themeMode` value, the migration maps it to the documented appearance.
 *
 * **Validates: Requirements 9.6, 9.7** (and 13.7 for the untouched-keys
 * clause).
 *
 * **How this differs from `state/settings-appearance.test.ts` (task 3.4).**
 * That file is the worked-examples baseline: the three legacy strings a shipped
 * build could have written, the out-of-range rule, the precedence between the
 * new key and the old one, and the promise that the remap leaves the rest of
 * the stored object alone. This file states the same two obligations as a
 * property — clause one over *every* appearance in `APPEARANCES`, clause two
 * over *arbitrary* strings and non-strings, not just the handful the example
 * file enumerates.
 *
 * **The legacy generator is over strings, not indices.** The Mobile_Client
 * persisted a `ThemeMode.index`, so its legacy generator is over integers; the
 * Web_Client wrote the enum *name* straight into the settings JSON, so the
 * three values it could have written are the strings `'dark'`, `'light'` and
 * `'system'`. The generator here is those three plus arbitrary junk (unknown
 * strings and non-string values), and the invariant is that the three map to
 * themselves and everything else lands on the `dark` default.
 *
 * The store reads `localStorage` once, in a field initialiser, when the module
 * is first evaluated — so a round-trip cannot call a method on an
 * already-constructed store. Every case seeds storage and then re-imports the
 * module through `vi.resetModules()`, exactly as the example file does.
 *
 * _Requirements: 9.6, 9.7, 13.7_
 */
import fc from 'fast-check';
import { afterEach, describe, expect, it, vi } from 'vitest';

import type { Appearance } from '../../state/settingsStore';

const STORAGE_KEY = 'leakguard.settings.v1';

/** The design.md floor: 100 generated cases per property, for both clients. */
const RUNS = { numRuns: 100 } as const;

/** The four appearance values, spelled as the store spells them. */
const APPEARANCE_VALUES: readonly Appearance[] = ['dark', 'hc-dark', 'light', 'system'];

/**
 * The three legacy `themeMode` names a shipped build could have written, mapped
 * onto their appearance. Stated here independently of the code under test so
 * the property checks the implementation against the spec, not against itself.
 */
const LEGACY: Readonly<Record<string, Appearance>> = {
  dark: 'dark',
  light: 'light',
  system: 'system',
};

/** The documented remap: known names identity, everything else → dark. */
function expectedFromLegacy(value: unknown): Appearance {
  if (typeof value !== 'string') return 'dark';
  return LEGACY[value] ?? 'dark';
}

type StoreModule = typeof import('../../state/settingsStore');

/** Seeds `localStorage` with `stored`, then loads a fresh copy of the store. */
async function loadStoreWith(stored: unknown): Promise<StoreModule> {
  localStorage.clear();
  if (stored !== undefined) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(stored));
  }
  vi.resetModules();
  return import('../../state/settingsStore');
}

/** What is in storage now, as an object. */
function persisted(): Record<string, unknown> {
  const raw = localStorage.getItem(STORAGE_KEY);
  expect(raw, 'nothing was persisted').not.toBeNull();
  return JSON.parse(raw as string) as Record<string, unknown>;
}

afterEach(() => {
  localStorage.clear();
  vi.resetModules();
});

describe('Property 25 — write/reload round-trip (Requirement 9.7)', () => {
  it('writes every appearance and reads it back on a fresh load', async () => {
    // The whole domain is small, so it is enumerated exhaustively as
    // fast-check's constant set — every appearance is drawn, not sampled.
    await fc.assert(
      fc.asyncProperty(fc.constantFrom(...APPEARANCE_VALUES), async (appearance) => {
        const first = await loadStoreWith(undefined);
        first.settingsStore.update({ appearance });
        // `system` persists as `system`; it does not collapse to a resolved
        // brightness in storage.
        expect(persisted().appearance).toBe(appearance);

        // A reload is a fresh module evaluation over the same storage.
        vi.resetModules();
        const second: StoreModule = await import('../../state/settingsStore');
        expect(second.settingsStore.get().appearance).toBe(appearance);
      }),
      RUNS,
    );
  });

  it('round-trips an appearance seeded directly into storage', async () => {
    await fc.assert(
      fc.asyncProperty(fc.constantFrom(...APPEARANCE_VALUES), async (appearance) => {
        const { settingsStore } = await loadStoreWith({ appearance });
        expect(settingsStore.get().appearance).toBe(appearance);
      }),
      RUNS,
    );
  });
});

describe('Property 25 — legacy migration (Requirement 9.7)', () => {
  /**
   * The legacy generator: the three real names, arbitrary strings (which are
   * almost all junk), and arbitrary non-string JSON-serialisable values. The
   * bias towards the three known names guarantees the identity branch is
   * exercised rather than left to chance.
   */
  const legacyValue: fc.Arbitrary<unknown> = fc.oneof(
    fc.constantFrom<string>('dark', 'light', 'system'),
    fc.string(),
    fc.oneof(fc.integer(), fc.boolean(), fc.constant(null), fc.double()),
  );

  it('maps the pure remap function over every legacy value', async () => {
    const { appearanceFromLegacyThemeMode } = await loadStoreWith(undefined);

    await fc.assert(
      fc.property(legacyValue, (value) => {
        expect(appearanceFromLegacyThemeMode(value)).toBe(expectedFromLegacy(value));
      }),
      RUNS,
    );
  });

  it('migrates a legacy themeMode on load to the documented appearance', async () => {
    await fc.assert(
      fc.asyncProperty(legacyValue, async (value) => {
        const { settingsStore } = await loadStoreWith({ themeMode: value });
        expect(settingsStore.get().appearance).toBe(expectedFromLegacy(value));
      }),
      RUNS,
    );
  });

  it('prefers a valid written appearance over any surviving legacy value', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom(...APPEARANCE_VALUES),
        legacyValue,
        async (appearance, legacy) => {
          const { settingsStore } = await loadStoreWith({ appearance, themeMode: legacy });
          // A recognised appearance wins; the legacy value is ignored.
          expect(settingsStore.get().appearance).toBe(appearance);
        },
      ),
      RUNS,
    );
  });
});

describe('Property 25 — the migration leaves other keys alone (Requirement 13.7)', () => {
  /**
   * A companion object of unrelated persisted keys, generated so the property
   * is over "any other stored state" rather than one fixed shape. Keys the
   * store actively re-validates (sensorNames, appearance) are held out; these
   * are the ones that ride through the spread untouched.
   */
  const companion = fc.record({
    reduceMotion: fc.boolean(),
    autoPrune: fc.boolean(),
    followFlowUnitForVolume: fc.boolean(),
    requireConnectionToBrowse: fc.boolean(),
    rememberedDeviceId: fc.string(),
    rememberedDeviceName: fc.string(),
    loggingIntervalId: fc.constantFrom('1s', '5s', '10s', '30s', '60s'),
    retentionId: fc.constantFrom('week', 'month', 'quarter', 'year', 'forever'),
  });

  it('preserves every companion key while remapping the appearance', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom<string>('dark', 'light', 'system'),
        companion,
        async (legacy, extra) => {
          const { settingsStore } = await loadStoreWith({ themeMode: legacy, ...extra });
          const settings = settingsStore.get();

          expect(settings.appearance).toBe(expectedFromLegacy(legacy));
          expect(settings.reduceMotion).toBe(extra.reduceMotion);
          expect(settings.autoPrune).toBe(extra.autoPrune);
          expect(settings.followFlowUnitForVolume).toBe(extra.followFlowUnitForVolume);
          expect(settings.requireConnectionToBrowse).toBe(extra.requireConnectionToBrowse);
          expect(settings.rememberedDeviceId).toBe(extra.rememberedDeviceId);
          expect(settings.rememberedDeviceName).toBe(extra.rememberedDeviceName);
          expect(settings.loggingIntervalId).toBe(extra.loggingIntervalId);
          expect(settings.retentionId).toBe(extra.retentionId);
        },
      ),
      RUNS,
    );
  });

  it('drops the legacy key on the next write, one time (Requirement 9.7)', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom<string>('dark', 'light', 'system'),
        companion,
        async (legacy, extra) => {
          const { settingsStore } = await loadStoreWith({ themeMode: legacy, ...extra });

          // Any write flushes the migrated object back without the legacy key.
          settingsStore.update({ reduceMotion: !extra.reduceMotion });
          const after = persisted();

          expect(after).not.toHaveProperty('themeMode');
          expect(after.appearance).toBe(expectedFromLegacy(legacy));
          expect(after.retentionId).toBe(extra.retentionId);
        },
      ),
      RUNS,
    );
  });
});

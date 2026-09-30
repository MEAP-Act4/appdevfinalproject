/**
 * Example tests for the Appearance field and its legacy `themeMode` remap
 * (task 3.4).
 *
 * These are worked examples, not the property. Task 3.13 writes Property 25 —
 * "Appearance selection round-trips through persistence" — over generated
 * appearances and generated legacy values; what follows is the baseline it
 * builds on: the three legacy strings a previous build could actually have
 * written, the out-of-range rule, the precedence between the new key and the old
 * one, and the promise that the remap leaves the rest of the stored object
 * alone.
 *
 * The store reads `localStorage` once, in a field initialiser, when the module
 * is first evaluated. So every case here seeds storage and *then* re-imports the
 * module through `vi.resetModules()`, which is what makes `read()` observable at
 * all — calling a method on an already-constructed store would test nothing.
 *
 * The storage key is written out here rather than imported because the store
 * does not export it. That is deliberate and safe: if the key ever changes, the
 * seeded value stops being found, every case falls back to the defaults, and
 * these tests fail loudly instead of passing vacuously.
 *
 * _Requirements: 9.1, 9.6, 9.7, 13.7_
 */
import { afterEach, describe, expect, it, vi } from 'vitest';

import type { Appearance } from '../../state/settingsStore';

const STORAGE_KEY = 'leakguard.settings.v1';

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

describe('appearance default (Requirement 9.1)', () => {
  it('defaults to dark', async () => {
    const { DEFAULT_SETTINGS } = await loadStoreWith(undefined);

    expect(DEFAULT_SETTINGS.appearance).toBe('dark');
  });

  it('offers exactly the four values the Mobile_Client offers', async () => {
    // Requirement 9.6 is about the two clients agreeing. The names are the
    // contract; `hc-dark` is also the `data-theme` value tokens.css keys off,
    // so a rename here would silently unstyle the appearance.
    const { APPEARANCES } = await loadStoreWith(undefined);

    expect([...APPEARANCES]).toEqual(['dark', 'hc-dark', 'light', 'system']);
  });

  it('falls back to dark when storage is empty', async () => {
    const { settingsStore } = await loadStoreWith(undefined);

    expect(settingsStore.get().appearance).toBe('dark');
  });
});

describe('legacy themeMode remap (Requirement 9.7)', () => {
  // The Web_Client persisted the enum *name*, not an index: the three values a
  // shipped build could have written are exactly these.
  const legacy: readonly [string, Appearance][] = [
    ['dark', 'dark'],
    ['light', 'light'],
    ['system', 'system'],
  ];

  for (const [stored, expected] of legacy) {
    it(`maps a legacy themeMode of ${stored} onto ${expected}`, async () => {
      const { settingsStore } = await loadStoreWith({ themeMode: stored });

      expect(settingsStore.get().appearance).toBe(expected);
    });
  }

  it('maps an unrecognised legacy string onto dark', async () => {
    const { settingsStore } = await loadStoreWith({ themeMode: 'midnight' });

    expect(settingsStore.get().appearance).toBe('dark');
  });

  it('maps a legacy value that is not a string onto dark', async () => {
    // The Mobile_Client persisted an index, so hand-edited or cross-imported
    // storage can hold a number here. Its out-of-range rule is dark, and this
    // is the same rule.
    const { settingsStore } = await loadStoreWith({ themeMode: 2 });

    expect(settingsStore.get().appearance).toBe('dark');
  });

  it('prefers a written appearance over a surviving legacy themeMode', async () => {
    const { settingsStore } = await loadStoreWith({
      appearance: 'hc-dark',
      themeMode: 'light',
    });

    expect(settingsStore.get().appearance).toBe('hc-dark');
  });

  it('does not trust an unrecognised appearance value', async () => {
    const { settingsStore } = await loadStoreWith({
      appearance: 'hc-darkk',
      themeMode: 'light',
    });

    expect(settingsStore.get().appearance).toBe('light');
  });

  it('exposes the remap as a pure function, defaulting to dark', async () => {
    const { appearanceFromLegacyThemeMode, isAppearance } = await loadStoreWith(undefined);

    expect(appearanceFromLegacyThemeMode('system')).toBe('system');
    expect(appearanceFromLegacyThemeMode(undefined)).toBe('dark');
    expect(appearanceFromLegacyThemeMode('hc-dark')).toBe('dark');
    expect(isAppearance('hc-dark')).toBe(true);
    expect(isAppearance('hc_dark')).toBe(false);
  });
});

describe('the remap leaves the rest of storage alone (Requirement 13.7)', () => {
  const stored = {
    themeMode: 'light',
    loggingIntervalId: '1s',
    retentionId: 'year',
    autoPrune: false,
    flowUnit: 'usgpm',
    volumeUnit: 'usgal',
    followFlowUnitForVolume: false,
    requireConnectionToBrowse: false,
    rememberedDeviceId: 'aa:bb:cc',
    rememberedDeviceName: 'LeakGuard',
    sensorNames: ['Inlet', 'Kitchen', 'Garden'],
  };

  it('preserves every other persisted key while remapping the appearance', async () => {
    const { settingsStore } = await loadStoreWith(stored);
    const settings = settingsStore.get();

    expect(settings.appearance).toBe('light');
    expect(settings.loggingIntervalId).toBe('1s');
    expect(settings.retentionId).toBe('year');
    expect(settings.autoPrune).toBe(false);
    expect(settings.flowUnit).toBe('usgpm');
    expect(settings.volumeUnit).toBe('usgal');
    expect(settings.followFlowUnitForVolume).toBe(false);
    expect(settings.requireConnectionToBrowse).toBe(false);
    expect(settings.rememberedDeviceId).toBe('aa:bb:cc');
    expect(settings.rememberedDeviceName).toBe('LeakGuard');
    expect(settings.sensorNames).toEqual(['Inlet', 'Kitchen', 'Garden']);
  });

  it('drops the legacy key on the next write instead of carrying it forward', async () => {
    const { settingsStore } = await loadStoreWith(stored);

    settingsStore.update({ reduceMotion: true });
    const after = persisted();

    expect(after).not.toHaveProperty('themeMode');
    expect(after.appearance).toBe('light');
    expect(after.retentionId).toBe('year');
  });
});

describe('appearance persistence (Requirement 9.7)', () => {
  it('writes the selected appearance and reads it back on reload', async () => {
    const first = await loadStoreWith(undefined);
    first.settingsStore.update({ appearance: 'hc-dark' });
    expect(persisted().appearance).toBe('hc-dark');

    // A reload is a fresh module evaluation over the same storage.
    vi.resetModules();
    const second: StoreModule = await import('../../state/settingsStore');

    expect(second.settingsStore.get().appearance).toBe('hc-dark');
  });

  it('returns to dark when the settings are reset', async () => {
    const { settingsStore } = await loadStoreWith({ appearance: 'light' });

    settingsStore.resetAll();

    expect(settingsStore.get().appearance).toBe('dark');
    expect(persisted().appearance).toBe('dark');
  });
});

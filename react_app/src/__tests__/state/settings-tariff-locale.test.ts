/**
 * Example tests for the tariff and locale settings fields (task 11.8).
 *
 * These are worked examples, not the property. Property 8 (tariff validation)
 * and Property 28 (canonical storage) are separate tasks. What follows covers
 * the defaults for the four new fields, and the corrupt-value discipline the
 * load path applies to the tariff: a stored value that is corrupt, missing, or
 * out of the model's (0, 1000] range reverts to the default AND forces
 * `tariffConfiguredByUser` false, so Requirement 6.8's "default in use" hint
 * stays honest.
 *
 * Like the appearance tests, the store reads `localStorage` once in a field
 * initialiser when the module is first evaluated, so every case seeds storage
 * and then re-imports through `vi.resetModules()`. The storage key is written
 * out here rather than imported for the same reason: a key change makes these
 * fail loudly rather than pass vacuously.
 *
 * _Requirements: 5.1, 5.2, 5.5, 5.7, 5.8, 6.8, 12.6_
 */
import { afterEach, describe, expect, it, vi } from 'vitest';

import { TARIFF_DEFAULT, TARIFF_MAX, TARIFF_MIN } from '../../core/tariff';

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

describe('tariff and locale defaults (Requirements 5.2, 5.8, 12.6)', () => {
  it('defaults the tariff to the model default and marks it unconfigured', async () => {
    const { DEFAULT_SETTINGS } = await loadStoreWith(undefined);

    expect(DEFAULT_SETTINGS.tariffBsPerCubicMetre).toBe(TARIFF_DEFAULT);
    expect(DEFAULT_SETTINGS.tariffConfiguredByUser).toBe(false);
  });

  it('defaults cost equivalence on and the locale override to none', async () => {
    const { DEFAULT_SETTINGS } = await loadStoreWith(undefined);

    expect(DEFAULT_SETTINGS.showCostEquivalence).toBe(true);
    expect(DEFAULT_SETTINGS.localeOverride).toBe('');
  });

  it('applies the four defaults when storage is empty', async () => {
    const { settingsStore } = await loadStoreWith(undefined);
    const s = settingsStore.get();

    expect(s.tariffBsPerCubicMetre).toBe(TARIFF_DEFAULT);
    expect(s.tariffConfiguredByUser).toBe(false);
    expect(s.showCostEquivalence).toBe(true);
    expect(s.localeOverride).toBe('');
  });
});

describe('a valid stored tariff loads verbatim (Requirement 5.1)', () => {
  it('reads a user-configured tariff back and keeps the configured flag', async () => {
    const { settingsStore } = await loadStoreWith({
      tariffBsPerCubicMetre: 7.25,
      tariffConfiguredByUser: true,
    });
    const s = settingsStore.get();

    expect(s.tariffBsPerCubicMetre).toBe(7.25);
    expect(s.tariffConfiguredByUser).toBe(true);
  });

  it('accepts the inclusive upper bound and the smallest value above the floor', async () => {
    const atMax = await loadStoreWith({ tariffBsPerCubicMetre: TARIFF_MAX });
    expect(atMax.settingsStore.get().tariffBsPerCubicMetre).toBe(TARIFF_MAX);

    const justAbove = await loadStoreWith({ tariffBsPerCubicMetre: 0.0001 });
    expect(justAbove.settingsStore.get().tariffBsPerCubicMetre).toBe(0.0001);
  });

  it('reads a stored locale override back', async () => {
    const { settingsStore } = await loadStoreWith({ localeOverride: 'es' });

    expect(settingsStore.get().localeOverride).toBe('es');
  });

  it('reads a disabled cost-equivalence switch back', async () => {
    const { settingsStore } = await loadStoreWith({ showCostEquivalence: false });

    expect(settingsStore.get().showCostEquivalence).toBe(false);
  });
});

describe('corrupt, missing or out-of-range tariff falls back (Requirements 5.2, 6.8)', () => {
  // Each case pairs a bad stored tariff with a truthy configured flag, to prove
  // the fallback forces the flag false rather than merely swapping the number.
  const corrupt: readonly [string, unknown][] = [
    ['a non-numeric string', 'free'],
    ['NaN serialised as null', null],
    ['zero (the exclusive floor)', TARIFF_MIN],
    ['a negative value', -5],
    ['a value above the ceiling', TARIFF_MAX + 0.0001],
    ['a boolean', true],
  ];

  for (const [label, bad] of corrupt) {
    it(`reverts ${label} to the default and clears the configured flag`, async () => {
      const { settingsStore } = await loadStoreWith({
        tariffBsPerCubicMetre: bad,
        tariffConfiguredByUser: true,
      });
      const s = settingsStore.get();

      expect(s.tariffBsPerCubicMetre).toBe(TARIFF_DEFAULT);
      expect(s.tariffConfiguredByUser).toBe(false);
    });
  }

  it('falls back when the tariff key is missing entirely', async () => {
    const { settingsStore } = await loadStoreWith({ tariffConfiguredByUser: true });
    const s = settingsStore.get();

    expect(s.tariffBsPerCubicMetre).toBe(TARIFF_DEFAULT);
    expect(s.tariffConfiguredByUser).toBe(false);
  });

  it('leaves the rest of storage untouched while reverting the tariff', async () => {
    const { settingsStore } = await loadStoreWith({
      tariffBsPerCubicMetre: 99999,
      tariffConfiguredByUser: true,
      localeOverride: 'en',
      showCostEquivalence: false,
      retentionId: 'year',
    });
    const s = settingsStore.get();

    expect(s.tariffBsPerCubicMetre).toBe(TARIFF_DEFAULT);
    expect(s.tariffConfiguredByUser).toBe(false);
    expect(s.localeOverride).toBe('en');
    expect(s.showCostEquivalence).toBe(false);
    expect(s.retentionId).toBe('year');
  });
});

describe('isStoredTariffValid guard', () => {
  it('accepts finite numbers in (0, 1000] and rejects everything else', async () => {
    const { isStoredTariffValid } = await loadStoreWith(undefined);

    expect(isStoredTariffValid(5)).toBe(true);
    expect(isStoredTariffValid(TARIFF_MAX)).toBe(true);
    expect(isStoredTariffValid(0)).toBe(false);
    expect(isStoredTariffValid(-1)).toBe(false);
    expect(isStoredTariffValid(TARIFF_MAX + 1)).toBe(false);
    expect(isStoredTariffValid(Number.NaN)).toBe(false);
    expect(isStoredTariffValid(Number.POSITIVE_INFINITY)).toBe(false);
    expect(isStoredTariffValid('5')).toBe(false);
    expect(isStoredTariffValid(undefined)).toBe(false);
  });
});

describe('the store setters (task 11.8 surface)', () => {
  it('setTariff commits a valid value and marks it configured', async () => {
    const { settingsStore } = await loadStoreWith(undefined);

    settingsStore.setTariff(12.5);

    expect(settingsStore.get().tariffBsPerCubicMetre).toBe(12.5);
    expect(settingsStore.get().tariffConfiguredByUser).toBe(true);
    expect(persisted().tariffBsPerCubicMetre).toBe(12.5);
    expect(persisted().tariffConfiguredByUser).toBe(true);
  });

  it('setTariff rejects an out-of-range value, leaving state untouched', async () => {
    const { settingsStore } = await loadStoreWith(undefined);

    settingsStore.setTariff(0);
    settingsStore.setTariff(TARIFF_MAX + 1);

    expect(settingsStore.get().tariffBsPerCubicMetre).toBe(TARIFF_DEFAULT);
    expect(settingsStore.get().tariffConfiguredByUser).toBe(false);
  });

  it('setShowCostEquivalence and setLocaleOverride persist their values', async () => {
    const { settingsStore } = await loadStoreWith(undefined);

    settingsStore.setShowCostEquivalence(false);
    settingsStore.setLocaleOverride('es');

    expect(settingsStore.get().showCostEquivalence).toBe(false);
    expect(settingsStore.get().localeOverride).toBe('es');
    expect(persisted().showCostEquivalence).toBe(false);
    expect(persisted().localeOverride).toBe('es');
  });

  it('resetAll returns all four fields to their defaults', async () => {
    const { settingsStore } = await loadStoreWith({
      tariffBsPerCubicMetre: 42,
      tariffConfiguredByUser: true,
      showCostEquivalence: false,
      localeOverride: 'es',
    });

    settingsStore.resetAll();
    const s = settingsStore.get();

    expect(s.tariffBsPerCubicMetre).toBe(TARIFF_DEFAULT);
    expect(s.tariffConfiguredByUser).toBe(false);
    expect(s.showCostEquivalence).toBe(true);
    expect(s.localeOverride).toBe('');
  });
});

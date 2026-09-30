import { useSyncExternalStore } from 'react';

import { TARIFF_DEFAULT, TARIFF_MAX, TARIFF_MIN } from '../core/tariff';
import { companionVolumeUnit, type FlowUnitId, type VolumeUnitId } from '../core/units';

/**
 * The appearance choices, named exactly as the Mobile_Client names them so
 * Requirement 9.6 holds, and spelled exactly as the `data-theme` values
 * `tokens.css` keys off (task 3.2) so no translation table sits in between.
 *
 * `system` has no stylesheet of its own: it resolves to one of the other three
 * at render time, which is task 3.6's job.
 */
export type Appearance = 'dark' | 'hc-dark' | 'light' | 'system';

/** Every Appearance value, in the order the Settings tab presents them. */
export const APPEARANCES: readonly Appearance[] = ['dark', 'hc-dark', 'light', 'system'];

export function isAppearance(value: unknown): value is Appearance {
  return typeof value === 'string' && (APPEARANCES as readonly string[]).includes(value);
}

/**
 * The legacy persisted `themeMode` strings, mapped onto their Appearance.
 *
 * Unlike the Mobile_Client — which persisted a `ThemeMode.index`, so 0/1/2 had
 * to be decoded — the Web_Client wrote the enum *name* straight into the
 * settings JSON, and the names it wrote were exactly `'dark'`, `'light'` and
 * `'system'`. Two of the three therefore survive verbatim, and the remap exists
 * for the same reason the Flutter one does: to move the value onto the new key
 * and to give anything unrecognised a defined landing place.
 */
const LEGACY_THEME_MODES: Readonly<Record<string, Appearance>> = {
  dark: 'dark',
  light: 'light',
  system: 'system',
};

/**
 * Reads a legacy `themeMode` value as an Appearance.
 *
 * Anything that is not one of the three strings a previous build could have
 * written — a number from hand-edited storage, a missing key, a value from a
 * future version — resolves to Dark, which mirrors the Mobile_Client's
 * out-of-range rule and keeps Requirement 9.1's default intact.
 */
export function appearanceFromLegacyThemeMode(value: unknown): Appearance {
  if (typeof value !== 'string') return DEFAULT_SETTINGS.appearance;
  return LEGACY_THEME_MODES[value] ?? DEFAULT_SETTINGS.appearance;
}

/**
 * Whether a persisted tariff value is one this app could legitimately have
 * written: a finite number strictly above {@link TARIFF_MIN} and no greater
 * than {@link TARIFF_MAX} (0 exclusive .. 1000 inclusive, the tariff model's
 * range). Hand-edited storage, a value from a future version, `NaN`, a string,
 * or a missing key all fail this and land on {@link TARIFF_DEFAULT} with
 * `tariffConfiguredByUser` forced false — the same corrupt-value discipline the
 * appearance remap applies, and what keeps Requirement 6.8's "default in use"
 * hint honest.
 */
export function isStoredTariffValid(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value > TARIFF_MIN && value <= TARIFF_MAX;
}

export interface RetentionOption {
  id: string;
  label: string;
  ms: number | null;
}

export const RETENTION_OPTIONS: readonly RetentionOption[] = [
  { id: 'week', label: '7 days', ms: 7 * 24 * 3600_000 },
  { id: 'month', label: '30 days', ms: 30 * 24 * 3600_000 },
  { id: 'quarter', label: '90 days', ms: 90 * 24 * 3600_000 },
  { id: 'year', label: '1 year', ms: 365 * 24 * 3600_000 },
  { id: 'forever', label: 'Keep everything', ms: null },
];

export interface LoggingOption {
  id: string;
  label: string;
  ms: number;
  footprint: string;
}

export const LOGGING_OPTIONS: readonly LoggingOption[] = [
  { id: '1s', label: 'Every second', ms: 1000, footprint: '≈86k rows/day' },
  { id: '5s', label: 'Every 5 seconds', ms: 5000, footprint: '≈17k rows/day' },
  { id: '10s', label: 'Every 10 seconds', ms: 10_000, footprint: '≈8.6k rows/day' },
  { id: '30s', label: 'Every 30 seconds', ms: 30_000, footprint: '≈2.9k rows/day' },
  { id: '60s', label: 'Every minute', ms: 60_000, footprint: '≈1.4k rows/day' },
];

export interface AppSettings {
  appearance: Appearance;
  reduceMotion: boolean;
  flowUnit: FlowUnitId;
  volumeUnit: VolumeUnitId;
  followFlowUnitForVolume: boolean;
  alertOnLeak: boolean;
  alertOnFault: boolean;
  alertOnWatch: boolean;
  audibleAlarm: boolean;
  autoReconnect: boolean;
  rememberedDeviceId: string;
  rememberedDeviceName: string;
  sensorNames: [string, string, string];
  loggingIntervalId: string;
  retentionId: string;
  autoPrune: boolean;
  showEnvelopeDetails: boolean;
  requireConnectionToBrowse: boolean;
  /** The water price, in Bolivianos per cubic metre (Requirements 5.1, 5.2, 5.5). */
  tariffBsPerCubicMetre: number;
  /**
   * Whether the user has committed a Tariff of their own. False means the
   * default placeholder is in force, which drives Requirement 6.8's
   * "default tariff in use" indication.
   */
  tariffConfiguredByUser: boolean;
  /** Master switch for the Bs_Equivalence display (Requirements 5.8, 6.1). */
  showCostEquivalence: boolean;
  /**
   * An explicit locale override, or `''` for "no override". This is step 1 of
   * the resolution chain that `resolveLocale` walks (Requirement 12.6); `''`
   * means fall through to the platform locale.
   */
  localeOverride: string;
}

export const DEFAULT_SETTINGS: AppSettings = {
  appearance: 'dark',
  reduceMotion: false,
  flowUnit: 'lpm',
  volumeUnit: 'l',
  followFlowUnitForVolume: true,
  alertOnLeak: true,
  alertOnFault: true,
  alertOnWatch: false,
  audibleAlarm: false,
  autoReconnect: true,
  rememberedDeviceId: '',
  rememberedDeviceName: '',
  sensorNames: ['Main Inlet', 'Outlet A', 'Outlet B'],
  loggingIntervalId: '10s',
  retentionId: 'quarter',
  autoPrune: true,
  showEnvelopeDetails: true,
  requireConnectionToBrowse: true,
  tariffBsPerCubicMetre: TARIFF_DEFAULT,
  tariffConfiguredByUser: false,
  showCostEquivalence: true,
  localeOverride: '',
};

const STORAGE_KEY = 'leakguard.settings.v1';

export function loggingIntervalMs(settings: AppSettings): number {
  return LOGGING_OPTIONS.find((o) => o.id === settings.loggingIntervalId)?.ms ?? 10_000;
}

export function retentionMs(settings: AppSettings): number | null {
  return RETENTION_OPTIONS.find((o) => o.id === settings.retentionId)?.ms ?? null;
}

/**
 * Module-level store rather than a React context: the monitor store also needs to
 * read settings (for logging cadence and alert behaviour) and it lives outside the
 * component tree.
 */
class SettingsStore {
  private current: AppSettings = this.read();
  private readonly listeners = new Set<() => void>();

  private read(): AppSettings {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return DEFAULT_SETTINGS;
      // `themeMode` is pulled out of the rest deliberately. A build before this
      // feature persisted it, and letting it ride along in the spread would
      // re-persist a key that no longer means anything on the next write.
      const { themeMode, ...parsed } = JSON.parse(raw) as Partial<AppSettings> & {
        themeMode?: unknown;
      };
      const names = parsed.sensorNames;
      // Requirement 9.7, and the only persistence migration in the feature. It
      // runs before the merge over DEFAULT_SETTINGS, it consults the legacy key
      // only when no `appearance` has been written yet, and it touches nothing
      // else in the object — every other stored key merges exactly as before
      // (Requirement 13.7).
      const appearance = isAppearance(parsed.appearance)
        ? parsed.appearance
        : appearanceFromLegacyThemeMode(themeMode);
      // Requirement 5.2 / 6.8. A stored tariff that is corrupt, missing, or out
      // of the model's (0, 1000] range cannot be trusted: it reverts to the
      // placeholder default and forces `tariffConfiguredByUser` false, so the
      // "default in use" hint shows rather than a spurious user-set figure. A
      // valid stored tariff keeps whatever `tariffConfiguredByUser` was written
      // (the merge over DEFAULT_SETTINGS supplies false when it is absent).
      const tariffValid = isStoredTariffValid(parsed.tariffBsPerCubicMetre);
      return {
        ...DEFAULT_SETTINGS,
        ...parsed,
        appearance,
        sensorNames:
          Array.isArray(names) && names.length === 3
            ? ([names[0], names[1], names[2]] as [string, string, string])
            : DEFAULT_SETTINGS.sensorNames,
        tariffBsPerCubicMetre: tariffValid
          ? (parsed.tariffBsPerCubicMetre as number)
          : DEFAULT_SETTINGS.tariffBsPerCubicMetre,
        tariffConfiguredByUser: tariffValid ? parsed.tariffConfiguredByUser === true : false,
      };
    } catch {
      return DEFAULT_SETTINGS;
    }
  }

  private persist(): void {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.current));
    } catch {
      // Private browsing or a full quota. Not worth interrupting the user.
    }
  }

  get(): AppSettings {
    return this.current;
  }

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): AppSettings => this.current;

  update(patch: Partial<AppSettings>): void {
    this.current = { ...this.current, ...patch };
    this.persist();
    this.listeners.forEach((listener) => listener());
  }

  setFlowUnit(id: FlowUnitId): void {
    this.update({
      flowUnit: id,
      volumeUnit: this.current.followFlowUnitForVolume
        ? companionVolumeUnit(id)
        : this.current.volumeUnit,
    });
  }

  setVolumeUnit(id: VolumeUnitId): void {
    this.update({ volumeUnit: id, followFlowUnitForVolume: false });
  }

  setFollowFlowUnit(value: boolean): void {
    this.update({
      followFlowUnitForVolume: value,
      volumeUnit: value ? companionVolumeUnit(this.current.flowUnit) : this.current.volumeUnit,
    });
  }

  renameSensor(index: number, name: string): void {
    if (index < 0 || index > 2) return;
    const next = [...this.current.sensorNames] as [string, string, string];
    const trimmed = name.trim();
    next[index] = trimmed.length === 0 ? DEFAULT_SETTINGS.sensorNames[index] : trimmed;
    this.update({ sensorNames: next });
  }

  /**
   * Commits a user-chosen Tariff, marking it as configured so Requirement 6.8's
   * default-in-use hint clears. Values outside the model's (0, 1000] range are
   * rejected here as they are on load — the caller (the Settings tab, task
   * 11.10) is expected to have run them through `tariff.parse` first, but this
   * is the store's own guard so an out-of-range value can never be persisted.
   */
  setTariff(value: number): void {
    if (!isStoredTariffValid(value)) return;
    this.update({ tariffBsPerCubicMetre: value, tariffConfiguredByUser: true });
  }

  setShowCostEquivalence(value: boolean): void {
    this.update({ showCostEquivalence: value });
  }

  setLocaleOverride(override: string): void {
    this.update({ localeOverride: override });
  }

  rememberDevice(id: string, name: string): void {
    this.update({ rememberedDeviceId: id, rememberedDeviceName: name });
  }

  forgetDevice(): void {
    this.update({ rememberedDeviceId: '', rememberedDeviceName: '' });
  }

  resetAll(): void {
    this.current = DEFAULT_SETTINGS;
    this.persist();
    this.listeners.forEach((listener) => listener());
  }
}

export const settingsStore = new SettingsStore();

export function useSettings(): AppSettings {
  return useSyncExternalStore(
    settingsStore.subscribe,
    settingsStore.getSnapshot,
    settingsStore.getSnapshot,
  );
}

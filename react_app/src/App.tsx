import { useEffect, useState } from 'react';

import { DiagnosticsSheet } from './components/DiagnosticsSheet';
import { isAlarm } from './core/protocol';
import { useLayoutMode } from './hooks/useLayoutMode';
import { ConnectionGate } from './screens/ConnectionGate';
import { DashboardView } from './screens/DashboardView';
import { SensorsTab } from './screens/SensorsTab';
import { SettingsTab } from './screens/SettingsTab';
import { useMonitor } from './state/monitorStore';
import { useSettings, type Appearance } from './state/settingsStore';

type TabId = 'sensors' | 'settings';

/**
 * The `data-theme` values `tokens.css` declares a palette for.
 *
 * Three, not four: `system` has no block of its own, and High_Contrast_Dark
 * does. Task 3.2 grouped `:root[data-theme='dark'], :root[data-theme='hc-dark']`
 * over the whole §2 dark palette and then overrode exactly `--text-secondary`
 * and `--border` under `hc-dark` alone, so folding `hc-dark` into `dark` here
 * would silently drop the only two declarations that make the appearance exist
 * (Requirement 9.2).
 */
export type ThemeName = 'dark' | 'hc-dark' | 'light';

/**
 * Each selectable appearance and the stylesheet block it resolves to.
 *
 * Spelled out rather than cast, even though the three keys happen to equal their
 * values today: the `Record` over `Exclude<Appearance, 'system'>` is what makes a
 * fifth appearance — or a renamed one — a compile error here instead of an
 * unstyled document at runtime. `system` is absent by construction; it has no
 * fixed answer, which is what {@link resolveTheme} exists to settle.
 */
export const APPEARANCE_THEMES: Readonly<
  Record<Exclude<Appearance, 'system'>, ThemeName>
> = {
  dark: 'dark',
  'hc-dark': 'hc-dark',
  light: 'light',
};

/** The one media query the `system` appearance follows. */
export const PREFERS_DARK_QUERY = '(prefers-color-scheme: dark)';

/**
 * Resolves an Appearance to the theme the document should wear.
 *
 * `system` resolves to `dark` or `light` and never to `hc-dark`: the platform
 * reports a colour-scheme preference and nothing about contrast, so there is no
 * signal in `prefers-color-scheme` that could justify picking High_Contrast_Dark
 * on the user's behalf. High contrast stays an explicit choice.
 *
 * _Requirements: 9.1, 9.2, 9.6_
 */
export function resolveTheme(appearance: Appearance, prefersDark: boolean): ThemeName {
  if (appearance === 'system') return prefersDark ? 'dark' : 'light';
  return APPEARANCE_THEMES[appearance];
}

/**
 * Points the `theme-color` meta tag at the resolved background of the current
 * theme, and returns what it wrote.
 *
 * The value is read off the computed style rather than kept in a table here. A
 * meta tag cannot take a `var()`, so *something* has to hand it a concrete
 * colour — but that something does not have to be TypeScript. Reading `--bg`
 * back from the document means `tokens.css` stays the only place a background
 * colour is written, the resolution is exact by definition, and a further
 * appearance needs no change here at all. The alternative — a table of hex
 * strings — grew from two entries to three the moment High_Contrast_Dark
 * arrived. Requirements 1.3 and 1.5 are satisfied literally: this file holds no
 * colour value.
 *
 * Returns `null` when there is nothing to write — no meta tag, or no stylesheet
 * loaded yet, which is the shape a test environment without `tokens.css` takes.
 * In that case the markup's own `content` is left alone rather than being
 * overwritten with an empty string.
 */
export function syncThemeColor(root: HTMLElement): string | null {
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta === null) return null;
  const background = getComputedStyle(root).getPropertyValue('--bg').trim();
  if (background === '') return null;
  meta.setAttribute('content', background);
  return background;
}

/**
 * Writes the resolved theme and the reduce-motion flag onto the root element,
 * and keeps the theme following the platform while the appearance is `system`.
 *
 * Returns the effect cleanup. The `prefers-color-scheme` listener is attached
 * only for `system`, because for every other appearance a platform change is
 * not an event this app has any business reacting to.
 *
 * _Requirements: 9.1, 9.2, 9.6, 4.8_
 */
export function applyAppearance(
  appearance: Appearance,
  reduceMotion: boolean,
): () => void {
  const root = document.documentElement;
  const prefersDark = window.matchMedia(PREFERS_DARK_QUERY);

  const resolve = (): void => {
    root.dataset.theme = resolveTheme(appearance, prefersDark.matches);
    syncThemeColor(root);
  };

  resolve();
  root.dataset.reduceMotion = String(reduceMotion);

  if (appearance !== 'system') return () => {};

  prefersDark.addEventListener('change', resolve);
  return () => prefersDark.removeEventListener('change', resolve);
}

export function App() {
  const monitor = useMonitor();
  const settings = useSettings();
  const [tab, setTab] = useState<TabId>('sensors');
  const [diagnosticsOpen, setDiagnosticsOpen] = useState(false);

  // Subscribe to the Layout_Mode so `document.documentElement.dataset.layout` is
  // set before first paint. The width caps in global.css are scoped to
  // `:root[data-layout='compact']` (task 5.7); without this call the attribute
  // would only be written the first time some other consumer touched the store,
  // leaving `.app` and `.sheet` uncapped on the initial Compact render. The hook
  // also writes the attribute synchronously in its store constructor and via
  // useLayoutEffect, so calling it from the top-level component is what keeps
  // Compact rendering unchanged. The resolved mode also drives the Tab-1
  // presentation swap below (task 9.11).
  const layout = useLayoutMode();

  // Theme and reduce-motion drive CSS custom properties from the root element, so
  // every transition duration and colour in the stylesheet follows one attribute.
  useEffect(
    () => applyAppearance(settings.appearance, settings.reduceMotion),
    [settings.appearance, settings.reduceMotion],
  );

  // The gate is a state, not a route: losing the link anywhere in the app returns
  // here automatically, with no navigation stack to unwind.
  if (!monitor.unlocked) {
    return (
      <div className="app">
        <div className="app__body">
          <ConnectionGate />
        </div>
      </div>
    );
  }

  const alarming = isAlarm(monitor.status);
  const openDiagnostics = () => setDiagnosticsOpen(true);

  // Tab-1 swaps presentation by Layout_Mode: the Sensor_Carousel in Compact, the
  // Dashboard_View in Medium/Expanded (Requirements 3.10, 4.1, 4.2). Both read
  // the selected channel from `selectionStore` and the live telemetry from
  // `monitorStore` — module-level singletons this conditional swap does not
  // remount — so the selection and buffered history survive the band change
  // (Requirements 4.5, 4.7). `DashboardView` takes the mode as a prop rather than
  // resolving it itself, and gets the same Diagnostics_Sheet entry point the
  // carousel uses (Requirement 3.10). The dashboard reuses `.panel`, whose
  // animation the global Reduce_Motion rule already collapses, so no new CSS is
  // needed for Requirement 4.8. The two bottom tabs below are unchanged in every
  // mode: exactly two in Compact (Requirement 4.2) and the same two destinations
  // in the wider modes, mirroring the Mobile_Client shell (task 9.10).
  const sensorsView =
    layout === 'compact' ? (
      <SensorsTab onOpenDiagnostics={openDiagnostics} />
    ) : (
      <DashboardView mode={layout} onOpenDiagnostics={openDiagnostics} />
    );

  return (
    <div className="app">
      <div className="app__body">
        {tab === 'sensors' ? (
          sensorsView
        ) : (
          <SettingsTab onOpenDiagnostics={openDiagnostics} />
        )}
      </div>

      <nav className="tabbar" role="tablist" aria-label="Main sections">
        <button
          type="button"
          role="tab"
          className="tabbar__item"
          aria-selected={tab === 'sensors'}
          onClick={() => setTab('sensors')}
        >
          <span aria-hidden="true" style={{ fontSize: 18 }}>
            💧
          </span>
          Sensors
          {/* The badge keeps an active alarm visible even from the settings tab. */}
          {alarming ? <span className="tabbar__badge" aria-hidden="true" /> : null}
        </button>
        <button
          type="button"
          role="tab"
          className="tabbar__item"
          aria-selected={tab === 'settings'}
          onClick={() => setTab('settings')}
        >
          <span aria-hidden="true" style={{ fontSize: 18 }}>
            ⚙
          </span>
          Settings
        </button>
      </nav>

      {diagnosticsOpen ? (
        <DiagnosticsSheet onClose={() => setDiagnosticsOpen(false)} />
      ) : null}
    </div>
  );
}

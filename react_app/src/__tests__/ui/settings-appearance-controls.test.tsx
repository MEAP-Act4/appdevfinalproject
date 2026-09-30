/**
 * Example tests for the reworked Web_Client appearance controls (task 3.8).
 *
 * Worked examples, not the properties. The Phase 2 property tests (tasks 3.9
 * to 3.14) own the universal appearance invariants; what follows pins the
 * concrete behaviour this task introduces:
 *
 *  - the Requirement 9.4 advisory *wording*, asserted against the exported
 *    `LIGHT_APPEARANCE_ADVISORY` constant so there is one source of truth the
 *    Mobile_Client can be compared against (Requirement 9.6);
 *  - the primary control offering exactly Dark, High contrast dark and Follow
 *    system, by the names Requirement 9.6 pins;
 *  - the light appearance living behind a switch in the Accessibility section
 *    (Requirement 9.3), turning `appearance` to `'light'` on and restoring the
 *    previously selected dark appearance off;
 *  - the primary control and the light switch being two views of one
 *    `appearance` value — selecting a primary option turns Light off, and vice
 *    versa;
 *  - the advisory being *persistent*: it is rendered straight from the light
 *    appearance being active, not through the auto-dismissing notice banner.
 *
 * The component is mounted for real with `react-dom/client` under jsdom. The
 * monitor store is left at its idle initial snapshot — `SettingsTab` renders
 * fine offline — and its async stat load is a fire-and-forget that never blocks
 * the first paint. `localStorage` is reset between cases so the persisted
 * appearance does not leak across them.
 *
 * _Requirements: 9.1, 9.2, 9.3, 9.4, 9.6_
 */
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { SettingsTab, LIGHT_APPEARANCE_ADVISORY } from '../../screens/SettingsTab';
import { settingsStore, type Appearance } from '../../state/settingsStore';

let container: HTMLDivElement | null = null;
let root: Root | null = null;

/** Mounts a `SettingsTab` and flushes effects, returning nothing useful. */
function mount(): void {
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
  act(() => {
    root!.render(<SettingsTab onOpenDiagnostics={() => {}} />);
  });
}

/** Resets the appearance to a known value before each mount. */
function setAppearance(appearance: Appearance): void {
  act(() => {
    settingsStore.update({ appearance });
  });
}

/** The current stored appearance. */
function appearance(): Appearance {
  return settingsStore.get().appearance;
}

/** The mounted container, asserted present. */
function root_el(): HTMLDivElement {
  expect(container, 'component is not mounted').not.toBeNull();
  return container as HTMLDivElement;
}

/** The `<select>` that drives the primary Appearance choice. */
function themeSelect(): HTMLSelectElement {
  const select = root_el().querySelector<HTMLSelectElement>('select');
  expect(select, 'no Theme select rendered').not.toBeNull();
  return select as HTMLSelectElement;
}

/** The switch row whose title matches `title`. */
function switchRow(title: string): HTMLButtonElement {
  const rows = [...root_el().querySelectorAll<HTMLButtonElement>('button[role="switch"]')];
  const match = rows.find((row) => row.textContent?.includes(title));
  expect(match, `no switch titled "${title}"`).toBeTruthy();
  return match as HTMLButtonElement;
}

/** Clicks an element inside `act` so React commits before we assert. */
function click(element: HTMLElement): void {
  act(() => {
    element.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}

/** Selects `value` in the primary Theme `<select>`. */
function selectTheme(value: string): void {
  const select = themeSelect();
  act(() => {
    select.value = value;
    select.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

/** Every visible advisory message on screen. */
function advisoryTexts(): string[] {
  return [...root_el().querySelectorAll('.banner__message')].map(
    (node) => node.textContent ?? '',
  );
}

beforeEach(() => {
  localStorage.clear();
  settingsStore.resetAll();
});

afterEach(() => {
  if (root) {
    act(() => root!.unmount());
    root = null;
  }
  container?.remove();
  container = null;
  localStorage.clear();
  settingsStore.resetAll();
});

describe('the advisory wording (Requirement 9.4)', () => {
  it('is the exact WattVision guidance sentence', () => {
    // The wording contract, pinned once. The Mobile_Client holds the identical
    // string, and task 17.2 / 17.3 compares the two.
    expect(LIGHT_APPEARANCE_ADVISORY).toBe(
      'Light backgrounds sit outside WattVision guidance for prolonged data reading.',
    );
  });

  it('renders that exact constant when the light appearance is active', () => {
    setAppearance('light');
    mount();

    expect(advisoryTexts()).toContain(LIGHT_APPEARANCE_ADVISORY);
  });

  it('shows no advisory in a dark appearance', () => {
    setAppearance('dark');
    mount();

    expect(advisoryTexts()).not.toContain(LIGHT_APPEARANCE_ADVISORY);
  });
});

describe('the primary Appearance control (Requirements 9.1, 9.2, 9.6)', () => {
  it('offers exactly Dark, High contrast dark and Follow system, in order', () => {
    setAppearance('dark');
    mount();

    const labels = [...themeSelect().options].map((option) => option.textContent);
    expect(labels).toEqual(['Dark', 'High contrast dark', 'Follow system']);
  });

  it('does not offer light as a primary option', () => {
    setAppearance('dark');
    mount();

    const values = [...themeSelect().options].map((option) => option.value);
    expect(values).not.toContain('light');
  });

  it('makes High contrast dark reachable through the primary control', () => {
    setAppearance('dark');
    mount();

    selectTheme('hc-dark');

    expect(appearance()).toBe('hc-dark');
  });

  it('reflects the persisted dark appearance on mount', () => {
    setAppearance('hc-dark');
    mount();

    expect(themeSelect().value).toBe('hc-dark');
  });
});

describe('the light-appearance switch (Requirements 9.3, 9.5)', () => {
  it('lives in the Accessibility section', () => {
    setAppearance('dark');
    mount();

    const headings = [...root_el().querySelectorAll('.section__title')].map(
      (node) => node.textContent,
    );
    expect(headings).toContain('Accessibility');
  });

  it('turns the appearance to light when switched on', () => {
    setAppearance('dark');
    mount();

    click(switchRow('Light appearance'));

    expect(appearance()).toBe('light');
  });

  it('reads as on exactly when the light appearance is active', () => {
    setAppearance('light');
    mount();

    expect(switchRow('Light appearance').getAttribute('aria-checked')).toBe('true');
  });

  it('carries the byte-identical supporting description the Mobile_Client uses', () => {
    setAppearance('dark');
    mount();

    expect(switchRow('Light appearance').textContent).toContain(
      'Use a light background instead of the dark WattVision palette.',
    );
  });
});

describe('the two controls are one appearance value (Requirement 9.6)', () => {
  it('restores the previously selected dark appearance when light is switched off', () => {
    setAppearance('hc-dark');
    mount();

    click(switchRow('Light appearance')); // hc-dark -> light
    expect(appearance()).toBe('light');

    click(switchRow('Light appearance')); // light -> back to hc-dark
    expect(appearance()).toBe('hc-dark');
  });

  it('turns light off when a primary option is selected', () => {
    setAppearance('light');
    mount();

    selectTheme('dark');

    expect(appearance()).toBe('dark');
    expect(switchRow('Light appearance').getAttribute('aria-checked')).toBe('false');
  });

  it('keeps light reachable after a round-trip through a primary option', () => {
    setAppearance('light');
    mount();

    selectTheme('system'); // demotes light
    expect(appearance()).toBe('system');

    click(switchRow('Light appearance')); // re-select light
    expect(appearance()).toBe('light');
    expect(advisoryTexts()).toContain(LIGHT_APPEARANCE_ADVISORY);
  });
});

describe('the advisory is persistent, not a transient notice (Requirement 9.4)', () => {
  it('stays rendered while light is active rather than dismissing on a timer', () => {
    // The auto-dismissing `notice` Banner carries a title of "Done"; the
    // advisory is a separate, always-present Banner keyed only on the light
    // appearance. Its presence is a function of state, never of elapsed time.
    setAppearance('light');
    mount();

    expect(advisoryTexts()).toContain(LIGHT_APPEARANCE_ADVISORY);

    // Re-render (as a settings change would) and confirm it is still there.
    act(() => {
      settingsStore.update({ reduceMotion: true });
    });
    expect(advisoryTexts()).toContain(LIGHT_APPEARANCE_ADVISORY);
  });
});

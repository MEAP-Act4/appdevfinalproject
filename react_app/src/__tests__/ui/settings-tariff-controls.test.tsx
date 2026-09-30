/**
 * Example tests for the Web_Client tariff controls (task 11.10).
 *
 * Worked examples, not the properties. The tariff *parse/format* invariants are
 * owned by the pure `core/tariff` suite and its property tests; what follows
 * pins the concrete Settings-tab behaviour this task introduces:
 *
 *  - a rejected entry retains the persisted value, reverts the field on blur,
 *    and shows the accepted-range message (Requirement 5.4);
 *  - an accepted entry commits to the store synchronously (Requirement 5.3);
 *  - the "Show cost equivalence" switch drives `showCostEquivalence`
 *    (Requirement 5.8);
 *  - the locale-override select writes `localeOverride`, with "Follow system"
 *    mapping to the empty-string sentinel (Requirement 12.6);
 *  - the Tariff control is labelled as an editable placeholder, not a billed
 *    figure (Requirement 5.2).
 *
 * The component is mounted for real with `react-dom/client` under jsdom, the
 * monitor store left at its idle snapshot, and `localStorage` reset between
 * cases so a persisted tariff does not leak across them.
 *
 * _Requirements: 5.1, 5.2, 5.3, 5.4, 5.8, 12.5, 12.6_
 */
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import {
  SettingsTab,
  TARIFF_CONTROL_SUBTITLE,
  TARIFF_CONTROL_TITLE,
} from '../../screens/SettingsTab';
import { TARIFF_DEFAULT, TARIFF_RANGE_MESSAGE, formatForEditing } from '../../core/tariff';
import { settingsStore } from '../../state/settingsStore';

let container: HTMLDivElement | null = null;
let root: Root | null = null;

function mount(): void {
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
  act(() => {
    root!.render(<SettingsTab onOpenDiagnostics={() => {}} />);
  });
}

function root_el(): HTMLDivElement {
  expect(container, 'component is not mounted').not.toBeNull();
  return container as HTMLDivElement;
}

/** The tariff text input, found by its accessible label. */
function tariffInput(): HTMLInputElement {
  const label = [...root_el().querySelectorAll('label')].find(
    (node) => node.textContent === TARIFF_CONTROL_TITLE,
  );
  expect(label, 'no Water tariff label rendered').toBeTruthy();
  const input = root_el().querySelector<HTMLInputElement>(`#${label!.getAttribute('for')!}`);
  expect(input, 'no Water tariff input rendered').not.toBeNull();
  return input as HTMLInputElement;
}

/**
 * Sets a React-controlled input's value through the native value setter so
 * React's input tracker sees the change, then fires the events React listens
 * for. React 19 delegates `blur` through the bubbling `focusout` event, so that
 * — not a non-bubbling `blur` — is what triggers the `onBlur` handler.
 */
function setInputValue(input: HTMLInputElement, text: string): void {
  const setter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype,
    'value',
  )?.set;
  setter?.call(input, text);
  input.dispatchEvent(new Event('input', { bubbles: true }));
}

/** Types `text` into the tariff field and commits it via blur. */
function typeAndBlur(text: string): void {
  const input = tariffInput();
  act(() => {
    setInputValue(input, text);
  });
  act(() => {
    input.dispatchEvent(new FocusEvent('focusout', { bubbles: true }));
  });
}

/** The switch row whose title matches `title`. */
function switchRow(title: string): HTMLButtonElement {
  const rows = [...root_el().querySelectorAll<HTMLButtonElement>('button[role="switch"]')];
  const match = rows.find((row) => row.textContent?.includes(title));
  expect(match, `no switch titled "${title}"`).toBeTruthy();
  return match as HTMLButtonElement;
}

function click(element: HTMLElement): void {
  act(() => {
    element.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}

/** The `<select>` whose label's title matches `title`. */
function selectRow(title: string): HTMLSelectElement {
  const label = [...root_el().querySelectorAll('label')].find((node) =>
    [...node.querySelectorAll('.row__title')].some((child) => child.textContent === title),
  );
  expect(label, `no select labelled "${title}"`).toBeTruthy();
  const select = root_el().querySelector<HTMLSelectElement>(`#${label!.getAttribute('for')!}`);
  expect(select, `no select for "${title}"`).not.toBeNull();
  return select as HTMLSelectElement;
}

function selectValue(select: HTMLSelectElement, value: string): void {
  act(() => {
    select.value = value;
    select.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

/** Every visible alert message on screen. */
function alertTexts(): string[] {
  return [...root_el().querySelectorAll('[role="alert"]')].map((node) => node.textContent ?? '');
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

describe('the Tariff control label (Requirement 5.2)', () => {
  it('describes the value as an editable placeholder, not a billed figure', () => {
    mount();

    // The subtitle is the wording contract, pinned once against the exported
    // constant so the Mobile_Client (task 11.9) can be compared to it. It calls
    // the value an editable placeholder and explicitly disclaims it as a billed
    // figure (Requirement 5.2).
    expect(TARIFF_CONTROL_SUBTITLE).toContain('placeholder');
    expect(TARIFF_CONTROL_SUBTITLE).toContain('not a billed figure');
    expect(root_el().textContent).toContain(TARIFF_CONTROL_SUBTITLE);
  });

  it('opens on the editing form of the default placeholder', () => {
    mount();
    expect(tariffInput().value).toBe(formatForEditing(TARIFF_DEFAULT));
  });
});

describe('a rejected entry (Requirement 5.4)', () => {
  it('retains the persisted value, reverts the field, and shows the range message', () => {
    // Seed a valid persisted tariff so we can prove it survives a rejection.
    act(() => settingsStore.setTariff(7.5));
    mount();

    typeAndBlur('9999'); // above the 1000 maximum → rejected

    // Persisted value untouched.
    expect(settingsStore.get().tariffBsPerCubicMetre).toBe(7.5);
    // Field reverted to the persisted value's editing form.
    expect(tariffInput().value).toBe(formatForEditing(7.5));
    // Accepted-range message shown.
    expect(alertTexts()).toContain(TARIFF_RANGE_MESSAGE);
  });

  it('rejects non-numeric input the same way', () => {
    act(() => settingsStore.setTariff(3.25));
    mount();

    typeAndBlur('abc');

    expect(settingsStore.get().tariffBsPerCubicMetre).toBe(3.25);
    expect(tariffInput().value).toBe(formatForEditing(3.25));
    expect(alertTexts()).toContain(TARIFF_RANGE_MESSAGE);
  });
});

describe('an accepted entry (Requirement 5.3)', () => {
  it('commits the parsed value to the store and clears any message', () => {
    mount();

    typeAndBlur('12.5');

    expect(settingsStore.get().tariffBsPerCubicMetre).toBe(12.5);
    expect(settingsStore.get().tariffConfiguredByUser).toBe(true);
    expect(alertTexts()).not.toContain(TARIFF_RANGE_MESSAGE);
  });

  it('accepts a comma decimal separator (Requirement 12.5)', () => {
    mount();

    typeAndBlur('8,25');

    expect(settingsStore.get().tariffBsPerCubicMetre).toBe(8.25);
  });
});

describe('the cost-equivalence switch (Requirement 5.8)', () => {
  it('drives showCostEquivalence', () => {
    mount();
    expect(settingsStore.get().showCostEquivalence).toBe(true);

    click(switchRow('Show cost equivalence'));

    expect(settingsStore.get().showCostEquivalence).toBe(false);
  });
});

describe('the locale override (Requirement 12.6)', () => {
  it('writes a supported locale override', () => {
    mount();

    selectValue(selectRow('Number & currency format'), 'es');

    expect(settingsStore.get().localeOverride).toBe('es');
  });

  it('maps "Follow system" to the empty-string sentinel', () => {
    act(() => settingsStore.setLocaleOverride('es'));
    mount();

    selectValue(selectRow('Number & currency format'), '');

    expect(settingsStore.get().localeOverride).toBe('');
  });
});

/**
 * Example tests for the Bs_Equivalence rendered beside every Web_Client volume
 * figure (task 11.12).
 *
 * The Cost_Formatter's formula, prefix, locale body and null/`--` contract are
 * owned by the pure `core/cost` suite and Properties 10–12; this file pins the
 * concrete component wiring this task introduces:
 *
 *  - a Bs_Equivalence is rendered beside every cumulative volume total in
 *    `TotalsCard` — "Since reset", "Last 24 h", "Last 7 d" (Requirement 6.1);
 *  - a Bs_Equivalence is rendered beside the "Total used" window volume in
 *    `WindowDetail` (Requirement 6.2);
 *  - the figure is derived from the CANONICAL LITRES, not the displayed volume
 *    number, so a change of volume unit leaves it unchanged (Requirement 6.7);
 *  - it is rendered in the secondary text colour at the body type size next to
 *    the primary value (Requirement 6.5);
 *  - disabling `showCostEquivalence` suppresses it and nothing else
 *    (Requirement 5.8 / 6.1);
 *  - an unconfigured (default) Tariff shows the "default tariff" hint, and a
 *    user-configured Tariff does not (Requirement 6.8);
 *  - flow figures (peak, while-running, per-window averages) are NOT annotated
 *    (Requirement 6.7 / 13.8 — cost is derived from litres only).
 *
 * Components are mounted for real under jsdom. `localStorage` and both stores are
 * reset between cases so a persisted setting cannot leak across them.
 *
 * _Requirements: 6.1, 6.2, 6.5, 6.7, 6.8, 6.9_
 */
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { TotalsCard } from '../../components/channel/cards';
import { WindowDetail } from '../../components/channel/Averages';
import { createCostFormatter } from '../../core/cost';
import { createFormatter } from '../../core/units';
import { AVERAGE_WINDOWS, type SensorAggregates, type WindowStats } from '../../data/db';
import { settingsStore } from '../../state/settingsStore';

let container: HTMLDivElement | null = null;
let root: Root | null = null;

function root_el(): HTMLDivElement {
  expect(container, 'component is not mounted').not.toBeNull();
  return container as HTMLDivElement;
}

/** The rendered Bs_Equivalence figures, in document order. */
function costTexts(): string[] {
  return [...root_el().querySelectorAll('.cost-equivalence')].map(
    (node) => node.textContent ?? '',
  );
}

/** Builds a window-stats fixture with an arbitrary volume and flow figures. */
function windowStats(totalLitres: number, index = 0): WindowStats {
  return {
    window: AVERAGE_WINDOWS[index]!,
    averageLpm: 4.2,
    peakLpm: 9.9,
    totalLitres,
    sampleCount: 100,
    coverage: 1,
    activeFraction: 0.5,
  };
}

/** A per-sensor aggregate with distinct day/threeDay/week volumes. */
function aggregates(day: number, week: number): SensorAggregates {
  return {
    sensorIndex: 0,
    day: windowStats(day, 0),
    threeDay: windowStats((day + week) / 2, 1),
    week: windowStats(week, 2),
  };
}

function mountWindowDetail(litres: number): void {
  const settings = settingsStore.get();
  const formatter = createFormatter(settings.flowUnit, settings.volumeUnit);
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
  act(() => {
    root!.render(<WindowDetail stats={windowStats(litres)} formatter={formatter} />);
  });
}

function mountTotals(day: number, week: number): void {
  const settings = settingsStore.get();
  const formatter = createFormatter(settings.flowUnit, settings.volumeUnit);
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
  act(() => {
    root!.render(
      <TotalsCard sensorIndex={0} aggregates={aggregates(day, week)} formatter={formatter} />,
    );
  });
}

/** The Bs_Equivalence the formatter produces for `litres` under `settings`. */
function expectedBs(litres: number): string {
  const settings = settingsStore.get();
  const text = createCostFormatter({
    tariffBsPerCubicMetre: settings.tariffBsPerCubicMetre,
    // jsdom's navigator.language resolves to `en`; the pure formula suite owns
    // the locale-separator behaviour, so pinning against the formatter here
    // keeps this file agnostic to the runtime locale.
    locale: 'en',
    enabled: settings.showCostEquivalence,
    isDefaultTariff: !settings.tariffConfiguredByUser,
  }).format(litres);
  expect(text, 'formatter returned null for an enabled figure').not.toBeNull();
  return text as string;
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

describe('Bs_Equivalence beside the window volume (Requirement 6.2)', () => {
  it('renders one Bs figure beside the "Total used" volume, and none for the flow figures', () => {
    mountWindowDetail(3600); // 3.6 m³

    const costs = costTexts();
    // Exactly one cost figure: the volume tile. Peak and While-running are flow.
    expect(costs).toHaveLength(1);
    expect(costs[0]).toContain(expectedBs(3600).replace(' default tariff', ''));
    expect(costs[0]).toContain('Bs.');
  });

  it('renders the figure in the secondary colour at body size', () => {
    mountWindowDetail(1000);
    const el = root_el().querySelector<HTMLElement>('.cost-equivalence');
    expect(el).not.toBeNull();
    expect(el!.style.color).toBe('var(--text-secondary)');
    expect(el!.style.fontSize).toBe('var(--size-body)');
  });
});

describe('Bs_Equivalence beside every cumulative total (Requirement 6.1)', () => {
  it('renders a Bs figure for each of the three volume tiles', () => {
    // deviceTotal comes from the idle monitor snapshot → 0 L → Bs. 0.00.
    mountTotals(2000, 7000);

    const costs = costTexts();
    expect(costs).toHaveLength(3);
    // "Since reset" (device total, 0 on the idle store), "Last 24 h", "Last 7 d".
    expect(costs[0]).toContain(expectedBs(0).replace(' default tariff', ''));
    expect(costs[1]).toContain(expectedBs(2000).replace(' default tariff', ''));
    expect(costs[2]).toContain(expectedBs(7000).replace(' default tariff', ''));
  });
});

describe('display-unit invariance (Requirement 6.7)', () => {
  it('produces the same Bs figure for the same litres regardless of volume unit', () => {
    // Litres unit.
    settingsStore.update({ volumeUnit: 'l', followFlowUnitForVolume: false });
    mountWindowDetail(3600);
    const litresCost = costTexts()[0];

    act(() => root!.unmount());
    container!.remove();

    // Gallons unit — the displayed volume number changes, the Bs must not.
    settingsStore.update({ volumeUnit: 'usgal', followFlowUnitForVolume: false });
    mountWindowDetail(3600);
    const gallonsCost = costTexts()[0];

    expect(gallonsCost).toBe(litresCost);
  });
});

describe('the enable switch (Requirement 5.8 / 6.1)', () => {
  it('renders no Bs figure when cost display is disabled', () => {
    settingsStore.setShowCostEquivalence(false);
    mountWindowDetail(3600);

    expect(costTexts()).toHaveLength(0);
    // The volume figure itself is still present.
    expect(root_el().textContent).toContain('Total used');
  });
});

describe('the default-tariff hint (Requirement 6.8)', () => {
  it('shows the "default tariff" hint while the Tariff is unconfigured', () => {
    // Fresh state → tariffConfiguredByUser is false.
    expect(settingsStore.get().tariffConfiguredByUser).toBe(false);
    mountWindowDetail(3600);

    expect(costTexts()[0]).toContain('default tariff');
  });

  it('omits the hint once the user configures a Tariff', () => {
    settingsStore.setTariff(7.5);
    expect(settingsStore.get().tariffConfiguredByUser).toBe(true);
    mountWindowDetail(3600);

    const cost = costTexts()[0];
    expect(cost).toContain('Bs.');
    expect(cost).not.toContain('default tariff');
  });
});

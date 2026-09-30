/**
 * Example tests for the Web_Client `DashboardView` (task 9.9).
 *
 * The heavy cross-client composition guarantee is Property 29 (task 9.14),
 * which reads `test_fixtures/layout/compositions.json` and asserts this view's
 * cells equal it exactly. These are the narrower structural examples task 9.9
 * owns:
 *
 *  - the ordered cell list built by `dashboardCells` matches the canonical
 *    Medium and Expanded compositions — roles in order, with the right spans;
 *  - Compact builds no grid, because the Dashboard_View is never mounted there;
 *  - the mounted view lays the cells out on `.grid12` with the matching
 *    `.span-*` classes, three KPI cards first in the fixed channel order;
 *  - the `.chip[aria-pressed]` channel selectors are a multi-select — all three
 *    start pressed and toggle independently (Requirement 3.9);
 *  - the Diagnostics_Sheet entry point fires the handler (Requirement 3.10).
 *
 * The monitor store is left at its idle initial snapshot; the KPI cards and the
 * chart render regardless (null telemetry reads as zero flow), which is all the
 * structural assertions need.
 *
 * _Requirements: 3.1, 3.2, 3.3, 3.4, 3.9, 3.10_
 */
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it } from 'vitest';

import { DashboardView, dashboardCells } from '../../screens/DashboardView';
import type { LayoutMode } from '../../core/layout';
import { settingsStore } from '../../state/settingsStore';

let container: HTMLDivElement | null = null;
let root: Root | null = null;

function mount(mode: LayoutMode, onOpenDiagnostics: () => void = () => {}): void {
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
  act(() => {
    root!.render(<DashboardView mode={mode} onOpenDiagnostics={onOpenDiagnostics} />);
  });
}

afterEach(() => {
  if (root) {
    act(() => root!.unmount());
    root = null;
  }
  container?.remove();
  container = null;
  settingsStore.resetAll();
});

describe('dashboardCells composition (task 9.9)', () => {
  it('builds the Medium composition: KPI 4·4·4, chart 12, alerts 12', () => {
    expect(dashboardCells('medium')).toEqual([
      { role: 'kpi-main-inlet', span: 4 },
      { role: 'kpi-outlet-a', span: 4 },
      { role: 'kpi-outlet-b', span: 4 },
      { role: 'main-chart', span: 12 },
      { role: 'alerts-panel', span: 12 },
    ]);
  });

  it('builds the Expanded composition: KPI 4·4·4, chart 8, alerts 4', () => {
    expect(dashboardCells('expanded')).toEqual([
      { role: 'kpi-main-inlet', span: 4 },
      { role: 'kpi-outlet-a', span: 4 },
      { role: 'kpi-outlet-b', span: 4 },
      { role: 'main-chart', span: 8 },
      { role: 'alerts-panel', span: 4 },
    ]);
  });

  it('builds no grid in Compact — the carousel is shown there instead', () => {
    expect(dashboardCells('compact')).toEqual([]);
  });

  it('keeps every run summing to exactly 12 (Grid_12, Requirement 2.2)', () => {
    for (const mode of ['medium', 'expanded'] as const) {
      const spans = dashboardCells(mode).map((c) => c.span);
      // KPI run is the first three cells; the chart+alerts run is the rest.
      const kpiRun = spans.slice(0, 3).reduce((a, b) => a + b, 0);
      const tailRun = spans.slice(3).reduce((a, b) => a + b, 0);
      expect(kpiRun).toBe(12);
      // Medium wraps chart(12) then alerts(12): two runs of 12. Expanded is
      // one run of 8+4. Either way each run is 12.
      if (mode === 'expanded') expect(tailRun).toBe(12);
      else expect(tailRun).toBe(24); // 12 + 12, two full-width runs
    }
  });
});

describe('DashboardView rendering (task 9.9)', () => {
  it('lays the Expanded cells onto .grid12 with matching span classes', () => {
    mount('expanded');
    const grid = container!.querySelector('.grid12');
    expect(grid, 'no .grid12 rendered').not.toBeNull();
    const cellClasses = Array.from(grid!.children).map(
      (child) => (child as HTMLElement).className,
    );
    expect(cellClasses).toEqual([
      'span-4',
      'span-4',
      'span-4',
      'span-8',
      'span-4',
    ]);
  });

  it('lays the Medium cells onto .grid12 with matching span classes', () => {
    mount('medium');
    const grid = container!.querySelector('.grid12')!;
    const cellClasses = Array.from(grid.children).map(
      (child) => (child as HTMLElement).className,
    );
    expect(cellClasses).toEqual([
      'span-4',
      'span-4',
      'span-4',
      'span-12',
      'span-12',
    ]);
  });

  it('reuses the .panel animation class so Reduce_Motion needs no new CSS', () => {
    mount('expanded');
    expect(container!.querySelector('.panel')).not.toBeNull();
  });
});

describe('DashboardView channel selectors (Requirement 3.9)', () => {
  it('renders three channel chips, all pressed by default', () => {
    mount('expanded');
    const chips = container!.querySelectorAll<HTMLButtonElement>('.chip');
    expect(chips).toHaveLength(3);
    for (const chip of chips) {
      expect(chip.getAttribute('aria-pressed')).toBe('true');
    }
  });

  it('toggles a single channel independently, keeping the others selected', () => {
    mount('expanded');
    const chips = () =>
      Array.from(container!.querySelectorAll<HTMLButtonElement>('.chip'));

    act(() => {
      chips()[1]!.click();
    });

    const pressed = chips().map((c) => c.getAttribute('aria-pressed'));
    expect(pressed).toEqual(['true', 'false', 'true']);

    // A second channel can be off at the same time — a true multi-select.
    act(() => {
      chips()[0]!.click();
    });
    expect(chips().map((c) => c.getAttribute('aria-pressed'))).toEqual([
      'false',
      'false',
      'true',
    ]);
  });
});

describe('DashboardView Diagnostics_Sheet entry point (Requirement 3.10)', () => {
  it('invokes the handler from the diagnostics control', () => {
    let opened = 0;
    mount('expanded', () => {
      opened += 1;
    });
    const button = container!.querySelector<HTMLButtonElement>(
      'button[aria-label="Diagnostics"]',
    );
    expect(button, 'no diagnostics entry point rendered').not.toBeNull();
    act(() => button!.click());
    expect(opened).toBe(1);
  });
});

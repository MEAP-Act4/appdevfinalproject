/**
 * Example tests for the Web_Client `DashboardView` Main_Chart channel selection
 * — the exhaustive eight-subset sweep (task 9.15).
 *
 * `dashboard-view.test.tsx` (task 9.9) already pins that the three
 * `.chip[aria-pressed]` selectors start pressed and toggle independently. This
 * file complements it with the case task 9.15 owns and 9.9 left alone: the
 * **exhaustive** sweep of all `2^3 = 8` subsets of the three channels, asserting
 * that for each subset the multi-series `Sparkline` receives *exactly* the
 * selected channels' series — the right count, in canonical channel order —
 * including the all-off subset, where the impl keeps one channel plotted rather
 * than blanking the chart. Eight cases is the whole input space, so this is
 * stronger than sampling. It is the Web twin of the Flutter
 * `dashboard_chart_selection_test.dart` sweep.
 *
 * **How a plotted series is identified.** `monitorStore` is mocked so each
 * channel carries a live series of a *distinct length* (channel 0 → 5 points,
 * channel 1 → 4, channel 2 → 3). The `Sparkline` draws one `path.sparkline__line`
 * per series with a cubic segment per gap, so the number of `C` commands in a
 * line path is `points - 1` — which recovers the channel that produced it. The
 * sequence of drawn line lengths therefore proves both *which* channels are
 * plotted and *in what order*, not merely how many. The chips are pressed by
 * index to reach each subset.
 *
 * **Scoping to the Main_Chart.** The three dense KPI `SensorPage` cells each
 * render their *own* single-series `Sparkline` off the same mocked
 * `liveSeries`, so a container-wide `path.sparkline__line` query would also
 * catch those three KPI lines (lengths 5/4/3) and mask the Main_Chart's own
 * series. The count is therefore taken only from within the Main_Chart's
 * `Sparkline`, located by the `role="group"` "Channels plotted" chip row that
 * lives in the same card — the one element unique to the Main_Chart.
 *
 * _Requirements: 3.9_
 */
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { SENSOR_COUNT } from '../../core/protocol';

// Distinct-length series per channel, so a drawn line path can be traced back
// to the channel that produced it by its point count. Declared through
// `vi.hoisted` so it is initialised before the hoisted `vi.mock` factory runs.
const { SERIES_BY_CHANNEL } = vi.hoisted(() => ({
  SERIES_BY_CHANNEL: [
    [1, 2, 3, 4, 5], // channel 0 → 5 points
    [5, 4, 3, 2], //    channel 1 → 4 points
    [2, 2, 2], //       channel 2 → 3 points
  ] as number[][],
}));

// Mock the monitor store so the chart has non-empty, per-channel-distinct
// series to draw. The base snapshot is the real store's own initial snapshot
// (so the KPI cells' reads — aggregates, status, config, latest — stay valid),
// with only the link state and the live series overridden. The real
// `monitorStore` methods (e.g. `zeroTotals`) are kept via `importActual`.
vi.mock('../../state/monitorStore', async () => {
  const actual =
    await vi.importActual<typeof import('../../state/monitorStore')>(
      '../../state/monitorStore',
    );
  const snapshot = {
    ...actual.monitorStore.getSnapshot(),
    linkState: 'ready' as const,
    stale: false,
    usingSimulator: false,
    liveSeries: SERIES_BY_CHANNEL,
  };
  return {
    ...actual,
    useMonitor: () => snapshot,
  };
});

// Imported after the mock is registered.
const { DashboardView } = await import('../../screens/DashboardView');
const { settingsStore } = await import('../../state/settingsStore');

let container: HTMLDivElement | null = null;
let root: Root | null = null;

function mount(): void {
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
  act(() => {
    root!.render(<DashboardView mode="expanded" onOpenDiagnostics={() => {}} />);
  });
}

/**
 * The Main_Chart card — the element that owns the channel selectors and the
 * multi-series `Sparkline`. Found by the "Channels plotted" chip row, which is
 * unique to the Main_Chart (the KPI `SensorPage` cells render no such group),
 * then walked up to the enclosing `.card`. Scoping every query through this
 * node keeps the three KPI single-series sparklines — which draw off the same
 * mocked `liveSeries` — out of the counts.
 */
function mainChart(): HTMLElement {
  const group = container!.querySelector<HTMLElement>(
    '[role="group"][aria-label="Channels plotted"]',
  );
  if (!group) throw new Error('Main_Chart channel selector group not found');
  return group.closest<HTMLElement>('.card') ?? group.parentElement!;
}

/** The channel chips, in document (canonical channel) order. */
function chips(): HTMLButtonElement[] {
  return Array.from(mainChart().querySelectorAll<HTMLButtonElement>('.chip'));
}

/** Clicks the chip for [channel] and flushes the update. */
function toggle(channel: number): void {
  act(() => chips()[channel]!.click());
}

/**
 * The point-count of each drawn `.sparkline__line`, in draw order. A line path
 * is `M …` followed by one `C …` per gap, so `points = 1 + (# of C commands)`.
 */
function drawnSeriesLengths(): number[] {
  const lines = Array.from(
    mainChart().querySelectorAll<SVGPathElement>('path.sparkline__line'),
  );
  return lines.map((line) => {
    const d = line.getAttribute('d') ?? '';
    const cubics = (d.match(/C/g) ?? []).length;
    return cubics + 1;
  });
}

/** The expected drawn-series lengths for a set of selected channels, in order. */
function expectedLengths(selected: readonly number[]): number[] {
  return selected.map((i) => SERIES_BY_CHANNEL[i]!.length);
}

/** Which chips report pressed, as booleans in channel order. */
function pressed(): boolean[] {
  return chips().map((c) => c.getAttribute('aria-pressed') === 'true');
}

beforeEach(() => {
  mount();
});

afterEach(() => {
  if (root) {
    act(() => root!.unmount());
    root = null;
  }
  container?.remove();
  container = null;
  settingsStore.resetAll();
});

describe('Main_Chart channel selection is an exhaustive 8-subset multi-select (Requirement 3.9)', () => {
  it('renders three chips and plots all three series by default (the all-on subset)', () => {
    expect(chips()).toHaveLength(SENSOR_COUNT);
    expect(pressed()).toEqual([true, true, true]);
    expect(drawnSeriesLengths()).toEqual(expectedLengths([0, 1, 2]));
  });

  it('plots exactly the selected channels for each of the seven non-empty subsets', () => {
    // Walk a path that visits every non-empty subset of {0,1,2} exactly once,
    // toggling one chip per step and checking the drawn series after each.
    // Start state: {0,1,2}. Each entry is the channel toggled and the subset it
    // produces.
    const steps: readonly (readonly [number, number[]])[] = [
      [0, [1, 2]], //     drop 0  → {1,2}
      [1, [2]], //        drop 1  → {2}
      [0, [0, 2]], //     add 0   → {0,2}
      [2, [0]], //        drop 2  → {0}
      [1, [0, 1]], //     add 1   → {0,1}
      [0, [1]], //        drop 0  → {1}
      [2, [1, 2]], //     add 2   → {1,2}  (already seen, harmless bridge)
      [1, [2]], //        drop 1  → {2}    (bridge)
      [0, [0, 2]], //     add 0   → {0,2}  (bridge)
      [1, [0, 1, 2]], //  add 1   → {0,1,2} back to all-on
    ];

    // Confirm the start state first.
    expect(drawnSeriesLengths()).toEqual(expectedLengths([0, 1, 2]));

    for (const [channel, subset] of steps) {
      toggle(channel);
      expect(pressed().filter(Boolean).length).toBe(subset.length);
      expect(drawnSeriesLengths()).toEqual(expectedLengths(subset));
    }
  });

  it('the empty subset draws no series and shows the "no channels" placeholder', () => {
    // Drop all three channels — the genuine eighth subset. The Web_Client does
    // not force one channel to stay on (unlike the Flutter twin's guard); it
    // instead renders a placeholder and plots nothing, which is still "exactly
    // the selected channels": none.
    toggle(0);
    toggle(1);
    toggle(2);

    expect(pressed()).toEqual([false, false, false]);
    expect(drawnSeriesLengths()).toEqual([]);
    expect(mainChart().querySelector('path.sparkline__line')).toBeNull();
    expect(mainChart().textContent).toContain('No channels selected');
  });
});

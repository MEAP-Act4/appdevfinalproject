/**
 * Example test for the `dense` flag on the extracted `SensorPage` (task 7.3).
 *
 * Task 7.3 is a pure refactor: the seven channel components moved out of
 * `screens/SensorsTab.tsx` into `components/channel/` unchanged, and `SensorPage`
 * gained one flag mirroring the Flutter `ChannelKpiCard.dense` from task 7.1.
 * The heavier structural carousel/dashboard agreement is Property 7 (task 7.7)
 * and the dashboard composition tests are task 9.15; this file only pins the
 * one behaviour the flag introduces.
 *
 * What is asserted:
 *
 *  - the default rendering — the shape the Sensor_Carousel constructs, with no
 *    `dense` prop — sizes the live-flow KPI at the carousel hero size, so the
 *    extraction changes nothing the phone shows;
 *  - `dense` shrinks that same KPI to the WattVision §4 dashboard size;
 *  - the two sizes are exactly `HERO_KPI_SIZE` and `DENSE_KPI_SIZE`, read from
 *    the component rather than restated here, so the flag cannot drift from its
 *    documented contract.
 *
 * The hero KPI is the first `.metric__value` in the page — `SensorPage` renders
 * it before the averages tiles. The monitor store is left at its idle initial
 * snapshot: the KPI renders regardless (a null telemetry reads as 0 flow), which
 * is all the size assertion needs.
 *
 * _Requirements: 3.5, 4.6, 13.1_
 */
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it } from 'vitest';

import {
  SensorPage,
  HERO_KPI_SIZE,
  DENSE_KPI_SIZE,
} from '../../components/channel';
import { createFormatter } from '../../core/units';
import { settingsStore } from '../../state/settingsStore';

let container: HTMLDivElement | null = null;
let root: Root | null = null;

/** Mounts `SensorPage` for the inlet channel, with or without `dense`. */
function mount(dense?: boolean): void {
  const settings = settingsStore.get();
  const formatter = createFormatter(settings.flowUnit, settings.volumeUnit);
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
  act(() => {
    root!.render(
      dense === undefined ? (
        <SensorPage sensorIndex={0} formatter={formatter} />
      ) : (
        <SensorPage sensorIndex={0} formatter={formatter} dense={dense} />
      ),
    );
  });
}

/** The pixel `fontSize` of the hero KPI — the first metric value on the page. */
function heroKpiSize(): string {
  const value = container?.querySelector<HTMLElement>('.metric__value');
  expect(value, 'no KPI value rendered').not.toBeNull();
  return (value as HTMLElement).style.fontSize;
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

describe('SensorPage dense flag (task 7.3)', () => {
  it('renders the carousel hero size by default, leaving the phone unchanged', () => {
    mount();
    expect(heroKpiSize()).toBe(`${HERO_KPI_SIZE}px`);
  });

  it('renders the carousel hero size when dense is explicitly off', () => {
    mount(false);
    expect(heroKpiSize()).toBe(`${HERO_KPI_SIZE}px`);
  });

  it('shrinks the KPI to the WattVision dashboard size when dense', () => {
    mount(true);
    expect(heroKpiSize()).toBe(`${DENSE_KPI_SIZE}px`);
  });

  it('pins the two sizes to their documented contract', () => {
    // The dashboard KPI is WattVision §4's 32px; the hero is deliberately
    // larger. A regression in either constant fails here rather than silently
    // changing every channel.
    expect(DENSE_KPI_SIZE).toBe(32);
    expect(HERO_KPI_SIZE).toBeGreaterThan(DENSE_KPI_SIZE);
  });
});

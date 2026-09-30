/**
 * Worked examples for the shared per-channel projection (task 7.6).
 *
 * These are examples, not the property — task 7.7 writes Property 7 (the
 * carousel and dashboard agree through this one `ChannelView`). What follows
 * builds a synthetic monitor snapshot plus settings and pins that, for a chosen
 * index, `ChannelView.of` returns the expected live flow, live series, window
 * stats, Status, and formatted strings — the same values `SensorPage` derives
 * inline today, so the projection is a faithful single source.
 *
 * _Requirements: 4.6, 13.2_
 */
import { describe, expect, it } from 'vitest';

import { ChannelView, channelViewOf } from '../../core/channelView';
import { createFormatter } from '../../core/units';
import type { LeakStatus, Telemetry } from '../../core/protocol';
import {
  AVERAGE_WINDOWS,
  emptySnapshot,
  type AggregateSnapshot,
  type SensorAggregates,
  type WindowStats,
} from '../../data/db';
import { DEFAULT_SETTINGS, type AppSettings } from '../../state/settingsStore';
import type { MonitorSnapshot } from '../../state/monitorStore';

function telemetry(flowLpm: [number, number, number], status: LeakStatus): Telemetry {
  return {
    kind: 'telemetry',
    seq: 1,
    uptimeMs: 1000,
    flowLpm,
    volumeL: [100, 20, 30],
    balanceLpm: flowLpm[0] - (flowLpm[1] + flowLpm[2]),
    expectedLpm: 0,
    thresholdLpm: 0.5,
    status,
    breachStreak: 0,
    faultStreak: 0,
    receivedAt: 1_700_000_000_000,
  };
}

function windowStats(index: 0 | 1 | 2, averageLpm: number): WindowStats {
  return {
    window: AVERAGE_WINDOWS[index]!,
    averageLpm,
    peakLpm: averageLpm * 2,
    totalLitres: averageLpm * 10,
    sampleCount: 500,
    coverage: 0.8,
    activeFraction: 0.5,
  };
}

/** A snapshot whose channel 1 (Outlet A) carries known, distinct values. */
function snapshot(): MonitorSnapshot {
  const base = emptySnapshot();
  const aggregates: AggregateSnapshot = {
    ...base,
    perSensor: base.perSensor.map((s): SensorAggregates => {
      if (s.sensorIndex !== 1) return s;
      return {
        sensorIndex: 1,
        day: windowStats(0, 3.5),
        threeDay: windowStats(1, 2.25),
        week: windowStats(2, 1.1),
      };
    }),
  };

  return {
    ...initialMonitorShape(),
    latest: telemetry([12, 4.2, 0], 'WATCH'),
    status: 'WATCH',
    liveSeries: [
      [10, 11, 12],
      [4.0, 4.1, 4.2],
      [0, 0, 0],
    ],
    aggregates,
  };
}

/** The non-channel fields of a snapshot, filled with inert defaults. */
function initialMonitorShape(): MonitorSnapshot {
  return {
    linkState: 'ready',
    usingSimulator: true,
    lastError: null,
    discovered: [],
    connectedDevice: null,
    transportKind: 'sim',
    latest: null,
    status: 'UNKNOWN',
    config: null,
    baseline: [],
    calibration: null,
    liveSeries: [[], [], []],
    aggregates: emptySnapshot(),
    rawLog: [],
    stale: false,
    secondsSinceLastSample: null,
    alarmAcknowledged: false,
    historyOnly: false,
    unlocked: true,
  };
}

const settings: AppSettings = {
  ...DEFAULT_SETTINGS,
  sensorNames: ['Main Inlet', 'Kitchen', 'Outlet B'],
  flowUnit: 'lpm',
  volumeUnit: 'l',
};

describe('ChannelView.of', () => {
  it('projects the live/series/status/aggregate fields for a channel', () => {
    const view = ChannelView.of(snapshot(), settings, 1);

    expect(view.sensorIndex).toBe(1);
    expect(view.name).toBe('Kitchen');
    // live = telemetry.flowLpm[1]
    expect(view.live).toBe(4.2);
    // series = monitor.liveSeries[1]
    expect(view.series).toEqual([4.0, 4.1, 4.2]);
    // status = monitor.status
    expect(view.status).toBe('WATCH');
    // windows = day, 3-day, week in order, from perSensor[1]
    expect(view.windows.map((w) => w.window.id)).toEqual(['day', 'threeDay', 'week']);
    expect(view.windows.map((w) => w.averageLpm)).toEqual([3.5, 2.25, 1.1]);
  });

  it('formats every string through the Formatter', () => {
    const formatter = createFormatter('lpm', 'l');
    const view = ChannelView.of(snapshot(), settings, 1);

    expect(view.text.liveReading).toBe(formatter.flowText(4.2));
    expect(view.text.liveReading).toBe('4.20 L/min');
    expect(view.text.status).toBe('WATCH');
    expect(view.text.averages).toEqual([
      formatter.flowText(3.5),
      formatter.flowText(2.25),
      formatter.flowText(1.1),
    ]);
    expect(view.text.averages).toEqual(['3.50 L/min', '2.25 L/min', '1.10 L/min']);
    // Cost_Formatter arrives in task 11.12; the slot is null until then.
    expect(view.text.bsEquivalence).toBeNull();
  });

  it('respects the flow unit when formatting', () => {
    const lph: AppSettings = { ...settings, flowUnit: 'lph', volumeUnit: 'l' };
    const view = ChannelView.of(snapshot(), lph, 1);
    // 4.2 L/min -> 252 L/h at 1 decimal.
    expect(view.text.liveReading).toBe('252.0 L/h');
    expect(view.text.averages[0]).toBe('210.0 L/h');
  });

  it('falls back to zero live flow and empty series when idle', () => {
    const idle: MonitorSnapshot = { ...initialMonitorShape() };
    const view = channelViewOf(idle, settings, 2);

    expect(view.live).toBe(0);
    expect(view.series).toEqual([]);
    expect(view.status).toBe('UNKNOWN');
    // An empty snapshot still carries three zeroed windows.
    expect(view.windows.map((w) => w.window.id)).toEqual(['day', 'threeDay', 'week']);
    expect(view.text.liveReading).toBe('0.00 L/min');
    expect(view.text.averages).toEqual(['0.00 L/min', '0.00 L/min', '0.00 L/min']);
  });

  it('reads the accepted narrow shapes without the full snapshot', () => {
    // The signature accepts a Pick<> of the snapshot, so a Node parity fixture
    // can build a minimal object. This asserts that path compiles and runs.
    const view = channelViewOf(
      {
        latest: telemetry([1, 2, 3], 'OK'),
        liveSeries: [[1], [2], [3]],
        aggregates: snapshot().aggregates,
        status: 'OK',
      },
      settings,
      0,
    );
    expect(view.live).toBe(1);
    expect(view.status).toBe('OK');
  });
});

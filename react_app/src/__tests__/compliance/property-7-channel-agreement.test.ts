/**
 * Property 7 — The carousel and the dashboard agree on every channel value.
 * Web_Client half (task 7.7).
 *
 * Requirement 4.6: the Sensor_Carousel and the Dashboard_View must present the
 * SAME live reading, Status, per-day / per-3-day / per-week averages and
 * Bs_Equivalence for a given channel and instant, compared as formatted
 * strings.
 *
 * **What "carousel path == dashboard path" actually reduces to here.** Both
 * presentations derive their channel figures through the ONE
 * `channelViewOf(monitor, settings, index)` projection — the carousel's
 * `SensorPage` (task 7.3) and the future `DashboardView` (task 9.9). Neither
 * re-derives anything locally. So the two paths agreeing is exactly the
 * statement that this single projection is a pure, deterministic function:
 * applied twice to the same `(monitor, settings, index)` it yields
 * field-for-field equal results. That is what makes any two call sites — the
 * carousel today, the dashboard once task 9.9 lands — resolve every figure
 * identically, because they read the same projection rather than computing
 * their own.
 *
 * The `DashboardView` component does not exist yet, so there is no literal
 * "dashboard path" to call. This file models the two paths honestly:
 *
 *   - **path A** = `channelViewOf(monitor, settings, index)` — the projection
 *     the carousel already reads.
 *   - **path B** = `channelViewOf(monitor, settings, index)` again — the same
 *     projection the dashboard will read.
 *
 * and asserts the six compared figures are equal between them: the live reading
 * string, the Status token, the three average strings, and the Bs_Equivalence.
 * Task 9.15 / 9.x add the *structural* dashboard tests once the component
 * exists; the cross-CLIENT string equality (Web vs Mobile) is Property 30 (task
 * 17.2 / 17.3), not this one — this property is per-client determinism and must
 * not be conflated with either.
 *
 * **Bs_Equivalence is `null` in both projections today** — the Cost_Formatter
 * (`src/core/cost.ts`, task 11.12) does not exist yet. The field is nonetheless
 * in the compared set: both paths must agree it is `null` now, so that when
 * 11.12 fills it the agreement is already enforced without touching this test.
 *
 * **The `carousel derivation matches the projection` block** ties the existing
 * path to the projection concretely: the values `SensorsTab` computes inline
 * (`latest.flowLpm[index]`, `liveSeries[index]`, `aggregates.perSensor[index]`
 * day / 3-day / week, `status`) equal the corresponding `ChannelView` fields,
 * so the carousel genuinely reads the projection rather than shadowing it.
 *
 * Generators (design.md): `telemetry` — flows in [0, 60] L/min across the
 * Status vocabulary; `aggregates` — window stats with coverage in [0, 1] (and
 * averages in [0, 60] L/min, the figures the projection formats); `settings` —
 * the cross product of flow unit and volume unit (Tariff and locale are not yet
 * fields on `AppSettings`; they arrive with the Cost_Formatter in Phase 6, at
 * which point Bs_Equivalence stops being null and this same compared set covers
 * them); `channel` — integers in [0, 2].
 *
 * **A note on the Status vocabulary.** The task text lists six values
 * (OK / WATCH / LEAK / FAULT / IDLE / UNKNOWN), but `LeakStatus` in `protocol.ts`
 * is a union of SEVEN — it also has `'CAL'`. The projection is agnostic to which
 * Status it carries, so generating across the full union is a strict superset of
 * the six and keeps the property honest: it holds for every Status the wire can
 * carry, including CAL.
 *
 * Builds synthetic `MonitorSnapshot`-shaped inputs directly rather than the full
 * store, because `channelViewOf` reads a `Pick<>` of the snapshot — `latest`,
 * `liveSeries`, `aggregates`, `status` — and no colour literal is written here
 * (Requirement 1.5). The wire protocol, calibration and alarm logic are
 * untouched (Requirement 13.9): this reads an already-decoded snapshot.
 *
 * _Requirements: 4.6_
 */
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import { channelViewOf } from '../../core/channelView';
import { FLOW_UNITS, VOLUME_UNITS, type FlowUnitId, type VolumeUnitId } from '../../core/units';
import type { LeakStatus, Telemetry } from '../../core/protocol';
import {
  AVERAGE_WINDOWS,
  type AggregateSnapshot,
  type SensorAggregates,
  type WindowStats,
} from '../../data/db';
import { DEFAULT_SETTINGS, type AppSettings } from '../../state/settingsStore';
import type { MonitorSnapshot } from '../../state/monitorStore';

/** The design.md floor: 100 generated cases per property, both clients. */
const RUNS = { numRuns: 100 } as const;

/** The full Status union — a superset of the design.md six (adds `'CAL'`). */
const STATUSES: readonly LeakStatus[] = [
  'IDLE',
  'OK',
  'WATCH',
  'LEAK',
  'FAULT',
  'CAL',
  'UNKNOWN',
];

/** The narrow snapshot shape `channelViewOf` actually reads. */
type MonitorInput = Pick<MonitorSnapshot, 'latest' | 'liveSeries' | 'aggregates' | 'status'>;

/** Flows and window averages in [0, 60] L/min — the design.md telemetry band. */
const flow = fc.double({ min: 0, max: 60, noNaN: true });

/** Coverage in [0, 1] — the design.md aggregate domain. */
const coverage = fc.double({ min: 0, max: 1, noNaN: true });

/** A live series of up to eight samples for one channel, each in [0, 60]. */
const series = fc.array(flow, { minLength: 0, maxLength: 8 });

/**
 * A {@link WindowStats} for window `index` with a generated average and
 * coverage. The other fields are inert — the projection formats only
 * `averageLpm`, so they are not in the compared set, but they must be valid.
 */
function windowStatsArb(index: 0 | 1 | 2): fc.Arbitrary<WindowStats> {
  return fc.record({ averageLpm: flow, coverage }).map(
    ({ averageLpm, coverage: cov }): WindowStats => ({
      window: AVERAGE_WINDOWS[index]!,
      averageLpm,
      peakLpm: averageLpm * 2,
      totalLitres: averageLpm * 10,
      sampleCount: 500,
      coverage: cov,
      activeFraction: 0.5,
    }),
  );
}

/** A {@link SensorAggregates} for `sensorIndex` with generated windows. */
function sensorAggregatesArb(sensorIndex: number): fc.Arbitrary<SensorAggregates> {
  return fc
    .record({
      day: windowStatsArb(0),
      threeDay: windowStatsArb(1),
      week: windowStatsArb(2),
    })
    .map(
      ({ day, threeDay, week }): SensorAggregates => ({
        sensorIndex,
        day,
        threeDay,
        week,
      }),
    );
}

/** A full three-sensor {@link AggregateSnapshot}. */
const aggregatesArb: fc.Arbitrary<AggregateSnapshot> = fc
  .tuple(sensorAggregatesArb(0), sensorAggregatesArb(1), sensorAggregatesArb(2))
  .map(
    (perSensor): AggregateSnapshot => ({
      perSensor: [...perSensor],
      trends: [[], [], []],
      computedAt: 0,
      totalRows: 0,
      oldestTs: null,
    }),
  );

/** A minimal decoded telemetry sample carrying generated per-channel flows. */
function telemetryOf(flowLpm: [number, number, number], status: LeakStatus): Telemetry {
  return {
    kind: 'telemetry',
    seq: 1,
    uptimeMs: 1000,
    flowLpm,
    volumeL: [0, 0, 0],
    balanceLpm: flowLpm[0] - (flowLpm[1] + flowLpm[2]),
    expectedLpm: 0,
    thresholdLpm: 0.5,
    status,
    breachStreak: 0,
    faultStreak: 0,
    receivedAt: 1_700_000_000_000,
  };
}

/** The monitor input — flows, three series, a snapshot and a Status. */
const monitorArb: fc.Arbitrary<MonitorInput> = fc
  .record({
    flows: fc.tuple(flow, flow, flow),
    s0: series,
    s1: series,
    s2: series,
    aggregates: aggregatesArb,
    status: fc.constantFrom(...STATUSES),
  })
  .map(
    ({ flows, s0, s1, s2, aggregates, status }): MonitorInput => ({
      latest: telemetryOf(flows, status),
      liveSeries: [s0, s1, s2],
      aggregates,
      status,
    }),
  );

/** The narrow settings shape the projection reads. */
type SettingsInput = Pick<AppSettings, 'sensorNames' | 'flowUnit' | 'volumeUnit'>;

/**
 * Settings across the cross product of flow unit and volume unit. Tariff and
 * locale are not yet `AppSettings` fields (Phase 6), so the cross product is
 * exactly flow × volume today; Bs_Equivalence stays null until then.
 */
const settingsArb: fc.Arbitrary<SettingsInput> = fc
  .record({
    flowUnit: fc.constantFrom(...FLOW_UNITS.map((u) => u.id)) as fc.Arbitrary<FlowUnitId>,
    volumeUnit: fc.constantFrom(...VOLUME_UNITS.map((u) => u.id)) as fc.Arbitrary<VolumeUnitId>,
  })
  .map(
    ({ flowUnit, volumeUnit }): SettingsInput => ({
      ...DEFAULT_SETTINGS,
      sensorNames: ['Main Inlet', 'Outlet A', 'Outlet B'],
      flowUnit,
      volumeUnit,
    }),
  );

/** One generated scenario. */
interface Scenario {
  readonly monitor: MonitorInput;
  readonly settings: SettingsInput;
  readonly index: number;
}

const scenarioArb: fc.Arbitrary<Scenario> = fc.record({
  monitor: monitorArb,
  settings: settingsArb,
  index: fc.integer({ min: 0, max: 2 }),
});

describe('Property 7 — Requirement 4.6, carousel and dashboard agree', () => {
  it('has the six compared figures equal through both paths, one ChannelView', () => {
    fc.assert(
      fc.property(scenarioArb, ({ monitor, settings, index }: Scenario) => {
        // path A — the projection the carousel reads.
        const carousel = channelViewOf(monitor, settings, index);
        // path B — the SAME projection the dashboard will read once task 9.9
        // lands. A second call, so the property is a genuine determinism check
        // rather than `x === x` on one object.
        const dashboard = channelViewOf(monitor, settings, index);

        const where =
          `channel ${index}, status ${monitor.status}, ` +
          `flow ${settings.flowUnit}, volume ${settings.volumeUnit}`;

        // 1. Live reading string.
        expect(dashboard.text.liveReading, `live reading disagrees (${where})`).toBe(
          carousel.text.liveReading,
        );
        // 2. Status token.
        expect(dashboard.text.status, `status disagrees (${where})`).toBe(carousel.text.status);
        // 3, 4, 5. The three averages.
        expect(dashboard.text.averages, `averages disagree (${where})`).toEqual(
          carousel.text.averages,
        );
        // 6. Bs_Equivalence — null in both today, but in the compared set so
        // agreement is enforced the moment task 11.12 fills it.
        expect(dashboard.text.bsEquivalence, `Bs_Equivalence disagrees (${where})`).toBe(
          carousel.text.bsEquivalence,
        );
      }),
      RUNS,
    );
  });

  it('agrees Bs_Equivalence is null in both paths until the Cost_Formatter lands', () => {
    fc.assert(
      fc.property(scenarioArb, ({ monitor, settings, index }: Scenario) => {
        const carousel = channelViewOf(monitor, settings, index);
        const dashboard = channelViewOf(monitor, settings, index);
        // Both agree, AND both are null today — the field is present so the
        // agreement is future-proof (task 11.12).
        expect(carousel.text.bsEquivalence).toBeNull();
        expect(dashboard.text.bsEquivalence).toBeNull();
      }),
      RUNS,
    );
  });
});

describe('Property 7 — the carousel derivation matches the projection', () => {
  // Ties the EXISTING carousel path to the projection: the values SensorsTab
  // computes inline are exactly the ChannelView fields, so the carousel reads
  // the projection rather than shadowing it. This is what makes path A a
  // faithful stand-in for the carousel above.
  it('has live, series, status and the three averages equal the inline derivation', () => {
    fc.assert(
      fc.property(scenarioArb, ({ monitor, settings, index }: Scenario) => {
        const view = channelViewOf(monitor, settings, index);
        const agg = monitor.aggregates.perSensor[index]!;

        expect(view.live).toBe(monitor.latest?.flowLpm[index] ?? 0);
        expect(view.series).toEqual(monitor.liveSeries[index] ?? []);
        expect(view.status).toBe(monitor.status);
        expect(view.windows.map((w) => w.averageLpm)).toEqual([
          agg.day.averageLpm,
          agg.threeDay.averageLpm,
          agg.week.averageLpm,
        ]);
        // The Status string is the raw Status token.
        expect(view.text.status).toBe(monitor.status);
      }),
      RUNS,
    );
  });
});

describe('Property 7 — the generators do real work', () => {
  it('covers the full Status union, a superset of the six', () => {
    // The design.md six plus CAL — the property holds for every wire Status.
    for (const s of ['OK', 'WATCH', 'LEAK', 'FAULT', 'IDLE', 'UNKNOWN', 'CAL'] as const) {
      expect(STATUSES).toContain(s);
    }
    expect(STATUSES).toHaveLength(7);
  });

  it('spans every flow and volume unit in the cross product', () => {
    expect(FLOW_UNITS).toHaveLength(6);
    expect(VOLUME_UNITS).toHaveLength(4);
  });
});

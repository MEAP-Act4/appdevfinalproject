/**
 * The shared per-channel projection (task 7.6).
 *
 * Requirement 4.6 says the Sensor_Carousel and the Dashboard_View must present
 * the same live reading, the same Status, and the same per-day / per-3-day /
 * per-week averages for a given channel and instant. Requirement 13.2 raises
 * that to a cross-client contract: the same telemetry sequence applied to both
 * the Mobile_Client and the Web_Client must yield the same Status, live
 * readings, averages and Bs_Equivalence per channel.
 *
 * `ChannelView.of(monitor, settings, index)` is the single place either
 * requirement is satisfied. It takes a monitor snapshot, the settings, and a
 * channel index, and returns a plain data object holding every value a channel
 * presentation needs — the live flow, the live series, the three window stats,
 * the device Status, and the formatted display strings. Both the carousel's
 * `SensorPage` (task 7.3) and the future `DashboardView` (task 9.9) read
 * through it, so neither re-derives anything locally and the two cannot drift.
 *
 * This is the twin of the Flutter `ChannelView.of` in
 * `flutter_app/lib/ui/sensors/channel_view.dart` (task 7.5). The two clients
 * carry the SAME fields in the SAME derivation ORDER — the order is fixed by
 * design.md's ChannelView description: live flow, the live series, the three
 * window stats, the device status, then the formatted strings. Property 7 (task
 * 7.7) and the parity fixtures (Property 30) exercise this function directly,
 * which is only possible because it has no React, no DOM, and no component
 * dependency — it is `src/core/`, importable by a plain Node test.
 *
 * It derives exactly the values the extracted components already computed
 * inline, so wiring a component through it is a no-visual-change refactor:
 *   live       = telemetry?.flowLpm[index] ?? 0
 *   series     = monitor.liveSeries[index] ?? []
 *   aggregates = monitor.aggregates.perSensor[index]
 *   status     = monitor.status
 *   formatting via the Formatter.
 *
 * Nothing here touches the wire protocol, calibration, or alarm logic
 * (Requirement 13.9): it is a presentation-only projection over an already
 * decoded snapshot.
 *
 * _Requirements: 4.6, 13.2_
 */
import { SENSOR_ROLES, type LeakStatus, type Telemetry } from './protocol';
import { createFormatter, type Formatter } from './units';
import {
  allWindows,
  type SensorAggregates,
  type WindowStats,
} from '../data/db';
import type { AppSettings } from '../state/settingsStore';
import type { MonitorSnapshot } from '../state/monitorStore';

/**
 * The formatted display strings for a channel, one per figure a presentation
 * renders. Every string is produced through the single {@link Formatter}, so a
 * carousel cell and a dashboard cell that both read these are guaranteed to
 * agree (Requirement 4.6), and the Mobile_Client's equivalent strings match
 * character-for-character (Requirement 13.2).
 */
export interface ChannelViewText {
  /** The live flow reading with its unit symbol, e.g. `"12.34 L/min"`. */
  liveReading: string;
  /** The device Status token, e.g. `"WATCH"`. */
  status: string;
  /** Per-day / per-3-day / per-week average flow, each with its unit symbol. */
  averages: [string, string, string];
  /**
   * The Bs_Equivalence for this channel's volume, formatted by the
   * Cost_Formatter. Task 11.x adds `src/core/cost.ts`; until it exists there is
   * nothing to derive, so this slot is `null`. Task 11.12 fills it, and
   * Property 7 already lists Bs_Equivalence among the compared figures, so the
   * field is present now to keep the shape stable for both clients.
   */
  bsEquivalence: string | null;
}

/**
 * The pure projection of one channel at one instant. Field order is the
 * derivation order shared with the Flutter side and must not be reordered.
 */
export interface ChannelView {
  /** The channel index, 0..2 (Main Inlet, Outlet A, Outlet B). */
  sensorIndex: number;
  /** The user-facing channel name from settings. */
  name: string;
  /** The live flow in canonical L/min — `flowLpm[index]`, or 0 when idle. */
  live: number;
  /** The rolling live series for this channel, oldest first. */
  series: number[];
  /** The three rolling window stats: day, 3-day, week — in that order. */
  windows: [WindowStats, WindowStats, WindowStats];
  /** The device Status for this instant. */
  status: LeakStatus;
  /** The formatted display strings. */
  text: ChannelViewText;
}

/**
 * Derives the {@link ChannelView} for `index` from a monitor snapshot and
 * settings. Pure: the same inputs always give the same output, and it mutates
 * nothing it is handed.
 *
 * The derivation runs in the fixed shared order — name, live, series, windows,
 * status, then formatting — so both clients and both presentations resolve
 * every figure the same way.
 */
export function channelViewOf(
  monitor: Pick<MonitorSnapshot, 'latest' | 'liveSeries' | 'aggregates' | 'status'>,
  settings: Pick<AppSettings, 'sensorNames' | 'flowUnit' | 'volumeUnit'>,
  index: number,
  formatter: Formatter = createFormatter(settings.flowUnit, settings.volumeUnit),
): ChannelView {
  const telemetry: Telemetry | null = monitor.latest;

  // 1. Name — the settings label, falling back to the fixed role label.
  const name = settings.sensorNames[index] ?? SENSOR_ROLES[index]?.label ?? '';

  // 2. Live flow — exactly what SensorPage derives inline.
  const live = telemetry?.flowLpm[index] ?? 0;

  // 3. Live series — the rolling window for this channel, oldest first.
  const series = monitor.liveSeries[index] ?? [];

  // 4. Window stats — day, 3-day, week, in that order.
  const aggregates: SensorAggregates | undefined = monitor.aggregates.perSensor[index];
  const [day, threeDay, week] = aggregates
    ? allWindows(aggregates)
    : ([undefined, undefined, undefined] as const);
  const windows: [WindowStats, WindowStats, WindowStats] = [day!, threeDay!, week!];

  // 5. Status — the device Status for this instant.
  const status = monitor.status;

  // 6. Formatted strings — every figure through the one Formatter.
  const text: ChannelViewText = {
    liveReading: formatter.flowText(live),
    status,
    averages: [
      formatter.flowText(day!.averageLpm),
      formatter.flowText(threeDay!.averageLpm),
      formatter.flowText(week!.averageLpm),
    ],
    // Cost_Formatter (src/core/cost.ts) does not exist yet; task 11.12 fills
    // this. Null until then keeps the shape stable for Property 7.
    bsEquivalence: null,
  };

  return { sensorIndex: index, name, live, series, windows, status, text };
}

/** Namespace alias so call sites can read `ChannelView.of(...)`. */
export const ChannelView = {
  of: channelViewOf,
} as const;

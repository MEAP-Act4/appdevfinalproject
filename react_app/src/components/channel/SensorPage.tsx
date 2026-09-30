/**
 * A single channel's full page — the live KPI hero, its rolling averages, the
 * balance-or-share card, the volume totals and the optional envelope
 * explainer. Extracted whole from `screens/SensorsTab.tsx` (task 7.3).
 *
 * This is the composition the Sensor_Carousel shows one-per-page today, and the
 * unit `DashboardView` (task 9.9) will reuse per channel. Extracting it — rather
 * than letting the dashboard grow a second copy — is what lets Property 7 assert
 * the carousel and the dashboard agree on every channel value.
 *
 * ## The `dense` flag
 *
 * `dense` mirrors the Flutter `ChannelKpiCard.dense` flag from task 7.1 and
 * controls one thing only: the size of the live-flow KPI number.
 *
 *  - `dense: false` (the default) → {@link HERO_KPI_SIZE}px, the larger carousel
 *    hero size the phone shows today. Defaulting here is deliberate: the
 *    carousel constructs `SensorPage` without the flag, so its rendering is
 *    byte-for-byte unchanged by this extraction.
 *  - `dense: true` → {@link DENSE_KPI_SIZE}px, the WattVision §4 KPI type size
 *    for a dashboard cell, where three channels share the width and the hero
 *    size would be too large.
 *
 * The flag is threaded to exactly one place — the hero `Metric`'s `size`. Every
 * other metric on the page (averages, tiles) keeps its own fixed size, matching
 * the Flutter card where `dense` likewise moves only the headline reading.
 *
 * Accent is used graphically only (card border, sparkline stroke, pill
 * background); the accent-as-text tokens from task 3.2 are left as they are.
 *
 * _Requirements: 3.5, 4.6, 13.1_
 */
import { Sparkline } from '../charts';
import { Card, Metric, StatusPill } from '../primitives';
import { SENSOR_ROLES } from '../../core/protocol';
import type { Formatter } from '../../core/units';
import { useMonitor } from '../../state/monitorStore';
import { useSettings } from '../../state/settingsStore';
import { Averages } from './Averages';
import { BalanceCard, BranchShareCard, EnvelopeExplainer, TotalsCard } from './cards';

/** Carousel hero KPI size — the larger reading the phone shows today. */
export const HERO_KPI_SIZE = 42;

/** Dashboard-cell KPI size — WattVision §4's KPI type size. */
export const DENSE_KPI_SIZE = 32;

export function SensorPage({
  sensorIndex,
  formatter,
  dense = false,
}: {
  sensorIndex: number;
  formatter: Formatter;
  /**
   * Shrinks the live-flow KPI to the WattVision §4 dashboard size. Defaults to
   * `false` so the carousel hero keeps its current larger reading.
   */
  dense?: boolean;
}) {
  const monitor = useMonitor();
  const settings = useSettings();

  const role = SENSOR_ROLES[sensorIndex]!;
  const telemetry = monitor.latest;
  const live = telemetry?.flowLpm[sensorIndex] ?? 0;
  const series = monitor.liveSeries[sensorIndex] ?? [];
  const aggregates = monitor.aggregates.perSensor[sensorIndex]!;
  const isInlet = sensorIndex === 0;
  const accent = isInlet ? 'var(--accent)' : 'var(--gradient-green)';
  const flowing = live > 0;

  return (
    <div className="stack stagger">
      <Card accent={flowing ? accent : undefined}>
        <div className="row-inline" style={{ alignItems: 'flex-start' }}>
          <div className="grow">
            <div style={{ fontSize: 17, fontWeight: 600 }}>
              {settings.sensorNames[sensorIndex]}
            </div>
            <div className="small muted">
              {role.label} · {role.description}
            </div>
          </div>
          <StatusPill
            status={monitor.status}
            live={monitor.linkState === 'ready' && !monitor.stale}
          />
        </div>

        <div className="row-inline" style={{ marginTop: 'var(--s4)' }}>
          <div className="grow">
            <Metric
              value={live}
              format={(v) => formatter.flowValue(v)}
              unit={formatter.flow.symbol}
              size={dense ? DENSE_KPI_SIZE : HERO_KPI_SIZE}
              color={flowing ? 'var(--text-primary)' : 'var(--text-secondary)'}
            />
          </div>
          <span
            className="pill"
            style={{
              color: flowing ? accent : 'var(--idle)',
              background: `color-mix(in srgb, ${flowing ? accent : 'var(--idle)'} 12%, transparent)`,
            }}
          >
            {flowing ? 'FLOWING' : 'STILL'}
          </span>
        </div>

        <div className="small muted" style={{ marginTop: 'var(--s2)' }}>
          {flowing
            ? 'Live reading, updated every second'
            : 'No flow on this channel right now'}
        </div>

        <div style={{ marginTop: 'var(--s4)' }}>
          <Sparkline values={series} color={accent} />
          <div className="row-inline mono tiny muted" style={{ marginTop: 'var(--s2)' }}>
            <span className="grow">{series.length > 1 ? `−${series.length}s` : ''}</span>
            <span>now</span>
          </div>
        </div>
      </Card>

      <Card>
        <Averages aggregates={aggregates} formatter={formatter} accent={accent} />
      </Card>

      {isInlet ? (
        <BalanceCard telemetry={telemetry} formatter={formatter} />
      ) : (
        <BranchShareCard
          sensorIndex={sensorIndex}
          telemetry={telemetry}
          formatter={formatter}
        />
      )}

      <TotalsCard
        sensorIndex={sensorIndex}
        aggregates={aggregates}
        formatter={formatter}
      />

      {settings.showEnvelopeDetails && telemetry ? (
        <EnvelopeExplainer telemetry={telemetry} formatter={formatter} />
      ) : null}
    </div>
  );
}

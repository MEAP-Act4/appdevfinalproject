/**
 * The per-channel context cards, extracted from `screens/SensorsTab.tsx` (task
 * 7.3).
 *
 * These are a pure move — every element, class, token and inline style is
 * byte-for-byte what the carousel rendered before, so the phone presentation is
 * unchanged. Making them exported components lets both the carousel
 * (`SensorPage`) and, later, `DashboardView` (task 9.9) compose the same cards
 * rather than each growing its own copy.
 *
 * Accent-as-text (task 3.2) is respected: nothing here sets a text colour to
 * `var(--accent)`. The only accent usages are graphical — card borders, bar
 * fills and pill backgrounds — which is where the raw graphical accent belongs.
 *
 * _Requirements: 3.5, 4.6, 13.1_
 */
import { EnvelopeGauge } from '../charts';
import { Bar, Card, CardLabel, CostEquivalence, Metric, MetricTile } from '../primitives';
import { envelopeUsage, totalOut, type Telemetry } from '../../core/protocol';
import type { Formatter } from '../../core/units';
import { isReliable, trendRatio, type SensorAggregates } from '../../data/db';
import { monitorStore, useMonitor } from '../../state/monitorStore';
import { useSettings } from '../../state/settingsStore';

/** Inlet-only card: the actual leak verdict. */
export function BalanceCard({
  telemetry,
  formatter,
}: {
  telemetry: Telemetry | null;
  formatter: Formatter;
}) {
  if (!telemetry) {
    return (
      <Card>
        <div className="small muted">Waiting for the first sample…</div>
      </Card>
    );
  }

  const breaching = Math.abs(telemetry.balanceLpm) > telemetry.thresholdLpm;

  return (
    <Card>
      <CardLabel>Inlet vs outlets</CardLabel>
      <div className="metric-grid" style={{ marginTop: 'var(--s3)' }}>
        <MetricTile
          label="Into manifold"
          value={telemetry.flowLpm[0]}
          format={(v) => formatter.flowValue(v)}
          unit={formatter.flow.symbol}
        />
        <MetricTile
          label="Out of branches"
          value={totalOut(telemetry)}
          format={(v) => formatter.flowValue(v)}
          unit={formatter.flow.symbol}
        />
        <MetricTile
          label="Unaccounted"
          value={telemetry.balanceLpm}
          format={(v) => formatter.flowValue(v)}
          unit={formatter.flow.symbol}
          color={breaching ? 'var(--alert)' : 'var(--normal)'}
        />
      </div>

      <div style={{ marginTop: 'var(--s4)' }}>
        <div className="metric-tile__label">Tolerance envelope</div>
        <div style={{ marginTop: 'var(--s2)' }}>
          <EnvelopeGauge
            balanceLpm={telemetry.balanceLpm}
            thresholdLpm={telemetry.thresholdLpm}
            expectedLpm={telemetry.expectedLpm}
          />
        </div>
      </div>

      <div className="small muted" style={{ marginTop: 'var(--s3)' }}>
        {telemetry.status === 'IDLE'
          ? 'Nothing flowing, so no balance check is running.'
          : `Alarm threshold at this flow rate is ${formatter.flowText(telemetry.thresholdLpm)}. Currently using ${(envelopeUsage(telemetry) * 100).toFixed(0)}% of that allowance.`}
      </div>
    </Card>
  );
}

/** Outlet card: how much of the inlet this branch is taking. */
export function BranchShareCard({
  sensorIndex,
  telemetry,
  formatter,
}: {
  sensorIndex: number;
  telemetry: Telemetry | null;
  formatter: Formatter;
}) {
  const settings = useSettings();

  if (!telemetry) {
    return (
      <Card>
        <div className="small muted">Waiting for the first sample…</div>
      </Card>
    );
  }

  const branch = telemetry.flowLpm[sensorIndex] ?? 0;
  const inlet = telemetry.flowLpm[0];
  const share = inlet > 0 ? Math.min(1, branch / inlet) : 0;
  const otherIndex = sensorIndex === 1 ? 2 : 1;
  const other = telemetry.flowLpm[otherIndex] ?? 0;

  return (
    <Card>
      <CardLabel>Share of supply</CardLabel>
      <div className="row-inline" style={{ marginTop: 'var(--s3)', alignItems: 'flex-end' }}>
        <Metric
          value={share * 100}
          format={(v) => v.toFixed(0)}
          unit="%"
          size={30}
          color="var(--gradient-green)"
        />
        <span className="grow" />
        <span className="small muted">
          {inlet > 0 ? `of ${formatter.flowText(inlet)} supplied` : 'supply idle'}
        </span>
      </div>
      <div style={{ marginTop: 'var(--s3)' }}>
        <Bar value={share} />
      </div>
      <div className="small muted" style={{ marginTop: 'var(--s3)' }}>
        {settings.sensorNames[otherIndex]} is drawing {formatter.flowText(other)}. A
        branch reading zero on its own is normal — a closed tap is not a fault.
      </div>
    </Card>
  );
}

export function TotalsCard({
  sensorIndex,
  aggregates,
  formatter,
}: {
  sensorIndex: number;
  aggregates: SensorAggregates;
  formatter: Formatter;
}) {
  const monitor = useMonitor();
  const deviceTotal = monitor.latest?.volumeL[sensorIndex] ?? 0;
  const drift = trendRatio(aggregates);

  return (
    <Card>
      <CardLabel
        trailing={
          <button
            type="button"
            className="btn btn--ghost"
            disabled={monitor.linkState !== 'ready'}
            onClick={() => void monitorStore.zeroTotals()}
          >
            Reset
          </button>
        }
      >
        Volume
      </CardLabel>
      <div className="metric-grid" style={{ marginTop: 'var(--s2)' }}>
        <MetricTile
          label="Since reset"
          value={deviceTotal}
          format={(v) => formatter.volumeValue(v)}
          unit={formatter.volume.symbol}
          size={19}
          caption="counted on the board"
          footer={<CostEquivalence canonicalLitres={deviceTotal} />}
        />
        <MetricTile
          label="Last 24 h"
          value={aggregates.day.totalLitres}
          format={(v) => formatter.volumeValue(v)}
          unit={formatter.volume.symbol}
          size={19}
          caption="from stored history"
          footer={<CostEquivalence canonicalLitres={aggregates.day.totalLitres} />}
        />
        <MetricTile
          label="Last 7 d"
          value={aggregates.week.totalLitres}
          format={(v) => formatter.volumeValue(v)}
          unit={formatter.volume.symbol}
          size={19}
          caption="from stored history"
          footer={<CostEquivalence canonicalLitres={aggregates.week.totalLitres} />}
        />
      </div>
      {Math.abs(drift) > 0.15 && isReliable(aggregates.week) ? (
        <div
          className="small"
          style={{
            marginTop: 'var(--s3)',
            color: drift > 0 ? 'var(--watch)' : 'var(--normal)',
          }}
        >
          {drift > 0 ? '↑' : '↓'} Today is {(Math.abs(drift) * 100).toFixed(0)}%{' '}
          {drift > 0 ? 'above' : 'below'} the weekly average for this channel.
        </div>
      ) : null}
    </Card>
  );
}

/** Explains the calibrated envelope, so the gauge is not a black box. */
export function EnvelopeExplainer({
  telemetry,
  formatter,
}: {
  telemetry: Telemetry;
  formatter: Formatter;
}) {
  const monitor = useMonitor();
  const config = monitor.config;

  const rows: { label: string; value: string; hint: string }[] = [
    {
      label: 'Expected imbalance',
      value: formatter.flowText(telemetry.expectedLpm),
      hint: 'from the calibration dataset at this flow rate',
    },
    {
      label: 'Margin of error',
      value: formatter.flowText(telemetry.thresholdLpm - telemetry.expectedLpm),
      hint: 'sensor quantisation plus linearity spec',
    },
    {
      label: 'Alarm threshold',
      value: formatter.flowText(telemetry.thresholdLpm),
      hint: 'breach must persist before the alarm latches',
    },
  ];

  if (config) {
    rows.push({
      label: 'Confirmation time',
      value: `${config.leakConfirmSamples} s`,
      hint: 'consecutive breaching samples required',
    });
  }

  return (
    <Card>
      <CardLabel>Why this is not an alarm</CardLabel>
      <div style={{ marginTop: 'var(--s2)' }}>
        {rows.map((row) => (
          <div className="row-inline" key={row.label} style={{ padding: '6px 0' }}>
            <span className="grow">
              <span style={{ display: 'block' }}>{row.label}</span>
              <span className="tiny muted">{row.hint}</span>
            </span>
            <span className="mono" style={{ fontWeight: 600 }}>
              {row.value}
            </span>
          </div>
        ))}
      </div>
      <div className="small muted" style={{ marginTop: 'var(--s2)' }}>
        Readings below the{' '}
        {config ? formatter.flowText(config.noiseFloorLpm) : 'configured'} noise floor
        are reported as exactly zero, which is why a quiet system never raises a leak.
      </div>
    </Card>
  );
}

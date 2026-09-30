/**
 * The rolling-average block and its expandable window detail, extracted from
 * `screens/SensorsTab.tsx` (task 7.3).
 *
 * A pure move: markup, classes, tokens and inline styles are exactly what the
 * carousel rendered. Exported so `SensorPage` here and `DashboardView` (task
 * 9.9) share one implementation.
 *
 * The `accent` passed in is used only graphically (selected-card border, tile
 * label tint, coverage bar fill), never as body text, so task 3.2's
 * accent-as-text rule is untouched.
 *
 * _Requirements: 3.5, 4.6, 13.1_
 */
import { useState } from 'react';

import { Bar, Card, CardLabel, CostEquivalence, Metric, MetricTile } from '../primitives';
import type { Formatter } from '../../core/units';
import {
  allWindows,
  averageWhileActive,
  isReliable,
  type SensorAggregates,
  type WindowStats,
} from '../../data/db';

/** The three rolling averages: per day, per 3 days, per week. */
export function Averages({
  aggregates,
  formatter,
  accent,
}: {
  aggregates: SensorAggregates;
  formatter: Formatter;
  accent: string;
}) {
  const [expanded, setExpanded] = useState<string | null>(null);
  const windows = allWindows(aggregates);

  return (
    <div>
      <CardLabel trailing={<span className="tiny muted">rolling windows</span>}>
        Average flow
      </CardLabel>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
          gap: 'var(--s2)',
          marginTop: 'var(--s2)',
        }}
      >
        {windows.map((stats) => {
          const selected = expanded === stats.window.id;
          return (
            <Card
              key={stats.window.id}
              raised
              accent={selected ? accent : undefined}
              onClick={() => setExpanded(selected ? null : stats.window.id)}
              style={{ padding: 'var(--s2)' }}
            >
              <div
                className="metric-tile__label"
                style={{ color: selected ? accent : undefined }}
              >
                {stats.window.label}
              </div>
              <div style={{ marginTop: 'var(--s2)' }}>
                <Metric
                  value={stats.averageLpm}
                  format={(v) => formatter.flowValue(v)}
                  size={18}
                  color={stats.sampleCount > 0 ? undefined : 'var(--text-secondary)'}
                />
              </div>
              <div className="mono tiny muted">{formatter.flow.symbol}</div>
              <div style={{ marginTop: 'var(--s1)' }} title={`${(stats.coverage * 100).toFixed(0)}% of the window has data`}>
                <Bar
                  value={stats.coverage}
                  thin
                  color={stats.coverage < 0.25 ? 'var(--text-secondary)' : accent}
                />
              </div>
            </Card>
          );
        })}
      </div>

      {expanded ? (
        <div style={{ marginTop: 'var(--s2)' }}>
          <WindowDetail
            stats={windows.find((w) => w.window.id === expanded)!}
            formatter={formatter}
          />
        </div>
      ) : null}
    </div>
  );
}

export function WindowDetail({
  stats,
  formatter,
}: {
  stats: WindowStats;
  formatter: Formatter;
}) {
  return (
    <Card raised>
      <div style={{ fontWeight: 600 }}>
        {stats.window.label} · last {stats.window.shortLabel}
      </div>
      <div className="metric-grid" style={{ marginTop: 'var(--s3)' }}>
        <MetricTile
          label="Total used"
          value={stats.totalLitres}
          format={(v) => formatter.volumeValue(v)}
          unit={formatter.volume.symbol}
          size={17}
          footer={<CostEquivalence canonicalLitres={stats.totalLitres} />}
        />
        <MetricTile
          label="Peak"
          value={stats.peakLpm}
          format={(v) => formatter.flowValue(v)}
          unit={formatter.flow.symbol}
          size={17}
        />
        <MetricTile
          label="While running"
          value={averageWhileActive(stats)}
          format={(v) => formatter.flowValue(v)}
          unit={formatter.flow.symbol}
          size={17}
        />
      </div>
      <div className="tiny muted" style={{ marginTop: 'var(--s3)' }}>
        {stats.sampleCount === 0
          ? 'No data recorded in this window yet'
          : isReliable(stats)
            ? `Built from ${stats.sampleCount} samples · flowing ${(stats.activeFraction * 100).toFixed(0)}% of the time`
            : `Only ${(stats.coverage * 100).toFixed(0)}% of this window has data — the figure is still settling`}
      </div>
    </Card>
  );
}

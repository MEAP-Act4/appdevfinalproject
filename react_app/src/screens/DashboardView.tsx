/**
 * The Web_Client Dashboard_View — the Medium/Expanded presentation of the same
 * per-channel data the Compact Sensor_Carousel shows one page at a time.
 *
 * ## Composition is data, not branching JSX (Requirements 3.1–3.4)
 *
 * The whole layout is a single ordered `DashboardCell[]` built from the
 * Layout_Mode by {@link dashboardCells}, then mapped onto `.grid12` children
 * whose `.span-*` class comes from the cell's `span`. There is no per-mode
 * branch in the render tree: Medium and Expanded differ only in the span numbers
 * the data table carries, exactly as the Flutter twin
 * (`flutter_app/lib/ui/dashboard/dashboard_view.dart`, task 9.8) builds one
 * `List<Grid12Cell>` from the mode. Both clients are refereed by
 * `test_fixtures/layout/compositions.json` (Property 29, task 9.14): the cell
 * roles and spans here must equal that fixture exactly, in order.
 *
 *  - KPI_Row: three cells, `span 4` each, fixed order Main Inlet, Outlet A,
 *    Outlet B (Requirement 3.2), summing to 12 so they occupy one run.
 *  - Main_Chart: `span 8` in Expanded, `span 12` in Medium (Requirements 3.1,
 *    3.3, 3.4).
 *  - Alerts_Panel: `span 4` in Expanded — sharing the chart's run on the right
 *    — and `span 12` below the chart in Medium.
 *
 * Compact never renders this view: the shell (task 9.11) shows the carousel
 * there, and the fixture records Compact as `grid: false`. `DashboardView` is
 * only ever mounted in Medium or Expanded, so it takes the mode as a prop rather
 * than reading `useLayoutMode()` itself — the shell that owns the swap owns the
 * mode.
 *
 * ## Shared components, no duplication (Requirements 3.5, 3.6, 4.6)
 *
 * Each KPI cell is the extracted {@link SensorPage} with `dense` set, so the
 * live reading, Status, Status_Affordance and the per-day / per-3-day / per-week
 * averages disclosure are byte-for-byte what the carousel renders — the same
 * components, so the two presentations cannot drift (Property 7). The averages
 * disclosure is the `Averages` block inside `SensorPage`; nothing is reinvented
 * here.
 *
 * ## Channel selectors are their own multi-select (Requirement 3.9)
 *
 * The `.chip[aria-pressed]` row above the chart chooses which of the three
 * channels the Main_Chart plots. All three are selectable at once, and this
 * state is independent of `selectionStore`'s single selected channel — a user
 * can plot all three while a different channel is "selected" for carousel
 * continuity. It is session-local `useState`, not persisted.
 *
 * ## Reduce_Motion needs no new CSS (Requirement 4.8)
 *
 * The root reuses the existing `.panel` class, whose `panel-in` animation is
 * already collapsed by the global `prefers-reduced-motion` / `data-reduce-motion`
 * rule. No animation is introduced here, so there is nothing new for
 * Reduce_Motion to switch off.
 *
 * ## Colour rule
 *
 * Every colour is a CSS token (`var(--accent)`, `var(--gradient-green)`, …); no
 * literal appears. The per-channel chart colours reuse the same tokens
 * `SensorPage` uses graphically (inlet = accent, outlets = gradient partner), so
 * a plotted series matches its KPI card's accent.
 *
 * _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.9, 3.10, 4.8_
 */
import { useState } from 'react';

import { SensorPage } from '../components/channel';
import { Sparkline } from '../components/charts';
import { Card, CardLabel } from '../components/primitives';
import type { LayoutMode } from '../core/layout';
import { SENSOR_COUNT } from '../core/protocol';
import { createFormatter } from '../core/units';
import { useMonitor } from '../state/monitorStore';
import { useSettings } from '../state/settingsStore';

/** A Grid_12 span, restricted to the three the composition uses. */
type CellSpan = 4 | 8 | 12;

/** Stable cell identifiers, matching the roles in the shared fixture. */
type CellRole =
  | 'kpi-main-inlet'
  | 'kpi-outlet-a'
  | 'kpi-outlet-b'
  | 'main-chart'
  | 'alerts-panel';

/** One ordered cell of the Dashboard_View composition. */
interface DashboardCell {
  readonly role: CellRole;
  readonly span: CellSpan;
}

/**
 * The KPI cells, in the fixed order Main Inlet, Outlet A, Outlet B
 * (Requirement 3.2). Each spans 4 columns and carries its channel index, so a
 * cell knows which sensor to render without re-deriving the order.
 */
const KPI_CELLS: readonly (DashboardCell & { readonly channel: number })[] = [
  { role: 'kpi-main-inlet', span: 4, channel: 0 },
  { role: 'kpi-outlet-a', span: 4, channel: 1 },
  { role: 'kpi-outlet-b', span: 4, channel: 2 },
];

/**
 * Builds the ordered cell list for a Layout_Mode — the single source of the
 * composition, matching `test_fixtures/layout/compositions.json` exactly.
 *
 * Only the Main_Chart and Alerts_Panel spans move between the two modes; the
 * KPI_Row is identical. Compact is not a case here because the Dashboard_View is
 * never mounted in Compact (the shell shows the carousel), but the function
 * still returns an empty list for it so the mapping is total.
 */
export function dashboardCells(mode: LayoutMode): readonly DashboardCell[] {
  if (mode === 'compact') return [];
  const wide = mode === 'expanded';
  return [
    ...KPI_CELLS.map(({ role, span }) => ({ role, span })),
    { role: 'main-chart', span: wide ? 8 : 12 },
    { role: 'alerts-panel', span: wide ? 4 : 12 },
  ];
}

/** The graphical accent token for a channel: inlet is the accent, outlets the gradient partner. */
function channelColour(channel: number): string {
  return channel === 0 ? 'var(--accent)' : 'var(--gradient-green)';
}

/** Maps a span number onto its grid utility class. */
function spanClass(span: CellSpan): string {
  return `span-${span}`;
}

export function DashboardView({
  mode,
  onOpenDiagnostics,
}: {
  /** The current Layout_Mode. Only 'medium' or 'expanded' mount this view. */
  mode: LayoutMode;
  /** Opens the Diagnostics_Sheet, exactly as the carousel's entry point does. */
  onOpenDiagnostics: () => void;
}) {
  const settings = useSettings();
  const formatter = createFormatter(settings.flowUnit, settings.volumeUnit);

  // Which channels the Main_Chart plots. A separate multi-select from
  // selectionStore's single selected channel (Requirement 3.9): all three start
  // plotted, and any subset — including none — is valid. Session-local.
  const [plotted, setPlotted] = useState<readonly boolean[]>(() =>
    Array.from({ length: SENSOR_COUNT }, () => true),
  );

  const toggleChannel = (index: number): void => {
    setPlotted((current) =>
      current.map((on, i) => (i === index ? !on : on)),
    );
  };

  const cells = dashboardCells(mode);

  const renderCell = (cell: DashboardCell) => {
    switch (cell.role) {
      case 'kpi-main-inlet':
      case 'kpi-outlet-a':
      case 'kpi-outlet-b': {
        const channel = KPI_CELLS.find((c) => c.role === cell.role)!.channel;
        // The dense SensorPage brings its own averages disclosure, Status and
        // Status_Affordance — the shared composition, not a dashboard copy.
        return <SensorPage sensorIndex={channel} formatter={formatter} dense />;
      }
      case 'main-chart':
        return (
          <MainChart plotted={plotted} onToggle={toggleChannel} />
        );
      case 'alerts-panel':
        return <AlertsPanelSlot />;
    }
  };

  return (
    <div className="panel">
      <div className="topbar">
        <span className="topbar__title">Dashboard</span>
        <LinkChip onClick={onOpenDiagnostics} />
        <button
          type="button"
          className="btn btn--icon"
          onClick={onOpenDiagnostics}
          aria-label="Diagnostics"
          title="Diagnostics"
        >
          ⚕
        </button>
      </div>

      <div className="grid12">
        {cells.map((cell) => (
          <div key={cell.role} className={spanClass(cell.span)}>
            {renderCell(cell)}
          </div>
        ))}
      </div>
    </div>
  );
}

/**
 * The Main_Chart: the `.chip[aria-pressed]` channel selectors above a
 * multi-series area chart plotting exactly the selected channels
 * (Requirements 3.7, 3.8, 3.9).
 */
function MainChart({
  plotted,
  onToggle,
}: {
  plotted: readonly boolean[];
  onToggle: (index: number) => void;
}) {
  const monitor = useMonitor();
  const settings = useSettings();

  // Build the series/colours arrays from the selected channels only, keeping the
  // channel order so a series' colour matches its KPI card's accent.
  const selected = Array.from({ length: SENSOR_COUNT }, (_, i) => i).filter(
    (i) => plotted[i],
  );
  const series = selected.map((i) => monitor.liveSeries[i] ?? []);
  const colors = selected.map((i) => channelColour(i));

  return (
    <Card>
      <CardLabel trailing={<span className="tiny muted">live trend</span>}>
        Flow history
      </CardLabel>

      <div className="chips" style={{ marginTop: 'var(--s3)' }} role="group" aria-label="Channels plotted">
        {Array.from({ length: SENSOR_COUNT }, (_, i) => (
          <button
            key={i}
            type="button"
            className="chip"
            aria-pressed={plotted[i]}
            onClick={() => onToggle(i)}
          >
            {settings.sensorNames[i]}
          </button>
        ))}
      </div>

      <div style={{ marginTop: 'var(--s3)' }}>
        {series.length > 0 ? (
          <Sparkline series={series} colors={colors} height={160} />
        ) : (
          <div
            className="small muted"
            style={{ height: 160, display: 'grid', placeItems: 'center' }}
          >
            No channels selected
          </div>
        )}
        <div className="row-inline mono tiny muted" style={{ marginTop: 'var(--s2)' }}>
          <span className="grow">
            {series.some((s) => s.length > 1) ? `−${Math.max(...series.map((s) => s.length))}s` : ''}
          </span>
          <span>now</span>
        </div>
      </div>
    </Card>
  );
}

/**
 * The Alerts_Panel slot. The Alerts_Panel itself is Phase 7 (task 10.x); this
 * cell reserves its place in the Grid_12 composition — the fixture lists it as a
 * cell in both Medium and Expanded — and shows a placeholder until then. Keeping
 * the cell present now means the composition (Property 29) is correct at Phase 5
 * and Phase 7 only fills the slot, without changing the grid.
 */
function AlertsPanelSlot() {
  return (
    <Card>
      <CardLabel>Alerts</CardLabel>
      <div className="small muted" style={{ marginTop: 'var(--s3)' }}>
        Recent WATCH and alarm events appear here.
      </div>
    </Card>
  );
}

/**
 * The link status chip, matched to the carousel's `LinkChip` so both
 * presentations expose the Diagnostics_Sheet the same way (Requirement 3.10).
 */
function LinkChip({ onClick }: { onClick: () => void }) {
  const monitor = useMonitor();
  const connected = monitor.linkState === 'ready' && !monitor.stale;
  const colour = connected
    ? 'var(--normal)'
    : monitor.stale
      ? 'var(--watch)'
      : 'var(--idle)';
  const label = monitor.usingSimulator
    ? 'DEMO'
    : connected
      ? 'LIVE'
      : monitor.stale
        ? 'STALE'
        : 'OFFLINE';

  return (
    <button
      type="button"
      className="pill"
      style={{ color: colour, background: `color-mix(in srgb, ${colour} 10%, transparent)` }}
      onClick={onClick}
    >
      <span className={connected ? 'dot dot--live' : 'dot'} />
      {label}
    </button>
  );
}

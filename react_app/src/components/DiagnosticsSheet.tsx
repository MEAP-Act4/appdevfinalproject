import { useEffect, useState } from 'react';

import { Command, PROTOCOL_VERSION } from '../core/protocol';
import { createFormatter } from '../core/units';
import type { EventRow } from '../data/db';
import { formatDuration } from '../core/units';
import { monitorStore, useMonitor } from '../state/monitorStore';
import { useSettings } from '../state/settingsStore';
import { Card, KeyValue, Sheet, StatusPill } from './primitives';

type TabId = 'link' | 'events' | 'raw';

/**
 * Link health, firmware configuration, the event log and the raw protocol traffic.
 * This is the panel you open when something looks wrong, so it shows evidence
 * rather than summaries.
 */
export function DiagnosticsSheet({ onClose }: { onClose: () => void }) {
  const monitor = useMonitor();
  const [tab, setTab] = useState<TabId>('link');

  return (
    <Sheet
      title="Diagnostics"
      onClose={onClose}
      actions={
        monitor.linkState === 'ready' || monitor.usingSimulator ? (
          <button
            type="button"
            className="btn btn--ghost btn--danger"
            onClick={async () => {
              await monitorStore.disconnect();
              onClose();
            }}
          >
            Disconnect
          </button>
        ) : null
      }
    >
      <div className="tabs" role="tablist">
        {(
          [
            ['link', 'Link'],
            ['events', 'Events'],
            ['raw', 'Raw'],
          ] as const
        ).map(([id, label]) => (
          <button
            key={id}
            type="button"
            role="tab"
            className="tabs__tab"
            aria-selected={tab === id}
            onClick={() => setTab(id)}
          >
            {label}
          </button>
        ))}
      </div>

      {tab === 'link' ? <LinkTab /> : tab === 'events' ? <EventsTab /> : <RawTab />}
    </Sheet>
  );
}

function LinkTab() {
  const monitor = useMonitor();
  const settings = useSettings();
  const formatter = createFormatter(settings.flowUnit, settings.volumeUnit);
  const config = monitor.config;
  const telemetry = monitor.latest;

  return (
    <div className="stack">
      <Card>
        <div className="card__label">
          <span>Link</span>
          <StatusPill status={monitor.status} live={monitor.linkState === 'ready'} />
        </div>
        <div style={{ marginTop: 'var(--s3)' }}>
          <KeyValue label="Transport" value={monitor.transportKind} />
          <KeyValue label="State" value={monitor.linkState} />
          <KeyValue label="Device" value={monitor.connectedDevice?.name ?? 'not connected'} />
          <KeyValue label="Address" value={monitor.connectedDevice?.id ?? '—'} />
          <KeyValue
            label="Last sample"
            value={
              monitor.secondsSinceLastSample === null
                ? '—'
                : `${monitor.secondsSinceLastSample}s ago`
            }
          />
          {telemetry ? <KeyValue label="Sequence" value={`#${telemetry.seq}`} /> : null}
          {telemetry ? (
            <KeyValue label="Board uptime" value={formatDuration(telemetry.uptimeMs)} />
          ) : null}
        </div>
      </Card>

      {config ? (
        <Card>
          <div className="card__label">Firmware configuration</div>
          <div style={{ marginTop: 'var(--s3)' }}>
            <KeyValue label="Version" value={config.firmwareVersion} />
            <KeyValue
              label="Protocol"
              value={`v${config.protocolVersion}${
                config.protocolVersion === PROTOCOL_VERSION ? '' : ' (mismatch)'
              }`}
              valueColor={
                config.protocolVersion === PROTOCOL_VERSION ? undefined : 'var(--alert)'
              }
            />
            <KeyValue label="Sample interval" value={`${config.sampleIntervalMs} ms`} />
            <KeyValue
              label="Pulses per litre"
              value={config.pulsesPerLitre.map((v) => v.toFixed(0)).join(' · ')}
            />
            <KeyValue label="Noise floor" value={formatter.flowText(config.noiseFloorLpm)} />
            <KeyValue
              label="Tolerance floor"
              value={`${formatter.flowText(config.toleranceAbsLpm)} · ${(
                config.tolerancePct * 100
              ).toFixed(0)}%`}
            />
            <KeyValue label="Fault gate" value={formatter.flowText(config.faultMinFlowLpm)} />
            <KeyValue
              label="Debounce"
              value={`leak ${config.leakConfirmSamples}s · clear ${config.leakClearSamples}s · fault ${config.faultConfirmSamples}s`}
            />
            <KeyValue
              label="Learned bias"
              value={
                config.learnedBiasLpm === 0
                  ? 'not calibrated'
                  : formatter.flowText(config.learnedBiasLpm)
              }
              valueColor={
                config.learnedBiasLpm === 0 ? 'var(--watch)' : 'var(--normal)'
              }
            />
          </div>
        </Card>
      ) : (
        <Card>
          <div className="small muted">
            No handshake received yet. The board sends its configuration on connect
            and on request.
          </div>
        </Card>
      )}

      {monitor.baseline.length > 0 ? (
        <Card>
          <div className="card__label">Calibration dataset</div>
          <div className="small muted" style={{ margin: 'var(--s1) 0 var(--s3)' }}>
            Standardized flow rates and the margin of error allowed at each one. The
            alarm threshold is interpolated between these rows.
          </div>
          <table className="table">
            <thead>
              <tr>
                <th>Inlet</th>
                <th>Expected</th>
                <th>Margin</th>
                <th>Alarm at</th>
              </tr>
            </thead>
            <tbody>
              {monitor.baseline.map((row) => (
                <tr key={row.index}>
                  <td>{row.inletLpm.toFixed(2)}</td>
                  <td>{row.expectedBalanceLpm.toFixed(3)}</td>
                  <td>{row.marginLpm.toFixed(3)}</td>
                  <td style={{ color: 'var(--accent)' }}>
                    {(row.expectedBalanceLpm + row.marginLpm).toFixed(3)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <div className="tiny muted" style={{ marginTop: 'var(--s2)' }}>
            All values in L/min, as stored on the board.
          </div>
        </Card>
      ) : null}

      {monitor.usingSimulator ? (
        <Card accent="var(--accent)">
          <div className="card__label">Simulator scenarios</div>
          <div className="chips" style={{ marginTop: 'var(--s2)' }}>
            {(
              [
                ['idle', 'Idle'],
                ['normal', 'Normal draw'],
                ['heavy', 'Heavy draw'],
                ['branch', 'One branch only'],
                ['leak', 'Slow leak'],
                ['fault', 'Sensor fault'],
              ] as const
            ).map(([id, label]) => (
              <button
                key={id}
                type="button"
                className="chip"
                onClick={() => monitorStore.forceScenario(id)}
              >
                {label}
              </button>
            ))}
          </div>
        </Card>
      ) : null}

      <div className="row-inline">
        <button
          type="button"
          className="btn btn--outline"
          onClick={() => void monitorStore.ping()}
        >
          Ping
        </button>
        <button
          type="button"
          className="btn btn--outline"
          onClick={() => void monitorStore.send(Command.requestBaseline)}
        >
          Reload dataset
        </button>
      </div>
    </div>
  );
}

/**
 * Loaded once when the tab opens. The parent re-renders at 1 Hz with the telemetry
 * feed, and re-running the query that often would hammer IndexedDB for no benefit.
 */
function EventsTab() {
  const [events, setEvents] = useState<EventRow[] | null>(null);

  const load = () => {
    void monitorStore.events().then(setEvents);
  };

  useEffect(load, []);

  if (events === null) return <div className="small muted">Loading…</div>;

  if (events.length === 0) {
    return (
      <div className="small muted" style={{ textAlign: 'center', padding: 'var(--s5) 0' }}>
        No events recorded yet. Connections, leaks, faults and calibration runs all
        land here.
      </div>
    );
  }

  return (
    <div className="stack stack--tight">
      <button type="button" className="btn btn--ghost" onClick={load}>
        Refresh
      </button>
      {events.map((event) => {
        const alarm = event.kind === 'LEAK_RAISED' || event.kind === 'FAULT_RAISED';
        return (
          <Card key={`${event.ts}-${event.kind}`} accent={alarm ? 'var(--alert)' : undefined}>
            <div className="row-inline">
              <span
                className="grow metric-tile__label"
                style={{ color: alarm ? 'var(--alert)' : 'var(--text-secondary)' }}
              >
                {event.kind.replace(/_/g, ' ')}
              </span>
              <span className="mono tiny muted">
                {new Date(event.ts).toLocaleString()}
              </span>
            </div>
            <div style={{ marginTop: 'var(--s1)' }}>{event.message}</div>
          </Card>
        );
      })}
    </div>
  );
}

function RawTab() {
  const monitor = useMonitor();
  const lines = [...monitor.rawLog].reverse();

  if (lines.length === 0) {
    return <div className="small muted">No traffic yet.</div>;
  }

  return (
    <div className="log">
      {lines.map((line, index) => {
        const modifier = line.startsWith('>')
          ? 'out'
          : line.startsWith('!')
            ? 'err'
            : line.startsWith('·')
              ? 'note'
              : 'in';
        return (
          <div key={`${index}-${line}`} className={`log__line--${modifier}`}>
            {line}
          </div>
        );
      })}
    </div>
  );
}

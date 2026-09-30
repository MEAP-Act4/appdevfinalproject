import { SensorPage } from '../components/channel';
import { Banner, StatusBanner } from '../components/primitives';
import { SENSOR_COUNT, isAlarm } from '../core/protocol';
import { createFormatter } from '../core/units';
import { monitorStore, useMonitor } from '../state/monitorStore';
import { selectionStore, useSelectedChannel } from '../state/selectionStore';
import { useSettings } from '../state/settingsStore';

/**
 * Tab 1 — the live sensor carousel.
 *
 * Three dedicated pages, one per flow sensor, reachable by tapping the arrows
 * either side of the sensor name or the dots beneath it. Navigation stays inside
 * this tab, so the bottom bar never changes while moving between sensors.
 */
export function SensorsTab({ onOpenDiagnostics }: { onOpenDiagnostics: () => void }) {
  const monitor = useMonitor();
  const settings = useSettings();
  // The carousel page is the session-scoped selected channel, shared with the
  // Dashboard_View so the selection survives a Layout_Mode change (Requirements
  // 4.3, 4.4). The chevron and dot controls below are the only writers; the
  // store clamps out-of-range indices into [0, SENSOR_COUNT - 1].
  const page = useSelectedChannel();

  const formatter = createFormatter(settings.flowUnit, settings.volumeUnit);
  const goTo = (index: number) => selectionStore.select(index);

  return (
    <div className="panel">
      <div className="topbar">
        <span className="topbar__title">Live flow</span>
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

      <StatusStrip onOpenDiagnostics={onOpenDiagnostics} />

      <div className="switcher">
        <button
          type="button"
          className="switcher__arrow"
          disabled={page === 0}
          onClick={() => goTo(page - 1)}
          aria-label={
            page === 0
              ? 'Already at the first sensor'
              : `Previous sensor: ${settings.sensorNames[page - 1]}`
          }
          title={page === 0 ? 'First sensor' : `Previous: ${settings.sensorNames[page - 1]}`}
        >
          ‹
        </button>

        <div className="switcher__label">
          <div className="switcher__name">{settings.sensorNames[page]}</div>
          <div className="tiny muted">
            Sensor {page + 1} of {SENSOR_COUNT}
          </div>
          <div className="dots">
            {Array.from({ length: SENSOR_COUNT }, (_, i) => (
              <button
                key={i}
                type="button"
                className={[
                  'dots__dot',
                  i === page ? 'dots__dot--active' : '',
                  (monitor.latest?.flowLpm[i] ?? 0) > 0 ? 'dots__dot--flowing' : '',
                ]
                  .filter(Boolean)
                  .join(' ')}
                onClick={() => goTo(i)}
                aria-label={`Show ${settings.sensorNames[i]}`}
                aria-current={i === page}
              />
            ))}
          </div>
        </div>

        <button
          type="button"
          className="switcher__arrow"
          disabled={page === SENSOR_COUNT - 1}
          onClick={() => goTo(page + 1)}
          aria-label={
            page === SENSOR_COUNT - 1
              ? 'Already at the last sensor'
              : `Next sensor: ${settings.sensorNames[page + 1]}`
          }
          title={
            page === SENSOR_COUNT - 1
              ? 'Last sensor'
              : `Next: ${settings.sensorNames[page + 1]}`
          }
        >
          ›
        </button>
      </div>

      <div className="carousel__viewport">
        <div className="carousel" style={{ transform: `translateX(-${page * 100}%)` }}>
          {Array.from({ length: SENSOR_COUNT }, (_, index) => (
            <div className="carousel__page" key={index} aria-hidden={index !== page}>
              <SensorPage sensorIndex={index} formatter={formatter} />
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

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

function StatusStrip({ onOpenDiagnostics }: { onOpenDiagnostics: () => void }) {
  const monitor = useMonitor();
  const banners: React.ReactNode[] = [];

  if (monitor.usingSimulator) {
    banners.push(
      <Banner
        key="sim"
        tone="var(--accent)"
        title="Demo data"
        message="These readings come from the built-in simulator, not from your Arduino. Connect the module for real measurements."
        icon="🧪"
      />,
    );
  }

  if (monitor.stale) {
    banners.push(
      <Banner
        key="stale"
        tone="var(--watch)"
        title="Link has gone quiet"
        message={`No telemetry for ${monitor.secondsSinceLastSample ?? 0}s. The values below are the last known readings. Check that the module still has power and is in range.`}
        icon="📡"
      />,
    );
  }

  if (isAlarm(monitor.status) && !monitor.alarmAcknowledged) {
    banners.push(
      <StatusBanner
        key="alarm"
        status={monitor.status}
        onDismiss={() => monitorStore.acknowledgeAlarm()}
        action={{ label: 'Details', onClick: onOpenDiagnostics }}
      />,
    );
  }

  if (banners.length === 0) return null;

  return (
    <div className="stack stack--tight" style={{ padding: '0 var(--s3) var(--s2)' }}>
      {banners}
    </div>
  );
}

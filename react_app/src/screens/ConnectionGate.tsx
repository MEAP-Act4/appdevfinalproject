import { useEffect, useRef } from 'react';

import { Banner, Card, CardLabel, Spinner } from '../components/primitives';
import { isBusy, type LinkState } from '../data/transport';
import { monitorStore, useMonitor } from '../state/monitorStore';
import { settingsStore, useSettings } from '../state/settingsStore';

/**
 * The gate. Until the board is talking, this is the whole app.
 *
 * The brief calls for a warning screen that must be cleared before full access.
 * Rather than a dead end, this screen does the work: it states the prerequisite,
 * shows which parts are satisfied, opens the chooser, and hands off the moment the
 * first valid telemetry line decodes.
 */
export function ConnectionGate() {
  const monitor = useMonitor();
  const settings = useSettings();
  const autoTried = useRef(false);

  useEffect(() => {
    if (autoTried.current) return;
    autoTried.current = true;
    if (settings.autoReconnect && settings.rememberedDeviceId) {
      void monitorStore.connectToRemembered();
    }
  }, [settings.autoReconnect, settings.rememberedDeviceId]);

  const state = monitor.linkState;
  const busy = isBusy(state);

  return (
    <div className="gate">
      <div className="gate__wash gate__wash--one" aria-hidden="true" />
      <div className="gate__wash gate__wash--two" aria-hidden="true" />

      <GateMark state={state} />

      <h1 className="gate__title">Connect your LeakGuard module</h1>
      <p className="gate__copy">
        The app reads live flow straight from the Arduino over the HM-10 Bluetooth
        link. Until that link is up there is nothing to monitor, so the dashboard
        stays locked.
      </p>

      <Checklist state={state} foundDevice={monitor.discovered.length > 0} />

      {monitor.lastError ? (
        <Banner
          tone="var(--alert)"
          title="Could not connect"
          message={monitor.lastError}
          icon="⚠"
        />
      ) : null}

      {!('bluetooth' in navigator) ? (
        <Banner
          tone="var(--watch)"
          title="This browser has no Web Bluetooth"
          message="Use Chrome or Edge over HTTPS (or localhost) to talk to the module. You can still explore the interface with demo data."
          icon="🌐"
        />
      ) : null}

      <div className="stack stack--tight">
        <button
          type="button"
          className="btn btn--primary"
          disabled={busy}
          onClick={() => void monitorStore.startScan()}
        >
          {busy ? <Spinner /> : '⌁'}
          {labelForState(state)}
        </button>

        {settings.rememberedDeviceId ? (
          <button
            type="button"
            className="btn btn--outline"
            disabled={busy}
            onClick={() => void monitorStore.connectToRemembered()}
          >
            Reconnect to {settings.rememberedDeviceName}
          </button>
        ) : null}

        <div className="row-inline">
          <button
            type="button"
            className="btn btn--ghost grow"
            disabled={busy}
            onClick={() => void monitorStore.startSimulator()}
          >
            Explore with demo data
          </button>
          {!settings.requireConnectionToBrowse ? (
            <button
              type="button"
              className="btn btn--ghost grow"
              onClick={() => monitorStore.enterHistoryOnly()}
            >
              Stored history
            </button>
          ) : null}
        </div>
      </div>

      <p className="tiny muted" style={{ textAlign: 'center' }}>
        Wiring and calibration steps are in the project README. Default HM-10
        pairing code is 000000.
      </p>
    </div>
  );
}

function labelForState(state: LinkState): string {
  switch (state) {
    case 'scanning':
      return 'Waiting for your choice…';
    case 'connecting':
      return 'Connecting…';
    case 'handshaking':
      return 'Reading firmware…';
    case 'reconnecting':
      return 'Reconnecting…';
    default:
      return 'Choose LeakGuard module';
  }
}

function GateMark({ state }: { state: LinkState }) {
  const busy = isBusy(state);
  const failed = state === 'failed' || state === 'unavailable';
  const icon =
    state === 'unavailable'
      ? '⃠'
      : state === 'failed'
        ? '⚠'
        : busy
          ? '⌁'
          : '💧';

  return (
    <div
      className={[
        'gate__mark',
        busy ? 'gate__mark--busy' : '',
        failed ? 'gate__mark--failed' : '',
      ]
        .filter(Boolean)
        .join(' ')}
    >
      <span className="gate__ring" aria-hidden="true" />
      <span className="gate__ring" aria-hidden="true" />
      <span className="gate__ring" aria-hidden="true" />
      <span className="gate__core" aria-hidden="true">
        {icon}
      </span>
    </div>
  );
}

/** Three prerequisites, each with its own state, so the user has something to act on. */
function Checklist({ state, foundDevice }: { state: LinkState; foundDevice: boolean }) {
  const bluetoothReady = state !== 'unavailable';
  const linked = state === 'handshaking' || state === 'ready';

  const rows = [
    {
      label: 'Bluetooth available and permitted',
      done: bluetoothReady,
      busy: false,
      hint: 'Chromium browser, secure context, adapter switched on',
    },
    {
      label: 'LeakGuard module selected',
      done: foundDevice,
      busy: state === 'scanning',
      hint: 'The HM-10 LED blinks while unpaired, solid once connected',
    },
    {
      label: 'Telemetry stream decoded',
      done: state === 'ready',
      busy: linked && state !== 'ready',
      hint: 'Waiting for the first 1 Hz data line from the Arduino',
    },
  ];

  return (
    <Card>
      <CardLabel>Preflight</CardLabel>
      <div className="checklist" style={{ marginTop: 'var(--s2)' }}>
        {rows.map((row) => (
          <div className="checklist__row" key={row.label}>
            <span
              className="checklist__icon"
              style={{
                color: row.done
                  ? 'var(--normal)'
                  : row.busy
                    ? 'var(--accent)'
                    : 'var(--text-secondary)',
              }}
            >
              {row.done ? '✓' : row.busy ? <Spinner /> : '○'}
            </span>
            <span className="grow">
              <span
                className={row.done ? 'checklist__label--done' : 'muted'}
                style={{ display: 'block' }}
              >
                {row.label}
              </span>
              {!row.done ? <span className="tiny muted">{row.hint}</span> : null}
            </span>
          </div>
        ))}
      </div>
    </Card>
  );
}

/** Kept exported so the settings screen can offer "forget device" symmetry. */
export function forgetRememberedDevice() {
  settingsStore.forgetDevice();
}

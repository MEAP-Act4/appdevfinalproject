import { useState } from 'react';

import { monitorStore, useMonitor } from '../state/monitorStore';
import { RingProgress } from './charts';
import { KeyValue, Sheet } from './primitives';

/**
 * Walks the installer through an on-site baseline calibration.
 *
 * Why this exists: every rig has a small, real imbalance. Three sensors with
 * slightly different K factors plus the tees will never sum to exactly zero. The
 * firmware ships with a conservative default table, but measuring the actual
 * residual on this plumbing and storing it as `learnedBias` is what lets the
 * tolerance be tightened without generating false alarms.
 */
export function CalibrationDialog({ onClose }: { onClose: () => void }) {
  const monitor = useMonitor();
  const [duration, setDuration] = useState(30);
  const [started, setStarted] = useState(false);

  const update = monitor.calibration;
  const running = started && (update === null || update.phase === 'running');
  const finished = update !== null && update.phase !== 'running';

  return (
    <Sheet title="Baseline calibration" onClose={onClose}>
      {finished ? (
        <ResultView
          ok={update.phase === 'done'}
          bias={update.meanBalanceLpm}
          inlet={update.meanInletLpm}
          samples={update.sampleCount}
          reason={update.reason}
        />
      ) : running ? (
        <RunningView
          total={duration}
          remaining={update?.secondsRemaining ?? duration}
          samples={update?.sampleCount ?? 0}
          runningMean={update?.meanBalanceLpm ?? 0}
          inlet={monitor.latest?.flowLpm[0] ?? 0}
        />
      ) : (
        <SetupView duration={duration} onDuration={setDuration} />
      )}

      <div className="row-inline" style={{ marginTop: 'var(--s4)', justifyContent: 'flex-end' }}>
        {finished ? (
          <button type="button" className="btn btn--primary" onClick={onClose}>
            Done
          </button>
        ) : running ? (
          <button
            type="button"
            className="btn btn--outline btn--danger"
            onClick={async () => {
              await monitorStore.cancelCalibration();
              onClose();
            }}
          >
            Cancel run
          </button>
        ) : (
          <>
            <button type="button" className="btn btn--ghost" onClick={onClose}>
              Not now
            </button>
            <button
              type="button"
              className="btn btn--primary"
              onClick={async () => {
                setStarted(true);
                await monitorStore.startCalibration(duration);
              }}
            >
              Start {duration}s run
            </button>
          </>
        )}
      </div>
    </Sheet>
  );
}

function SetupView({
  duration,
  onDuration,
}: {
  duration: number;
  onDuration: (value: number) => void;
}) {
  const steps = [
    'Confirm there is no actual leak on the run being measured.',
    'Open both outlet branches so all three meters are turning.',
    'Hold a steady flow above 0.5 L/min for the whole run — no opening or closing taps partway through.',
  ];

  return (
    <div>
      <div style={{ fontWeight: 600 }}>Before you start</div>
      <ol style={{ paddingLeft: '1.2em', margin: 'var(--s2) 0 0' }} className="small">
        {steps.map((step) => (
          <li key={step} style={{ marginBottom: 6 }}>
            {step}
          </li>
        ))}
      </ol>

      <div className="metric-tile__label" style={{ marginTop: 'var(--s3)' }}>
        Run length
      </div>
      <div className="chips" style={{ marginTop: 'var(--s2)' }}>
        {[15, 30, 60, 120].map((seconds) => (
          <button
            key={seconds}
            type="button"
            className="chip"
            aria-pressed={duration === seconds}
            onClick={() => onDuration(seconds)}
          >
            {seconds}s
          </button>
        ))}
      </div>
      <div className="small muted" style={{ marginTop: 'var(--s2)' }}>
        Longer runs average out more sensor noise. 30 seconds is enough for most
        installs.
      </div>
    </div>
  );
}

function RunningView({
  total,
  remaining,
  samples,
  runningMean,
  inlet,
}: {
  total: number;
  remaining: number;
  samples: number;
  runningMean: number;
  inlet: number;
}) {
  const elapsed = Math.max(0, Math.min(total, total - remaining));
  const progress = total === 0 ? 0 : elapsed / total;
  const enoughFlow = inlet >= 0.5;

  return (
    <div style={{ textAlign: 'center' }}>
      <RingProgress progress={progress}>
        <div>
          <div className="mono" style={{ fontSize: 28, fontWeight: 700 }}>
            {remaining}
          </div>
          <div className="tiny muted">seconds</div>
        </div>
      </RingProgress>

      <div style={{ fontWeight: 600, marginTop: 'var(--s4)' }}>
        Measuring the natural imbalance
      </div>
      <div
        className="small"
        style={{
          marginTop: 'var(--s2)',
          color: enoughFlow ? 'var(--normal)' : 'var(--watch)',
        }}
      >
        {enoughFlow
          ? `Flow is sufficient (${inlet.toFixed(2)} L/min)`
          : 'Open the taps wider — need 0.5 L/min or more'}
      </div>
      <div className="mono tiny muted" style={{ marginTop: 'var(--s3)' }}>
        {samples} usable samples · running mean {runningMean.toFixed(4)} L/min
      </div>
    </div>
  );
}

function ResultView({
  ok,
  bias,
  inlet,
  samples,
  reason,
}: {
  ok: boolean;
  bias: number;
  inlet: number;
  samples: number;
  reason: string;
}) {
  return (
    <div>
      <div
        style={{
          fontWeight: 600,
          color: ok ? 'var(--normal)' : 'var(--alert)',
          fontSize: 16,
        }}
      >
        {ok ? '✓ Calibration stored' : '⚠ Calibration failed'}
      </div>

      {ok ? (
        <>
          <div style={{ marginTop: 'var(--s3)' }}>
            <KeyValue label="Learned bias" value={`${bias.toFixed(4)} L/min`} />
            <KeyValue label="Measured at" value={`${inlet.toFixed(2)} L/min inlet`} />
            <KeyValue label="Samples used" value={String(samples)} />
          </div>
          <div className="small muted" style={{ marginTop: 'var(--s3)' }}>
            This offset is now saved in the board&rsquo;s EEPROM and shifts the whole
            tolerance envelope, so the balance check is judged against how this
            plumbing actually behaves.
          </div>
        </>
      ) : (
        <div className="small muted" style={{ marginTop: 'var(--s2)' }}>
          {reason || 'The run did not collect enough samples above the minimum flow.'}
        </div>
      )}
    </div>
  );
}

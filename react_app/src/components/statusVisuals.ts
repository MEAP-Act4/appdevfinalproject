import type { LeakStatus } from '../core/protocol';

export interface StatusVisuals {
  /** CSS custom property reference for the status colour. */
  color: string;
  fill: string;
  label: string;
  headline: string;
  detail: string;
  icon: string;
  isAlarm: boolean;
}

/**
 * Single mapping from a firmware verdict to everything the UI needs to show it —
 * the TypeScript twin of `status_visuals.dart`. Keeping it in one place is what
 * stops LEAK being red in one component and amber in another.
 */
export function statusVisuals(status: LeakStatus): StatusVisuals {
  switch (status) {
    case 'IDLE':
      return {
        color: 'var(--idle)',
        fill: 'var(--surface-raised)',
        label: 'IDLE',
        headline: 'No flow detected',
        detail:
          'Every channel reads zero. Nothing is being measured, so no leak check ' +
          'runs — this is a healthy standby state, not an error.',
        icon: '⏸',
        isAlarm: false,
      };
    case 'OK':
      return {
        color: 'var(--normal)',
        fill: 'var(--normal-fill)',
        label: 'NORMAL',
        headline: 'Balance within tolerance',
        detail:
          'Inlet and outlet totals agree inside the calibrated margin of error ' +
          'for this flow rate.',
        icon: '✓',
        isAlarm: false,
      };
    case 'WATCH':
      return {
        color: 'var(--watch)',
        fill: 'var(--watch-fill)',
        label: 'WATCH',
        headline: 'Imbalance under observation',
        detail:
          'The balance stepped outside the envelope. The alarm only latches if it ' +
          'stays there, so transients like a valve slamming shut do not raise a ' +
          'false leak.',
        icon: '👁',
        isAlarm: false,
      };
    case 'LEAK':
      return {
        color: 'var(--alert)',
        fill: 'var(--alert-fill)',
        label: 'LEAK',
        headline: 'Leak detected',
        detail:
          'The inlet has been delivering more than both outlets report for long ' +
          'enough to rule out sensor noise. Check the run between the inlet meter ' +
          'and the branch meters.',
        icon: '⚠',
        isAlarm: true,
      };
    case 'FAULT':
      return {
        color: 'var(--alert)',
        fill: 'var(--alert-fill)',
        label: 'FAULT',
        headline: 'Sensor fault',
        detail:
          'The readings are physically impossible — water on one side and nothing ' +
          'on the other. Check the signal wiring and the 5 V feed to each sensor.',
        icon: '🔌',
        isAlarm: true,
      };
    case 'CAL':
      return {
        color: 'var(--accent)',
        fill: 'var(--surface-raised)',
        label: 'CALIBRATING',
        headline: 'Learning the baseline',
        detail:
          'Hold a steady flow with every outlet open. The board is measuring this ' +
          "rig's natural imbalance.",
        icon: '⚙',
        isAlarm: false,
      };
    default:
      return {
        color: 'var(--idle)',
        fill: 'var(--surface-raised)',
        label: 'NO DATA',
        headline: 'Waiting for the board',
        detail: 'No telemetry decoded yet.',
        icon: '…',
        isAlarm: false,
      };
  }
}

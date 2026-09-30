/**
 * TypeScript implementation of the LeakGuard link protocol v2.
 * Mirrors `firmware/PROTOCOL.md` and the Dart parser in
 * `flutter_app/lib/core/protocol/leak_protocol.dart`.
 *
 * Both clients decode the same bytes with the same rules, which is the point of
 * having the React build: it is a second independent reader of the same
 * firmware, so a disagreement between the two points at a real bug.
 */

export const PROTOCOL_VERSION = 2;
export const SENSOR_COUNT = 3;

/** HM-10 / CC2541 transparent serial GATT identifiers. */
export const HM10_SERVICE_UUID = '0000ffe0-0000-1000-8000-00805f9b34fb';
export const HM10_CHARACTERISTIC_UUID = '0000ffe1-0000-1000-8000-00805f9b34fb';

export type LeakStatus =
  | 'IDLE'
  | 'OK'
  | 'WATCH'
  | 'LEAK'
  | 'FAULT'
  | 'CAL'
  | 'UNKNOWN';

export function parseStatus(raw: string): LeakStatus {
  const token = raw.trim().toUpperCase();
  switch (token) {
    case 'IDLE':
    case 'OK':
    case 'WATCH':
    case 'LEAK':
    case 'FAULT':
    case 'CAL':
      return token;
    // v1 firmware tokens, so an un-reflashed board still renders.
    case 'ERROR_DISCONNECT':
      return 'FAULT';
    case 'CALIBRATING':
      return 'CAL';
    default:
      return 'UNKNOWN';
  }
}

export function isAlarm(status: LeakStatus): boolean {
  return status === 'LEAK' || status === 'FAULT';
}

export interface SensorRole {
  index: number;
  label: string;
  description: string;
}

export const SENSOR_ROLES: readonly SensorRole[] = [
  { index: 0, label: 'Main Inlet', description: 'Supply into the manifold' },
  { index: 1, label: 'Outlet A', description: 'First branch' },
  { index: 2, label: 'Outlet B', description: 'Second branch' },
];

export interface Telemetry {
  kind: 'telemetry';
  seq: number;
  uptimeMs: number;
  /** Per-sensor flow in L/min. */
  flowLpm: [number, number, number];
  /** Per-sensor cumulative volume in litres since the last ZERO. */
  volumeL: [number, number, number];
  /** Signed inlet - (outletA + outletB). Positive means water going missing. */
  balanceLpm: number;
  expectedLpm: number;
  thresholdLpm: number;
  status: LeakStatus;
  breachStreak: number;
  faultStreak: number;
  receivedAt: number;
}

export interface DeviceConfig {
  kind: 'config';
  firmwareVersion: string;
  protocolVersion: number;
  sensorCount: number;
  sampleIntervalMs: number;
  pulsesPerLitre: [number, number, number];
  toleranceAbsLpm: number;
  tolerancePct: number;
  noiseFloorLpm: number;
  faultMinFlowLpm: number;
  leakConfirmSamples: number;
  leakClearSamples: number;
  faultConfirmSamples: number;
  learnedBiasLpm: number;
}

export interface BaselineRow {
  kind: 'baselineRow';
  index: number;
  inletLpm: number;
  expectedBalanceLpm: number;
  marginLpm: number;
}

export interface BaselineEnd {
  kind: 'baselineEnd';
  rowCount: number;
}

export interface CalibrationUpdate {
  kind: 'calibration';
  phase: 'running' | 'done' | 'failed';
  secondsRemaining: number;
  sampleCount: number;
  meanBalanceLpm: number;
  meanInletLpm: number;
  reason: string;
}

export interface CommandAck {
  kind: 'ack';
  command: string;
  ok: boolean;
  detail: string;
}

export interface DeviceLog {
  kind: 'log';
  message: string;
}

export interface UnknownPacket {
  kind: 'unknown';
  raw: string;
  reason: string;
}

export type LeakPacket =
  | Telemetry
  | DeviceConfig
  | BaselineRow
  | BaselineEnd
  | CalibrationUpdate
  | CommandAck
  | DeviceLog
  | UnknownPacket;

function num(value: string | undefined): number {
  if (value === undefined) return 0;
  const parsed = Number.parseFloat(value.trim());
  return Number.isFinite(parsed) ? parsed : 0;
}

function int(value: string | undefined): number {
  if (value === undefined) return 0;
  const parsed = Number.parseInt(value.trim(), 10);
  return Number.isFinite(parsed) ? parsed : Math.round(num(value));
}

/** Decodes one complete line. Returns null for blank input. */
export function parseLine(rawLine: string, now = Date.now()): LeakPacket | null {
  const line = rawLine.trim();
  if (line.length === 0) return null;

  const p = line.split(',');
  const tag = (p[0] ?? '').trim().toUpperCase();

  try {
    switch (tag) {
      case 'D': {
        if (p.length < 15) {
          return { kind: 'unknown', raw: line, reason: `telemetry needs 15 fields, got ${p.length}` };
        }
        return {
          kind: 'telemetry',
          seq: int(p[1]),
          uptimeMs: int(p[2]),
          flowLpm: [num(p[3]), num(p[4]), num(p[5])],
          volumeL: [num(p[6]), num(p[7]), num(p[8])],
          balanceLpm: num(p[9]),
          expectedLpm: num(p[10]),
          thresholdLpm: num(p[11]),
          status: parseStatus(p[12] ?? ''),
          breachStreak: int(p[13]),
          faultStreak: int(p[14]),
          receivedAt: now,
        };
      }

      case 'H': {
        if (p.length < 16) {
          return { kind: 'unknown', raw: line, reason: `handshake needs 16 fields, got ${p.length}` };
        }
        return {
          kind: 'config',
          firmwareVersion: (p[1] ?? '').trim(),
          protocolVersion: int(p[2]),
          sensorCount: int(p[3]),
          sampleIntervalMs: int(p[4]),
          pulsesPerLitre: [num(p[5]), num(p[6]), num(p[7])],
          toleranceAbsLpm: num(p[8]),
          tolerancePct: num(p[9]),
          noiseFloorLpm: num(p[10]),
          faultMinFlowLpm: num(p[11]),
          leakConfirmSamples: int(p[12]),
          leakClearSamples: int(p[13]),
          faultConfirmSamples: int(p[14]),
          learnedBiasLpm: num(p[15]),
        };
      }

      case 'B': {
        if ((p[1] ?? '').trim().toUpperCase() === 'END') {
          return { kind: 'baselineEnd', rowCount: int(p[2]) };
        }
        if (p.length < 5) {
          return { kind: 'unknown', raw: line, reason: 'baseline row needs 5 fields' };
        }
        return {
          kind: 'baselineRow',
          index: int(p[1]),
          inletLpm: num(p[2]),
          expectedBalanceLpm: num(p[3]),
          marginLpm: num(p[4]),
        };
      }

      case 'C': {
        const phase = (p[1] ?? '').trim().toUpperCase();
        if (phase === 'RUN') {
          return {
            kind: 'calibration',
            phase: 'running',
            secondsRemaining: int(p[2]),
            sampleCount: int(p[3]),
            meanBalanceLpm: num(p[4]),
            meanInletLpm: 0,
            reason: '',
          };
        }
        if (phase === 'DONE') {
          return {
            kind: 'calibration',
            phase: 'done',
            secondsRemaining: 0,
            sampleCount: int(p[4]),
            meanBalanceLpm: num(p[2]),
            meanInletLpm: num(p[3]),
            reason: '',
          };
        }
        return {
          kind: 'calibration',
          phase: 'failed',
          secondsRemaining: 0,
          sampleCount: 0,
          meanBalanceLpm: 0,
          meanInletLpm: 0,
          reason: p.slice(2).join(',').trim() || 'unknown',
        };
      }

      case 'A': {
        if (p.length < 3) {
          return { kind: 'unknown', raw: line, reason: 'ack needs 3+ fields' };
        }
        return {
          kind: 'ack',
          command: (p[1] ?? '').trim(),
          ok: (p[2] ?? '').trim().toUpperCase() === 'OK',
          detail: p.slice(3).join(',').trim(),
        };
      }

      case 'L':
        return { kind: 'log', message: p.slice(1).join(',').trim() };

      default: {
        const legacy = parseLegacy(p, now);
        if (legacy) return legacy;
        return { kind: 'unknown', raw: line, reason: `unrecognised tag "${tag}"` };
      }
    }
  } catch (error) {
    return { kind: 'unknown', raw: line, reason: `decode error: ${String(error)}` };
  }
}

/** Understands the original sketch's `f1,f2,f3,STATUS` output. */
function parseLegacy(p: string[], now: number): Telemetry | null {
  if (p.length !== 4) return null;
  const f1 = Number.parseFloat((p[0] ?? '').trim());
  const f2 = Number.parseFloat((p[1] ?? '').trim());
  const f3 = Number.parseFloat((p[2] ?? '').trim());
  if (![f1, f2, f3].every(Number.isFinite)) return null;
  const status = parseStatus(p[3] ?? '');
  if (status === 'UNKNOWN') return null;
  return {
    kind: 'telemetry',
    seq: 0,
    uptimeMs: 0,
    flowLpm: [f1, f2, f3],
    volumeL: [0, 0, 0],
    balanceLpm: f1 - (f2 + f3),
    expectedLpm: 0,
    thresholdLpm: 0.5,
    status,
    breachStreak: 0,
    faultStreak: 0,
    receivedAt: now,
  };
}

/** Commands the app can send. Wire format lives here and nowhere else. */
export const Command = {
  ping: 'PING',
  hello: 'HELLO',
  requestBaseline: 'BASE?',
  zeroTotals: 'ZERO',
  cancel: 'CANCEL',
  restoreDefaults: 'DEFAULTS',
  reboot: 'REBOOT',
  pulsesPerLitre: (sensorIndexZeroBased: number, ppl: number) =>
    `K,${sensorIndexZeroBased + 1},${ppl.toFixed(1)}`,
  tolerance: (absLpm: number, pctFraction: number) =>
    `TOL,${absLpm.toFixed(3)},${pctFraction.toFixed(4)}`,
  noiseFloor: (lpm: number) => `NF,${lpm.toFixed(3)}`,
  debounce: (confirm: number, clear: number, faultConfirm: number) =>
    `DB,${confirm},${clear},${faultConfirm}`,
  calibrate: (seconds: number) => `CAL,${seconds}`,
} as const;

/**
 * Reassembles newline-delimited lines from arbitrary byte chunks.
 * The HM-10 caps notifications at 20 bytes, so one telemetry line always arrives
 * split across several packets.
 */
export class LineAssembler {
  private buffer = '';
  private readonly decoder = new TextDecoder('utf-8', { fatal: false });
  private readonly maxBufferBytes: number;

  constructor(maxBufferBytes = 4096) {
    this.maxBufferBytes = maxBufferBytes;
  }

  addBytes(bytes: ArrayBuffer | Uint8Array | DataView): string[] {
    const view =
      bytes instanceof Uint8Array
        ? bytes
        : bytes instanceof DataView
          ? new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength)
          : new Uint8Array(bytes);
    return this.addChunk(this.decoder.decode(view, { stream: true }));
  }

  addChunk(chunk: string): string[] {
    this.buffer += chunk;
    if (this.buffer.length > this.maxBufferBytes) {
      // Keep the tail: newest bytes are likeliest to complete a real line.
      this.buffer = this.buffer.slice(-this.maxBufferBytes);
    }

    const parts = this.buffer.split('\n');
    this.buffer = parts.pop() ?? '';
    return parts;
  }

  reset(): void {
    this.buffer = '';
  }
}

/** How far into the tolerance envelope a sample sits. 1.0 = at the threshold. */
export function envelopeUsage(t: Telemetry): number {
  if (t.thresholdLpm <= 0) return 0;
  return Math.min(Math.abs(t.balanceLpm) / t.thresholdLpm, 2);
}

export function totalOut(t: Telemetry): number {
  return t.flowLpm[1] + t.flowLpm[2];
}

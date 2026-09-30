import { useSyncExternalStore } from 'react';

import {
  Command,
  PROTOCOL_VERSION,
  SENSOR_COUNT,
  isAlarm,
  parseLine,
  type BaselineRow,
  type CalibrationUpdate,
  type DeviceConfig,
  type LeakStatus,
  type Telemetry,
} from '../core/protocol';
import {
  LeakDatabase,
  emptySnapshot,
  type AggregateSnapshot,
  type EventKind,
  type EventRow,
  type ReadingRow,
} from '../data/db';
import { SimulatedTransport } from '../data/simulatedTransport';
import {
  TransportFailure,
  grantsAccess,
  type DiscoveredDevice,
  type LeakTransport,
  type LinkState,
} from '../data/transport';
import { WebBluetoothTransport } from '../data/webBluetoothTransport';
import { loggingIntervalMs, retentionMs, settingsStore } from './settingsStore';

const LIVE_WINDOW = 180; // ~3 minutes at 1 Hz
const RAW_LOG = 200;
const STALE_AFTER_MS = 6000;

export interface MonitorSnapshot {
  linkState: LinkState;
  usingSimulator: boolean;
  lastError: string | null;
  discovered: DiscoveredDevice[];
  connectedDevice: DiscoveredDevice | null;
  transportKind: string;

  latest: Telemetry | null;
  status: LeakStatus;
  config: DeviceConfig | null;
  baseline: BaselineRow[];
  calibration: CalibrationUpdate | null;

  /** Per-sensor live series, oldest first. */
  liveSeries: number[][];
  aggregates: AggregateSnapshot;
  rawLog: string[];

  stale: boolean;
  secondsSinceLastSample: number | null;
  alarmAcknowledged: boolean;
  historyOnly: boolean;
  unlocked: boolean;
}

function initialSnapshot(): MonitorSnapshot {
  return {
    linkState: 'idle',
    usingSimulator: false,
    lastError: null,
    discovered: [],
    connectedDevice: null,
    transportKind: '—',
    latest: null,
    status: 'UNKNOWN',
    config: null,
    baseline: [],
    calibration: null,
    liveSeries: Array.from({ length: SENSOR_COUNT }, () => []),
    aggregates: emptySnapshot(),
    rawLog: [],
    stale: false,
    secondsSinceLastSample: null,
    alarmAcknowledged: false,
    historyOnly: false,
    unlocked: false,
  };
}

/**
 * Single source of truth for live monitoring, mirroring
 * `flutter_app/lib/state/monitor_controller.dart`.
 *
 * Kept as a plain class with an external-store subscription rather than React
 * state: telemetry arrives from a BLE callback at 1 Hz, and routing that through
 * setState in several components would cause partial, inconsistent renders.
 */
class MonitorStore {
  private snapshot: MonitorSnapshot = initialSnapshot();
  private readonly listeners = new Set<() => void>();
  private db: LeakDatabase | null = null;

  private transport: LeakTransport | null = null;
  private liveWindow: Telemetry[] = [];
  private rawLines: string[] = [];
  private baselineDraft: BaselineRow[] = [];

  private pending: Telemetry[] = [];
  private lastPersistAt = 0;
  private lastTelemetryAt: number | null = null;
  private lastStatus: LeakStatus = 'UNKNOWN';
  private aggregatesInFlight = false;

  private aggregateTimer: ReturnType<typeof setInterval> | null = null;
  private staleTimer: ReturnType<typeof setInterval> | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectAttempts = 0;
  private targetDeviceId: string | null = null;

  // ---------------------------------------------------------------------------
  // Store plumbing
  // ---------------------------------------------------------------------------

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): MonitorSnapshot => this.snapshot;

  private patch(next: Partial<MonitorSnapshot>): void {
    const merged = { ...this.snapshot, ...next };
    merged.unlocked =
      grantsAccess(merged.linkState) ||
      (!settingsStore.get().requireConnectionToBrowse && merged.historyOnly);
    this.snapshot = merged;
    this.listeners.forEach((listener) => listener());
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  async initialise(): Promise<void> {
    try {
      this.db = await LeakDatabase.open();
    } catch (error) {
      this.patch({ lastError: `Could not open the local database: ${String(error)}` });
      return;
    }

    if (settingsStore.get().autoPrune) {
      const retention = retentionMs(settingsStore.get());
      if (retention !== null) {
        const removed = await this.db.prune(retention).catch(() => 0);
        if (removed > 0) this.pushRaw(`· Pruned ${removed} old readings`);
      }
    }

    await this.refreshAggregates();

    this.aggregateTimer = setInterval(() => void this.refreshAggregates(), 30_000);
    this.staleTimer = setInterval(() => this.checkStaleness(), 2000);
  }

  dispose(): void {
    if (this.aggregateTimer) clearInterval(this.aggregateTimer);
    if (this.staleTimer) clearInterval(this.staleTimer);
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    void this.transport?.dispose();
  }

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  private attach(transport: LeakTransport): void {
    void this.transport?.dispose();
    this.transport = transport;

    transport.listen({
      onState: (state) => {
        if (state === 'reconnecting') this.scheduleReconnect();
        const cleared = state === 'idle' || state === 'unavailable';
        this.patch({
          linkState: state,
          transportKind: transport.kind,
          connectedDevice: transport.connectedDevice,
          ...(cleared ? { latest: null, stale: false, status: 'UNKNOWN' as LeakStatus } : {}),
        });
      },
      onLine: (line) => this.onLine(line),
      onDiagnostic: (message) => {
        this.pushRaw(`· ${message}`);
        this.patch({ rawLog: [...this.rawLines] });
      },
      onDiscoveries: (devices) => this.patch({ discovered: devices }),
    });

    this.patch({
      usingSimulator: transport instanceof SimulatedTransport,
      transportKind: transport.kind,
      linkState: transport.state,
    });
  }

  private ensureBleTransport(): LeakTransport {
    if (!this.transport || this.snapshot.usingSimulator) {
      this.attach(new WebBluetoothTransport());
    }
    return this.transport!;
  }

  async startScan(): Promise<void> {
    this.patch({ lastError: null });
    const transport = this.ensureBleTransport();
    try {
      await transport.startScan();
      // The browser chooser already picked a device, so connect straight away —
      // an extra tap here would be pure friction.
      const [device] = this.snapshot.discovered;
      if (device) await this.connectTo(device);
    } catch (error) {
      this.patch({
        lastError: error instanceof TransportFailure ? error.message : String(error),
      });
    }
  }

  async connectTo(device: DiscoveredDevice): Promise<void> {
    this.patch({ lastError: null });
    this.targetDeviceId = device.id;
    this.reconnectAttempts = 0;
    try {
      await this.transport!.connect(device.id);
      settingsStore.rememberDevice(device.id, device.name);
      await this.logEvent('CONNECTED', `Connected to ${device.name}`);
    } catch (error) {
      this.patch({
        lastError: error instanceof TransportFailure ? error.message : String(error),
      });
    }
  }

  async connectToRemembered(): Promise<boolean> {
    const id = settingsStore.get().rememberedDeviceId;
    if (!id) return false;
    const transport = this.ensureBleTransport();
    if (!(transport instanceof WebBluetoothTransport)) return false;
    this.targetDeviceId = id;
    const ok = await transport.reconnectKnown(id);
    if (!ok) {
      this.pushRaw(
        '· Silent reconnect unavailable. The browser requires a user gesture to ' +
          'pick the device.',
      );
      this.patch({ rawLog: [...this.rawLines] });
    }
    return ok;
  }

  async startSimulator(): Promise<void> {
    this.patch({ lastError: null });
    this.attach(new SimulatedTransport());
    await this.transport!.connect(SimulatedTransport.DEMO_DEVICE_ID);
  }

  async disconnect(): Promise<void> {
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.targetDeviceId = null;
    await this.flushPending(true);
    await this.transport?.disconnect();
    await this.logEvent('DISCONNECTED', 'Disconnected by user');
    this.liveWindow = [];
    this.patch({
      latest: null,
      status: 'UNKNOWN',
      stale: false,
      liveSeries: Array.from({ length: SENSOR_COUNT }, () => []),
      historyOnly: false,
    });
  }

  private scheduleReconnect(): void {
    if (!settingsStore.get().autoReconnect) return;
    if (!this.targetDeviceId || this.snapshot.usingSimulator) return;
    if (this.reconnectTimer) return;

    const backoff = [1, 2, 4, 8, 15, 30];
    const seconds = backoff[Math.min(this.reconnectAttempts, backoff.length - 1)]!;
    this.reconnectAttempts++;

    this.pushRaw(`· Reconnecting in ${seconds}s (attempt ${this.reconnectAttempts})`);
    this.patch({ rawLog: [...this.rawLines] });

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (grantsAccess(this.snapshot.linkState)) return;
      const transport = this.transport;
      if (transport instanceof WebBluetoothTransport && this.targetDeviceId) {
        void transport.reconnectKnown(this.targetDeviceId).then((ok) => {
          if (!ok) this.scheduleReconnect();
        });
      }
    }, seconds * 1000);
  }

  enterHistoryOnly(): void {
    this.patch({ historyOnly: true });
  }

  // ---------------------------------------------------------------------------
  // Line handling
  // ---------------------------------------------------------------------------

  private onLine(line: string): void {
    this.pushRaw(line);
    const packet = parseLine(line);
    if (!packet) return;

    switch (packet.kind) {
      case 'telemetry':
        this.onTelemetry(packet);
        break;

      case 'config': {
        this.transport?.markReady();
        const incompatible = packet.protocolVersion !== PROTOCOL_VERSION;
        this.patch({
          config: packet,
          rawLog: [...this.rawLines],
          lastError: incompatible
            ? `Firmware speaks protocol v${packet.protocolVersion}, the app expects ` +
              `v${PROTOCOL_VERSION}. Re-flash LeakMonitor.ino.`
            : this.snapshot.lastError,
        });
        break;
      }

      case 'baselineRow':
        this.baselineDraft.push(packet);
        break;

      case 'baselineEnd': {
        const rows = [...this.baselineDraft];
        this.baselineDraft = [];
        this.patch({ baseline: rows });
        const id = this.snapshot.connectedDevice?.id;
        if (id && this.db) void this.db.putBaseline(id, rows).catch(() => undefined);
        break;
      }

      case 'calibration':
        if (packet.phase === 'done') {
          void this.logEvent(
            'CALIBRATION',
            `Calibrated: bias ${packet.meanBalanceLpm.toFixed(3)} L/min at ` +
              `${packet.meanInletLpm.toFixed(2)} L/min over ${packet.sampleCount} samples`,
          );
          void this.send(Command.hello);
        }
        this.patch({
          calibration: packet,
          lastError:
            packet.phase === 'failed'
              ? `Calibration failed: ${packet.reason}`
              : this.snapshot.lastError,
        });
        break;

      case 'ack':
        this.patch({
          rawLog: [...this.rawLines],
          lastError: packet.ok
            ? this.snapshot.lastError
            : `Device rejected ${packet.command}: ${packet.detail}`,
        });
        break;

      case 'log':
        this.patch({ rawLog: [...this.rawLines] });
        break;

      case 'unknown':
        this.pushRaw(`! ${packet.reason}`);
        this.patch({ rawLog: [...this.rawLines] });
        break;
    }
  }

  private onTelemetry(telemetry: Telemetry): void {
    this.transport?.markReady();
    this.lastTelemetryAt = Date.now();
    this.reconnectAttempts = 0;

    this.liveWindow.push(telemetry);
    if (this.liveWindow.length > LIVE_WINDOW) {
      this.liveWindow = this.liveWindow.slice(-LIVE_WINDOW);
    }

    this.handleStatusTransition(telemetry);
    this.accumulate(telemetry);

    this.patch({
      latest: telemetry,
      status: telemetry.status,
      stale: false,
      secondsSinceLastSample: 0,
      liveSeries: Array.from({ length: SENSOR_COUNT }, (_, i) =>
        this.liveWindow.map((t) => t.flowLpm[i] ?? 0),
      ),
      rawLog: [...this.rawLines],
      connectedDevice: this.transport?.connectedDevice ?? null,
    });
  }

  private pushRaw(line: string): void {
    this.rawLines.push(line);
    if (this.rawLines.length > RAW_LOG) this.rawLines = this.rawLines.slice(-RAW_LOG);
  }

  // ---------------------------------------------------------------------------
  // Alarms
  // ---------------------------------------------------------------------------

  private handleStatusTransition(telemetry: Telemetry): void {
    const previous = this.lastStatus;
    const current = telemetry.status;
    if (previous === current) return;
    this.lastStatus = current;

    const settings = settingsStore.get();

    if (current === 'LEAK') {
      this.patch({ alarmAcknowledged: false });
      void this.logEvent(
        'LEAK_RAISED',
        `Leak confirmed — losing ${telemetry.balanceLpm.toFixed(2)} L/min against a ` +
          `${telemetry.thresholdLpm.toFixed(2)} L/min threshold`,
        telemetry.balanceLpm,
        telemetry.thresholdLpm,
      );
      if (settings.alertOnLeak) this.fireAlert(true);
    } else if (current === 'FAULT') {
      this.patch({ alarmAcknowledged: false });
      void this.logEvent(
        'FAULT_RAISED',
        'Sensor fault — the inlet and outlet readings are inconsistent',
        telemetry.balanceLpm,
        telemetry.thresholdLpm,
      );
      if (settings.alertOnFault) this.fireAlert(true);
    } else if (current === 'WATCH') {
      if (settings.alertOnWatch) this.fireAlert(false);
    } else if (current === 'OK' || current === 'IDLE') {
      if (previous === 'LEAK') {
        void this.logEvent('LEAK_CLEARED', 'Leak cleared — balance back in range');
      } else if (previous === 'FAULT') {
        void this.logEvent('FAULT_CLEARED', 'Sensor fault cleared');
      }
      this.patch({ alarmAcknowledged: false });
    }
  }

  private fireAlert(heavy: boolean): void {
    const settings = settingsStore.get();
    if (navigator.vibrate) {
      navigator.vibrate(heavy ? [120, 60, 120] : 30);
    }
    if (heavy && settings.audibleAlarm) {
      // A short synthesised beep avoids shipping an audio asset.
      try {
        const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
        if (!Ctor) return;
        const ctx = new Ctor();
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.frequency.value = 880;
        gain.gain.value = 0.08;
        osc.connect(gain).connect(ctx.destination);
        osc.start();
        setTimeout(() => {
          osc.stop();
          void ctx.close();
        }, 260);
      } catch {
        // Autoplay policy may block this until the user interacts. Non-fatal.
      }
    }
  }

  acknowledgeAlarm(): void {
    this.patch({ alarmAcknowledged: true });
  }

  private checkStaleness(): void {
    if (!grantsAccess(this.snapshot.linkState)) return;
    if (this.lastTelemetryAt === null) return;
    const gone = Date.now() - this.lastTelemetryAt;
    const stale = gone > STALE_AFTER_MS;
    if (stale !== this.snapshot.stale || stale) {
      if (stale && !this.snapshot.stale) {
        this.pushRaw(`! No telemetry for ${Math.round(gone / 1000)}s`);
      }
      this.patch({
        stale,
        secondsSinceLastSample: Math.round(gone / 1000),
        rawLog: [...this.rawLines],
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  private accumulate(telemetry: Telemetry): void {
    this.pending.push(telemetry);
    const interval = loggingIntervalMs(settingsStore.get());
    if (this.lastPersistAt !== 0 && Date.now() - this.lastPersistAt < interval) return;
    void this.flushPending();
  }

  private async flushPending(force = false): Promise<void> {
    if (this.pending.length === 0 || !this.db) return;
    const batch = this.pending;
    this.pending = [];
    this.lastPersistAt = Date.now();

    try {
      await this.db.putReading(this.condense(batch));
    } catch (error) {
      this.pushRaw(`! DB write failed: ${String(error)}`);
      return;
    }
    if (force) await this.refreshAggregates();
  }

  /**
   * Collapses N one-second samples into one row: mean flow, latest cumulative
   * volume, worst status. `samples` preserves the weighting for the averages.
   */
  private condense(batch: Telemetry[]): ReadingRow {
    const n = batch.length;
    const sumFlow = [0, 0, 0];
    let sumBalance = 0;
    let sumExpected = 0;
    let sumThreshold = 0;

    const severity: Record<LeakStatus, number> = {
      UNKNOWN: 0,
      IDLE: 1,
      OK: 2,
      CAL: 3,
      WATCH: 4,
      FAULT: 5,
      LEAK: 6,
    };
    let worst: LeakStatus = 'IDLE';

    for (const t of batch) {
      for (let i = 0; i < 3; i++) sumFlow[i] = (sumFlow[i] ?? 0) + (t.flowLpm[i] ?? 0);
      sumBalance += t.balanceLpm;
      sumExpected += t.expectedLpm;
      sumThreshold += t.thresholdLpm;
      if (severity[t.status] > severity[worst]) worst = t.status;
    }

    const last = batch[batch.length - 1]!;
    return {
      ts: last.receivedAt,
      deviceId: this.snapshot.connectedDevice?.id ?? 'unknown',
      seq: last.seq,
      f: [(sumFlow[0] ?? 0) / n, (sumFlow[1] ?? 0) / n, (sumFlow[2] ?? 0) / n],
      v: [...last.volumeL],
      balance: sumBalance / n,
      expected: sumExpected / n,
      threshold: sumThreshold / n,
      status: worst,
      samples: n,
    };
  }

  private async refreshAggregates(): Promise<void> {
    if (this.aggregatesInFlight || !this.db) return;
    this.aggregatesInFlight = true;
    try {
      const aggregates = await this.db.computeAggregates();
      this.patch({ aggregates });
    } catch (error) {
      this.pushRaw(`! Aggregate query failed: ${String(error)}`);
    } finally {
      this.aggregatesInFlight = false;
    }
  }

  async refresh(): Promise<void> {
    await this.flushPending();
    await this.refreshAggregates();
  }

  private async logEvent(
    kind: EventKind,
    message: string,
    balance?: number,
    threshold?: number,
  ): Promise<void> {
    if (!this.db) return;
    const row: EventRow = {
      ts: Date.now(),
      kind,
      message,
      deviceId: this.snapshot.connectedDevice?.id ?? '',
    };
    if (balance !== undefined) row.balance = balance;
    if (threshold !== undefined) row.threshold = threshold;
    await this.db.putEvent(row).catch(() => undefined);
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  async send(command: string): Promise<boolean> {
    if (!this.transport) {
      this.patch({ lastError: 'Not connected.' });
      return false;
    }
    try {
      await this.transport.send(command);
      this.pushRaw(`> ${command}`);
      this.patch({ rawLog: [...this.rawLines] });
      return true;
    } catch (error) {
      this.patch({
        lastError: error instanceof TransportFailure ? error.message : String(error),
      });
      return false;
    }
  }

  async setTolerance(absLpm: number, pctFraction: number): Promise<void> {
    if (await this.send(Command.tolerance(absLpm, pctFraction))) {
      await this.logEvent(
        'CONFIG_CHANGED',
        `Tolerance set to ${absLpm.toFixed(2)} L/min / ${(pctFraction * 100).toFixed(0)}%`,
      );
      await this.send(Command.hello);
    }
  }

  async setNoiseFloor(lpm: number): Promise<void> {
    if (await this.send(Command.noiseFloor(lpm))) await this.send(Command.hello);
  }

  async setDebounce(confirm: number, clear: number, faultConfirm: number): Promise<void> {
    if (await this.send(Command.debounce(confirm, clear, faultConfirm))) {
      await this.send(Command.hello);
    }
  }

  async setPulsesPerLitre(sensorIndex: number, ppl: number): Promise<void> {
    if (await this.send(Command.pulsesPerLitre(sensorIndex, ppl))) {
      await this.send(Command.hello);
    }
  }

  async startCalibration(seconds: number): Promise<void> {
    this.patch({ calibration: null });
    await this.send(Command.calibrate(seconds));
  }

  cancelCalibration(): Promise<boolean> {
    return this.send(Command.cancel);
  }

  zeroTotals(): Promise<boolean> {
    return this.send(Command.zeroTotals);
  }

  restoreDeviceDefaults(): Promise<boolean> {
    return this.send(Command.restoreDefaults);
  }

  rebootDevice(): Promise<boolean> {
    return this.send(Command.reboot);
  }

  ping(): Promise<boolean> {
    return this.send(Command.ping);
  }

  forceScenario(scenario: string): void {
    const transport = this.transport;
    if (transport instanceof SimulatedTransport) {
      transport.forceScenario(scenario as Parameters<SimulatedTransport['forceScenario']>[0]);
    }
  }

  // ---------------------------------------------------------------------------
  // Data management
  // ---------------------------------------------------------------------------

  exportCsv(): Promise<string> {
    return this.db?.exportCsv() ?? Promise.resolve('');
  }

  events(limit = 100): Promise<EventRow[]> {
    return this.db?.events(limit) ?? Promise.resolve([]);
  }

  readingCount(): Promise<number> {
    return this.db?.count() ?? Promise.resolve(0);
  }

  databaseSizeBytes(): Promise<number> {
    return this.db?.estimatedSizeBytes() ?? Promise.resolve(0);
  }

  async clearHistory(): Promise<void> {
    this.pending = [];
    await this.db?.clearAll();
    await this.refreshAggregates();
  }

  async pruneNow(): Promise<number> {
    const retention = retentionMs(settingsStore.get());
    if (retention === null || !this.db) return 0;
    const removed = await this.db.prune(retention);
    await this.refreshAggregates();
    return removed;
  }
}

export const monitorStore = new MonitorStore();

export function useMonitor(): MonitorSnapshot {
  return useSyncExternalStore(
    monitorStore.subscribe,
    monitorStore.getSnapshot,
    monitorStore.getSnapshot,
  );
}

export { isAlarm };

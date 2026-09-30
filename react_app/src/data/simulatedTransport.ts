import type {
  DiscoveredDevice,
  LeakTransport,
  LinkState,
  TransportListeners,
} from './transport';

type Scenario = 'idle' | 'normal' | 'heavy' | 'branch' | 'leak' | 'fault';

/**
 * In-process stand-in for the HM-10 link.
 *
 * Re-implements the firmware's decision logic — noise floor, interpolated
 * tolerance envelope, debounce, hysteresis — and emits the same v2 protocol lines,
 * so every layer above the transport is exercised identically with or without
 * hardware. This is also the only way to run the app in a browser that has no Web
 * Bluetooth support.
 */
export class SimulatedTransport implements LeakTransport {
  readonly kind = 'Simulator';

  static readonly DEMO_DEVICE_ID = 'SIM:LEAKGUARD-DEMO';

  private static readonly DEVICE: DiscoveredDevice = {
    id: SimulatedTransport.DEMO_DEVICE_ID,
    name: 'LeakGuard Simulator',
    rssi: -48,
    advertisesLeakService: true,
  };

  // Mirrors of the firmware defaults.
  private static readonly BASELINE: readonly [number, number, number][] = [
    [0.0, 0.0, 0.2],
    [0.5, 0.05, 0.25],
    [1.0, 0.08, 0.3],
    [2.0, 0.12, 0.38],
    [4.0, 0.2, 0.55],
    [8.0, 0.35, 0.95],
    [15.0, 0.6, 1.6],
    [30.0, 1.1, 3.0],
  ];

  private static readonly NOISE_FLOOR = 0.12;
  private static readonly TOLERANCE_ABS = 0.2;
  private static readonly TOLERANCE_PCT = 0.08;
  private static readonly FAULT_MIN_FLOW = 0.5;
  private static readonly LEAK_CONFIRM = 8;
  private static readonly LEAK_CLEAR = 5;
  private static readonly FAULT_CONFIRM = 10;

  private listeners: TransportListeners | null = null;
  private currentState: LinkState = 'idle';
  private connected: DiscoveredDevice | null = null;
  private ticker: ReturnType<typeof setInterval> | null = null;
  private calTicker: ReturnType<typeof setInterval> | null = null;
  private disposed = false;

  private seq = 0;
  private uptimeMs = 0;
  private volume: [number, number, number] = [0, 0, 0];
  private breachStreak = 0;
  private cleanStreak = 0;
  private faultStreak = 0;
  private status = 'IDLE';

  private scenario: Scenario = 'idle';
  private scenarioTicks = 0;
  private leakSeverity = 0;

  get state(): LinkState {
    return this.currentState;
  }

  get connectedDevice(): DiscoveredDevice | null {
    return this.connected;
  }

  listen(listeners: TransportListeners): void {
    this.listeners = listeners;
    listeners.onState(this.currentState);
  }

  private setState(next: LinkState): void {
    if (this.disposed || this.currentState === next) return;
    this.currentState = next;
    this.listeners?.onState(next);
  }

  private emit(line: string): void {
    this.listeners?.onLine(line);
  }

  async isSupported(): Promise<boolean> {
    return true;
  }

  async startScan(): Promise<void> {
    this.setState('scanning');
    await new Promise((resolve) => setTimeout(resolve, 500));
    this.listeners?.onDiscoveries([SimulatedTransport.DEVICE]);
    this.setState('idle');
  }

  async stopScan(): Promise<void> {}

  async connect(): Promise<void> {
    this.setState('connecting');
    await new Promise((resolve) => setTimeout(resolve, 600));
    this.connected = SimulatedTransport.DEVICE;
    this.setState('handshaking');
    this.listeners?.onDiagnostic('Simulator attached — no hardware in use.');
    this.emit('L,LeakGuard simulator boot');
    this.sendHandshake();
    this.ticker = setInterval(() => this.tick(), 1000);
  }

  markReady(): void {
    this.setState('ready');
  }

  private sendHandshake(): void {
    this.emit(
      [
        'H',
        '2.0.0-sim',
        '2',
        '3',
        '1000',
        '450.0',
        '450.0',
        '450.0',
        SimulatedTransport.TOLERANCE_ABS.toFixed(3),
        SimulatedTransport.TOLERANCE_PCT.toFixed(4),
        SimulatedTransport.NOISE_FLOOR.toFixed(3),
        SimulatedTransport.FAULT_MIN_FLOW.toFixed(3),
        String(SimulatedTransport.LEAK_CONFIRM),
        String(SimulatedTransport.LEAK_CLEAR),
        String(SimulatedTransport.FAULT_CONFIRM),
        '0.0000',
      ].join(','),
    );
  }

  private sendBaseline(): void {
    SimulatedTransport.BASELINE.forEach((row, i) => {
      this.emit(`B,${i},${row[0].toFixed(2)},${row[1].toFixed(3)},${row[2].toFixed(3)}`);
    });
    this.emit(`B,END,${SimulatedTransport.BASELINE.length}`);
  }

  async send(command: string): Promise<void> {
    const verb = command.trim().toUpperCase().split(',')[0] ?? '';
    switch (verb) {
      case 'PING':
        this.emit('A,PING,OK,PONG');
        break;
      case 'HELLO':
      case 'CFG?':
        this.sendHandshake();
        break;
      case 'BASE?':
        this.sendBaseline();
        break;
      case 'ZERO':
        this.volume = [0, 0, 0];
        this.emit('A,ZERO,OK,totals cleared');
        break;
      case 'CAL':
        this.emit('A,CAL,OK,started');
        this.runFakeCalibration();
        break;
      case 'CANCEL':
        if (this.calTicker) clearInterval(this.calTicker);
        this.calTicker = null;
        this.status = 'IDLE';
        this.emit('A,CANCEL,OK,aborted');
        break;
      default:
        this.emit(`A,${verb},OK,simulated`);
    }
  }

  private runFakeCalibration(): void {
    this.status = 'CAL';
    let remaining = 12;
    if (this.calTicker) clearInterval(this.calTicker);
    this.calTicker = setInterval(() => {
      remaining--;
      this.emit(`C,RUN,${remaining},${12 - remaining},0.0412`);
      if (remaining <= 0) {
        if (this.calTicker) clearInterval(this.calTicker);
        this.calTicker = null;
        this.emit('C,DONE,0.0396,2.140,11');
        this.status = 'IDLE';
      }
    }, 1000);
  }

  /** Cycles through every UI state within a couple of minutes. */
  private advanceScenario(): void {
    this.scenarioTicks--;
    if (this.scenarioTicks > 0) return;

    const order: Record<Scenario, Scenario> = {
      idle: 'normal',
      normal: 'heavy',
      heavy: 'branch',
      branch: 'leak',
      leak: 'idle',
      fault: 'idle',
    };
    this.scenario = order[this.scenario];

    const lengths: Record<Scenario, number> = {
      idle: 20,
      normal: 35,
      heavy: 20,
      branch: 25,
      leak: 45,
      fault: 18,
    };
    this.scenarioTicks = lengths[this.scenario];

    if (this.scenario === 'leak') {
      this.leakSeverity = 0.6 + Math.random() * 1.4;
    }
  }

  private noise(magnitude: number): number {
    return (Math.random() - 0.5) * magnitude;
  }

  private tick(): void {
    if (this.disposed) return;
    this.advanceScenario();

    let inlet = 0;
    let outA = 0;
    let outB = 0;

    switch (this.scenario) {
      case 'idle':
        break;
      case 'normal':
        inlet = 2.2 + this.noise(0.3);
        outA = inlet * 0.52 + this.noise(0.16);
        outB = inlet - outA + this.noise(0.16);
        break;
      case 'heavy':
        inlet = 7.6 + this.noise(0.8);
        outA = inlet * 0.48 + this.noise(0.3);
        outB = inlet - outA + this.noise(0.3);
        break;
      case 'branch':
        // Only branch A open. The original firmware called this a disconnect; the
        // new logic must report OK.
        inlet = 1.6 + this.noise(0.24);
        outA = inlet + this.noise(0.2);
        outB = 0;
        break;
      case 'leak': {
        inlet = 3.4 + this.noise(0.3);
        const missing = this.leakSeverity;
        outA = (inlet - missing) * 0.5 + this.noise(0.16);
        outB = (inlet - missing) * 0.5 + this.noise(0.16);
        break;
      }
      case 'fault':
        inlet = 3.0 + this.noise(0.3);
        break;
    }

    const flow: [number, number, number] = [
      SimulatedTransport.applyNoiseFloor(Math.max(0, inlet)),
      SimulatedTransport.applyNoiseFloor(Math.max(0, outA)),
      SimulatedTransport.applyNoiseFloor(Math.max(0, outB)),
    ];

    for (let i = 0; i < 3; i++) {
      this.volume[i] += flow[i] / 60;
    }

    const out = flow[1] + flow[2];
    const balance = flow[0] - out;
    const { expected, threshold } = SimulatedTransport.envelope(flow[0]);

    this.evaluate(flow, out, balance, threshold);

    this.seq++;
    this.uptimeMs += 1000;

    this.emit(
      [
        'D',
        this.seq,
        this.uptimeMs,
        flow[0].toFixed(2),
        flow[1].toFixed(2),
        flow[2].toFixed(2),
        this.volume[0].toFixed(3),
        this.volume[1].toFixed(3),
        this.volume[2].toFixed(3),
        balance.toFixed(3),
        expected.toFixed(3),
        threshold.toFixed(3),
        this.status,
        this.breachStreak,
        this.faultStreak,
      ].join(','),
    );
  }

  private static applyNoiseFloor(value: number): number {
    return value < SimulatedTransport.NOISE_FLOOR ? 0 : value;
  }

  /** Same interpolation as `baselineEnvelope()` in the firmware. */
  private static envelope(inlet: number): { expected: number; threshold: number } {
    const table = SimulatedTransport.BASELINE;
    const first = table[0]!;
    const last = table[table.length - 1]!;

    let expected: number;
    let margin: number;

    if (inlet <= first[0]) {
      expected = first[1];
      margin = first[2];
    } else if (inlet >= last[0]) {
      expected = last[1];
      margin = last[2];
    } else {
      expected = last[1];
      margin = last[2];
      for (let i = 1; i < table.length; i++) {
        const hi = table[i]!;
        if (inlet <= hi[0]) {
          const lo = table[i - 1]!;
          const span = hi[0] - lo[0];
          const t = span > 0 ? (inlet - lo[0]) / span : 0;
          expected = lo[1] + t * (hi[1] - lo[1]);
          margin = lo[2] + t * (hi[2] - lo[2]);
          break;
        }
      }
    }

    let threshold = expected + margin;
    const pctBand = inlet * SimulatedTransport.TOLERANCE_PCT;
    if (SimulatedTransport.TOLERANCE_ABS > threshold) {
      threshold = SimulatedTransport.TOLERANCE_ABS;
    }
    if (pctBand > threshold) threshold = pctBand;
    return { expected, threshold };
  }

  private evaluate(
    flow: [number, number, number],
    out: number,
    balance: number,
    threshold: number,
  ): void {
    if (this.status === 'CAL') return;

    // Rule 0 — nothing detected. Never an alarm.
    if (flow[0] === 0 && flow[1] === 0 && flow[2] === 0) {
      this.breachStreak = 0;
      this.cleanStreak = 0;
      this.faultStreak = 0;
      this.status = 'IDLE';
      return;
    }

    // Rule 1 — implausible topology.
    const shapeA =
      flow[0] >= SimulatedTransport.FAULT_MIN_FLOW && flow[1] === 0 && flow[2] === 0;
    const shapeB = out >= SimulatedTransport.FAULT_MIN_FLOW && flow[0] === 0;
    if (shapeA || shapeB) {
      this.faultStreak++;
      if (this.faultStreak >= SimulatedTransport.FAULT_CONFIRM) {
        this.status = 'FAULT';
        this.breachStreak = 0;
        this.cleanStreak = 0;
        return;
      }
      if (this.status !== 'LEAK') this.status = 'WATCH';
      return;
    }
    this.faultStreak = 0;

    // Rule 2 — envelope. Only the "water going missing" direction escalates.
    const absBal = Math.abs(balance);
    if (balance > 0 && absBal > threshold) {
      this.cleanStreak = 0;
      this.breachStreak++;
      if (this.breachStreak >= SimulatedTransport.LEAK_CONFIRM) {
        this.status = 'LEAK';
      } else if (this.status !== 'LEAK') {
        this.status = 'WATCH';
      }
      return;
    }
    if (balance < 0 && absBal > threshold) {
      this.breachStreak = 0;
      this.cleanStreak = 0;
      if (this.status !== 'LEAK') this.status = 'WATCH';
      return;
    }

    // Rule 3 — inside the envelope, clear with hysteresis.
    this.breachStreak = 0;
    this.cleanStreak++;
    if (this.status === 'LEAK' || this.status === 'FAULT') {
      if (this.cleanStreak >= SimulatedTransport.LEAK_CLEAR) this.status = 'OK';
    } else {
      this.status = 'OK';
    }
  }

  forceScenario(scenario: Scenario): void {
    this.scenario = scenario;
    this.scenarioTicks = 30;
    if (scenario === 'leak') this.leakSeverity = 1.4;
  }

  async disconnect(): Promise<void> {
    if (this.ticker) clearInterval(this.ticker);
    if (this.calTicker) clearInterval(this.calTicker);
    this.ticker = null;
    this.calTicker = null;
    this.connected = null;
    this.setState('idle');
  }

  async dispose(): Promise<void> {
    this.disposed = true;
    await this.disconnect();
    this.listeners = null;
  }
}

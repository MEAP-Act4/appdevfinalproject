// Temporary verification harness. Deleted after the run.
import { LineAssembler, parseLine, envelopeUsage } from './src/core/protocol.ts';
import { SimulatedTransport } from './src/data/simulatedTransport.ts';

let failures = 0;
function check(name: string, condition: boolean, detail = '') {
  if (condition) {
    console.log(`  PASS  ${name}`);
  } else {
    failures++;
    console.log(`  FAIL  ${name} ${detail}`);
  }
}

console.log('\n1. Telemetry decode');
const line =
  'D,412,412337,2.13,1.07,1.02,18.442,9.210,9.108,0.040,0.124,0.500,OK,0,0';
const packet = parseLine(line, 1000);
check('kind is telemetry', packet?.kind === 'telemetry');
if (packet?.kind === 'telemetry') {
  check('seq', packet.seq === 412);
  check('inlet', packet.flowLpm[0] === 2.13);
  check('outlets', packet.flowLpm[1] === 1.07 && packet.flowLpm[2] === 1.02);
  check('volumes', packet.volumeL[0] === 18.442);
  check('balance', packet.balanceLpm === 0.04);
  check('threshold', packet.thresholdLpm === 0.5);
  check('status', packet.status === 'OK');
  check('envelope usage 8%', Math.round(envelopeUsage(packet) * 100) === 8);
}

console.log('\n2. Handshake decode');
const hs = parseLine(
  'H,2.0.0,2,3,1000,450.0,450.0,450.0,0.200,0.0800,0.120,0.500,8,5,10,0.0000',
);
check('kind is config', hs?.kind === 'config');
if (hs?.kind === 'config') {
  check('protocol v2', hs.protocolVersion === 2);
  check('noise floor', hs.noiseFloorLpm === 0.12);
  check('tolerance pct', hs.tolerancePct === 0.08);
  check('leak confirm', hs.leakConfirmSamples === 8);
}

console.log('\n3. Fragmented reassembly (HM-10 20-byte notifications)');
const assembler = new LineAssembler();
const payload = `${line}\nA,PING,OK,PONG\nB,END,8\n`;
const bytes = new TextEncoder().encode(payload);
const collected: string[] = [];
for (let i = 0; i < bytes.length; i += 20) {
  collected.push(...assembler.addBytes(bytes.slice(i, i + 20)));
}
check('three lines recovered', collected.length === 3, `got ${collected.length}`);
check('first line intact', collected[0] === line);
check('ack intact', collected[1] === 'A,PING,OK,PONG');
check('baseline end intact', collected[2] === 'B,END,8');

console.log('\n4. Legacy v1 sketch output still decodes');
const legacy = parseLine('1.50,0.75,0.75,OK');
check('legacy is telemetry', legacy?.kind === 'telemetry');
if (legacy?.kind === 'telemetry') {
  check('legacy balance is zero', Math.abs(legacy.balanceLpm) < 1e-9);
}
check(
  'legacy ERROR_DISCONNECT maps to FAULT',
  (() => {
    const p = parseLine('3.00,0.00,0.00,ERROR_DISCONNECT');
    return p?.kind === 'telemetry' && p.status === 'FAULT';
  })(),
);

console.log('\n5. Malformed input is contained, not thrown');
for (const bad of ['', '   ', 'D,1,2', 'garbage', 'D,a,b,c,d,e,f,g,h,i,j,k,l,m,n', ',,,,']) {
  const result = parseLine(bad);
  check(
    `"${bad}" handled`,
    result === null || result.kind === 'unknown' || result.kind === 'telemetry',
  );
}

console.log('\n6. Tolerance envelope interpolation matches the dataset');
type EnvFn = (inlet: number) => { expected: number; threshold: number };
const envelope = (SimulatedTransport as unknown as { envelope: EnvFn }).envelope;
const cases: [number, number][] = [
  [0.0, 0.2],
  [0.5, 0.3],
  [1.0, 0.38],
  [2.0, 0.5],
  [4.0, 0.75],
  [8.0, 1.3],
  [15.0, 2.2],
];
for (const [inlet, expectedThreshold] of cases) {
  const { threshold } = envelope(inlet);
  check(
    `inlet ${inlet} -> threshold ${expectedThreshold}`,
    Math.abs(threshold - expectedThreshold) < 1e-6,
    `got ${threshold.toFixed(4)}`,
  );
}
const mid = envelope(3.0);
check(
  'interpolates between rows (2.0 and 4.0)',
  mid.threshold > 0.5 && mid.threshold < 0.75,
  `got ${mid.threshold.toFixed(4)}`,
);
const high = envelope(40);
check('clamps above the last row', Math.abs(high.threshold - 4.1) < 1e-6, `got ${high.threshold}`);

console.log('\n7. Decision logic: the false-alarm cases from the original sketch');
type EvalFn = (
  flow: [number, number, number],
  out: number,
  balance: number,
  threshold: number,
) => void;
interface Probe {
  status: string;
  breachStreak: number;
  faultStreak: number;
  cleanStreak: number;
  evaluate: EvalFn;
}
function makeProbe(): Probe {
  const instance = new SimulatedTransport() as unknown as Probe;
  return instance;
}
function feed(probe: Probe, flow: [number, number, number], ticks: number) {
  for (let i = 0; i < ticks; i++) {
    const out = flow[1] + flow[2];
    const balance = flow[0] - out;
    const { threshold } = envelope(flow[0]);
    probe.evaluate(flow, out, balance, threshold);
  }
}

// a) Nothing detected must never alarm.
const idle = makeProbe();
feed(idle, [0, 0, 0], 120);
check('all-zero for 120s stays IDLE', idle.status === 'IDLE', `got ${idle.status}`);

// b) One branch closed is normal operation, not a disconnect.
const oneBranch = makeProbe();
feed(oneBranch, [1.6, 1.6, 0], 60);
check(
  'only outlet A open reports OK (was ERROR_DISCONNECT in v1)',
  oneBranch.status === 'OK',
  `got ${oneBranch.status}`,
);

// c) Quantisation-scale imbalance stays inside the envelope.
const noisy = makeProbe();
feed(noisy, [2.0, 1.1, 0.75], 60); // balance 0.15, threshold 0.50
check('0.15 L/min imbalance at 2 L/min stays OK', noisy.status === 'OK', `got ${noisy.status}`);

// d) A single transient breach does not latch an alarm.
const transient = makeProbe();
feed(transient, [2.0, 1.0, 1.0], 20); // settle into OK
feed(transient, [2.0, 0.6, 0.6], 3); // balance 0.8 > 0.5, but only 3s
check(
  '3s breach reports WATCH, not LEAK',
  transient.status === 'WATCH',
  `got ${transient.status}`,
);

// e) A sustained breach does latch.
const real = makeProbe();
feed(real, [2.0, 1.0, 1.0], 20);
feed(real, [2.0, 0.6, 0.6], 10); // 10s > leakConfirm 8
check('10s breach latches LEAK', real.status === 'LEAK', `got ${real.status}`);

// f) Hysteresis: it clears only after enough clean samples.
feed(real, [2.0, 1.0, 1.0], 2);
check('2s clean keeps LEAK latched', real.status === 'LEAK', `got ${real.status}`);
feed(real, [2.0, 1.0, 1.0], 5);
check('7s clean clears to OK', real.status === 'OK', `got ${real.status}`);

// g) Genuine wiring fault is still caught, after debounce.
const fault = makeProbe();
feed(fault, [3.0, 0, 0], 5);
check('5s of dead outlets is WATCH only', fault.status === 'WATCH', `got ${fault.status}`);
feed(fault, [3.0, 0, 0], 10);
check('15s of dead outlets reports FAULT', fault.status === 'FAULT', `got ${fault.status}`);

// h) Dribble below the fault gate never reports a fault.
const dribble = makeProbe();
feed(dribble, [0.3, 0, 0], 120);
check(
  '0.3 L/min inlet with dead outlets never faults',
  dribble.status !== 'FAULT',
  `got ${dribble.status}`,
);

// i) Outlets over-reading is a calibration issue, not a leak.
const overRead = makeProbe();
feed(overRead, [2.0, 1.6, 1.6], 60); // balance -1.2
check(
  'negative balance never escalates past WATCH',
  overRead.status === 'WATCH',
  `got ${overRead.status}`,
);

console.log(
  `\n${failures === 0 ? 'ALL CHECKS PASSED' : `${failures} CHECK(S) FAILED`}\n`,
);
process.exit(failures === 0 ? 0 : 1);

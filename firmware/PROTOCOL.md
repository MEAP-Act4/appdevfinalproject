# LeakGuard Link Protocol v2

Plain ASCII, newline-terminated lines over the HM-10 serial bridge at **9600 baud**.
Every line starts with a single-character type tag followed by comma-separated fields.
Both the Flutter client and the React client implement this exact contract
(`lib/core/protocol/leak_protocol.dart` and `src/core/protocol.ts`).

BLE plumbing for the HM-10 (CC2541 transparent serial):

| Item | UUID |
|---|---|
| Service | `0000ffe0-0000-1000-8000-00805f9b34fb` |
| Characteristic (notify + write) | `0000ffe1-0000-1000-8000-00805f9b34fb` |

The HM-10 fragments at 20 bytes per notification, so clients **must** buffer
incoming bytes and split on `\n` rather than assuming one packet is one line.

---

## Device → App

### `D` — Telemetry (1 Hz)

```
D,<seq>,<uptimeMs>,<f1>,<f2>,<f3>,<v1>,<v2>,<v3>,<balance>,<expected>,<threshold>,<status>,<breachStreak>,<faultStreak>
```

| Field | Unit | Meaning |
|---|---|---|
| `seq` | — | Monotonic sample counter since boot |
| `uptimeMs` | ms | `millis()` at sample time |
| `f1 f2 f3` | L/min | Conditioned flow: inlet, outlet A, outlet B. Exactly `0.00` when below the noise floor |
| `v1 v2 v3` | L | Cumulative volume since last `ZERO` |
| `balance` | L/min | Signed `f1 - (f2 + f3)`. Positive = water going missing |
| `expected` | L/min | Baseline-table expected residual at this inlet flow, incl. learned bias |
| `threshold` | L/min | Alarm threshold at this inlet flow (`expected + margin`, floored by `toleranceAbs` and `inlet * tolerancePct`) |
| `status` | enum | `IDLE` `OK` `WATCH` `LEAK` `FAULT` `CAL` |
| `breachStreak` | samples | Consecutive out-of-envelope samples so far |
| `faultStreak` | samples | Consecutive implausible-shape samples so far |

Example:

```
D,412,412337,2.13,1.07,1.02,18.442,9.210,9.108,0.040,0.124,0.500,OK,0,0
```

### `H` — Handshake / configuration dump

Sent once at boot and in response to `HELLO` or `CFG?`.

```
H,<fwVersion>,<protoVersion>,<sensorCount>,<sampleIntervalMs>,<ppl1>,<ppl2>,<ppl3>,<toleranceAbs>,<tolerancePct>,<noiseFloor>,<faultMinFlow>,<leakConfirm>,<leakClear>,<faultConfirm>,<learnedBias>
```

### `B` — Baseline dataset rows

Sent in response to `BASE?`, one row per operating point, terminated by a sentinel.

```
B,<index>,<inletLpm>,<expectedBalance>,<marginLpm>
B,END,<rowCount>
```

### `C` — Calibration progress

```
C,RUN,<secondsRemaining>,<samplesCollected>,<runningMeanBalance>
C,DONE,<learnedBias>,<meanInletLpm>,<sampleCount>
C,FAIL,<reason>
```

### `A` — Command acknowledgement

```
A,<command>,OK,<detail>
A,<command>,ERR,<reason>
```

### `L` — Free-form log line

```
L,<text>
```

---

## App → Device

Terminate every command with `\n` (a `;` is also accepted as a terminator).

| Command | Effect |
|---|---|
| `PING` | Liveness check, replies `A,PING,OK,PONG` |
| `HELLO` / `CFG?` | Re-send the `H` line |
| `BASE?` | Dump the baseline dataset as `B` lines |
| `K,<1..3>,<pulsesPerLitre>` | Set a sensor's K factor (50–5000). YF-S201 nominal = 450 |
| `TOL,<absLpm>,<pctFraction>` | Set the absolute and proportional margin floors (≤10 L/min, ≤0.75) |
| `NF,<lpm>` | Set the noise floor (≤5 L/min) |
| `DB,<leakConfirm>,<leakClear>,<faultConfirm>` | Set debounce sample counts (1–120 each) |
| `ZERO` | Reset the cumulative volume totals |
| `CAL,<seconds>` | Start an on-site baseline learn (10–300 s) |
| `CANCEL` | Abort a calibration run |
| `DEFAULTS` | Restore factory config and re-save to EEPROM |
| `REBOOT` | Watchdog reset |

All setters persist to EEPROM immediately (magic + CRC16/CCITT guarded), so an
installer's calibration survives power cycles.

---

## Why the alarm logic looks the way it does

### The false-positive problem

A hall-effect flow sensor emits discrete pulses. Over a 1-second window the
count is quantised, so each sensor carries roughly ±1 pulse of uncertainty:

```
YF-S201: 450 pulses per litre  ->  F(Hz) = 7.5 * Q(L/min)
1 pulse of error over 1 s      =  0.133 L/min per sensor
three sensors in the balance   ≈  0.40 L/min of pure noise
```

The original sketch compared that balance against a fixed `0.5` on a single
sample, which sits *inside* the noise band. It also declared a disconnect fault
the instant one outlet read zero, which is what happens every time you close a
tap. Hence the constant false alarms.

### The three defences

1. **Noise floor** (`noiseFloorLpm`, default 0.12 L/min). Anything under it is
   reported as a hard `0.00`. When all three channels are zero the firmware
   returns `IDLE` and resets every streak counter, so *nothing detected* can
   never produce a leak or a fault verdict.

2. **Calibrated envelope** (`BASELINE_TABLE` in the firmware). Instead of one
   constant, the allowed error is interpolated from a dataset of standardized
   operating points:

   | Inlet L/min | Expected residual | Margin | Alarm threshold |
   |---:|---:|---:|---:|
   | 0.00 | 0.00 | 0.20 | 0.20 |
   | 0.50 | 0.05 | 0.25 | 0.30 |
   | 1.00 | 0.08 | 0.30 | 0.38 |
   | 2.00 | 0.12 | 0.38 | 0.50 |
   | 4.00 | 0.20 | 0.55 | 0.75 |
   | 8.00 | 0.35 | 0.95 | 1.30 |
   | 15.00 | 0.60 | 1.60 | 2.20 |
   | 30.00 | 1.10 | 3.00 | 4.10 |

   The effective threshold is the most forgiving of the interpolated table
   value, the absolute floor `toleranceAbs`, and the proportional band
   `inlet * tolerancePct`. `CAL` adds a site-measured `learnedBias` on top.

3. **Debounce and hysteresis**. A breach must persist for `leakConfirmSamples`
   (default 8 ≈ 8 s) before `LEAK` is announced; in between the status is
   `WATCH`, which the UI shows as a soft advisory rather than an alarm. Once
   latched, `LEAK` only clears after `leakClearSamples` consecutive clean
   samples. Faults need `faultConfirmSamples` (default 10) and are additionally
   gated on `faultMinFlowLpm`, so a dribble is never enough evidence.

Signed balance also matters: only the *positive* direction (inlet exceeds the
sum of the outlets, i.e. water going missing) can escalate to `LEAK`. The
opposite sign means the outlet sensors are over-reading, which is a calibration
problem, so it stays at `WATCH` and asks the installer to run `CAL`.

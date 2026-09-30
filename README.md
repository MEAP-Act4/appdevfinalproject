# LeakGuard — Smart Water Leak Monitoring

Three hall-effect flow sensors on an Arduino Uno compare what goes *into* a
manifold against what comes *out* of its two branches. A sustained mismatch means
water is going somewhere it should not. An HM-10 Bluetooth module streams the
readings to a mobile app.

```
                 ┌──────────────┐
    supply ─────▶│  Sensor 1    │────┬──────────────▶ ┌──────────┐ ── Outlet A
                 │  MAIN INLET  │    │   Sensor 2 ───▶│ manifold │
                 └──────────────┘    └───Sensor 3 ───▶└──────────┘ ── Outlet B

    balance = inlet − (outletA + outletB)      sustained positive balance = leak
```

| Folder | What it is |
|---|---|
| `firmware/LeakMonitor/LeakMonitor.ino` | Arduino Uno firmware. Calibration dataset, alarm logic, BLE protocol, EEPROM config. |
| `firmware/PROTOCOL.md` | The wire protocol both apps implement. Read this first. |
| `flutter_app/` | The production mobile app (Flutter/Dart, Android + iOS). |
| `react_app/` | A second client in React/TypeScript over Web Bluetooth, used for testing. |

---

## 1. The problem this fixes

The original sketch raised a leak whenever `|inlet − (outA + outB)| > 0.5` on a
**single** one-second sample, and raised a disconnect error the moment one outlet
read zero. In a real installation that fires constantly:

- A hall sensor emits discrete pulses. Over a 1 s window each channel carries
  roughly ±1 pulse of uncertainty, which on a YF-S201 is **±0.133 L/min**. Three
  sensors stack to about **0.4 L/min of pure noise**, so a fixed `0.5` threshold
  sits inside the noise band.
- One outlet reading zero is normal. It means a tap is closed.
- Valves opening and closing unbalance the manifold for a second or two.

The firmware now defends against all three:

**1. Noise floor.** Anything under `noiseFloorLpm` (default 0.12 L/min) is
reported as a hard `0.00`. When all three channels are zero the status is `IDLE`
and every streak counter resets — *nothing detected can never produce an alarm.*

**2. A calibrated dataset instead of one constant.** `BASELINE_TABLE` in the
firmware stores standardized operating points with the balance error a healthy rig
is *expected* to show and the margin of error allowed at that point. The threshold
is interpolated between rows:

| Inlet L/min | Expected residual | Margin | Alarm threshold |
|---:|---:|---:|---:|
| 0.00 | 0.00 | 0.20 | **0.20** |
| 0.50 | 0.05 | 0.25 | **0.30** |
| 1.00 | 0.08 | 0.30 | **0.38** |
| 2.00 | 0.12 | 0.38 | **0.50** |
| 4.00 | 0.20 | 0.55 | **0.75** |
| 8.00 | 0.35 | 0.95 | **1.30** |
| 15.00 | 0.60 | 1.60 | **2.20** |
| 30.00 | 1.10 | 3.00 | **4.10** |

The effective threshold is the most forgiving of the interpolated table value, the
absolute floor `toleranceAbs`, and the proportional band `inlet × tolerancePct`.
A `CAL` run adds a site-measured `learnedBias` on top.

**3. Debounce and hysteresis.** A breach must persist for `leakConfirmSamples`
(default 8 ≈ 8 s) before `LEAK` is announced. In between the status is `WATCH`,
which the apps show as a soft advisory, not an alarm. Once latched, `LEAK` only
clears after `leakClearSamples` consecutive clean samples. Faults need
`faultConfirmSamples` (default 10) *and* at least `faultMinFlowLpm` of flow, so a
dribble is never enough evidence.

Only the *positive* direction escalates. Outlets reading more than the inlet is a
calibration problem, so it stays at `WATCH` and prompts a recalibration.

### Status values

| Status | Meaning | Alarm? |
|---|---|---|
| `IDLE` | No flow on any channel | No — this is healthy standby |
| `OK` | Flowing, balance inside the envelope | No |
| `WATCH` | Outside the envelope, not yet confirmed | No, advisory |
| `LEAK` | Confirmed sustained imbalance | Yes |
| `FAULT` | Physically impossible readings — wiring or dead sensor | Yes |
| `CAL` | Baseline calibration in progress | No |

---

## 2. Wiring

| Signal | Pin | Notes |
|---|---|---|
| Sensor 1 — main inlet | `D2` | Hardware interrupt INT0 |
| Sensor 2 — outlet A | `D3` | Hardware interrupt INT1 |
| Sensor 3 — outlet B | `D4` | Pin-change interrupt PCINT20 |
| Heartbeat LED | `D8` | Blinks slowly when idle, solid when flowing |
| Alarm LED | `D9` | Fast blink on `LEAK`, solid on `FAULT` |
| HM-10 TX | → `D0` (RX) | |
| HM-10 RX | ← `D1` (TX) | **Through a 2 kΩ / 1 kΩ divider** — Uno TX is 5 V, HM-10 RX is 3.3 V |

All three sensors: red → 5 V, black → GND, yellow → the signal pin above.

> The HM-10 shares the hardware UART with USB serial. Unplug USB before relying on
> the Bluetooth link, or the two will fight over the same pins.

---

## 3. Flash the firmware

1. Open `firmware/LeakMonitor/LeakMonitor.ino` in the Arduino IDE (or
   `arduino-cli compile --fqbn arduino:avr:uno firmware/LeakMonitor`).
2. Board: **Arduino Uno**. No extra libraries needed — `EEPROM` and `avr/wdt` ship
   with the AVR core.
3. Upload, then open Serial Monitor at **9600 baud**. You should see:

```
L,LeakGuard boot
H,2.0.0,2,3,1000,450.0,450.0,450.0,0.200,0.0800,0.120,0.500,8,5,10,0.0000
D,1,1000,0.00,0.00,0.00,0.000,0.000,0.000,0.000,0.000,0.200,IDLE,0,0
```

The HM-10 defaults to 9600 baud and pairing code `000000`. If yours is at 115200,
either send `AT+BAUD4` to move it to 9600, or change `Serial.begin()` to match.

### Calibrate on site (do this once, after install)

With no leak present, open both outlet branches, hold a steady flow above
0.5 L/min, and run the calibration from the app (Settings → Leak detection → Run
baseline calibration), or send `CAL,30` over serial. The board averages the signed
balance error over the window and stores it in EEPROM as `learnedBias`. This is
what lets you tighten the tolerance without generating false alarms.

---

## 4. Flutter app

```bash
cd flutter_app
flutter create . --platforms=android,ios --project-name leakguard   # once
flutter pub get
flutter run
```

`flutter create .` generates the native host projects without touching `lib/` or
`pubspec.yaml`. **You must then add the Bluetooth permission entries** —
see `flutter_app/PLATFORM_SETUP.md`. Scanning silently fails without them.

### Structure

```
lib/
├── main.dart                     bootstrap: settings, database, controller
├── app.dart                      MaterialApp, theme switching, text-scale clamp
├── core/
│   ├── theme/design_tokens.dart  every colour, radius, spacing and duration
│   ├── theme/app_theme.dart      Material 3 themes + AppPalette extension
│   ├── protocol/leak_protocol.dart  protocol v2 decoder and command builders
│   └── units/measurement_units.dart unit conversion and formatting
├── data/
│   ├── ble/hm10_transport.dart      real BLE link (flutter_blue_plus)
│   ├── ble/simulated_transport.dart in-process fake board
│   ├── db/app_database.dart         sqflite time series + SQL aggregates
│   ├── models/                      reading, event and aggregate types
│   └── settings/                    AppSettings + SharedPreferences controller
├── state/monitor_controller.dart    the single source of truth
└── ui/
    ├── root_view.dart            gate ⇄ dashboard, animated
    ├── gate/                     the connection warning screen
    ├── shell/app_shell.dart      the two bottom tabs
    ├── sensors/                  tab 1: the sensor carousel
    ├── settings/                 tab 2: settings + calibration dialog
    ├── diagnostics/              link health, event log, raw traffic
    └── common/                   cards, metrics, charts, banners, motion
```

### What the app does

**Connection gate.** Nothing is reachable until the board is talking. The gate
explains the prerequisite, shows a three-item preflight checklist, scans, connects,
and hands off the moment the first valid telemetry line decodes. It is modelled as
*state*, not a route, so losing the link anywhere in the app returns here with no
navigation stack to unwind. Two escape hatches: a clearly-labelled **demo data**
mode backed by the simulator, and an optional history-only mode if you turn the
gate off in settings.

**Tab 1 — Sensors.** One dedicated page per sensor. Tap the chevrons either side of
the sensor name (or the dots, or swipe) to move between all three without leaving
the tab. Each page shows:

- the live reading, animated, at 1 Hz
- a 3-minute area sparkline
- **average flow per day, per 3 days and per week**, each with a coverage bar so a
  "weekly" figure built from two hours of data says so. Tap one to expand total
  volume, peak, and mean-while-running.
- the tolerance envelope gauge (inlet page) or share-of-supply (outlet pages)
- cumulative volume: board total, last 24 h, last 7 days, plus a day-vs-week drift
  note that acts as an early signal for a slow developing leak
- a plain-language breakdown of why the current reading is *not* an alarm

**Tab 2 — Settings.** Split between app-side and device-side:

| Group | Contains |
|---|---|
| Appearance | Dark / light / follow system, reduce motion, tolerance detail toggle |
| Units | Flow unit (L/min, L/h, L/s, US & imperial gal/min, m³/h), volume unit, auto-pairing, live preview |
| Sensor labels | Rename each channel |
| Alerts | Leak / fault / early-warning toggles, haptics, alert sound |
| Leak detection *(writes to the Arduino, EEPROM-backed)* | Run calibration, noise floor, minimum margin of error, proportional margin, confirmation time, clear time, per-sensor K factors, restore device defaults |
| Connection | Status, auto-reconnect, connection-gate toggle, forget device, disconnect, reboot board |
| Data & storage | Logging interval, retention, auto-prune, row count and size, CSV export, prune now, clear history |
| About | App version, firmware version, protocol compatibility, reset app settings |

Unit changes are display-only. Everything is stored in L/min and litres, so
switching to gallons never rewrites history.

**Database.** `sqflite`, with a `readings` time series, an `events` log, a cached
device profile and a cached copy of the firmware's calibration dataset. The board
streams at 1 Hz; the logging interval controls how often a row is written, and each
row records how many samples it covers so the weighted SQL averages stay correct at
any setting. All aggregation happens in SQL — pulling a week of rows into Dart to
average them would be hundreds of thousands of rows.

**Animation.** One motion token set (`Motion` in `design_tokens.dart`) drives
everything: staggered card entrances, tweened numeric readouts, cross-faded state
swaps, the sonar rings on the gate, the tab slide, and the gate-to-dashboard
release. A **reduce motion** setting collapses ambient animation while keeping
functional feedback.

---

## 5. React app (test client)

```bash
cd react_app
npm install
npm run dev      # http://localhost:5173
```

Same protocol, same design tokens, same two-tab layout, same three averaging
windows — a second independent reader of the same firmware, so a disagreement
between the two clients points at a real bug.

Differences, all forced by the browser:

- **Web Bluetooth needs a secure context.** `localhost` counts; serving to a phone
  over the LAN needs HTTPS or a tunnel.
- **There is no free-running scan.** `navigator.bluetooth.requestDevice` hands off
  to the browser's own chooser, so "scan" means "open the chooser".
- **Silent reconnect** only works for devices the origin was already granted, via
  `getDevices()`, and only in Chromium.
- Storage is **IndexedDB** instead of SQLite, so the aggregates are computed in a
  single cursor pass rather than in SQL.

In a browser without Web Bluetooth the gate says so and the demo path still works.

```
src/
├── core/protocol.ts              protocol v2 decoder (twin of the Dart one)
├── core/units.ts                 unit conversion and formatting
├── data/db.ts                    IndexedDB store + single-pass aggregates
├── data/webBluetoothTransport.ts real BLE link
├── data/simulatedTransport.ts    in-process fake board
├── state/monitorStore.ts         external store, twin of MonitorController
├── state/settingsStore.ts        localStorage-backed settings
├── screens/                      ConnectionGate, SensorsTab, SettingsTab
├── components/                   primitives, charts, diagnostics, calibration
└── styles/tokens.css             the WattVision tokens as CSS variables
```

---

## 6. Design system

Both clients implement the WattVision system from `DESIGN.md`: `#121212`
background, `#1E1E1E` cards with a 16 px radius, 20 px padding and a 1 px
`#2C2C2E` hairline, `#00E5FF` for data, `#FF453A` for alerts, `#32D74B` for normal,
Inter for text, JetBrains Mono for every metric, and spacing on an 8 px scale.
Charts are area charts with `#00E5FF → #30D158` gradients and `#2C2C2E` grid lines.
Alert boxes use the `#3A1C1C` fill with a 4 px left bar.

Two deliberate departures: the design doc is dark-only, but a dark-mode *setting*
was requested, so a light variant exists that darkens the neon accents for
contrast; and the 12-column desktop dashboard grid is restated as a single-column
mobile layout with the same spacing scale and card treatment.

---

## 7. Verification status

Verified on this machine:

- **Firmware compiles clean.** `arduino-cli 1.5.2-rc.1` with `arduino:avr` 1.8.8,
  `--warnings all`: zero errors, zero warnings. Sketch uses **11,318 of 32,256
  bytes of flash (35%)** and **611 of 2,048 bytes of RAM (29%)**, leaving 1,437
  bytes for locals — comfortable headroom on an ATmega328P.

  ```bash
  arduino-cli compile --fqbn arduino:avr:uno --warnings all firmware/LeakMonitor
  ```

  Compiling needs only the AVR core, not the board. Plug the Uno in whenever you
  are ready and run `arduino-cli upload -p COMx --fqbn arduino:avr:uno firmware/LeakMonitor`.

- React app: `npm run build` (TypeScript strict + Vite 8) compiles clean, and the
  production bundle serves with its assets resolving.

- A throwaway harness exercised the shared logic and passed 46 checks: telemetry and
  handshake decoding, reassembly of lines fragmented across 20-byte HM-10
  notifications, backward compatibility with the original sketch's output,
  malformed-input containment, the envelope interpolation against every dataset
  row, and the decision logic — all-zero input stays `IDLE` forever, a single
  closed branch reports `OK` rather than a disconnect, a 0.15 L/min imbalance at
  2 L/min stays `OK`, a 3 s breach is `WATCH` while a 10 s breach latches `LEAK`,
  hysteresis holds the latch for 2 s of clean data and releases at 7 s, a genuine
  dead-outlet fault is caught after 15 s, a 0.3 L/min dribble never faults, and a
  negative balance never escalates past `WATCH`.

**Not** verified here:

- The Flutter app was **not built or analysed** — Flutter and Dart are not
  installed on this machine. Run `flutter pub get && flutter analyze && flutter run`
  and expect to fix minor issues on first build.
- Neither client has been tested against real hardware.

### Why the sketch has a separate header

`firmware/LeakMonitor/leak_types.h` holds `SENSOR_COUNT`, `BaselinePoint`,
`Envelope`, `SystemStatus` and `Config`. They are not in the `.ino` on purpose.

The Arduino build step auto-generates a forward prototype for every function in a
sketch and injects those prototypes immediately before the first function
definition. Any type named in a function signature must therefore already be
visible at that injection point. Declaring `struct Envelope` partway down the
`.ino` is valid C++ but fails the Arduino preprocessor with
`'Envelope' does not name a type`, reported confusingly against the *definition*
line rather than the generated prototype. Putting the types in a header that the
sketch includes is the only placement guaranteed to come first.
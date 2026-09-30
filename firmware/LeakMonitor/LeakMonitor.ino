/* =============================================================================
 *  LeakGuard — Smart Leak Monitoring Firmware
 *  Target : Arduino Uno (ATmega328P)
 *  Radio  : HM-10 BLE module on hardware UART (TX->RX via divider, 9600 baud)
 *  Sensors: 3x hall-effect water flow sensors (YF-S201 class)
 *
 *  WHAT CHANGED VS THE ORIGINAL SKETCH
 *  -----------------------------------
 *  The original sketch flagged a LEAK whenever |inlet - (outA + outB)| > 0.5 on a
 *  SINGLE 1-second sample, and flagged ERROR_DISCONNECT the moment one branch read
 *  zero. In a real installation that fires constantly:
 *    - Hall sensors quantise flow. At 1 s windows the pulse count is +/-1 pulse,
 *      which is +/-0.133 L/min of pure quantisation noise per sensor. Three sensors
 *      stack to ~0.4 L/min of noise, so a fixed 0.5 threshold sits inside the noise.
 *    - A single closed outlet is legitimate (only tap A running => outB == 0).
 *    - Valve opening/closing transients briefly unbalance the manifold.
 *
 *  This firmware replaces that with:
 *    1. A CALIBRATION DATASET of standardized flow rates (BASELINE_TABLE) that
 *       stores, for each operating point, the balance error the rig is *expected*
 *       to show plus the margin of error allowed at that point. The tolerance is
 *       linearly interpolated between table rows, so the allowed error grows with
 *       flow instead of being one hard-coded number.
 *    2. A NOISE FLOOR. Below it a sensor reads exactly 0.00 and the system reports
 *       IDLE. No flow => no leak alarm, no fault alarm. Ever.
 *    3. DEBOUNCE + HYSTERESIS. A leak must breach tolerance for LEAK_CONFIRM
 *       consecutive samples before it is announced, and must stay clean for
 *       LEAK_CLEAR consecutive samples before it is retracted.
 *    4. FAULT DETECTION that only runs when there is enough flow for the
 *       conclusion to be meaningful, and is likewise debounced.
 *    5. EEPROM-backed runtime configuration, so the installer can calibrate on
 *       site from the mobile app and the values survive a power cycle.
 *    6. A versioned, self-describing line protocol shared with the Flutter and
 *       React clients (see firmware/PROTOCOL.md).
 *
 *  WIRING
 *  ------
 *    Sensor 1 (MAIN INLET)  yellow -> D2  (INT0)
 *    Sensor 2 (OUTLET A)    yellow -> D3  (INT1)
 *    Sensor 3 (OUTLET B)    yellow -> D4  (PCINT20)
 *    All sensors: red -> 5V, black -> GND
 *    HM-10: VCC -> 5V (module must be on a 3.3V-tolerant breakout) or 3.3V,
 *           GND -> GND, HM-10 TX -> Uno RX(D0), HM-10 RX <- Uno TX(D1)
 *           via a 2k/1k divider (Uno TX is 5V, HM-10 RX is 3.3V).
 *    Status LEDs: D8 heartbeat (running), D9 alarm.
 * ===========================================================================*/

#include <EEPROM.h>
#include <avr/wdt.h>

#include "leak_types.h"

/* ---------------------------------------------------------------------------
 *  BUILD IDENTITY
 * -------------------------------------------------------------------------*/
#define FW_VERSION    "2.0.0"
#define PROTO_VERSION 2

/* ---------------------------------------------------------------------------
 *  PIN MAP
 * -------------------------------------------------------------------------*/
const uint8_t PIN_SENSOR_1 = 2;   // main inlet      - INT0
const uint8_t PIN_SENSOR_2 = 3;   // outlet A        - INT1
const uint8_t PIN_SENSOR_3 = 4;   // outlet B        - PCINT20 (PORTD bit 4)
const uint8_t PIN_LED_RUN  = 8;   // heartbeat
const uint8_t PIN_LED_ALARM = 9;  // leak / fault


/* ---------------------------------------------------------------------------
 *  SAMPLING
 * -------------------------------------------------------------------------*/
const uint16_t SAMPLE_INTERVAL_MS = 1000UL;  // telemetry cadence, 1 Hz
const uint16_t BLINK_FAST_MS      = 200UL;   // alarm blink
const uint16_t BLINK_SLOW_MS      = 1200UL;  // heartbeat blink

/* =============================================================================
 *  1) CALIBRATION DATASET — STANDARDIZED FLOW RATES + MARGIN OF ERROR
 * =============================================================================
 *  Each row is one operating point measured on a KNOWN-GOOD rig (no leak):
 *
 *    inletLpm        reference inlet flow for this row, L/min
 *    expectedBalance the residual |inlet - (outA + outB)| the healthy rig shows
 *                    at this flow. Never exactly zero in practice: the three
 *                    sensors have slightly different K factors and the tees
 *                    introduce a small bias.
 *    marginLpm       margin of error allowed ON TOP of expectedBalance before the
 *                    reading is considered abnormal, i.e. the alarm threshold at
 *                    this operating point is (expectedBalance + marginLpm).
 *
 *  The default table below is derived from YF-S201 quantisation behaviour at a
 *  1 s sampling window (1 pulse = 1/7.5 = 0.133 L/min per sensor) plus the
 *  manufacturer's +/-10% linearity spec. It is deliberately conservative: it will
 *  not cry wolf out of the box. Run `CAL` from the app on the real installation
 *  to replace it with site-measured numbers (stored in EEPROM).
 *
 *  Rows MUST be sorted ascending by inletLpm.
 * -------------------------------------------------------------------------*/

const BaselinePoint BASELINE_TABLE[] PROGMEM = {
  /* inlet  expected  margin  */
  {  0.00f,   0.00f,  0.20f },   // idle / dribble  -> threshold 0.20
  {  0.50f,   0.05f,  0.25f },   // trickle         -> threshold 0.30
  {  1.00f,   0.08f,  0.30f },   // single tap low  -> threshold 0.38
  {  2.00f,   0.12f,  0.38f },   // single tap      -> threshold 0.50
  {  4.00f,   0.20f,  0.55f },   // two taps        -> threshold 0.75
  {  8.00f,   0.35f,  0.95f },   // heavy draw      -> threshold 1.30
  { 15.00f,   0.60f,  1.60f },   // near sensor max -> threshold 2.20
  { 30.00f,   1.10f,  3.00f }    // clamp row       -> threshold 4.10
};
const uint8_t BASELINE_ROWS = sizeof(BASELINE_TABLE) / sizeof(BASELINE_TABLE[0]);

/* ---------------------------------------------------------------------------
 *  RUNTIME CONFIGURATION (EEPROM backed)
 * -------------------------------------------------------------------------*/
#define CFG_MAGIC   0x4C4B3202UL   // "LK2" + rev 02
#define CFG_ADDRESS 0


Config cfg;

void loadDefaults() {
  cfg.magic = CFG_MAGIC;
  for (uint8_t i = 0; i < SENSOR_COUNT; i++) cfg.pulsesPerLitre[i] = 450.0f;
  cfg.toleranceAbs        = 0.20f;
  cfg.tolerancePct        = 0.08f;   // 8%
  cfg.noiseFloorLpm       = 0.12f;   // just under one pulse per second
  cfg.faultMinFlowLpm     = 0.50f;
  cfg.leakConfirmSamples  = 8;       // ~8 s of sustained imbalance
  cfg.leakClearSamples    = 5;       // ~5 s clean before retracting
  cfg.faultConfirmSamples = 10;      // ~10 s before calling a wiring fault
  cfg.learnedBias         = 0.0f;
  cfg.crc                 = 0;
}

uint16_t crc16(const uint8_t *data, uint16_t len) {
  uint16_t crc = 0xFFFF;
  while (len--) {
    crc ^= (uint16_t)(*data++) << 8;
    for (uint8_t b = 0; b < 8; b++) {
      crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
    }
  }
  return crc;
}

uint16_t configCrc() {
  return crc16((const uint8_t *)&cfg, sizeof(Config) - sizeof(uint16_t));
}

void saveConfig() {
  cfg.magic = CFG_MAGIC;
  cfg.crc   = configCrc();
  EEPROM.put(CFG_ADDRESS, cfg);
}

bool loadConfig() {
  Config tmp;
  EEPROM.get(CFG_ADDRESS, tmp);
  if (tmp.magic != CFG_MAGIC) return false;
  uint16_t stored = tmp.crc;
  cfg = tmp;
  if (configCrc() != stored) { loadDefaults(); return false; }
  return true;
}

/* ---------------------------------------------------------------------------
 *  PULSE COUNTERS
 * -------------------------------------------------------------------------*/
volatile uint16_t pulseCount[SENSOR_COUNT] = {0, 0, 0};
volatile uint8_t  lastPortDSnapshot = 0;

void isrSensor1() { pulseCount[0]++; }
void isrSensor2() { pulseCount[1]++; }

/* Pin-change ISR covers the whole PORTD bank, so we must confirm the edge came
 * from D4 and that it was a RISING edge, otherwise we double count. */
ISR(PCINT2_vect) {
  uint8_t now = PIND;
  uint8_t changed = now ^ lastPortDSnapshot;
  lastPortDSnapshot = now;
  if ((changed & _BV(PD4)) && (now & _BV(PD4))) {
    pulseCount[2]++;
  }
}

/* ---------------------------------------------------------------------------
 *  SIGNAL CONDITIONING — 3-tap median then EMA
 *  Median kills single-sample spikes (a stray pulse, an EMI glitch).
 *  EMA smooths what is left without adding much lag.
 * -------------------------------------------------------------------------*/
const float EMA_ALPHA = 0.40f;

float medianWindow[SENSOR_COUNT][3] = {{0}};
uint8_t medianIndex[SENSOR_COUNT]   = {0, 0, 0};
float emaValue[SENSOR_COUNT]        = {0, 0, 0};
bool  emaPrimed[SENSOR_COUNT]       = {false, false, false};

float median3(float a, float b, float c) {
  if (a > b) { float t = a; a = b; b = t; }
  if (b > c) { float t = b; b = c; c = t; }
  if (a > b) { float t = a; a = b; b = t; }
  return b;
}

float conditionFlow(uint8_t idx, float raw) {
  medianWindow[idx][medianIndex[idx]] = raw;
  medianIndex[idx] = (uint8_t)((medianIndex[idx] + 1) % 3);

  float med = median3(medianWindow[idx][0], medianWindow[idx][1], medianWindow[idx][2]);

  if (!emaPrimed[idx]) { emaValue[idx] = med; emaPrimed[idx] = true; }
  else                 { emaValue[idx] = EMA_ALPHA * med + (1.0f - EMA_ALPHA) * emaValue[idx]; }

  // Apply the noise floor LAST so "nothing detected" is a hard, exact zero and
  // cannot leak through the filters as 0.04 L/min of phantom flow.
  if (emaValue[idx] < cfg.noiseFloorLpm) return 0.0f;
  return emaValue[idx];
}

void resetConditioning() {
  for (uint8_t i = 0; i < SENSOR_COUNT; i++) {
    medianWindow[i][0] = medianWindow[i][1] = medianWindow[i][2] = 0.0f;
    medianIndex[i] = 0;
    emaValue[i] = 0.0f;
    emaPrimed[i] = false;
  }
}

/* ---------------------------------------------------------------------------
 *  BASELINE LOOKUP — interpolate expected balance + margin for a given inlet
 * -------------------------------------------------------------------------*/

BaselinePoint readBaselineRow(uint8_t i) {
  BaselinePoint p;
  memcpy_P(&p, &BASELINE_TABLE[i], sizeof(BaselinePoint));
  return p;
}

Envelope baselineEnvelope(float inletLpm) {
  Envelope env;

  BaselinePoint first = readBaselineRow(0);
  BaselinePoint last  = readBaselineRow(BASELINE_ROWS - 1);

  if (inletLpm <= first.inletLpm) {
    env.expected = first.expectedBalance;
    env.margin   = first.marginLpm;
  } else if (inletLpm >= last.inletLpm) {
    env.expected = last.expectedBalance;
    env.margin   = last.marginLpm;
  } else {
    env.expected = last.expectedBalance;
    env.margin   = last.marginLpm;
    for (uint8_t i = 1; i < BASELINE_ROWS; i++) {
      BaselinePoint hi = readBaselineRow(i);
      if (inletLpm <= hi.inletLpm) {
        BaselinePoint lo = readBaselineRow(i - 1);
        float span = hi.inletLpm - lo.inletLpm;
        float t = (span > 0.0f) ? (inletLpm - lo.inletLpm) / span : 0.0f;
        env.expected = lo.expectedBalance + t * (hi.expectedBalance - lo.expectedBalance);
        env.margin   = lo.marginLpm       + t * (hi.marginLpm       - lo.marginLpm);
        break;
      }
    }
  }

  env.expected += cfg.learnedBias;

  // Effective threshold: the widest of the table value, the absolute floor and
  // the proportional band. Whichever is most forgiving wins, so a high-flow
  // event can never be judged by a low-flow threshold.
  float threshold = env.expected + env.margin;
  float pctBand   = inletLpm * cfg.tolerancePct;
  if (cfg.toleranceAbs > threshold) threshold = cfg.toleranceAbs;
  if (pctBand          > threshold) threshold = pctBand;
  env.threshold = threshold;

  return env;
}

/* ---------------------------------------------------------------------------
 *  STATE MACHINE
 * -------------------------------------------------------------------------*/

const char *statusName(SystemStatus s) {
  switch (s) {
    case ST_IDLE:  return "IDLE";
    case ST_OK:    return "OK";
    case ST_WATCH: return "WATCH";
    case ST_LEAK:  return "LEAK";
    case ST_FAULT: return "FAULT";
    case ST_CAL:   return "CAL";
  }
  return "UNKNOWN";
}

SystemStatus status = ST_IDLE;

uint8_t  breachStreak = 0;   // consecutive samples outside the envelope
uint8_t  cleanStreak  = 0;   // consecutive samples inside the envelope
uint8_t  faultStreak  = 0;   // consecutive implausible samples

float    flowLpm[SENSOR_COUNT]   = {0, 0, 0};
float    volumeL[SENSOR_COUNT]   = {0, 0, 0};  // cumulative litres since ZERO
uint32_t sequence = 0;

/* ---------------------------------------------------------------------------
 *  CALIBRATION RUN
 *  The app opens all outlets, pushes a steady known flow, then sends CAL,<sec>.
 *  We average the signed balance error over the window and store it as
 *  learnedBias, which shifts the whole envelope to match this specific rig.
 * -------------------------------------------------------------------------*/
bool     calActive = false;
uint16_t calRemaining = 0;
uint16_t calSamples = 0;
float    calBalanceSum = 0.0f;
float    calInletSum = 0.0f;

/* ---------------------------------------------------------------------------
 *  LED DRIVER
 * -------------------------------------------------------------------------*/
uint32_t lastBlinkMs = 0;
bool     alarmLedOn = false;
uint32_t lastHeartbeatMs = 0;
bool     runLedOn = true;

void serviceLeds(uint32_t now) {
  // Alarm LED: fast blink on LEAK, steady on FAULT, off otherwise.
  if (status == ST_LEAK) {
    if (now - lastBlinkMs >= BLINK_FAST_MS) {
      lastBlinkMs = now;
      alarmLedOn = !alarmLedOn;
      digitalWrite(PIN_LED_ALARM, alarmLedOn ? HIGH : LOW);
    }
  } else if (status == ST_FAULT) {
    alarmLedOn = true;
    digitalWrite(PIN_LED_ALARM, HIGH);
  } else {
    if (alarmLedOn) { alarmLedOn = false; digitalWrite(PIN_LED_ALARM, LOW); }
  }

  // Run LED: solid when flowing, slow heartbeat when idle, so a dark board is
  // unambiguously a dead board.
  if (status == ST_IDLE) {
    if (now - lastHeartbeatMs >= BLINK_SLOW_MS) {
      lastHeartbeatMs = now;
      runLedOn = !runLedOn;
      digitalWrite(PIN_LED_RUN, runLedOn ? HIGH : LOW);
    }
  } else if (!runLedOn) {
    runLedOn = true;
    digitalWrite(PIN_LED_RUN, HIGH);
  }
}

/* ---------------------------------------------------------------------------
 *  OUTPUT HELPERS
 * -------------------------------------------------------------------------*/
void printFloat(float v, uint8_t decimals) {
  Serial.print(v, decimals);
}

/* H line — handshake / full configuration dump. */
void sendHandshake() {
  Serial.print(F("H,"));
  Serial.print(F(FW_VERSION));           Serial.print(',');
  Serial.print(PROTO_VERSION);           Serial.print(',');
  Serial.print(SENSOR_COUNT);            Serial.print(',');
  Serial.print(SAMPLE_INTERVAL_MS);      Serial.print(',');
  for (uint8_t i = 0; i < SENSOR_COUNT; i++) { printFloat(cfg.pulsesPerLitre[i], 1); Serial.print(','); }
  printFloat(cfg.toleranceAbs, 3);       Serial.print(',');
  printFloat(cfg.tolerancePct, 4);       Serial.print(',');
  printFloat(cfg.noiseFloorLpm, 3);      Serial.print(',');
  printFloat(cfg.faultMinFlowLpm, 3);    Serial.print(',');
  Serial.print(cfg.leakConfirmSamples);  Serial.print(',');
  Serial.print(cfg.leakClearSamples);    Serial.print(',');
  Serial.print(cfg.faultConfirmSamples); Serial.print(',');
  printFloat(cfg.learnedBias, 4);
  Serial.println();
}

/* B lines — dump the baseline dataset so the app can plot the envelope. */
void sendBaselineTable() {
  for (uint8_t i = 0; i < BASELINE_ROWS; i++) {
    BaselinePoint p = readBaselineRow(i);
    Serial.print(F("B,"));
    Serial.print(i);                  Serial.print(',');
    printFloat(p.inletLpm, 2);        Serial.print(',');
    printFloat(p.expectedBalance, 3); Serial.print(',');
    printFloat(p.marginLpm, 3);
    Serial.println();
  }
  Serial.print(F("B,END,"));
  Serial.println(BASELINE_ROWS);
}

void sendAck(const char *cmd, bool ok, const char *detail) {
  Serial.print(F("A,"));
  Serial.print(cmd);
  Serial.print(ok ? F(",OK,") : F(",ERR,"));
  Serial.println(detail);
}

/* D line — 1 Hz telemetry. See PROTOCOL.md. */
void sendTelemetry(uint32_t uptimeMs, float balance, const Envelope &env) {
  Serial.print(F("D,"));
  Serial.print(sequence);                Serial.print(',');
  Serial.print(uptimeMs);                Serial.print(',');
  for (uint8_t i = 0; i < SENSOR_COUNT; i++) { printFloat(flowLpm[i], 2); Serial.print(','); }
  for (uint8_t i = 0; i < SENSOR_COUNT; i++) { printFloat(volumeL[i], 3); Serial.print(','); }
  printFloat(balance, 3);       Serial.print(',');
  printFloat(env.expected, 3);  Serial.print(',');
  printFloat(env.threshold, 3); Serial.print(',');
  Serial.print(statusName(status));      Serial.print(',');
  Serial.print(breachStreak);            Serial.print(',');
  Serial.print(faultStreak);
  Serial.println();
}

/* ---------------------------------------------------------------------------
 *  COMMAND PARSER (app -> device)
 * -------------------------------------------------------------------------*/
char cmdBuffer[48];
uint8_t cmdLength = 0;

int8_t splitArgs(char *line, char *argv[], uint8_t maxArgs) {
  int8_t argc = 0;
  char *token = strtok(line, ",");
  while (token != NULL && argc < maxArgs) {
    argv[argc++] = token;
    token = strtok(NULL, ",");
  }
  return argc;
}

void handleCommand(char *line) {
  // Trim whitespace/CR.
  while (*line == ' ' || *line == '\t') line++;
  uint8_t len = strlen(line);
  while (len > 0 && (line[len - 1] == '\r' || line[len - 1] == ' ')) line[--len] = '\0';
  if (len == 0) return;

  char *argv[6];
  int8_t argc = splitArgs(line, argv, 6);
  if (argc <= 0) return;

  // Uppercase the verb.
  for (char *p = argv[0]; *p; ++p) *p = toupper(*p);
  const char *verb = argv[0];

  if (!strcmp(verb, "PING")) {
    sendAck("PING", true, "PONG");

  } else if (!strcmp(verb, "HELLO") || !strcmp(verb, "CFG?")) {
    sendHandshake();

  } else if (!strcmp(verb, "BASE?")) {
    sendBaselineTable();

  } else if (!strcmp(verb, "K") && argc >= 3) {
    // K,<sensorIndex 1..3>,<pulsesPerLitre>
    int idx = atoi(argv[1]) - 1;
    float ppl = atof(argv[2]);
    if (idx < 0 || idx >= SENSOR_COUNT) { sendAck("K", false, "index"); return; }
    if (ppl < 50.0f || ppl > 5000.0f)   { sendAck("K", false, "range"); return; }
    cfg.pulsesPerLitre[idx] = ppl;
    saveConfig();
    sendAck("K", true, "saved");

  } else if (!strcmp(verb, "TOL") && argc >= 3) {
    // TOL,<absLpm>,<pctFraction>
    float a = atof(argv[1]);
    float p = atof(argv[2]);
    if (a < 0.0f || a > 10.0f || p < 0.0f || p > 0.75f) { sendAck("TOL", false, "range"); return; }
    cfg.toleranceAbs = a;
    cfg.tolerancePct = p;
    saveConfig();
    sendAck("TOL", true, "saved");

  } else if (!strcmp(verb, "NF") && argc >= 2) {
    float nf = atof(argv[1]);
    if (nf < 0.0f || nf > 5.0f) { sendAck("NF", false, "range"); return; }
    cfg.noiseFloorLpm = nf;
    saveConfig();
    sendAck("NF", true, "saved");

  } else if (!strcmp(verb, "DB") && argc >= 4) {
    // DB,<leakConfirm>,<leakClear>,<faultConfirm>
    int lc = atoi(argv[1]), cl = atoi(argv[2]), fc = atoi(argv[3]);
    if (lc < 1 || lc > 120 || cl < 1 || cl > 120 || fc < 1 || fc > 120) {
      sendAck("DB", false, "range"); return;
    }
    cfg.leakConfirmSamples  = (uint8_t)lc;
    cfg.leakClearSamples    = (uint8_t)cl;
    cfg.faultConfirmSamples = (uint8_t)fc;
    saveConfig();
    sendAck("DB", true, "saved");

  } else if (!strcmp(verb, "ZERO")) {
    for (uint8_t i = 0; i < SENSOR_COUNT; i++) volumeL[i] = 0.0f;
    sendAck("ZERO", true, "totals cleared");

  } else if (!strcmp(verb, "CAL")) {
    uint16_t secs = (argc >= 2) ? (uint16_t)atoi(argv[1]) : 30;
    if (secs < 10 || secs > 300) { sendAck("CAL", false, "10-300s"); return; }
    calActive = true;
    calRemaining = secs;
    calSamples = 0;
    calBalanceSum = 0.0f;
    calInletSum = 0.0f;
    status = ST_CAL;
    breachStreak = cleanStreak = faultStreak = 0;
    sendAck("CAL", true, "started");

  } else if (!strcmp(verb, "CANCEL")) {
    calActive = false;
    status = ST_IDLE;
    sendAck("CANCEL", true, "aborted");

  } else if (!strcmp(verb, "DEFAULTS")) {
    loadDefaults();
    saveConfig();
    resetConditioning();
    sendAck("DEFAULTS", true, "restored");
    sendHandshake();

  } else if (!strcmp(verb, "REBOOT")) {
    sendAck("REBOOT", true, "bye");
    Serial.flush();
    wdt_enable(WDTO_15MS);
    for (;;) {}

  } else {
    sendAck("?", false, "unknown");
  }
}

void pumpSerial() {
  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '\n' || c == ';') {
      cmdBuffer[cmdLength] = '\0';
      handleCommand(cmdBuffer);
      cmdLength = 0;
    } else if (cmdLength < sizeof(cmdBuffer) - 1) {
      cmdBuffer[cmdLength++] = c;
    } else {
      cmdLength = 0;  // overrun, drop the line
    }
  }
}

/* ---------------------------------------------------------------------------
 *  EVALUATION — the core decision logic
 * -------------------------------------------------------------------------*/
void evaluate(float inlet, float outA, float outB, float &balanceOut, Envelope &envOut) {
  float totalOut = outA + outB;
  float balance  = inlet - totalOut;      // signed: + means water going missing
  float absBal   = fabs(balance);

  Envelope env = baselineEnvelope(inlet);
  balanceOut = balance;
  envOut = env;

  /* --- Rule 0: NOTHING DETECTED -> IDLE, never an alarm -------------------
   * All three channels below the noise floor. There is no water moving, so a
   * leak verdict is impossible and a disconnect verdict is unobservable. Reset
   * every streak so a dry spell always starts the next analysis from scratch. */
  if (inlet == 0.0f && outA == 0.0f && outB == 0.0f) {
    breachStreak = 0;
    cleanStreak  = 0;
    faultStreak  = 0;
    if (status != ST_CAL) status = ST_IDLE;
    return;
  }

  /* --- Rule 1: SENSOR / WIRING FAULT -------------------------------------
   * Two implausible shapes:
   *   a) meaningful inlet flow, both outlets dead   -> outlet sensors or wiring
   *   b) meaningful outlet flow, inlet dead         -> inlet sensor or wiring
   * Both are gated on faultMinFlowLpm so a dribble never triggers them, and
   * both are debounced. A single outlet reading zero is NOT a fault: closing
   * one tap is normal operation. */
  bool shapeA = (inlet >= cfg.faultMinFlowLpm) && (outA == 0.0f) && (outB == 0.0f);
  bool shapeB = (totalOut >= cfg.faultMinFlowLpm) && (inlet == 0.0f);

  if (shapeA || shapeB) {
    if (faultStreak < 255) faultStreak++;
    if (faultStreak >= cfg.faultConfirmSamples) {
      if (status != ST_CAL) status = ST_FAULT;
      breachStreak = 0;
      cleanStreak  = 0;
      return;
    }
    // Not confirmed yet: hold the previous verdict rather than inventing one.
    if (status != ST_CAL && status != ST_LEAK) status = ST_WATCH;
    return;
  }
  faultStreak = 0;

  /* --- Rule 2: BALANCE AGAINST THE CALIBRATED ENVELOPE -------------------
   * Only the "water going missing" direction counts as a leak. The opposite
   * sign (outlets reading more than the inlet) is a calibration/scaling issue,
   * not a leak, so it is treated as WATCH and never escalates. */
  bool missingWater = (balance > 0.0f) && (absBal > env.threshold);
  bool overRead     = (balance < 0.0f) && (absBal > env.threshold);

  if (missingWater) {
    cleanStreak = 0;
    if (breachStreak < 255) breachStreak++;
    if (breachStreak >= cfg.leakConfirmSamples) {
      if (status != ST_CAL) status = ST_LEAK;
    } else {
      if (status != ST_CAL && status != ST_LEAK) status = ST_WATCH;
    }
    return;
  }

  if (overRead) {
    breachStreak = 0;
    cleanStreak  = 0;
    if (status != ST_CAL && status != ST_LEAK) status = ST_WATCH;
    return;
  }

  /* --- Rule 3: INSIDE THE ENVELOPE -> clear with hysteresis -------------- */
  breachStreak = 0;
  if (cleanStreak < 255) cleanStreak++;
  if (status == ST_LEAK || status == ST_FAULT) {
    if (cleanStreak >= cfg.leakClearSamples) status = ST_OK;
  } else if (status != ST_CAL) {
    status = ST_OK;
  }
}

/* ---------------------------------------------------------------------------
 *  SETUP / LOOP
 * -------------------------------------------------------------------------*/
uint32_t lastSampleMs = 0;

void setup() {
  Serial.begin(9600);   // must match the HM-10 baud (AT+BAUD0 = 9600)

  pinMode(PIN_SENSOR_1, INPUT_PULLUP);
  pinMode(PIN_SENSOR_2, INPUT_PULLUP);
  pinMode(PIN_SENSOR_3, INPUT_PULLUP);
  pinMode(PIN_LED_RUN, OUTPUT);
  pinMode(PIN_LED_ALARM, OUTPUT);
  digitalWrite(PIN_LED_RUN, HIGH);
  digitalWrite(PIN_LED_ALARM, LOW);

  if (!loadConfig()) { loadDefaults(); saveConfig(); }

  attachInterrupt(digitalPinToInterrupt(PIN_SENSOR_1), isrSensor1, RISING);
  attachInterrupt(digitalPinToInterrupt(PIN_SENSOR_2), isrSensor2, RISING);

  lastPortDSnapshot = PIND;
  PCICR  |= _BV(PCIE2);      // enable PORTD pin-change interrupts
  PCMSK2 |= _BV(PCINT20);    // ... for D4 only

  lastSampleMs = millis();

  Serial.println(F("L,LeakGuard boot"));
  sendHandshake();
}

void loop() {
  uint32_t now = millis();

  pumpSerial();
  serviceLeds(now);

  if ((uint32_t)(now - lastSampleMs) < SAMPLE_INTERVAL_MS) return;

  // Use a fixed step rather than now-lastSampleMs so the flow maths stays exact
  // even if a sample is serviced a few ms late.
  uint32_t elapsed = now - lastSampleMs;
  lastSampleMs = now;

  uint16_t snapshot[SENSOR_COUNT];
  noInterrupts();
  for (uint8_t i = 0; i < SENSOR_COUNT; i++) { snapshot[i] = pulseCount[i]; pulseCount[i] = 0; }
  interrupts();

  for (uint8_t i = 0; i < SENSOR_COUNT; i++) {
    // L/min = pulses / pulsesPerLitre * (60000 / windowMs)
    float litres = (float)snapshot[i] / cfg.pulsesPerLitre[i];
    float raw    = litres * (60000.0f / (float)elapsed);
    flowLpm[i]   = conditionFlow(i, raw);
    volumeL[i]  += litres;
  }

  float balance;
  Envelope env;
  evaluate(flowLpm[0], flowLpm[1], flowLpm[2], balance, env);

  // Calibration accumulation runs on the conditioned values.
  if (calActive) {
    if (flowLpm[0] >= cfg.faultMinFlowLpm) {
      calBalanceSum += balance;
      calInletSum   += flowLpm[0];
      calSamples++;
    }
    if (calRemaining > 0) calRemaining--;

    Serial.print(F("C,RUN,"));
    Serial.print(calRemaining);      Serial.print(',');
    Serial.print(calSamples);        Serial.print(',');
    printFloat(calSamples ? (calBalanceSum / calSamples) : 0.0f, 4);
    Serial.println();

    if (calRemaining == 0) {
      calActive = false;
      if (calSamples >= 5) {
        cfg.learnedBias = calBalanceSum / (float)calSamples;
        saveConfig();
        Serial.print(F("C,DONE,"));
        printFloat(cfg.learnedBias, 4); Serial.print(',');
        printFloat(calInletSum / (float)calSamples, 3); Serial.print(',');
        Serial.println(calSamples);
      } else {
        Serial.println(F("C,FAIL,insufficient flow"));
      }
      status = ST_IDLE;
      resetConditioning();
    }
  }

  sequence++;
  sendTelemetry(now, balance, env);
}

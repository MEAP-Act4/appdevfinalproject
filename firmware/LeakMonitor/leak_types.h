#pragma once

/* =============================================================================
 *  LeakGuard shared types
 * =============================================================================
 *  These live in a header rather than in LeakMonitor.ino for a specific reason:
 *  the Arduino build step auto-generates a forward prototype for every function
 *  in a sketch and injects those prototypes immediately before the first function
 *  definition. Any type used in a function signature must therefore be visible
 *  BEFORE that injection point, and the only placement guaranteed to satisfy that
 *  is an #include at the top of the sketch.
 *
 *  Declaring `struct Envelope` or `enum SystemStatus` partway down the .ino
 *  compiles fine as plain C++ but fails under the Arduino preprocessor with
 *  "'Envelope' does not name a type" reported, confusingly, against the
 *  definition line.
 * ===========================================================================*/

#include <Arduino.h>

/** Number of flow sensors on the manifold: inlet, outlet A, outlet B. */
const uint8_t SENSOR_COUNT = 3;

/* ---------------------------------------------------------------------------
 *  One row of the standardized flow-rate calibration dataset.
 *
 *    inletLpm        reference inlet flow for this operating point, L/min
 *    expectedBalance the residual |inlet - (outA + outB)| a healthy rig shows
 *                    here. Never exactly zero: the three sensors have slightly
 *                    different K factors and the tees introduce a small bias.
 *    marginLpm       margin of error allowed ON TOP of expectedBalance before
 *                    the reading is treated as abnormal.
 * -------------------------------------------------------------------------*/
struct BaselinePoint {
  float inletLpm;
  float expectedBalance;
  float marginLpm;
};

/** Interpolated tolerance envelope for one instantaneous inlet flow. */
struct Envelope {
  float expected;   // expected residual imbalance, L/min
  float margin;     // margin of error on top of expected, L/min
  float threshold;  // expected + margin, after the configured floors
};

/** Firmware verdict for the current sample. */
enum SystemStatus : uint8_t {
  ST_IDLE  = 0,   // nothing detected. explicitly NOT an error.
  ST_OK    = 1,   // flowing, balance inside envelope
  ST_WATCH = 2,   // balance outside envelope but not yet confirmed
  ST_LEAK  = 3,   // confirmed sustained imbalance
  ST_FAULT = 4,   // sensor / wiring implausibility
  ST_CAL   = 5    // calibration run in progress
};

/* ---------------------------------------------------------------------------
 *  Runtime configuration, mirrored in EEPROM behind a magic number and CRC.
 * -------------------------------------------------------------------------*/
struct Config {
  uint32_t magic;

  // Pulses per litre for each sensor. YF-S201 nominal = 450 (F = 7.5 * Q L/min).
  float pulsesPerLitre[SENSOR_COUNT];

  // Absolute floor on the margin of error, L/min. Applied as a lower bound on
  // whatever the baseline dataset interpolates to.
  float toleranceAbs;

  // Proportional margin, as a fraction of inlet flow (0.08 = 8%). The effective
  // threshold is max(dataset, toleranceAbs, inlet * tolerancePct).
  float tolerancePct;

  // Below this a sensor reads exactly 0.00 L/min. Kills quantisation chatter and
  // guarantees "nothing detected" can never raise an alarm.
  float noiseFloorLpm;

  // Minimum inlet flow before a sensor-disconnect verdict is allowed. Under this
  // the branch split is not observable, so the firmware stays silent.
  float faultMinFlowLpm;

  // Consecutive-sample debounce counts.
  uint8_t leakConfirmSamples;   // breaches needed to raise LEAK
  uint8_t leakClearSamples;     // clean samples needed to clear LEAK
  uint8_t faultConfirmSamples;  // samples needed to raise FAULT

  // Learned per-rig bias from the last on-site CAL run, L/min. Added to the
  // interpolated expectedBalance. Zero until calibrated.
  float learnedBias;

  uint16_t crc;
};

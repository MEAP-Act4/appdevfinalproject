#!/usr/bin/env python3
"""Generate a sample LeakGuard recording in the app's CSV export format.

The recording runs healthy for a while, then a slow leak develops between the
upstream and downstream sensors (water goes missing: inlet > outA + outB), so
the app's replay re-evaluation will cross the debounce threshold and raise LEAK.

Only the timestamp and the three *_lpm flow columns matter to replay; the other
columns are filled plausibly so the file matches a real export.
"""
import csv
import datetime as dt
import math
import random

random.seed(20260929)

HEADER = [
    "timestamp_utc", "device_id", "seq",
    "inlet_lpm", "outlet_a_lpm", "outlet_b_lpm",
    "inlet_total_l", "outlet_a_total_l", "outlet_b_total_l",
    "balance_lpm", "expected_lpm", "threshold_lpm", "status", "samples",
]

# One sample per second. 1800 s = 30 min of "recording"; at 60x replay that is
# 30 s on screen, at 600x it is 3 s. Leak begins at t=900 and grows.
N = 1800
LEAK_START = 900

def noise(mag):
    return (random.random() - 0.5) * mag

rows = []
t0 = dt.datetime(2026, 9, 29, 8, 0, 0, tzinfo=dt.timezone.utc)
vol = [0.0, 0.0, 0.0]
for i in range(N):
    inlet = 3.4 + noise(0.25)
    if i < LEAK_START:
        # Healthy: outlets sum to the inlet within noise.
        outA = inlet * 0.5 + noise(0.12)
        outB = inlet - outA + noise(0.12)
    else:
        # Leak grows from 0 to ~1.6 L/min missing over 5 min, then holds.
        ramp = min(1.0, (i - LEAK_START) / 300.0)
        missing = 1.6 * ramp
        remaining = inlet - missing
        outA = remaining * 0.5 + noise(0.12)
        outB = remaining * 0.5 + noise(0.12)

    inlet = max(0.0, inlet)
    outA = max(0.0, outA)
    outB = max(0.0, outB)
    for k, v in enumerate((inlet, outA, outB)):
        vol[k] += v / 60.0

    ts = (t0 + dt.timedelta(seconds=i)).isoformat().replace("+00:00", "Z")
    # The replay recomputes status/balance/expected/threshold, so these are
    # placeholders (not read by ReplayTransport).
    rows.append([
        ts, "SAMPLE-RIG", i,
        f"{inlet:.3f}", f"{outA:.3f}", f"{outB:.3f}",
        f"{vol[0]:.3f}", f"{vol[1]:.3f}", f"{vol[2]:.3f}",
        "0.000", "0.000", "0.500", "OK", "1",
    ])

with open("sample_leak.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(HEADER)
    w.writerows(rows)

print(f"Wrote sample_leak.csv with {len(rows)} rows (leak begins at sample {LEAK_START}).")

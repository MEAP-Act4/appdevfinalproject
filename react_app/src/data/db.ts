/**
 * IndexedDB time-series store — the React build's equivalent of the Flutter app's
 * SQLite database.
 *
 * Design parity with the Dart side:
 *  * Rows hold canonical units (L/min, litres) and UTC epoch ms.
 *  * `samples` records how many 1 Hz device samples a row represents, so the
 *    logging interval can be coarsened without skewing averages.
 *  * All three averaging windows plus the 24 h trend are produced in a single
 *    cursor pass over the last seven days. IndexedDB has no GROUP BY, so doing it
 *    any other way would mean several full scans.
 */

import { SENSOR_COUNT, type LeakStatus } from '../core/protocol';

const DB_NAME = 'leakguard';
const DB_VERSION = 1;
const READINGS = 'readings';
const EVENTS = 'events';
const META = 'meta';

/** Seconds covered by one device sample. Matches SAMPLE_INTERVAL_MS. */
export const SECONDS_PER_SAMPLE = 1;

export interface ReadingRow {
  ts: number;
  deviceId: string;
  seq: number;
  f: [number, number, number];
  v: [number, number, number];
  balance: number;
  expected: number;
  threshold: number;
  status: LeakStatus;
  samples: number;
}

export type EventKind =
  | 'CONNECTED'
  | 'DISCONNECTED'
  | 'LEAK_RAISED'
  | 'LEAK_CLEARED'
  | 'FAULT_RAISED'
  | 'FAULT_CLEARED'
  | 'CALIBRATION'
  | 'CONFIG_CHANGED'
  | 'NOTE';

export interface EventRow {
  ts: number;
  kind: EventKind;
  message: string;
  deviceId: string;
  balance?: number;
  threshold?: number;
}

export type AverageWindowId = 'day' | 'threeDay' | 'week';

export interface AverageWindowMeta {
  id: AverageWindowId;
  label: string;
  shortLabel: string;
  ms: number;
}

export const AVERAGE_WINDOWS: readonly AverageWindowMeta[] = [
  { id: 'day', label: 'Per day', shortLabel: '24 h', ms: 24 * 3600_000 },
  { id: 'threeDay', label: 'Per 3 days', shortLabel: '72 h', ms: 3 * 24 * 3600_000 },
  { id: 'week', label: 'Per week', shortLabel: '7 d', ms: 7 * 24 * 3600_000 },
];

export interface WindowStats {
  window: AverageWindowMeta;
  averageLpm: number;
  peakLpm: number;
  totalLitres: number;
  sampleCount: number;
  /** 0..1 — how much of the window actually has data. */
  coverage: number;
  /** 0..1 — proportion of samples where this sensor was flowing. */
  activeFraction: number;
}

export interface TrendPoint {
  ts: number;
  valueLpm: number;
  alarm: boolean;
}

export interface SensorAggregates {
  sensorIndex: number;
  day: WindowStats;
  threeDay: WindowStats;
  week: WindowStats;
}

export interface AggregateSnapshot {
  perSensor: SensorAggregates[];
  trends: TrendPoint[][];
  computedAt: number;
  totalRows: number;
  oldestTs: number | null;
}

function emptyWindow(window: AverageWindowMeta): WindowStats {
  return {
    window,
    averageLpm: 0,
    peakLpm: 0,
    totalLitres: 0,
    sampleCount: 0,
    coverage: 0,
    activeFraction: 0,
  };
}

export function emptySnapshot(): AggregateSnapshot {
  return {
    perSensor: Array.from({ length: SENSOR_COUNT }, (_, i) => ({
      sensorIndex: i,
      day: emptyWindow(AVERAGE_WINDOWS[0]!),
      threeDay: emptyWindow(AVERAGE_WINDOWS[1]!),
      week: emptyWindow(AVERAGE_WINDOWS[2]!),
    })),
    trends: Array.from({ length: SENSOR_COUNT }, () => []),
    computedAt: 0,
    totalRows: 0,
    oldestTs: null,
  };
}

export function windowById(
  aggregates: SensorAggregates,
  id: AverageWindowId,
): WindowStats {
  return id === 'day' ? aggregates.day : id === 'threeDay' ? aggregates.threeDay : aggregates.week;
}

export function allWindows(aggregates: SensorAggregates): WindowStats[] {
  return [aggregates.day, aggregates.threeDay, aggregates.week];
}

export function isReliable(stats: WindowStats): boolean {
  return stats.coverage >= 0.25;
}

export function averageWhileActive(stats: WindowStats): number {
  return stats.activeFraction <= 0 ? 0 : stats.averageLpm / stats.activeFraction;
}

/** Week-over-day drift. Positive means recent usage is above the weekly norm. */
export function trendRatio(aggregates: SensorAggregates): number {
  if (aggregates.week.averageLpm <= 0.0001) return 0;
  return aggregates.day.averageLpm / aggregates.week.averageLpm - 1;
}

function promisify<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('IndexedDB request failed'));
  });
}

export class LeakDatabase {
  private readonly db: IDBDatabase;

  private constructor(db: IDBDatabase) {
    this.db = db;
  }

  static async open(): Promise<LeakDatabase> {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(READINGS)) {
        // ts as the key path gives us an ordered primary index for free, which is
        // what every range query here needs.
        db.createObjectStore(READINGS, { keyPath: 'ts' });
      }
      if (!db.objectStoreNames.contains(EVENTS)) {
        db.createObjectStore(EVENTS, { keyPath: 'ts' });
      }
      if (!db.objectStoreNames.contains(META)) {
        db.createObjectStore(META);
      }
    };
    const db = await promisify(request);
    return new LeakDatabase(db);
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  async putReading(row: ReadingRow): Promise<void> {
    const tx = this.db.transaction(READINGS, 'readwrite');
    // Two samples can land in the same millisecond on a fast flush; nudging the
    // key keeps both rather than silently overwriting.
    const store = tx.objectStore(READINGS);
    const existing = await promisify(store.getKey(row.ts));
    store.put(existing === undefined ? row : { ...row, ts: row.ts + 1 });
    return this.done(tx);
  }

  async putEvent(row: EventRow): Promise<void> {
    const tx = this.db.transaction(EVENTS, 'readwrite');
    const store = tx.objectStore(EVENTS);
    const existing = await promisify(store.getKey(row.ts));
    store.put(existing === undefined ? row : { ...row, ts: row.ts + 1 });
    return this.done(tx);
  }

  async putBaseline(deviceId: string, rows: unknown): Promise<void> {
    const tx = this.db.transaction(META, 'readwrite');
    tx.objectStore(META).put(rows, `baseline:${deviceId}`);
    return this.done(tx);
  }

  async getBaseline<T>(deviceId: string): Promise<T | undefined> {
    const tx = this.db.transaction(META, 'readonly');
    return promisify(tx.objectStore(META).get(`baseline:${deviceId}`)) as Promise<T | undefined>;
  }

  private done(tx: IDBTransaction): Promise<void> {
    return new Promise((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error ?? new Error('IndexedDB transaction failed'));
      tx.onabort = () => reject(tx.error ?? new Error('IndexedDB transaction aborted'));
    });
  }

  // ---------------------------------------------------------------------------
  // Aggregates
  // ---------------------------------------------------------------------------

  /**
   * One cursor pass over the last seven days builds every window at once.
   * Accumulators are weighted by `samples` so a row covering 10 device samples
   * counts ten times as much as a row covering one.
   */
  async computeAggregates(trendBuckets = 96): Promise<AggregateSnapshot> {
    const now = Date.now();
    const weekMs = AVERAGE_WINDOWS[2]!.ms;
    const dayMs = AVERAGE_WINDOWS[0]!.ms;
    const threeDayMs = AVERAGE_WINDOWS[1]!.ms;
    const bucketMs = Math.floor(dayMs / trendBuckets);

    type Acc = {
      weighted: number[];
      peak: number[];
      active: number[];
      samples: number;
    };
    const makeAcc = (): Acc => ({
      weighted: new Array<number>(SENSOR_COUNT).fill(0),
      peak: new Array<number>(SENSOR_COUNT).fill(0),
      active: new Array<number>(SENSOR_COUNT).fill(0),
      samples: 0,
    });

    const accDay = makeAcc();
    const acc3 = makeAcc();
    const accWeek = makeAcc();

    // bucket -> per-sensor weighted sums, sample count, alarm flag
    const buckets = new Map<
      number,
      { weighted: number[]; samples: number; alarm: boolean }
    >();

    let totalRows = 0;
    let oldestTs: number | null = null;

    const tx = this.db.transaction(READINGS, 'readonly');
    const store = tx.objectStore(READINGS);

    await new Promise<void>((resolve, reject) => {
      const cursorRequest = store.openCursor(IDBKeyRange.lowerBound(now - weekMs));
      cursorRequest.onerror = () =>
        reject(cursorRequest.error ?? new Error('cursor failed'));
      cursorRequest.onsuccess = () => {
        const cursor = cursorRequest.result;
        if (!cursor) {
          resolve();
          return;
        }
        const row = cursor.value as ReadingRow;
        const weight = row.samples > 0 ? row.samples : 1;

        const feed = (acc: Acc) => {
          acc.samples += weight;
          for (let i = 0; i < SENSOR_COUNT; i++) {
            const value = row.f[i] ?? 0;
            acc.weighted[i] = (acc.weighted[i] ?? 0) + value * weight;
            if (value > (acc.peak[i] ?? 0)) acc.peak[i] = value;
            if (value > 0) acc.active[i] = (acc.active[i] ?? 0) + weight;
          }
        };

        feed(accWeek);
        if (row.ts >= now - threeDayMs) feed(acc3);
        if (row.ts >= now - dayMs) {
          feed(accDay);

          const bucketKey = Math.floor(row.ts / bucketMs) * bucketMs;
          let bucket = buckets.get(bucketKey);
          if (!bucket) {
            bucket = {
              weighted: new Array<number>(SENSOR_COUNT).fill(0),
              samples: 0,
              alarm: false,
            };
            buckets.set(bucketKey, bucket);
          }
          bucket.samples += weight;
          for (let i = 0; i < SENSOR_COUNT; i++) {
            bucket.weighted[i] = (bucket.weighted[i] ?? 0) + (row.f[i] ?? 0) * weight;
          }
          if (row.status === 'LEAK' || row.status === 'FAULT') bucket.alarm = true;
        }

        cursor.continue();
      };
    });

    const countTx = this.db.transaction(READINGS, 'readonly');
    const countStore = countTx.objectStore(READINGS);
    totalRows = await promisify(countStore.count());
    const firstKey = await promisify(countStore.openCursor());
    oldestTs = firstKey ? (firstKey.key as number) : null;

    const toStats = (
      acc: Acc,
      meta: AverageWindowMeta,
      sensorIndex: number,
    ): WindowStats => {
      if (acc.samples === 0) return emptyWindow(meta);
      const weighted = acc.weighted[sensorIndex] ?? 0;
      const average = weighted / acc.samples;
      return {
        window: meta,
        averageLpm: average,
        peakLpm: acc.peak[sensorIndex] ?? 0,
        // mean L/min * covered minutes
        totalLitres: (weighted * SECONDS_PER_SAMPLE) / 60,
        sampleCount: acc.samples,
        coverage: Math.min((acc.samples * SECONDS_PER_SAMPLE) / (meta.ms / 1000), 1),
        activeFraction: (acc.active[sensorIndex] ?? 0) / acc.samples,
      };
    };

    const sortedBuckets = [...buckets.entries()].sort((a, b) => a[0] - b[0]);

    return {
      perSensor: Array.from({ length: SENSOR_COUNT }, (_, i) => ({
        sensorIndex: i,
        day: toStats(accDay, AVERAGE_WINDOWS[0]!, i),
        threeDay: toStats(acc3, AVERAGE_WINDOWS[1]!, i),
        week: toStats(accWeek, AVERAGE_WINDOWS[2]!, i),
      })),
      trends: Array.from({ length: SENSOR_COUNT }, (_, i) =>
        sortedBuckets.map(([ts, bucket]) => ({
          ts,
          valueLpm: bucket.samples === 0 ? 0 : (bucket.weighted[i] ?? 0) / bucket.samples,
          alarm: bucket.alarm,
        })),
      ),
      computedAt: Date.now(),
      totalRows,
      oldestTs,
    };
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  async readings(options: { fromMs?: number; limit?: number; newestFirst?: boolean } = {}): Promise<ReadingRow[]> {
    const { fromMs, limit = 500, newestFirst = true } = options;
    const tx = this.db.transaction(READINGS, 'readonly');
    const store = tx.objectStore(READINGS);
    const range = fromMs === undefined ? null : IDBKeyRange.lowerBound(fromMs);
    const out: ReadingRow[] = [];

    await new Promise<void>((resolve, reject) => {
      const request = store.openCursor(range, newestFirst ? 'prev' : 'next');
      request.onerror = () => reject(request.error ?? new Error('cursor failed'));
      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor || out.length >= limit) {
          resolve();
          return;
        }
        out.push(cursor.value as ReadingRow);
        cursor.continue();
      };
    });

    return out;
  }

  async events(limit = 100): Promise<EventRow[]> {
    const tx = this.db.transaction(EVENTS, 'readonly');
    const store = tx.objectStore(EVENTS);
    const out: EventRow[] = [];
    await new Promise<void>((resolve, reject) => {
      const request = store.openCursor(null, 'prev');
      request.onerror = () => reject(request.error ?? new Error('cursor failed'));
      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor || out.length >= limit) {
          resolve();
          return;
        }
        out.push(cursor.value as EventRow);
        cursor.continue();
      };
    });
    return out;
  }

  async count(): Promise<number> {
    const tx = this.db.transaction(READINGS, 'readonly');
    return promisify(tx.objectStore(READINGS).count());
  }

  /** Browser-reported origin usage. Approximate, and unavailable in some browsers. */
  async estimatedSizeBytes(): Promise<number> {
    if (!navigator.storage?.estimate) return 0;
    const estimate = await navigator.storage.estimate();
    return estimate.usage ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Maintenance
  // ---------------------------------------------------------------------------

  async prune(retentionMs: number): Promise<number> {
    const cutoff = Date.now() - retentionMs;
    const tx = this.db.transaction(READINGS, 'readwrite');
    const store = tx.objectStore(READINGS);
    let removed = 0;
    await new Promise<void>((resolve, reject) => {
      const request = store.openCursor(IDBKeyRange.upperBound(cutoff, true));
      request.onerror = () => reject(request.error ?? new Error('cursor failed'));
      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor) {
          resolve();
          return;
        }
        cursor.delete();
        removed++;
        cursor.continue();
      };
    });
    await this.done(tx);
    return removed;
  }

  async clearAll(): Promise<void> {
    const tx = this.db.transaction([READINGS, EVENTS], 'readwrite');
    tx.objectStore(READINGS).clear();
    tx.objectStore(EVENTS).clear();
    return this.done(tx);
  }

  /** CSV in canonical units, matching the Flutter export column-for-column. */
  async exportCsv(limit = 100_000): Promise<string> {
    const rows = await this.readings({ limit, newestFirst: false });
    const header =
      'timestamp_utc,device_id,seq,inlet_lpm,outlet_a_lpm,outlet_b_lpm,' +
      'inlet_total_l,outlet_a_total_l,outlet_b_total_l,' +
      'balance_lpm,expected_lpm,threshold_lpm,status,samples';
    const lines = rows.map((r) =>
      [
        new Date(r.ts).toISOString(),
        r.deviceId,
        r.seq,
        r.f[0].toFixed(3),
        r.f[1].toFixed(3),
        r.f[2].toFixed(3),
        r.v[0].toFixed(3),
        r.v[1].toFixed(3),
        r.v[2].toFixed(3),
        r.balance.toFixed(3),
        r.expected.toFixed(3),
        r.threshold.toFixed(3),
        r.status,
        r.samples,
      ].join(','),
    );
    return [header, ...lines].join('\n');
  }
}

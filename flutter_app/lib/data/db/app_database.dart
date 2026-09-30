import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/protocol/leak_protocol.dart';
import '../models/aggregates.dart';
import '../models/stored_reading.dart';

/// SQLite store for the telemetry time series, the event log and the cached
/// device profile.
///
/// Design notes:
///  * Everything is stored in canonical units (L/min, litres) and UTC epoch ms.
///  * `readings.samples` records how many 1 Hz device samples a row represents,
///    so the downsampler can write one row per N seconds and the aggregate
///    queries stay correct by weighting on that column.
///  * All aggregation happens in SQL. Pulling a week of rows into Dart to average
///    them would be 600k rows on a 1 Hz feed.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const String _fileName = 'leakguard.db';
  static const int _schemaVersion = 1;

  /// Assumed seconds covered by one device sample. Used for coverage and volume
  /// integration. Matches `SAMPLE_INTERVAL_MS` in the firmware.
  static const double secondsPerSample = 1.0;

  static Future<AppDatabase> open({String? overridePath}) async {
    final dbPath = overridePath ?? p.join(await getDatabasesPath(), _fileName);
    final db = await openDatabase(
      dbPath,
      version: _schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Single schema version so far. Future migrations branch here rather
        // than dropping user history.
      },
      onOpen: (db) async {
        // WAL keeps the 1 Hz writer from blocking the UI's reads.
        await db.execute('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
      },
    );
    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE readings (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        ts        INTEGER NOT NULL,
        device_id TEXT    NOT NULL DEFAULT '',
        seq       INTEGER NOT NULL DEFAULT 0,
        f1        REAL    NOT NULL DEFAULT 0,
        f2        REAL    NOT NULL DEFAULT 0,
        f3        REAL    NOT NULL DEFAULT 0,
        v1        REAL    NOT NULL DEFAULT 0,
        v2        REAL    NOT NULL DEFAULT 0,
        v3        REAL    NOT NULL DEFAULT 0,
        balance   REAL    NOT NULL DEFAULT 0,
        expected  REAL    NOT NULL DEFAULT 0,
        threshold REAL    NOT NULL DEFAULT 0,
        status    TEXT    NOT NULL DEFAULT 'UNKNOWN',
        samples   INTEGER NOT NULL DEFAULT 1
      )
    ''');
    batch.execute('CREATE INDEX idx_readings_ts ON readings(ts)');
    batch.execute(
      'CREATE INDEX idx_readings_device_ts ON readings(device_id, ts)',
    );

    batch.execute('''
      CREATE TABLE events (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        ts        INTEGER NOT NULL,
        kind      TEXT    NOT NULL,
        message   TEXT    NOT NULL DEFAULT '',
        device_id TEXT    NOT NULL DEFAULT '',
        balance   REAL,
        threshold REAL
      )
    ''');
    batch.execute('CREATE INDEX idx_events_ts ON events(ts)');

    batch.execute('''
      CREATE TABLE devices (
        device_id   TEXT PRIMARY KEY,
        name        TEXT NOT NULL DEFAULT '',
        firmware    TEXT NOT NULL DEFAULT '',
        last_seen   INTEGER NOT NULL DEFAULT 0,
        config_json TEXT NOT NULL DEFAULT ''
      )
    ''');

    /// Cached copy of the firmware's calibration dataset, so the envelope chart
    /// still renders while offline.
    batch.execute('''
      CREATE TABLE baseline (
        device_id TEXT    NOT NULL,
        idx       INTEGER NOT NULL,
        inlet     REAL    NOT NULL,
        expected  REAL    NOT NULL,
        margin    REAL    NOT NULL,
        PRIMARY KEY (device_id, idx)
      )
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> close() => _db.close();

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Future<int> insertReading(StoredReading reading) =>
      _db.insert('readings', reading.toRow());

  /// Batched insert for the downsampler's flush.
  Future<void> insertReadings(List<StoredReading> readings) async {
    if (readings.isEmpty) return;
    final batch = _db.batch();
    for (final r in readings) {
      batch.insert('readings', r.toRow());
    }
    await batch.commit(noResult: true);
  }

  Future<int> insertEvent(LeakEvent event) => _db.insert('events', event.toRow());

  Future<void> upsertDevice({
    required String deviceId,
    required String name,
    required String firmware,
    required String configJson,
  }) async {
    await _db.insert(
      'devices',
      <String, Object?>{
        'device_id': deviceId,
        'name': name,
        'firmware': firmware,
        'last_seen': DateTime.now().toUtc().millisecondsSinceEpoch,
        'config_json': configJson,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceBaseline(
    String deviceId,
    List<BaselineRow> rows,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'baseline',
        where: 'device_id = ?',
        whereArgs: <Object?>[deviceId],
      );
      for (final row in rows) {
        await txn.insert('baseline', <String, Object?>{
          'device_id': deviceId,
          'idx': row.index,
          'inlet': row.inletLpm,
          'expected': row.expectedBalanceLpm,
          'margin': row.marginLpm,
        });
      }
    });
  }

  Future<List<BaselineRow>> baselineFor(String deviceId) async {
    final rows = await _db.query(
      'baseline',
      where: 'device_id = ?',
      whereArgs: <Object?>[deviceId],
      orderBy: 'idx ASC',
    );
    return rows
        .map(
          (r) => BaselineRow(
            index: (r['idx'] as num).toInt(),
            inletLpm: (r['inlet'] as num).toDouble(),
            expectedBalanceLpm: (r['expected'] as num).toDouble(),
            marginLpm: (r['margin'] as num).toDouble(),
          ),
        )
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Aggregate reads
  // ---------------------------------------------------------------------------

  /// Computes the day / 3-day / week statistics for all three sensors plus the
  /// 24 h trend series, in as few queries as possible.
  Future<AggregateSnapshot> computeAggregates({
    int sensorCount = kSensorCount,
    int trendBuckets = 96,
  }) async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;

    final perWindow = <AverageWindow, List<WindowStats>>{};
    for (final window in AverageWindow.values) {
      perWindow[window] = await _statsForWindow(window, nowMs, sensorCount);
    }

    final trends = <List<TrendPoint>>[];
    for (var i = 0; i < sensorCount; i++) {
      trends.add(await _trend(i, nowMs, trendBuckets));
    }

    final meta = await _db.rawQuery(
      'SELECT COUNT(*) AS c, MIN(ts) AS oldest FROM readings',
    );
    final totalRows = (meta.first['c'] as num?)?.toInt() ?? 0;
    final oldest = (meta.first['oldest'] as num?)?.toInt();

    return AggregateSnapshot(
      perSensor: List<SensorAggregates>.generate(
        sensorCount,
        (i) => SensorAggregates(
          sensorIndex: i,
          day: perWindow[AverageWindow.day]![i],
          threeDay: perWindow[AverageWindow.threeDay]![i],
          week: perWindow[AverageWindow.week]![i],
        ),
      ),
      trends: trends,
      computedAt: DateTime.now(),
      totalRows: totalRows,
      oldestTimestampMs: oldest,
    );
  }

  Future<List<WindowStats>> _statsForWindow(
    AverageWindow window,
    int nowMs,
    int sensorCount,
  ) async {
    final fromMs = nowMs - window.duration.inMilliseconds;

    // One pass over the window, weighted by `samples`, for all three channels.
    final rows = await _db.rawQuery(
      '''
      SELECT
        SUM(f1 * samples) AS w1,
        SUM(f2 * samples) AS w2,
        SUM(f3 * samples) AS w3,
        MAX(f1)           AS p1,
        MAX(f2)           AS p2,
        MAX(f3)           AS p3,
        SUM(CASE WHEN f1 > 0 THEN samples ELSE 0 END) AS a1,
        SUM(CASE WHEN f2 > 0 THEN samples ELSE 0 END) AS a2,
        SUM(CASE WHEN f3 > 0 THEN samples ELSE 0 END) AS a3,
        SUM(samples)      AS n
      FROM readings
      WHERE ts >= ? AND ts <= ?
      ''',
      <Object?>[fromMs, nowMs],
    );

    final row = rows.first;
    final totalSamples = (row['n'] as num?)?.toInt() ?? 0;

    if (totalSamples == 0) {
      return List<WindowStats>.generate(
        sensorCount,
        (_) => WindowStats.empty(window),
      );
    }

    final windowSeconds = window.duration.inSeconds.toDouble();
    final coveredSeconds = totalSamples * secondsPerSample;
    final coverage = (coveredSeconds / windowSeconds).clamp(0.0, 1.0);

    return List<WindowStats>.generate(sensorCount, (i) {
      final weighted = (row['w${i + 1}'] as num?)?.toDouble() ?? 0;
      final peak = (row['p${i + 1}'] as num?)?.toDouble() ?? 0;
      final activeSamples = (row['a${i + 1}'] as num?)?.toInt() ?? 0;

      // Mean flow across every covered sample, idle included.
      final average = weighted / totalSamples;

      // Volume = mean L/min * covered minutes.
      final totalLitres = weighted * secondsPerSample / 60.0;

      return WindowStats(
        window: window,
        averageLpm: average,
        peakLpm: peak,
        totalLitres: totalLitres,
        sampleCount: totalSamples,
        coverage: coverage,
        activeFraction: activeSamples / totalSamples,
      );
    });
  }

  Future<List<TrendPoint>> _trend(
    int sensorIndex,
    int nowMs,
    int buckets,
  ) async {
    const windowMs = Duration.millisecondsPerDay;
    final fromMs = nowMs - windowMs;
    final bucketMs = windowMs ~/ buckets;
    final column = 'f${sensorIndex + 1}';

    final rows = await _db.rawQuery(
      '''
      SELECT
        (ts / $bucketMs) * $bucketMs AS bucket,
        SUM($column * samples) / SUM(samples) AS avg_flow,
        MAX(CASE WHEN status IN ('LEAK', 'FAULT') THEN 1 ELSE 0 END) AS alarm
      FROM readings
      WHERE ts >= ? AND ts <= ?
      GROUP BY bucket
      ORDER BY bucket ASC
      ''',
      <Object?>[fromMs, nowMs],
    );

    return rows
        .map(
          (r) => TrendPoint(
            timestampMs: (r['bucket'] as num).toInt(),
            valueLpm: (r['avg_flow'] as num?)?.toDouble() ?? 0,
            alarm: ((r['alarm'] as num?)?.toInt() ?? 0) == 1,
          ),
        )
        .toList(growable: false);
  }

  /// Raw rows for the history screen / CSV export.
  Future<List<StoredReading>> readings({
    int? fromMs,
    int? toMs,
    int limit = 500,
    bool newestFirst = true,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (fromMs != null) {
      where.add('ts >= ?');
      args.add(fromMs);
    }
    if (toMs != null) {
      where.add('ts <= ?');
      args.add(toMs);
    }
    final rows = await _db.query(
      'readings',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: newestFirst ? 'ts DESC' : 'ts ASC',
      limit: limit,
    );
    return rows.map(StoredReading.fromRow).toList(growable: false);
  }

  Future<List<LeakEvent>> events({int limit = 100}) async {
    final rows = await _db.query('events', orderBy: 'ts DESC', limit: limit);
    return rows.map(LeakEvent.fromRow).toList(growable: false);
  }

  Future<int> countReadings() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS c FROM readings');
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Approximate on-disk size in bytes.
  Future<int> estimatedSizeBytes() async {
    final r = await _db.rawQuery(
      'SELECT page_count * page_size AS bytes FROM pragma_page_count(), pragma_page_size()',
    );
    return (r.first['bytes'] as num?)?.toInt() ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Maintenance
  // ---------------------------------------------------------------------------

  /// Deletes readings older than [retention]. Returns rows removed.
  Future<int> pruneReadings(Duration retention) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(retention)
        .millisecondsSinceEpoch;
    return _db.delete('readings', where: 'ts < ?', whereArgs: <Object?>[cutoff]);
  }

  Future<void> clearReadings() async {
    await _db.delete('readings');
  }

  Future<void> clearEvents() async {
    await _db.delete('events');
  }

  Future<void> vacuum() => _db.execute('VACUUM');

  /// CSV in canonical units. Unit conversion is a presentation concern, so the
  /// export stays machine-friendly.
  Future<String> exportCsv({Duration? window, int limit = 100000}) async {
    final fromMs = window == null
        ? null
        : DateTime.now().toUtc().subtract(window).millisecondsSinceEpoch;
    final rows = await readings(
      fromMs: fromMs,
      limit: limit,
      newestFirst: false,
    );
    final buffer = StringBuffer()
      ..writeln(
        'timestamp_utc,device_id,seq,inlet_lpm,outlet_a_lpm,outlet_b_lpm,'
        'inlet_total_l,outlet_a_total_l,outlet_b_total_l,'
        'balance_lpm,expected_lpm,threshold_lpm,status,samples',
      );
    for (final r in rows) {
      buffer.writeln(
        <String>[
          DateTime.fromMillisecondsSinceEpoch(r.timestampMs, isUtc: true)
              .toIso8601String(),
          r.deviceId,
          '${r.seq}',
          r.flowLpm[0].toStringAsFixed(3),
          r.flowLpm[1].toStringAsFixed(3),
          r.flowLpm[2].toStringAsFixed(3),
          r.volumeL[0].toStringAsFixed(3),
          r.volumeL[1].toStringAsFixed(3),
          r.volumeL[2].toStringAsFixed(3),
          r.balanceLpm.toStringAsFixed(3),
          r.expectedLpm.toStringAsFixed(3),
          r.thresholdLpm.toStringAsFixed(3),
          r.status.wire,
          '${r.sampleCount}',
        ].join(','),
      );
    }
    return buffer.toString();
  }
}

import '../../core/protocol/leak_protocol.dart';

/// One persisted sample. Always stored in canonical units (L/min, litres) and
/// UTC-epoch milliseconds so unit and timezone settings can change freely
/// without invalidating history.
class StoredReading {
  const StoredReading({
    this.id,
    required this.timestampMs,
    required this.deviceId,
    required this.seq,
    required this.flowLpm,
    required this.volumeL,
    required this.balanceLpm,
    required this.expectedLpm,
    required this.thresholdLpm,
    required this.status,
    this.sampleCount = 1,
  });

  final int? id;
  final int timestampMs;
  final String deviceId;
  final int seq;
  final List<double> flowLpm;
  final List<double> volumeL;
  final double balanceLpm;
  final double expectedLpm;
  final double thresholdLpm;
  final LeakStatus status;

  /// How many 1 Hz device samples this row represents. Rows written by the
  /// downsampler cover several samples, and the aggregate queries weight by this
  /// so a coarse logging interval does not skew averages.
  final int sampleCount;

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true).toLocal();

  factory StoredReading.fromTelemetry(
    Telemetry t, {
    required String deviceId,
    int sampleCount = 1,
  }) {
    return StoredReading(
      timestampMs: t.receivedAt.toUtc().millisecondsSinceEpoch,
      deviceId: deviceId,
      seq: t.seq,
      flowLpm: List<double>.unmodifiable(t.flowLpm),
      volumeL: List<double>.unmodifiable(t.volumeL),
      balanceLpm: t.balanceLpm,
      expectedLpm: t.expectedLpm,
      thresholdLpm: t.thresholdLpm,
      status: t.status,
      sampleCount: sampleCount,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'ts': timestampMs,
        'device_id': deviceId,
        'seq': seq,
        'f1': flowLpm[0],
        'f2': flowLpm[1],
        'f3': flowLpm[2],
        'v1': volumeL[0],
        'v2': volumeL[1],
        'v3': volumeL[2],
        'balance': balanceLpm,
        'expected': expectedLpm,
        'threshold': thresholdLpm,
        'status': status.wire,
        'samples': sampleCount,
      };

  factory StoredReading.fromRow(Map<String, Object?> row) {
    double d(String key) => (row[key] as num?)?.toDouble() ?? 0;
    int i(String key) => (row[key] as num?)?.toInt() ?? 0;
    return StoredReading(
      id: row['id'] as int?,
      timestampMs: i('ts'),
      deviceId: (row['device_id'] as String?) ?? '',
      seq: i('seq'),
      flowLpm: <double>[d('f1'), d('f2'), d('f3')],
      volumeL: <double>[d('v1'), d('v2'), d('v3')],
      balanceLpm: d('balance'),
      expectedLpm: d('expected'),
      thresholdLpm: d('threshold'),
      status: LeakStatus.fromWire((row['status'] as String?) ?? 'UNKNOWN'),
      sampleCount: i('samples') == 0 ? 1 : i('samples'),
    );
  }
}

/// Kinds of entry in the event log.
enum EventKind {
  connected('CONNECTED'),
  disconnected('DISCONNECTED'),
  leakRaised('LEAK_RAISED'),
  leakCleared('LEAK_CLEARED'),
  faultRaised('FAULT_RAISED'),
  faultCleared('FAULT_CLEARED'),
  watch('WATCH'),
  watchRaised('WATCH_RAISED'),
  calibration('CALIBRATION'),
  configChanged('CONFIG_CHANGED'),
  note('NOTE');

  const EventKind(this.wire);
  final String wire;

  static EventKind fromWire(String raw) => EventKind.values.firstWhere(
        (e) => e.wire == raw,
        orElse: () => EventKind.note,
      );

  bool get isAlarm =>
      this == EventKind.leakRaised || this == EventKind.faultRaised;
}

/// A row in the event log — state transitions worth remembering, as opposed to
/// the continuous sample stream.
class LeakEvent {
  const LeakEvent({
    this.id,
    required this.timestampMs,
    required this.kind,
    required this.message,
    this.deviceId = '',
    this.balanceLpm,
    this.thresholdLpm,
  });

  final int? id;
  final int timestampMs;
  final EventKind kind;
  final String message;
  final String deviceId;
  final double? balanceLpm;
  final double? thresholdLpm;

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true).toLocal();

  Map<String, Object?> toRow() => <String, Object?>{
        'ts': timestampMs,
        'kind': kind.wire,
        'message': message,
        'device_id': deviceId,
        'balance': balanceLpm,
        'threshold': thresholdLpm,
      };

  factory LeakEvent.fromRow(Map<String, Object?> row) => LeakEvent(
        id: row['id'] as int?,
        timestampMs: (row['ts'] as num?)?.toInt() ?? 0,
        kind: EventKind.fromWire((row['kind'] as String?) ?? 'NOTE'),
        message: (row['message'] as String?) ?? '',
        deviceId: (row['device_id'] as String?) ?? '',
        balanceLpm: (row['balance'] as num?)?.toDouble(),
        thresholdLpm: (row['threshold'] as num?)?.toDouble(),
      );
}

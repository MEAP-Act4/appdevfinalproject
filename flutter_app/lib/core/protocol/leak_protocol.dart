/// Dart implementation of the LeakGuard link protocol v2.
/// Mirrors `firmware/PROTOCOL.md` and `react_app/src/core/protocol.ts`.
///
/// The HM-10 delivers at most 20 bytes per BLE notification, so a single
/// telemetry line arrives split across several packets. [LineAssembler] stitches
/// them back together; [LeakProtocol.parse] turns one complete line into a
/// [LeakPacket].
library;

import 'dart:convert';

const int kProtocolVersion = 2;
const int kSensorCount = 3;

/// HM-10 / CC2541 transparent-serial GATT identifiers.
const String kHm10ServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
const String kHm10CharacteristicUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

/// Firmware verdict for the current sample.
enum LeakStatus {
  /// No flow on any channel. Explicitly *not* an error condition.
  idle('IDLE'),

  /// Flowing and balanced inside the calibrated envelope.
  ok('OK'),

  /// Outside the envelope but not yet confirmed, or an over-read. Advisory only.
  watch('WATCH'),

  /// Confirmed sustained imbalance.
  leak('LEAK'),

  /// Implausible sensor topology — wiring or a dead sensor.
  fault('FAULT'),

  /// A baseline calibration run is in progress.
  calibrating('CAL'),

  /// Line was unreadable or the device has not reported yet.
  unknown('UNKNOWN');

  const LeakStatus(this.wire);

  /// The token used on the wire.
  final String wire;

  static LeakStatus fromWire(String raw) {
    final token = raw.trim().toUpperCase();
    for (final status in LeakStatus.values) {
      if (status.wire == token) return status;
    }
    // Tolerate the v1 firmware tokens so an un-flashed board still shows data.
    switch (token) {
      case 'ERROR_DISCONNECT':
        return LeakStatus.fault;
      case 'CALIBRATING':
        return LeakStatus.calibrating;
    }
    return LeakStatus.unknown;
  }

  bool get isAlarm => this == LeakStatus.leak || this == LeakStatus.fault;
  bool get isFlowing => this == LeakStatus.ok ||
      this == LeakStatus.watch ||
      this == LeakStatus.leak;
}

/// Logical role of each sensor on the manifold.
///
/// The wire index of each role is its declaration order, which `Enum.index`
/// already provides: inlet = 0, outletA = 1, outletB = 2. An enum cannot
/// re-declare `index`, so keep the declaration order in step with the
/// firmware's sensor numbering.
enum SensorRole {
  inlet('Main Inlet', 'Supply into the manifold'),
  outletA('Outlet A', 'First branch'),
  outletB('Outlet B', 'Second branch');

  const SensorRole(this.label, this.description);

  final String label;
  final String description;

  static SensorRole byIndex(int i) => SensorRole.values[i.clamp(0, 2)];
}

/// Base type for every decoded line.
sealed class LeakPacket {
  const LeakPacket();
}

/// `D` — one telemetry sample.
class Telemetry extends LeakPacket {
  const Telemetry({
    required this.seq,
    required this.uptimeMs,
    required this.flowLpm,
    required this.volumeL,
    required this.balanceLpm,
    required this.expectedLpm,
    required this.thresholdLpm,
    required this.status,
    required this.breachStreak,
    required this.faultStreak,
    required this.receivedAt,
  });

  final int seq;
  final int uptimeMs;

  /// Per-sensor flow in L/min, always length [kSensorCount].
  final List<double> flowLpm;

  /// Per-sensor cumulative volume in litres since the last `ZERO`.
  final List<double> volumeL;

  /// Signed `inlet - (outletA + outletB)`. Positive means water going missing.
  final double balanceLpm;

  /// Expected residual imbalance from the calibration dataset.
  final double expectedLpm;

  /// Alarm threshold at this operating point.
  final double thresholdLpm;

  final LeakStatus status;
  final int breachStreak;
  final int faultStreak;
  final DateTime receivedAt;

  double get inlet => flowLpm[0];
  double get outletA => flowLpm[1];
  double get outletB => flowLpm[2];
  double get totalOut => outletA + outletB;

  /// How far into the tolerance envelope this sample sits, 0..1+.
  /// 1.0 means exactly at the alarm threshold.
  double get envelopeUsage {
    if (thresholdLpm <= 0) return 0;
    return (balanceLpm.abs() / thresholdLpm).clamp(0.0, 2.0);
  }

  /// Estimated loss rate, floored at zero. Only meaningful while alarming.
  double get lossLpm {
    final excess = balanceLpm - thresholdLpm;
    return excess > 0 ? excess : 0;
  }

  @override
  String toString() =>
      'Telemetry(seq: $seq, flow: $flowLpm, status: ${status.wire})';
}

/// `H` — device handshake and full configuration.
class DeviceConfig extends LeakPacket {
  const DeviceConfig({
    required this.firmwareVersion,
    required this.protocolVersion,
    required this.sensorCount,
    required this.sampleIntervalMs,
    required this.pulsesPerLitre,
    required this.toleranceAbsLpm,
    required this.tolerancePct,
    required this.noiseFloorLpm,
    required this.faultMinFlowLpm,
    required this.leakConfirmSamples,
    required this.leakClearSamples,
    required this.faultConfirmSamples,
    required this.learnedBiasLpm,
  });

  final String firmwareVersion;
  final int protocolVersion;
  final int sensorCount;
  final int sampleIntervalMs;
  final List<double> pulsesPerLitre;
  final double toleranceAbsLpm;
  final double tolerancePct;
  final double noiseFloorLpm;
  final double faultMinFlowLpm;
  final int leakConfirmSamples;
  final int leakClearSamples;
  final int faultConfirmSamples;
  final double learnedBiasLpm;

  bool get isCompatible => protocolVersion == kProtocolVersion;
  bool get isCalibrated => learnedBiasLpm != 0.0;
}

/// `B` — one row of the calibration dataset.
class BaselineRow extends LeakPacket {
  const BaselineRow({
    required this.index,
    required this.inletLpm,
    required this.expectedBalanceLpm,
    required this.marginLpm,
  });

  final int index;
  final double inletLpm;
  final double expectedBalanceLpm;
  final double marginLpm;

  double get thresholdLpm => expectedBalanceLpm + marginLpm;
}

/// `B,END` — end of the dataset dump.
class BaselineEnd extends LeakPacket {
  const BaselineEnd(this.rowCount);
  final int rowCount;
}

enum CalibrationPhase { running, done, failed }

/// `C` — calibration progress.
class CalibrationUpdate extends LeakPacket {
  const CalibrationUpdate({
    required this.phase,
    this.secondsRemaining = 0,
    this.sampleCount = 0,
    this.meanBalanceLpm = 0,
    this.meanInletLpm = 0,
    this.reason = '',
  });

  final CalibrationPhase phase;
  final int secondsRemaining;
  final int sampleCount;
  final double meanBalanceLpm;
  final double meanInletLpm;
  final String reason;
}

/// `A` — command acknowledgement.
class CommandAck extends LeakPacket {
  const CommandAck({
    required this.command,
    required this.ok,
    required this.detail,
  });

  final String command;
  final bool ok;
  final String detail;
}

/// `L` — free-form device log.
class DeviceLog extends LeakPacket {
  const DeviceLog(this.message);
  final String message;
}

/// A line that did not decode. Kept rather than dropped so the diagnostics
/// screen can show the raw traffic.
class UnknownPacket extends LeakPacket {
  const UnknownPacket(this.raw, this.reason);
  final String raw;
  final String reason;
}

/// Stateless decoder.
class LeakProtocol {
  const LeakProtocol._();

  /// Decodes a single complete line (without its trailing newline).
  /// Returns `null` for blank lines.
  static LeakPacket? parse(String rawLine, {DateTime? now}) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;

    final parts = line.split(',');
    final tag = parts.first.trim().toUpperCase();

    try {
      switch (tag) {
        case 'D':
          return _parseTelemetry(parts, line, now ?? DateTime.now());
        case 'H':
          return _parseHandshake(parts, line);
        case 'B':
          return _parseBaseline(parts, line);
        case 'C':
          return _parseCalibration(parts, line);
        case 'A':
          if (parts.length < 3) {
            return UnknownPacket(line, 'ack needs 3+ fields');
          }
          return CommandAck(
            command: parts[1].trim(),
            ok: parts[2].trim().toUpperCase() == 'OK',
            detail: parts.length > 3 ? parts.sublist(3).join(',').trim() : '',
          );
        case 'L':
          return DeviceLog(parts.sublist(1).join(',').trim());
        default:
          // Graceful fallback for the original v1 sketch: "1.50,0.75,0.75,OK".
          final legacy = _parseLegacy(parts, now ?? DateTime.now());
          if (legacy != null) return legacy;
          return UnknownPacket(line, 'unrecognised tag "$tag"');
      }
    } on Object catch (error) {
      return UnknownPacket(line, 'decode error: $error');
    }
  }

  static Telemetry _parseTelemetry(
    List<String> p,
    String raw,
    DateTime now,
  ) {
    // D,seq,uptime,f1,f2,f3,v1,v2,v3,balance,expected,threshold,status,bs,fs
    const expectedFields = 15;
    if (p.length < expectedFields) {
      throw FormatException(
        'telemetry needs $expectedFields fields, got ${p.length}',
      );
    }
    return Telemetry(
      seq: _int(p[1]),
      uptimeMs: _int(p[2]),
      flowLpm: <double>[_double(p[3]), _double(p[4]), _double(p[5])],
      volumeL: <double>[_double(p[6]), _double(p[7]), _double(p[8])],
      balanceLpm: _double(p[9]),
      expectedLpm: _double(p[10]),
      thresholdLpm: _double(p[11]),
      status: LeakStatus.fromWire(p[12]),
      breachStreak: _int(p[13]),
      faultStreak: _int(p[14]),
      receivedAt: now,
    );
  }

  static DeviceConfig _parseHandshake(List<String> p, String raw) {
    // H,fw,proto,count,interval,ppl1,ppl2,ppl3,tolAbs,tolPct,nf,faultMin,
    //   leakConfirm,leakClear,faultConfirm,bias
    const expectedFields = 16;
    if (p.length < expectedFields) {
      throw FormatException(
        'handshake needs $expectedFields fields, got ${p.length}',
      );
    }
    return DeviceConfig(
      firmwareVersion: p[1].trim(),
      protocolVersion: _int(p[2]),
      sensorCount: _int(p[3]),
      sampleIntervalMs: _int(p[4]),
      pulsesPerLitre: <double>[_double(p[5]), _double(p[6]), _double(p[7])],
      toleranceAbsLpm: _double(p[8]),
      tolerancePct: _double(p[9]),
      noiseFloorLpm: _double(p[10]),
      faultMinFlowLpm: _double(p[11]),
      leakConfirmSamples: _int(p[12]),
      leakClearSamples: _int(p[13]),
      faultConfirmSamples: _int(p[14]),
      learnedBiasLpm: _double(p[15]),
    );
  }

  static LeakPacket _parseBaseline(List<String> p, String raw) {
    if (p.length >= 3 && p[1].trim().toUpperCase() == 'END') {
      return BaselineEnd(_int(p[2]));
    }
    if (p.length < 5) throw const FormatException('baseline row needs 5 fields');
    return BaselineRow(
      index: _int(p[1]),
      inletLpm: _double(p[2]),
      expectedBalanceLpm: _double(p[3]),
      marginLpm: _double(p[4]),
    );
  }

  static CalibrationUpdate _parseCalibration(List<String> p, String raw) {
    if (p.length < 2) throw const FormatException('calibration needs a phase');
    switch (p[1].trim().toUpperCase()) {
      case 'RUN':
        return CalibrationUpdate(
          phase: CalibrationPhase.running,
          secondsRemaining: p.length > 2 ? _int(p[2]) : 0,
          sampleCount: p.length > 3 ? _int(p[3]) : 0,
          meanBalanceLpm: p.length > 4 ? _double(p[4]) : 0,
        );
      case 'DONE':
        return CalibrationUpdate(
          phase: CalibrationPhase.done,
          meanBalanceLpm: p.length > 2 ? _double(p[2]) : 0,
          meanInletLpm: p.length > 3 ? _double(p[3]) : 0,
          sampleCount: p.length > 4 ? _int(p[4]) : 0,
        );
      default:
        return CalibrationUpdate(
          phase: CalibrationPhase.failed,
          reason: p.length > 2 ? p.sublist(2).join(',').trim() : 'unknown',
        );
    }
  }

  /// Understands the original sketch output `f1,f2,f3,STATUS` so the app still
  /// works against a board that has not been re-flashed yet. Volume, envelope
  /// and streak data are unavailable, so they come back as zero.
  static Telemetry? _parseLegacy(List<String> p, DateTime now) {
    if (p.length != 4) return null;
    final f1 = double.tryParse(p[0].trim());
    final f2 = double.tryParse(p[1].trim());
    final f3 = double.tryParse(p[2].trim());
    if (f1 == null || f2 == null || f3 == null) return null;
    final status = LeakStatus.fromWire(p[3]);
    if (status == LeakStatus.unknown) return null;
    final balance = f1 - (f2 + f3);
    return Telemetry(
      seq: 0,
      uptimeMs: 0,
      flowLpm: <double>[f1, f2, f3],
      volumeL: const <double>[0, 0, 0],
      balanceLpm: balance,
      expectedLpm: 0,
      thresholdLpm: 0.5,
      status: status,
      breachStreak: 0,
      faultStreak: 0,
      receivedAt: now,
    );
  }

  static int _int(String s) {
    final v = int.tryParse(s.trim());
    if (v != null) return v;
    return double.tryParse(s.trim())?.round() ?? 0;
  }

  static double _double(String s) {
    final v = double.tryParse(s.trim());
    if (v == null || v.isNaN || v.isInfinite) return 0;
    return v;
  }
}

/// Commands the app can send. Centralised so the wire format lives in one place.
class LeakCommand {
  const LeakCommand._();

  static const String ping = 'PING';
  static const String hello = 'HELLO';
  static const String requestBaseline = 'BASE?';
  static const String zeroTotals = 'ZERO';
  static const String cancel = 'CANCEL';
  static const String restoreDefaults = 'DEFAULTS';
  static const String reboot = 'REBOOT';

  static String pulsesPerLitre(int sensorIndexZeroBased, double ppl) =>
      'K,${sensorIndexZeroBased + 1},${ppl.toStringAsFixed(1)}';

  static String tolerance(double absLpm, double pctFraction) =>
      'TOL,${absLpm.toStringAsFixed(3)},${pctFraction.toStringAsFixed(4)}';

  static String noiseFloor(double lpm) => 'NF,${lpm.toStringAsFixed(3)}';

  static String debounce(int leakConfirm, int leakClear, int faultConfirm) =>
      'DB,$leakConfirm,$leakClear,$faultConfirm';

  static String calibrate(int seconds) => 'CAL,$seconds';
}

/// Reassembles newline-delimited lines from arbitrary byte chunks.
///
/// Guards against a misbehaving or noisy link by capping the buffer: a peer that
/// never sends `\n` cannot grow memory without bound.
class LineAssembler {
  LineAssembler({this.maxBufferBytes = 4096});

  final int maxBufferBytes;
  final StringBuffer _buffer = StringBuffer();

  /// Feeds raw bytes and returns every complete line found.
  List<String> addBytes(List<int> bytes) {
    // The firmware only ever emits printable ASCII, but decode leniently so one
    // corrupted byte cannot throw and kill the notification stream.
    return addChunk(const Utf8Decoder(allowMalformed: true).convert(bytes));
  }

  List<String> addChunk(String chunk) {
    _buffer.write(chunk);
    var text = _buffer.toString();

    if (text.length > maxBufferBytes) {
      // Keep the tail: the newest bytes are the ones most likely to complete a
      // real line.
      text = text.substring(text.length - maxBufferBytes);
    }

    final lines = <String>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        lines.add(text.substring(start, i));
        start = i + 1;
      }
    }

    _buffer
      ..clear()
      ..write(text.substring(start));

    return lines;
  }

  void reset() => _buffer.clear();
}

import 'dart:async';

/// Link lifecycle, independent of the underlying transport.
enum LinkState {
  /// Bluetooth is off, unsupported, or permissions were denied.
  unavailable,

  /// Ready, nothing connected.
  idle,

  scanning,
  connecting,

  /// GATT is up but the device has not sent a valid `H` handshake yet.
  handshaking,

  /// Fully usable.
  ready,

  /// Link dropped unexpectedly; a reconnect may be in flight.
  reconnecting,

  failed,
}

extension LinkStateX on LinkState {
  bool get isBusy =>
      this == LinkState.scanning ||
      this == LinkState.connecting ||
      this == LinkState.handshaking ||
      this == LinkState.reconnecting;

  bool get grantsAccess => this == LinkState.ready;
}

/// A device advertisement surfaced to the pairing UI.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.advertisesLeakService = false,
  });

  final String id;
  final String name;
  final int rssi;

  /// True when the advertisement contained the HM-10 FFE0 service UUID. Those
  /// are sorted to the top of the list.
  final bool advertisesLeakService;

  /// Rough 0..4 bar strength for the UI.
  int get bars {
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -80) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }

  String get displayName => name.trim().isEmpty ? 'Unnamed device' : name.trim();
}

/// Something went wrong on the link. Carries a message the UI can show verbatim.
class TransportFailure implements Exception {
  const TransportFailure(this.message, {this.isRecoverable = true, this.cause});

  final String message;
  final bool isRecoverable;
  final Object? cause;

  @override
  String toString() => 'TransportFailure($message)';
}

/// Abstraction over "a bidirectional byte pipe to the LeakGuard board".
///
/// Two implementations exist: the real HM-10 BLE link, and a simulator used for
/// UI work and for demonstrating the app without hardware present. The rest of
/// the app only knows about this interface.
abstract class LeakTransport {
  /// Human label shown in diagnostics, e.g. "BLE" or "Simulator".
  String get kind;

  Stream<LinkState> get stateStream;
  LinkState get state;

  /// Complete protocol lines, newline stripped.
  Stream<String> get lines;

  /// Non-fatal diagnostics worth surfacing.
  Stream<String> get diagnostics;

  Stream<List<DiscoveredDevice>> get discoveries;

  DiscoveredDevice? get connectedDevice;

  Future<bool> isSupported();

  /// Requests any OS permissions the transport needs. Returns false if denied.
  Future<bool> ensurePermissions();

  Future<void> startScan({Duration timeout = const Duration(seconds: 12)});

  Future<void> stopScan();

  Future<void> connect(String deviceId);

  Future<void> disconnect();

  /// Sends one command. Implementations append the newline and chunk to the
  /// transport MTU.
  Future<void> send(String command);

  Future<void> dispose();
}

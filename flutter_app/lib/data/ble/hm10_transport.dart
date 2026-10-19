import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/protocol/leak_protocol.dart';
import 'leak_transport.dart';

/// Real transport: HM-10 (CC2541) transparent serial over GATT.
///
/// Practical details this class handles so the rest of the app does not have to:
///  * The HM-10 advertises service `FFE0` with one characteristic `FFE1` used for
///    both notify and write. Some clones expose it without the notify property
///    set correctly, so we fall back to any writable characteristic in FFE0.
///  * Notifications are capped at 20 bytes, so lines arrive fragmented. A
///    [LineAssembler] restores them.
///  * Writes are chunked to 20 bytes with a small gap; the module's UART buffer
///    is tiny and will silently drop a longer burst.
///  * Android 12+ needs the new `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` runtime
///    permissions; older versions need location instead.
class Hm10Transport implements LeakTransport {
  Hm10Transport();

  static const int _mtuPayload = 20;
  static const Duration _writeGap = Duration(milliseconds: 25);
  static const Duration _connectTimeout = Duration(seconds: 15);

  /// If no telemetry arrives for this long the link is treated as stale.
  static const Duration staleAfter = Duration(seconds: 6);

  final StreamController<LinkState> _stateController =
      StreamController<LinkState>.broadcast();
  final StreamController<String> _lineController =
      StreamController<String>.broadcast();
  final StreamController<String> _diagnosticsController =
      StreamController<String>.broadcast();
  final StreamController<List<DiscoveredDevice>> _discoveryController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  final LineAssembler _assembler = LineAssembler();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _channel;
  DiscoveredDevice? _connected;

  LinkState _state = LinkState.idle;
  bool _disposed = false;

  /// Guards against overlapping writes: the HM-10 cannot interleave them.
  Future<void> _writeQueue = Future<void>.value();

  // --- Notify watchdog -------------------------------------------------------
  // HM-10 clones often keep the GATT link up (LED solid) but silently stop
  // delivering notifications after a few seconds. We track when data last
  // arrived and, if it goes quiet on a live link, toggle the notify descriptor
  // off/on to kick the module back into streaming — all without dropping the
  // connection.
  Timer? _notifyWatchdog;
  DateTime? _lastDataAt;
  bool _reArming = false;

  /// Quiet period on a live link before we re-arm notifications.
  static const Duration _notifyQuietAfter = Duration(seconds: 4);

  @override
  String get kind => 'BLE';

  @override
  LinkState get state => _state;

  @override
  Stream<LinkState> get stateStream => _stateController.stream;

  @override
  Stream<String> get lines => _lineController.stream;

  @override
  Stream<String> get diagnostics => _diagnosticsController.stream;

  @override
  Stream<List<DiscoveredDevice>> get discoveries => _discoveryController.stream;

  @override
  DiscoveredDevice? get connectedDevice => _connected;

  void _setState(LinkState next) {
    if (_disposed || _state == next) return;
    _state = next;
    _stateController.add(next);
  }

  void _log(String message) {
    if (_disposed) return;
    _diagnosticsController.add(message);
  }

  // ---------------------------------------------------------------------------
  // Capability + permissions
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isSupported() async {
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        _log('This device has no Bluetooth LE radio.');
        _setState(LinkState.unavailable);
      }
      return supported;
    } on Object catch (error) {
      _log('Could not query Bluetooth support: $error');
      return false;
    }
  }

  @override
  Future<bool> ensurePermissions() async {
    try {
      if (Platform.isAndroid) {
        final results = await <Permission>[
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();

        final denied = results.entries
            .where((e) => !e.value.isGranted)
            .map((e) => e.key.toString())
            .toList();

        if (denied.isNotEmpty) {
          // Pre-Android-12 devices report the new permissions as denied and use
          // location instead, so try that before giving up.
          final location = await Permission.locationWhenInUse.request();
          if (!location.isGranted) {
            _log('Bluetooth permission denied: ${denied.join(', ')}');
            _setState(LinkState.unavailable);
            return false;
          }
        }
      } else if (Platform.isIOS) {
        final status = await Permission.bluetooth.request();
        if (status.isPermanentlyDenied) {
          _log('Bluetooth permission permanently denied. Open Settings.');
          _setState(LinkState.unavailable);
          return false;
        }
      }
      return true;
    } on Object catch (error) {
      _log('Permission request failed: $error');
      return false;
    }
  }

  /// Watches the adapter so turning Bluetooth off is reflected immediately.
  void watchAdapter() {
    _adapterSub ??= FlutterBluePlus.adapterState.listen((adapterState) {
      if (adapterState == BluetoothAdapterState.on) {
        if (_state == LinkState.unavailable) _setState(LinkState.idle);
      } else {
        _log('Bluetooth adapter is ${adapterState.name}.');
        _setState(LinkState.unavailable);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 12)}) async {
    if (!await isSupported()) {
      throw const TransportFailure(
        'Bluetooth LE is not available on this device.',
        isRecoverable: false,
      );
    }
    if (!await ensurePermissions()) {
      throw const TransportFailure(
        'Bluetooth permission is required to find the LeakGuard module.',
      );
    }
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      throw const TransportFailure('Turn Bluetooth on to continue.');
    }

    await stopScan();
    _setState(LinkState.scanning);

    final seen = <String, DiscoveredDevice>{};

    _scanSub = FlutterBluePlus.onScanResults.listen(
      (results) {
        var changed = false;
        for (final result in results) {
          final advertisesService = result.advertisementData.serviceUuids.any(
            (guid) => _isLeakServiceUuid(guid),
          );
          final id = result.device.remoteId.str;
          final name = result.advertisementData.advName.isNotEmpty
              ? result.advertisementData.advName
              : result.device.platformName;

          final candidate = DiscoveredDevice(
            id: id,
            name: name,
            rssi: result.rssi,
            advertisesLeakService: advertisesService,
          );

          final previous = seen[id];
          if (previous == null ||
              previous.rssi != candidate.rssi ||
              previous.name != candidate.name) {
            seen[id] = candidate;
            changed = true;
          }
        }
        if (changed) _emitDiscoveries(seen.values.toList());
      },
      onError: (Object error) => _log('Scan error: $error'),
    );

    try {
      // Scanning unfiltered: many HM-10 clones do not put FFE0 in the
      // advertisement, they only expose it after connecting. Filtering by
      // service would hide exactly the modules we care about.
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );
    } on Object catch (error) {
      _setState(LinkState.failed);
      throw TransportFailure('Could not start scanning: $error', cause: error);
    }

    // When the timeout elapses FlutterBluePlus stops on its own; reflect that.
    Timer(timeout + const Duration(milliseconds: 250), () {
      if (_state == LinkState.scanning) _setState(LinkState.idle);
    });
  }

  void _emitDiscoveries(List<DiscoveredDevice> devices) {
    devices.sort((a, b) {
      // Modules advertising the service first, then likely HM-10 names, then by
      // signal strength.
      if (a.advertisesLeakService != b.advertisesLeakService) {
        return a.advertisesLeakService ? -1 : 1;
      }
      final aLikely = _looksLikeHm10(a.name);
      final bLikely = _looksLikeHm10(b.name);
      if (aLikely != bLikely) return aLikely ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });
    if (!_disposed) _discoveryController.add(devices);
  }

  static bool _looksLikeHm10(String name) {
    final n = name.toUpperCase();
    return n.contains('HM') ||
        n.contains('BT05') ||
        n.contains('MLT') ||
        n.contains('LEAK');
  }

  static bool _isLeakServiceUuid(Guid guid) {
    final s = guid.str.toLowerCase().replaceAll('-', '');
    return s == 'ffe0' || s.startsWith('0000ffe0');
  }

  static bool _isLeakCharacteristicUuid(Guid guid) {
    final s = guid.str.toLowerCase().replaceAll('-', '');
    return s == 'ffe1' || s.startsWith('0000ffe1');
  }

  @override
  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    } on Object catch (error) {
      _log('stopScan: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Connect
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect(String deviceId) async {
    await stopScan();
    _setState(LinkState.connecting);
    _assembler.reset();

    final device = BluetoothDevice.fromId(deviceId);
    _device = device;

    try {
      await _connectionSub?.cancel();
      // `connectionState` replays the CURRENT value on subscribe, which is
      // `disconnected` here because we have not connected yet. Acting on that
      // flipped the link straight to `reconnecting` and kicked off a reconnect
      // race against our own in-flight connect(). Only treat a `disconnected`
      // as a real drop once we have actually observed `connected` first.
      var hasConnected = false;
      _connectionSub = device.connectionState.listen((connectionState) {
        if (connectionState == BluetoothConnectionState.connected) {
          hasConnected = true;
          return;
        }
        if (connectionState == BluetoothConnectionState.disconnected) {
          if (!hasConnected) return; // spurious pre-connect emission, ignore
          _log('Disconnected: ${device.disconnectReason?.description ?? 'link lost'}');
          _channel = null;
          _connected = null;
          if (_state == LinkState.ready ||
              _state == LinkState.handshaking ||
              _state == LinkState.connecting) {
            _setState(LinkState.reconnecting);
          }
        }
      });

      // `license` is a flutter_blue_plus 2.x requirement: this is a personal /
      // educational project, so the nonprofit terms apply.
      await device.connect(
        license: License.nonprofit,
        timeout: _connectTimeout,
        autoConnect: false,
      );

      // Ask for the biggest MTU the phone will grant. The HM-10 ignores it and
      // stays at 20 bytes, but a larger MTU costs nothing and helps clones.
      if (Platform.isAndroid) {
        try {
          await device.requestMtu(64);
        } on Object catch (_) {
          // Non-fatal: plenty of stacks refuse this.
        }
      }

      final services = await device.discoverServices();
      final channel = _selectChannel(services);
      if (channel == null) {
        await device.disconnect();
        throw const TransportFailure(
          'That device is not a LeakGuard module — no FFE0 serial service found.',
        );
      }
      _channel = channel;

      await _notifySub?.cancel();
      _notifySub = channel.onValueReceived.listen(
        _ingest,
        onError: (Object error) => _log('Notify error: $error'),
      );
      device.cancelWhenDisconnected(_notifySub!);

      if (channel.properties.notify || channel.properties.indicate) {
        await channel.setNotifyValue(true);
      } else {
        _log(
          'Characteristic FFE1 does not advertise notify. '
          'Falling back to polling is not supported — check the module.',
        );
      }

      _connected = DiscoveredDevice(
        id: deviceId,
        name: device.platformName,
        rssi: 0,
        advertisesLeakService: true,
      );

      _setState(LinkState.handshaking);

      // Nudge the board: it sends `H` at boot, but we may have connected later.
      // These writes are best-effort: an HM-10 clone can drop the link if it is
      // written to before it has settled, and a write that throws here used to
      // bubble up and fail the whole connection. Delay briefly to let the link
      // settle, then fire the nudges without letting a write error tear the
      // connection down — the board streams telemetry on its own regardless, so
      // a missed HELLO/BASE? is harmless.
      unawaited(Future<void>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        try {
          await send(LeakCommand.hello);
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await send(LeakCommand.requestBaseline);
        } on Object catch (error) {
          _log('Initial nudge skipped: $error');
        }
      }));

      // Start the notify watchdog: HM-10 clones often keep the GATT link up
      // (LED stays solid) but silently stop pushing notifications after a few
      // seconds. The watchdog re-arms the CCCD when the feed goes quiet, which
      // kicks the module back into streaming without dropping the connection.
      _startNotifyWatchdog();
    } on TransportFailure {
      _setState(LinkState.failed);
      rethrow;
    } on Object catch (error) {
      _setState(LinkState.failed);
      throw TransportFailure('Connection failed: $error', cause: error);
    }
  }

  BluetoothCharacteristic? _selectChannel(List<BluetoothService> services) {
    BluetoothCharacteristic? fallback;

    for (final service in services) {
      final isLeakService = _isLeakServiceUuid(service.uuid);
      for (final characteristic in service.characteristics) {
        final props = characteristic.properties;
        final writable = props.write || props.writeWithoutResponse;
        final readable = props.notify || props.indicate;

        if (isLeakService && _isLeakCharacteristicUuid(characteristic.uuid)) {
          return characteristic;
        }
        if (isLeakService && writable && readable) {
          fallback ??= characteristic;
        }
      }
    }
    return fallback;
  }

  /// Called for the caller-visible "ready" transition once a valid handshake or
  /// telemetry line has been decoded. Kept separate so the controller decides
  /// what counts as a working link.
  void markReady() {
    if (_state == LinkState.handshaking ||
        _state == LinkState.reconnecting ||
        _state == LinkState.connecting) {
      _setState(LinkState.ready);
    }
  }

  void _ingest(List<int> bytes) {
    _lastDataAt = DateTime.now();
    for (final line in _assembler.addBytes(bytes)) {
      if (line.trim().isEmpty) continue;
      if (!_disposed) _lineController.add(line);
    }
  }

  // ---------------------------------------------------------------------------
  // Notify watchdog — recover a silent-but-connected HM-10
  // ---------------------------------------------------------------------------

  void _startNotifyWatchdog() {
    _lastDataAt = DateTime.now();
    _notifyWatchdog?.cancel();
    _notifyWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_disposed) return;
      final channel = _channel;
      if (channel == null) return;
      final last = _lastDataAt;
      if (last == null) return;
      // Only act on a live link that has simply gone quiet.
      if (DateTime.now().difference(last) >= _notifyQuietAfter) {
        unawaited(_reArmNotify());
      }
    });
  }

  /// Toggle the notify descriptor off then on to make a silent clone resume
  /// streaming, without tearing down the GATT link.
  Future<void> _reArmNotify() async {
    if (_reArming || _disposed) return;
    final channel = _channel;
    if (channel == null) return;
    if (!(channel.properties.notify || channel.properties.indicate)) return;
    _reArming = true;
    try {
      _log('Feed quiet — re-arming notifications.');
      await channel.setNotifyValue(false);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await channel.setNotifyValue(true);
      // A gentle nudge in case the board is waiting for a prompt.
      try {
        await _sendNow(LeakCommand.hello);
      } on Object catch (_) {
        // Best effort only.
      }
      // Reset the clock so we do not hammer the descriptor every tick.
      _lastDataAt = DateTime.now();
    } on Object catch (error) {
      _log('Re-arm failed: $error');
    } finally {
      _reArming = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  @override
  Future<void> send(String command) {
    // Serialise every write through a queue. Two concurrent 20-byte writes to an
    // HM-10 interleave on the UART and corrupt both commands.
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _sendNow(command);
        completer.complete();
      } on Object catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> _sendNow(String command) async {
    final channel = _channel;
    if (channel == null) {
      throw const TransportFailure('Not connected.');
    }

    final payload = '${command.trim()}\n'.codeUnits;
    final withoutResponse = channel.properties.writeWithoutResponse &&
        !channel.properties.write;

    for (var offset = 0; offset < payload.length; offset += _mtuPayload) {
      final end = (offset + _mtuPayload).clamp(0, payload.length);
      await channel.write(
        payload.sublist(offset, end),
        withoutResponse: withoutResponse,
      );
      if (end < payload.length) await Future<void>.delayed(_writeGap);
    }
  }

  // ---------------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------------

  @override
  Future<void> disconnect() async {
    _notifyWatchdog?.cancel();
    _notifyWatchdog = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    try {
      await _device?.disconnect();
    } on Object catch (error) {
      _log('disconnect: $error');
    }
    _channel = null;
    _device = null;
    _connected = null;
    _assembler.reset();
    _setState(LinkState.idle);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _notifyWatchdog?.cancel();
    await stopScan();
    await _notifySub?.cancel();
    await _connectionSub?.cancel();
    await _adapterSub?.cancel();
    try {
      await _device?.disconnect();
    } on Object catch (_) {
      // Best effort.
    }
    await _stateController.close();
    await _lineController.close();
    await _diagnosticsController.close();
    await _discoveryController.close();
  }
}

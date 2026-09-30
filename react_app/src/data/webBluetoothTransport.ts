import {
  Command,
  HM10_CHARACTERISTIC_UUID,
  HM10_SERVICE_UUID,
  LineAssembler,
} from '../core/protocol';
import {
  TransportFailure,
  type DiscoveredDevice,
  type LeakTransport,
  type LinkState,
  type TransportListeners,
} from './transport';

/**
 * Web Bluetooth transport for the HM-10.
 *
 * Differences from the Flutter/native path, all forced by the browser API:
 *  * There is no free-running scan. `navigator.bluetooth.requestDevice` hands off
 *    to the browser's own chooser UI, which the user must drive. So "scan" here
 *    means "open the chooser", and the result is a single already-chosen device.
 *  * Reconnecting without a user gesture only works for devices the origin has
 *    already been granted, via `getDevices()`, and only in Chromium.
 *  * A secure context is required: HTTPS, or localhost during development.
 *
 * Everything below the byte stream — framing, decoding, evaluation — is identical
 * to the Flutter client.
 */
export class WebBluetoothTransport implements LeakTransport {
  readonly kind = 'Web Bluetooth';

  private listeners: TransportListeners | null = null;
  private currentState: LinkState = 'idle';
  private device: BluetoothDevice | null = null;
  private channel: BluetoothRemoteGATTCharacteristic | null = null;
  private connected: DiscoveredDevice | null = null;
  private readonly assembler = new LineAssembler();
  private writeQueue: Promise<void> = Promise.resolve();
  private disposed = false;

  private static readonly MTU_PAYLOAD = 20;
  private static readonly WRITE_GAP_MS = 25;

  /** No telemetry for this long and the link counts as stale. */
  static readonly STALE_AFTER_MS = 6000;

  get state(): LinkState {
    return this.currentState;
  }

  get connectedDevice(): DiscoveredDevice | null {
    return this.connected;
  }

  listen(listeners: TransportListeners): void {
    this.listeners = listeners;
    listeners.onState(this.currentState);
  }

  private setState(next: LinkState): void {
    if (this.disposed || this.currentState === next) return;
    this.currentState = next;
    this.listeners?.onState(next);
  }

  private log(message: string): void {
    this.listeners?.onDiagnostic(message);
  }

  async isSupported(): Promise<boolean> {
    if (typeof navigator === 'undefined' || !navigator.bluetooth) {
      this.log(
        'This browser has no Web Bluetooth support. Use Chrome, Edge or another ' +
          'Chromium browser over HTTPS or on localhost.',
      );
      this.setState('unavailable');
      return false;
    }
    if (!window.isSecureContext) {
      this.log('Web Bluetooth needs a secure context (HTTPS or localhost).');
      this.setState('unavailable');
      return false;
    }
    try {
      const available = await navigator.bluetooth.getAvailability();
      if (!available) {
        this.log('No Bluetooth adapter available, or it is switched off.');
        this.setState('unavailable');
      }
      return available;
    } catch {
      // getAvailability is not implemented everywhere; assume usable.
      return true;
    }
  }

  /**
   * Opens the browser's device chooser. Filtering on the FFE0 service would hide
   * the many HM-10 clones that omit it from their advertisement, so we accept all
   * devices and verify the service after connecting.
   */
  async startScan(): Promise<void> {
    if (!(await this.isSupported())) {
      throw new TransportFailure('Web Bluetooth is not available here.', false);
    }

    this.setState('scanning');
    try {
      const device = await navigator.bluetooth.requestDevice({
        acceptAllDevices: true,
        optionalServices: [HM10_SERVICE_UUID],
      });
      this.device = device;
      const discovered: DiscoveredDevice = {
        id: device.id,
        name: device.name ?? 'Unnamed device',
        rssi: 0,
        advertisesLeakService: false,
      };
      this.listeners?.onDiscoveries([discovered]);
      this.setState('idle');
    } catch (error) {
      this.setState('idle');
      if (error instanceof DOMException && error.name === 'NotFoundError') {
        // The user closed the chooser. Not an error worth shouting about.
        this.listeners?.onDiscoveries([]);
        return;
      }
      throw new TransportFailure(`Could not open the device chooser: ${String(error)}`);
    }
  }

  async stopScan(): Promise<void> {
    if (this.currentState === 'scanning') this.setState('idle');
  }

  /** Reattaches to a device this origin was already granted, without a prompt. */
  async reconnectKnown(deviceId: string): Promise<boolean> {
    if (!navigator.bluetooth?.getDevices) return false;
    try {
      const devices = await navigator.bluetooth.getDevices();
      const match = devices.find((d) => d.id === deviceId);
      if (!match) return false;
      this.device = match;
      await this.connect(deviceId);
      return true;
    } catch (error) {
      this.log(`Silent reconnect failed: ${String(error)}`);
      return false;
    }
  }

  async connect(deviceId: string): Promise<void> {
    const device = this.device;
    if (!device || device.id !== deviceId) {
      throw new TransportFailure(
        'Pick the module from the browser chooser first — the browser will not ' +
          'let a page connect to a device the user has not selected.',
      );
    }

    this.setState('connecting');
    this.assembler.reset();

    try {
      device.addEventListener('gattserverdisconnected', this.handleDisconnect);

      const server = await device.gatt?.connect();
      if (!server) throw new TransportFailure('GATT server unavailable.');

      const service = await server.getPrimaryService(HM10_SERVICE_UUID).catch(() => null);
      if (!service) {
        server.disconnect();
        throw new TransportFailure(
          'That device is not a LeakGuard module — no FFE0 serial service found.',
        );
      }

      const characteristic = await service
        .getCharacteristic(HM10_CHARACTERISTIC_UUID)
        .catch(() => null);
      if (!characteristic) {
        server.disconnect();
        throw new TransportFailure('FFE1 characteristic missing on this module.');
      }

      this.channel = characteristic;
      characteristic.addEventListener('characteristicvaluechanged', this.handleValue);
      await characteristic.startNotifications();

      this.connected = {
        id: device.id,
        name: device.name ?? 'LeakGuard module',
        rssi: 0,
        advertisesLeakService: true,
      };

      this.setState('handshaking');

      // The board sends H at boot; we may have connected later.
      await this.send(Command.hello);
      await this.send(Command.requestBaseline);
    } catch (error) {
      this.setState('failed');
      if (error instanceof TransportFailure) throw error;
      throw new TransportFailure(`Connection failed: ${String(error)}`);
    }
  }

  private readonly handleDisconnect = (): void => {
    this.log('Disconnected from the module.');
    this.channel = null;
    this.connected = null;
    if (
      this.currentState === 'ready' ||
      this.currentState === 'handshaking' ||
      this.currentState === 'connecting'
    ) {
      this.setState('reconnecting');
    }
  };

  private readonly handleValue = (event: Event): void => {
    const target = event.target as BluetoothRemoteGATTCharacteristic;
    const value = target.value;
    if (!value) return;
    for (const line of this.assembler.addBytes(value)) {
      if (line.trim().length === 0) continue;
      this.listeners?.onLine(line);
    }
  };

  markReady(): void {
    if (
      this.currentState === 'handshaking' ||
      this.currentState === 'reconnecting' ||
      this.currentState === 'connecting'
    ) {
      this.setState('ready');
    }
  }

  /**
   * Writes are serialised through a queue and chunked to 20 bytes. Two concurrent
   * writes to an HM-10 interleave on its UART and corrupt both commands.
   */
  send(command: string): Promise<void> {
    const task = this.writeQueue.then(() => this.sendNow(command));
    // Keep the chain alive even if one write rejects.
    this.writeQueue = task.catch(() => undefined);
    return task;
  }

  private async sendNow(command: string): Promise<void> {
    const channel = this.channel;
    if (!channel) throw new TransportFailure('Not connected.');

    const payload = new TextEncoder().encode(`${command.trim()}\n`);
    const canWriteWithoutResponse =
      channel.properties.writeWithoutResponse && !channel.properties.write;

    for (let offset = 0; offset < payload.length; offset += WebBluetoothTransport.MTU_PAYLOAD) {
      const chunk = payload.slice(offset, offset + WebBluetoothTransport.MTU_PAYLOAD);
      if (canWriteWithoutResponse) {
        await channel.writeValueWithoutResponse(chunk);
      } else {
        await channel.writeValue(chunk);
      }
      if (offset + WebBluetoothTransport.MTU_PAYLOAD < payload.length) {
        await new Promise((resolve) =>
          setTimeout(resolve, WebBluetoothTransport.WRITE_GAP_MS),
        );
      }
    }
  }

  async disconnect(): Promise<void> {
    try {
      this.channel?.removeEventListener('characteristicvaluechanged', this.handleValue);
      await this.channel?.stopNotifications().catch(() => undefined);
      this.device?.removeEventListener('gattserverdisconnected', this.handleDisconnect);
      this.device?.gatt?.disconnect();
    } catch (error) {
      this.log(`Disconnect: ${String(error)}`);
    }
    this.channel = null;
    this.connected = null;
    this.assembler.reset();
    this.setState('idle');
  }

  async dispose(): Promise<void> {
    this.disposed = true;
    await this.disconnect();
    this.listeners = null;
  }
}

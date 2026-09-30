/** Transport abstraction shared by the Web Bluetooth link and the simulator. */

export type LinkState =
  | 'unavailable'
  | 'idle'
  | 'scanning'
  | 'connecting'
  | 'handshaking'
  | 'ready'
  | 'reconnecting'
  | 'failed';

export function isBusy(state: LinkState): boolean {
  return (
    state === 'scanning' ||
    state === 'connecting' ||
    state === 'handshaking' ||
    state === 'reconnecting'
  );
}

export function grantsAccess(state: LinkState): boolean {
  return state === 'ready';
}

export interface DiscoveredDevice {
  id: string;
  name: string;
  /** Web Bluetooth does not expose RSSI from the chooser, so this stays 0. */
  rssi: number;
  advertisesLeakService: boolean;
}

export class TransportFailure extends Error {
  readonly recoverable: boolean;

  constructor(message: string, recoverable = true) {
    super(message);
    this.name = 'TransportFailure';
    this.recoverable = recoverable;
  }
}

export interface TransportListeners {
  onState: (state: LinkState) => void;
  onLine: (line: string) => void;
  onDiagnostic: (message: string) => void;
  onDiscoveries: (devices: DiscoveredDevice[]) => void;
}

export interface LeakTransport {
  readonly kind: string;
  readonly state: LinkState;
  readonly connectedDevice: DiscoveredDevice | null;

  listen(listeners: TransportListeners): void;
  isSupported(): Promise<boolean>;
  startScan(): Promise<void>;
  stopScan(): Promise<void>;
  connect(deviceId: string): Promise<void>;
  disconnect(): Promise<void>;
  send(command: string): Promise<void>;
  /** Called once a valid handshake or telemetry line has been decoded. */
  markReady(): void;
  dispose(): Promise<void>;
}

/**
 * Unit handling. The firmware always reports L/min and litres; conversion happens
 * at render time only, so stored history stays comparable when the user switches
 * units.
 */

export type FlowUnitId =
  | 'lpm'
  | 'lph'
  | 'lps'
  | 'usgpm'
  | 'impgpm'
  | 'm3ph';

export interface FlowUnit {
  id: FlowUnitId;
  symbol: string;
  label: string;
  /** Multiplier applied to a value in L/min. */
  fromLpm: number;
  decimals: number;
}

export const FLOW_UNITS: readonly FlowUnit[] = [
  { id: 'lpm', symbol: 'L/min', label: 'Litres per minute', fromLpm: 1, decimals: 2 },
  { id: 'lph', symbol: 'L/h', label: 'Litres per hour', fromLpm: 60, decimals: 1 },
  { id: 'lps', symbol: 'L/s', label: 'Litres per second', fromLpm: 1 / 60, decimals: 3 },
  { id: 'usgpm', symbol: 'gal/min', label: 'US gallons per minute', fromLpm: 0.2641720524, decimals: 2 },
  { id: 'impgpm', symbol: 'impgal/min', label: 'Imperial gallons per minute', fromLpm: 0.2199692483, decimals: 2 },
  { id: 'm3ph', symbol: 'm³/h', label: 'Cubic metres per hour', fromLpm: 0.06, decimals: 3 },
];

export type VolumeUnitId = 'l' | 'm3' | 'usgal' | 'impgal';

export interface VolumeUnit {
  id: VolumeUnitId;
  symbol: string;
  label: string;
  fromLitres: number;
  decimals: number;
}

export const VOLUME_UNITS: readonly VolumeUnit[] = [
  { id: 'l', symbol: 'L', label: 'Litres', fromLitres: 1, decimals: 1 },
  { id: 'm3', symbol: 'm³', label: 'Cubic metres', fromLitres: 0.001, decimals: 3 },
  { id: 'usgal', symbol: 'gal', label: 'US gallons', fromLitres: 0.2641720524, decimals: 1 },
  { id: 'impgal', symbol: 'impgal', label: 'Imperial gallons', fromLitres: 0.2199692483, decimals: 1 },
];

export function flowUnit(id: FlowUnitId): FlowUnit {
  return FLOW_UNITS.find((u) => u.id === id) ?? FLOW_UNITS[0]!;
}

export function volumeUnit(id: VolumeUnitId): VolumeUnit {
  return VOLUME_UNITS.find((u) => u.id === id) ?? VOLUME_UNITS[0]!;
}

/** The volume unit that naturally pairs with a flow unit. */
export function companionVolumeUnit(id: FlowUnitId): VolumeUnitId {
  switch (id) {
    case 'usgpm':
      return 'usgal';
    case 'impgpm':
      return 'impgal';
    case 'm3ph':
      return 'm3';
    default:
      return 'l';
  }
}

function fixed(value: number, decimals: number): string {
  if (!Number.isFinite(value)) return '--';
  const rounded = Number.parseFloat(value.toFixed(decimals));
  const safe = rounded === 0 ? 0 : rounded;
  return safe.toFixed(decimals);
}

export interface Formatter {
  flow: FlowUnit;
  volume: VolumeUnit;
  flowValue: (lpm: number, decimals?: number) => string;
  flowText: (lpm: number, decimals?: number) => string;
  volumeValue: (litres: number, decimals?: number) => string;
  volumeText: (litres: number, decimals?: number) => string;
}

export function createFormatter(flowId: FlowUnitId, volumeId: VolumeUnitId): Formatter {
  const flow = flowUnit(flowId);
  const volume = volumeUnit(volumeId);
  return {
    flow,
    volume,
    flowValue: (lpm, decimals) => fixed(lpm * flow.fromLpm, decimals ?? flow.decimals),
    flowText: (lpm, decimals) =>
      `${fixed(lpm * flow.fromLpm, decimals ?? flow.decimals)} ${flow.symbol}`,
    volumeValue: (litres, decimals) =>
      fixed(litres * volume.fromLitres, decimals ?? volume.decimals),
    volumeText: (litres, decimals) =>
      `${fixed(litres * volume.fromLitres, decimals ?? volume.decimals)} ${volume.symbol}`,
  };
}

export function formatDuration(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  if (seconds < 60) return `${seconds} s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    const rem = minutes % 60;
    return rem === 0 ? `${hours} h` : `${hours} h ${rem} m`;
  }
  const days = Math.floor(hours / 24);
  const rem = hours % 24;
  return rem === 0 ? `${days} d` : `${days} d ${rem} h`;
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

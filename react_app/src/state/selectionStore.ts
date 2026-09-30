import { useSyncExternalStore } from 'react';

import { SENSOR_COUNT } from '../core/protocol';

/**
 * The selected sensor channel, shared across the Compact carousel and the
 * Medium/Expanded Dashboard_View.
 *
 * Requirements 4.3 and 4.4 ask that the selection survive a Layout_Mode change:
 * the carousel page the user was on becomes the Dashboard_View's selected
 * channel, and vice versa. On the web this is a module-level singleton — the
 * same shape as `settingsStore` — so it already lives outside the component tree
 * and outlives the presentation swap by construction. That is the web
 * equivalent of the Flutter twin being "provided above the layout switch"
 * (task 9.2's `SelectionController`).
 *
 * Unlike `settingsStore`, this store has NO persistence at all: it never reads
 * or writes localStorage. The requirement is continuity across a breakpoint
 * change within a session, not across a restart, so a persisted settings key
 * would add storage with no stated need.
 */

/** The lowest selectable channel index. */
const MIN_CHANNEL = 0;

/** The highest selectable channel index — three sensors, so [0, 2]. */
const MAX_CHANNEL = SENSOR_COUNT - 1;

/** Clamps an arbitrary index into the valid channel range [0, SENSOR_COUNT - 1]. */
function clampChannel(index: number): number {
  if (!Number.isFinite(index)) return MIN_CHANNEL;
  const floored = Math.floor(index);
  if (floored < MIN_CHANNEL) return MIN_CHANNEL;
  if (floored > MAX_CHANNEL) return MAX_CHANNEL;
  return floored;
}

/**
 * Module-level store rather than a React context, for the same reason as
 * `settingsStore`: the value must survive the swap between the carousel and the
 * dashboard, which unmounts one presentation and mounts the other.
 */
class SelectionStore {
  private channel = MIN_CHANNEL;
  private readonly listeners = new Set<() => void>();

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): number => this.channel;

  /**
   * Selects a channel, clamping out-of-range indices into [0, SENSOR_COUNT - 1].
   * Subscribers are notified only when the clamped value actually changes.
   */
  select(index: number): void {
    const next = clampChannel(index);
    if (next === this.channel) return;
    this.channel = next;
    this.listeners.forEach((listener) => listener());
  }

  /** Test-only: returns the singleton to its initial state between cases. */
  reset(): void {
    if (this.channel === MIN_CHANNEL) return;
    this.channel = MIN_CHANNEL;
    this.listeners.forEach((listener) => listener());
  }
}

export const selectionStore = new SelectionStore();

export function useSelectedChannel(): number {
  return useSyncExternalStore(
    selectionStore.subscribe,
    selectionStore.getSnapshot,
    selectionStore.getSnapshot,
  );
}

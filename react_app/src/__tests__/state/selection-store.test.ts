/**
 * Example tests for the selection store (task 9.3).
 *
 * These are worked examples, not the property — task 9.12 writes Property 5,
 * "selection continuity across a Layout_Mode change". What follows is the
 * baseline it builds on: the default channel, the clamp on out-of-range
 * indices, an in-range set, and the promise that subscribers fire only on a
 * real change.
 *
 * The store is a module-level singleton, so state leaks between cases unless it
 * is returned to its initial value. It has no persistence to reset through (it
 * never touches localStorage), so — matching how `settings-appearance.test.ts`
 * copes with its own singleton, but without the storage seeding it does not
 * need — each case starts from the store's test-only `reset()`.
 *
 * _Requirements: 4.3, 4.4_
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { selectionStore, useSelectedChannel } from '../../state/selectionStore';

beforeEach(() => {
  selectionStore.reset();
});

describe('selection default (Requirements 4.3, 4.4)', () => {
  it('defaults to channel 0', () => {
    expect(selectionStore.getSnapshot()).toBe(0);
  });

  it('exposes a useSelectedChannel hook wired to useSyncExternalStore', () => {
    // The hook is a thin useSyncExternalStore wrapper; asserting the three
    // callbacks it depends on keeps the store's public shape a contract.
    expect(typeof useSelectedChannel).toBe('function');
    expect(typeof selectionStore.subscribe).toBe('function');
    expect(typeof selectionStore.getSnapshot).toBe('function');
  });
});

describe('select clamps into [0, 2]', () => {
  it('sets an in-range channel unchanged', () => {
    selectionStore.select(1);
    expect(selectionStore.getSnapshot()).toBe(1);

    selectionStore.select(2);
    expect(selectionStore.getSnapshot()).toBe(2);
  });

  it('clamps a below-range index up to 0', () => {
    selectionStore.select(-1);
    expect(selectionStore.getSnapshot()).toBe(0);
  });

  it('clamps an above-range index down to 2', () => {
    selectionStore.select(3);
    expect(selectionStore.getSnapshot()).toBe(2);
  });

  it('floors a fractional index before clamping', () => {
    selectionStore.select(1.9);
    expect(selectionStore.getSnapshot()).toBe(1);
  });

  it('treats a non-finite index as channel 0', () => {
    selectionStore.select(1);
    selectionStore.select(Number.NaN);
    expect(selectionStore.getSnapshot()).toBe(0);
  });
});

describe('subscribers are notified only on a real change', () => {
  it('notifies when the clamped value changes', () => {
    const listener = vi.fn();
    const unsubscribe = selectionStore.subscribe(listener);

    selectionStore.select(2);
    expect(listener).toHaveBeenCalledTimes(1);

    unsubscribe();
  });

  it('does not notify when the value is unchanged', () => {
    selectionStore.select(1);
    const listener = vi.fn();
    const unsubscribe = selectionStore.subscribe(listener);

    selectionStore.select(1);
    expect(listener).not.toHaveBeenCalled();

    unsubscribe();
  });

  it('does not notify when an out-of-range index clamps to the current value', () => {
    selectionStore.select(2);
    const listener = vi.fn();
    const unsubscribe = selectionStore.subscribe(listener);

    // Already at 2, and 3 clamps to 2 — no change, so no notification.
    selectionStore.select(3);
    expect(listener).not.toHaveBeenCalled();

    unsubscribe();
  });

  it('stops notifying after unsubscribe', () => {
    const listener = vi.fn();
    const unsubscribe = selectionStore.subscribe(listener);

    selectionStore.select(1);
    expect(listener).toHaveBeenCalledTimes(1);

    unsubscribe();
    selectionStore.select(2);
    expect(listener).toHaveBeenCalledTimes(1);
  });
});

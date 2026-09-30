/**
 * Example tests for `useLayoutMode` and its module store (task 5.4).
 *
 * Worked examples, not the property. Task 5.9 writes Property 1 — that
 * `resolveLayoutMode` is total and exclusive over every width. What is asserted
 * here is the DOM half the pure function does not touch: that the store resolves
 * an initial band and writes `data-layout`, that flipping a boundary query moves
 * both the snapshot and the attribute, and that unsubscribing detaches every
 * `matchMedia` listener.
 *
 * Two things make these tests real rather than circular:
 *
 * 1. **`matchMedia` is stubbed, deliberately.** jsdom does not implement it, and
 *    even where it does it never changes, so a fake that can be flipped is the
 *    only way to observe a band change at all. The fake mirrors the one in
 *    `appearance-theme.test.ts`.
 * 2. **The store is a module singleton built at import**, so each test resets the
 *    module registry and re-imports it *after* installing the fake, giving a
 *    fresh store wired to queries this test controls.
 *
 * The expected query strings are derived from `BREAKPOINTS`, not written as
 * literals here, so this file stays subject to the breakpoint scanner (task 1.9)
 * like any other.
 *
 * _Requirements: 2.1, 2.9, 2.10_
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { BREAKPOINTS, type LayoutMode } from '../../core/layout';

const MEDIUM_QUERY = `(min-width: ${BREAKPOINTS.medium}px)`;
const EXPANDED_QUERY = `(min-width: ${BREAKPOINTS.expanded}px)`;

// --- the matchMedia stub -----------------------------------------------------

/** A `MediaQueryList` whose `matches` can be flipped, firing `change`. */
class FakeMediaQuery {
  readonly listeners = new Set<(event: MediaQueryListEvent) => void>();

  constructor(
    readonly media: string,
    public matches: boolean,
  ) {}

  addEventListener(type: string, listener: (event: MediaQueryListEvent) => void): void {
    if (type === 'change') this.listeners.add(listener);
  }

  removeEventListener(type: string, listener: (event: MediaQueryListEvent) => void): void {
    if (type === 'change') this.listeners.delete(listener);
  }

  flip(matches: boolean): void {
    this.matches = matches;
    const event = { matches, media: this.media } as MediaQueryListEvent;
    for (const listener of [...this.listeners]) listener(event);
  }
}

/** The queries the store asked for, keyed by media string. */
let queries: Map<string, FakeMediaQuery>;

/**
 * Installs a fake `matchMedia` for a viewport of `width` CSS pixels: each query
 * matches iff the viewport is at least as wide as its `min-width`. Returns the
 * two boundary queries so a test can flip them.
 */
function stubMatchMedia(width: number): { medium: FakeMediaQuery; expanded: FakeMediaQuery } {
  queries = new Map();
  (window as unknown as { matchMedia: (media: string) => MediaQueryList }).matchMedia = (
    media: string,
  ): MediaQueryList => {
    const existing = queries.get(media);
    if (existing) return existing as unknown as MediaQueryList;
    const matches =
      (media === MEDIUM_QUERY && width >= BREAKPOINTS.medium) ||
      (media === EXPANDED_QUERY && width >= BREAKPOINTS.expanded);
    const query = new FakeMediaQuery(media, matches);
    queries.set(media, query);
    return query as unknown as MediaQueryList;
  };
  // Touch both so the store's construction finds them ready; also lets a test
  // that stubs a Compact viewport still reach the boundary queries to flip.
  window.matchMedia(MEDIUM_QUERY);
  window.matchMedia(EXPANDED_QUERY);
  return {
    medium: queries.get(MEDIUM_QUERY)!,
    expanded: queries.get(EXPANDED_QUERY)!,
  };
}

/**
 * Imports a fresh copy of the store module, built against the currently
 * installed fake `matchMedia`. Resetting the registry first is what makes the
 * module-level singleton re-run its constructor per test.
 */
async function freshStore(): Promise<typeof import('../../hooks/useLayoutMode')> {
  vi.resetModules();
  return import('../../hooks/useLayoutMode');
}

function currentAttribute(): string | undefined {
  return document.documentElement.dataset.layout;
}

beforeEach(() => {
  delete document.documentElement.dataset.layout;
});

afterEach(() => {
  delete (window as unknown as { matchMedia?: unknown }).matchMedia;
  delete document.documentElement.dataset.layout;
  vi.resetModules();
});

// --- initial resolution ------------------------------------------------------

describe('initial resolution and data-layout (Requirements 2.1, 2.10)', () => {
  const cases: readonly [number, LayoutMode][] = [
    [375, 'compact'],
    [BREAKPOINTS.medium - 1, 'compact'],
    [BREAKPOINTS.medium, 'medium'],
    [800, 'medium'],
    [BREAKPOINTS.expanded - 1, 'medium'],
    [BREAKPOINTS.expanded, 'expanded'],
    [1600, 'expanded'],
  ];

  for (const [width, mode] of cases) {
    it(`resolves ${width}px to ${mode} and writes it to data-layout`, async () => {
      stubMatchMedia(width);
      const { layoutModeStore } = await freshStore();

      expect(layoutModeStore.getSnapshot()).toBe(mode);
      expect(currentAttribute()).toBe(mode);
    });
  }

  it('writes data-layout at construction, before any subscription', async () => {
    stubMatchMedia(1600);
    // No subscribe() call — the constructor alone must have published.
    await freshStore();

    expect(currentAttribute()).toBe('expanded');
  });

  it('falls back to compact when matchMedia is unavailable', async () => {
    delete (window as unknown as { matchMedia?: unknown }).matchMedia;
    const { layoutModeStore } = await freshStore();

    expect(layoutModeStore.getSnapshot()).toBe('compact');
    expect(currentAttribute()).toBe('compact');
  });
});

// --- flipping a boundary -----------------------------------------------------

describe('a boundary crossing updates snapshot and data-layout (Requirement 2.9)', () => {
  it('moves compact → medium → expanded and back as queries flip', async () => {
    const { medium, expanded } = stubMatchMedia(375);
    const { layoutModeStore } = await freshStore();
    const seen: LayoutMode[] = [];
    const unsubscribe = layoutModeStore.subscribe(() => seen.push(layoutModeStore.getSnapshot()));

    expect(layoutModeStore.getSnapshot()).toBe('compact');
    expect(currentAttribute()).toBe('compact');

    // Cross into Medium.
    medium.flip(true);
    expect(layoutModeStore.getSnapshot()).toBe('medium');
    expect(currentAttribute()).toBe('medium');

    // Cross into Expanded (both boundary queries now match).
    expanded.flip(true);
    expect(layoutModeStore.getSnapshot()).toBe('expanded');
    expect(currentAttribute()).toBe('expanded');

    // Shrink back below the expanded boundary.
    expanded.flip(false);
    expect(layoutModeStore.getSnapshot()).toBe('medium');
    expect(currentAttribute()).toBe('medium');

    // Back to Compact.
    medium.flip(false);
    expect(layoutModeStore.getSnapshot()).toBe('compact');
    expect(currentAttribute()).toBe('compact');

    expect(seen).toEqual(['medium', 'expanded', 'medium', 'compact']);
    unsubscribe();
  });

  it('notifies subscribers only when the band actually changes', async () => {
    const { medium, expanded } = stubMatchMedia(375);
    const { layoutModeStore } = await freshStore();
    const listener = vi.fn();
    const unsubscribe = layoutModeStore.subscribe(listener);

    // A change event that does not cross a band boundary (expanded stays false
    // while already Compact) must not wake a subscriber into a redundant render.
    expanded.flip(false);
    expect(listener).not.toHaveBeenCalled();

    medium.flip(true);
    expect(listener).toHaveBeenCalledTimes(1);

    unsubscribe();
  });
});

// --- listener lifecycle ------------------------------------------------------

describe('unsubscribe detaches the matchMedia listeners', () => {
  it('attaches on first subscriber and detaches on last', async () => {
    const { medium, expanded } = stubMatchMedia(375);
    const { layoutModeStore } = await freshStore();

    expect(medium.listeners.size).toBe(0);
    expect(expanded.listeners.size).toBe(0);

    const unsubscribe = layoutModeStore.subscribe(() => undefined);
    expect(medium.listeners.size).toBe(1);
    expect(expanded.listeners.size).toBe(1);

    unsubscribe();
    expect(medium.listeners.size).toBe(0);
    expect(expanded.listeners.size).toBe(0);
  });

  it('stops updating the snapshot once every subscriber has left', async () => {
    const { medium } = stubMatchMedia(375);
    const { layoutModeStore } = await freshStore();

    const unsubscribe = layoutModeStore.subscribe(() => undefined);
    unsubscribe();

    // With no listeners attached, a flip is not observed by the store.
    medium.flip(true);
    expect(layoutModeStore.getSnapshot()).toBe('compact');
  });

  it('shares one store across subscribers and detaches only on the last', async () => {
    const { medium } = stubMatchMedia(375);
    const { layoutModeStore } = await freshStore();

    const first = layoutModeStore.subscribe(() => undefined);
    const second = layoutModeStore.subscribe(() => undefined);
    expect(medium.listeners.size).toBe(1);

    first();
    expect(medium.listeners.size).toBe(1);

    second();
    expect(medium.listeners.size).toBe(0);
  });
});

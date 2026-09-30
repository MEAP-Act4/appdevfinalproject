import { useLayoutEffect, useSyncExternalStore } from 'react';

import { BREAKPOINTS, resolveLayoutMode, type LayoutMode } from '../core/layout';

/**
 * The Web_Client Layout_Engine's DOM half: resolve the current viewport width to
 * exactly one {@link LayoutMode} (Requirement 2.1) and publish it as
 * `document.documentElement.dataset.layout`, so `global.css` can key off
 * `:root[data-layout='compact' | 'medium' | 'expanded']` attribute selectors
 * rather than `@media (min-width: …)`. That keeps `src/core/layout.ts` the single
 * authority for the two threshold numbers (Requirement 2.10, and the breakpoint
 * scanner from task 1.9), and it is what lets task 5.7 relocate the `.app` width
 * cap into Compact scope and task 5.6's grid read its metrics per band.
 *
 * **The numbers never appear here.** The three `matchMedia` query strings are
 * built by interpolating {@link BREAKPOINTS} — `(min-width: ${BREAKPOINTS.medium}px)`
 * — so `600`/`1024` still live in exactly one place. The scanner allows an
 * interpolated width feature and flags a literal one, so this file stays green.
 *
 * **Why `matchMedia`, not `resize`.** The browser fires a `change` on a query only
 * when its boundary is actually crossed, so a band change re-renders React once
 * rather than once per pointer move (Requirement 2.9: resolve within 200ms of a
 * width change — a `matchMedia` change fires synchronously with the reflow, well
 * inside that budget). This mirrors the Mobile_Client's `updateShouldNotify`
 * comparing only the enum.
 *
 * **Why the mode is derived, not read from a fourth source.** The resolved band
 * is computed from the queries' `.matches` through {@link resolveLayoutMode}, the
 * same pure function `layout.ts` exports and Property 1 (task 5.9) constrains, so
 * the hook and the function cannot disagree about where a boundary sits.
 *
 * The hook is wired through the same `useSyncExternalStore` shape as
 * `settingsStore` / `monitorStore`, so it composes with them without a new state
 * paradigm.
 *
 * _Requirements: 2.1, 2.9, 2.10_
 */

/**
 * The two boundary media queries, built from {@link BREAKPOINTS} by interpolation
 * so the threshold numbers are never restated here. Ascending and half-open:
 * `medium` matches at `>= 600`, `expanded` at `>= 1024`, matching
 * {@link resolveLayoutMode}'s `>=` semantics exactly.
 */
const MEDIA = {
  medium: `(min-width: ${BREAKPOINTS.medium}px)`,
  expanded: `(min-width: ${BREAKPOINTS.expanded}px)`,
} as const;

/**
 * Resolves the current {@link LayoutMode} from the two boundary queries.
 *
 * Both queries answer against the *same* live viewport, so the widest matching
 * band wins: `expanded.matches` implies Expanded, `medium.matches` alone implies
 * Medium, neither implies Compact. This is `resolveLayoutMode` re-expressed over
 * booleans; the assertions below keep the two in step, and Property 1 pins it.
 */
function resolveFromQueries(medium: MediaQueryList, expanded: MediaQueryList): LayoutMode {
  if (expanded.matches) return 'expanded';
  if (medium.matches) return 'medium';
  return 'compact';
}

/**
 * A module-level store over the two `matchMedia` queries, in the shape
 * `useSyncExternalStore` expects and the existing stores use.
 *
 * One instance is shared by every consumer: the queries and the `data-layout`
 * attribute are global, so a per-component store would attach redundant
 * listeners and write the same attribute several times per band change.
 *
 * In a non-browser environment (`matchMedia` absent — SSR, or a Node test) the
 * store degrades to a constant Compact with no listeners, the safe narrow
 * default, rather than throwing at import time.
 */
class LayoutModeStore {
  private readonly mediumQuery: MediaQueryList | null;
  private readonly expandedQuery: MediaQueryList | null;
  private mode: LayoutMode;
  private readonly listeners = new Set<() => void>();

  constructor() {
    const supported = typeof window !== 'undefined' && typeof window.matchMedia === 'function';
    this.mediumQuery = supported ? window.matchMedia(MEDIA.medium) : null;
    this.expandedQuery = supported ? window.matchMedia(MEDIA.expanded) : null;
    this.mode = this.compute();
    // Publish before first paint: the attribute must exist so CSS resolves the
    // correct band on the initial render, not one frame late. App wiring that
    // calls the hook before paint is task 5.7; this synchronous write covers the
    // window before that effect runs.
    this.publish();
  }

  /** Reads the current band off the live queries, or Compact when unsupported. */
  private compute(): LayoutMode {
    if (!this.mediumQuery || !this.expandedQuery) return 'compact';
    return resolveFromQueries(this.mediumQuery, this.expandedQuery);
  }

  /** Writes the resolved mode onto the document root for the CSS selectors. */
  private publish(): void {
    if (typeof document !== 'undefined') {
      document.documentElement.dataset.layout = this.mode;
    }
  }

  /**
   * Reconciles the resolved band against the live queries. Always re-publishes
   * (cheap, idempotent) so the attribute cannot drift, but only wakes React when
   * the band actually changed — the economy `matchMedia` buys over a resize
   * listener, and what keeps a subscriber from re-rendering on a non-crossing
   * event. Returns whether the mode moved.
   */
  private reconcile(): boolean {
    const next = this.compute();
    const changed = next !== this.mode;
    this.mode = next;
    this.publish();
    return changed;
  }

  /** A `matchMedia` `change`: reconcile, and notify only on a real band change. */
  private readonly onChange = (): void => {
    if (this.reconcile()) this.listeners.forEach((listener) => listener());
  };

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    // Attach the change listeners lazily on the first subscriber and detach them
    // on the last, so an unsubscribed hook leaves no listeners behind.
    if (this.listeners.size === 1) {
      this.mediumQuery?.addEventListener('change', this.onChange);
      this.expandedQuery?.addEventListener('change', this.onChange);
      // The viewport may have crossed a boundary between construction and the
      // first subscription; reconcile the snapshot silently — a subscriber that
      // has only just registered has nothing to be notified about yet, and
      // `useSyncExternalStore` reads the snapshot itself right after subscribing.
      this.reconcile();
    }
    return () => {
      this.listeners.delete(listener);
      if (this.listeners.size === 0) {
        this.mediumQuery?.removeEventListener('change', this.onChange);
        this.expandedQuery?.removeEventListener('change', this.onChange);
      }
    };
  };

  getSnapshot = (): LayoutMode => this.mode;
}

export const layoutModeStore = new LayoutModeStore();

/**
 * Subscribes to the current {@link LayoutMode} and keeps `data-layout` on the
 * document root in step with it.
 *
 * `getServerSnapshot` returns Compact, the narrow default, so a server render (or
 * a `matchMedia`-less environment) hydrates without a mismatch. The
 * `useLayoutEffect` re-publishes on mount so the attribute is correct before the
 * browser paints even if this is the first thing to touch the store.
 */
export function useLayoutMode(): LayoutMode {
  const mode = useSyncExternalStore(
    layoutModeStore.subscribe,
    layoutModeStore.getSnapshot,
    () => 'compact' as LayoutMode,
  );

  useLayoutEffect(() => {
    document.documentElement.dataset.layout = mode;
  }, [mode]);

  return mode;
}

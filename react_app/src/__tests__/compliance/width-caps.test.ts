/**
 * The relocated Web_Client width caps (task 5.7).
 *
 * The single highest-risk change in the feature is moving `.app`'s fixed 560
 * cap — and giving `.sheet` the same treatment — from an unconditional rule to a
 * `:root[data-layout='…']`-scoped one. The acceptance bar is that **Compact
 * rendering is unchanged**: at Compact widths `.app` and `.sheet` must still cap
 * at 560 and centre, exactly as they did before the move.
 *
 * This file pins that. It reads `src/styles/global.css` off disk and injects it
 * into a jsdom document — the same read-the-stylesheet-and-assert approach the
 * other CSS compliance tests take — then sets `data-layout` on the document root
 * to each of the three bands and reads back the computed `max-width` of `.app`
 * and `.sheet`:
 *
 * - `.app`: Compact 560 (Requirement 2.5, 2.10), Medium `none` (fills the
 *   viewport — Requirement 2.4), Expanded `none` (the `.grid12` scaffold's 1440
 *   `--grid-content-max` governs — Requirement 2.6). `.app` must impose no cap
 *   of its own in Expanded.
 * - `.sheet`: capped at 560 in Compact *and* Medium, `none` in Expanded, so the
 *   Diagnostics_Sheet stays phone-width until Expanded.
 *
 * The Compact assertion is the one with teeth: it is the byte-for-byte
 * unchanged-rendering guarantee. The other bands prove the cap was relocated,
 * not merely widened.
 *
 * Runs in the jsdom project so `getComputedStyle` resolves the attribute-scoped
 * cascade. Reading the file with `node:fs` is fine here — the jsdom environment
 * still exposes Node's module APIs; it is the DOM the test needs, which the node
 * project would not provide. The numbers written here — 560, 1440 — are content
 * caps, not Layout_Mode thresholds, so the breakpoint scanner (task 1.9) leaves
 * them alone; no colour literal appears either (Requirement 1.5).
 *
 * _Requirements: 2.10, 2.5, 2.6_
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { afterEach, beforeAll, describe, expect, it } from 'vitest';

import type { LayoutMode } from '../../core/layout';

const GLOBAL_CSS_PATH = join(process.cwd(), 'src', 'styles', 'global.css');

/** The historical phone cap, and the value Compact must reproduce exactly. */
const COMPACT_CAP = '560px';

/**
 * Injects `global.css` into the document once, so every assertion reads the same
 * stylesheet the app ships. jsdom resolves attribute selectors like
 * `:root[data-layout='compact'] .app` through `getComputedStyle`, which is what
 * lets this test observe the relocated cap rather than re-deriving it.
 */
function installStylesheet(): void {
  const css = readFileSync(GLOBAL_CSS_PATH, 'utf8');
  const style = document.createElement('style');
  style.setAttribute('data-test', 'global-css');
  style.textContent = css;
  document.head.appendChild(style);
}

/** Sets the band on the document root, exactly as `useLayoutMode` does. */
function setLayout(mode: LayoutMode): void {
  document.documentElement.dataset.layout = mode;
}

/**
 * The computed `max-width` of an element carrying `className`, resolved under
 * the current `data-layout`. The element is attached to the body so the cascade
 * applies, and removed by the caller's cleanup.
 */
function computedMaxWidth(className: string): string {
  const element = document.createElement('div');
  element.className = className;
  document.body.appendChild(element);
  const value = getComputedStyle(element).maxWidth;
  return value;
}

beforeAll(() => {
  installStylesheet();
});

afterEach(() => {
  delete document.documentElement.dataset.layout;
  document.body.innerHTML = '';
});

describe('the relocated .app width cap', () => {
  it('caps .app at 560 in Compact — the unchanged phone rendering', () => {
    setLayout('compact');
    expect(computedMaxWidth('app')).toBe(COMPACT_CAP);
  });

  it('leaves .app uncapped in Medium so it fills the viewport', () => {
    setLayout('medium');
    expect(computedMaxWidth('app')).toBe('none');
  });

  it('leaves .app uncapped in Expanded so the grid 1440 cap governs', () => {
    setLayout('expanded');
    expect(computedMaxWidth('app')).toBe('none');
  });

  it('keeps .app centred with margin auto', () => {
    // The cap is only half of "unchanged": a capped container that is not
    // centred renders differently. `margin: 0 auto` must survive the move.
    setLayout('compact');
    const element = document.createElement('div');
    element.className = 'app';
    document.body.appendChild(element);
    const style = getComputedStyle(element);
    expect(style.marginLeft).toBe('auto');
    expect(style.marginRight).toBe('auto');
  });
});

describe('the relocated .sheet width cap', () => {
  it('caps .sheet at 560 in Compact — unchanged from today', () => {
    setLayout('compact');
    expect(computedMaxWidth('sheet')).toBe(COMPACT_CAP);
  });

  it('caps .sheet at 560 in Medium so it stays phone-width', () => {
    setLayout('medium');
    expect(computedMaxWidth('sheet')).toBe(COMPACT_CAP);
  });

  it('lets .sheet widen in Expanded', () => {
    setLayout('expanded');
    expect(computedMaxWidth('sheet')).toBe('none');
  });
});

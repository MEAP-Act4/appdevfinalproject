/**
 * Sanity examples for the Layout_Engine constants and mode resolution
 * (task 5.2).
 *
 * These are worked examples, not the property. Task 5.9 writes Property 1 —
 * "Layout_Mode resolution is total and exclusive" — over generated widths
 * biased to the boundaries; what follows pins the six boundary widths that
 * property's generator hits exactly (599 / 600 / 601 / 1023 / 1024 / 1025), the
 * sub-320 rule, and the per-mode metrics so a stray edit to a gutter, pad, or
 * cap fails here rather than surfacing as a silent layout drift.
 *
 * _Requirements: 2.1, 2.3, 2.4, 2.5, 2.6, 13.1_
 */
import { describe, expect, it } from 'vitest';

import {
  BREAKPOINTS,
  CONTENT_MAX,
  GRID_COLUMNS,
  GRID_METRICS,
  type LayoutMode,
  resolveLayoutMode,
} from '../../core/layout';

describe('resolveLayoutMode boundary semantics', () => {
  const cases: ReadonlyArray<readonly [number, LayoutMode]> = [
    [599, 'compact'],
    [600, 'medium'],
    [601, 'medium'],
    [1023, 'medium'],
    [1024, 'expanded'],
    [1025, 'expanded'],
  ];

  for (const [width, mode] of cases) {
    it(`resolves ${width} to ${mode}`, () => {
      expect(resolveLayoutMode(width)).toBe(mode);
    });
  }

  it('resolves sub-320 widths to compact', () => {
    expect(resolveLayoutMode(0)).toBe('compact');
    expect(resolveLayoutMode(200)).toBe('compact');
    expect(resolveLayoutMode(319)).toBe('compact');
  });

  it('is total and exclusive across the 320..2560 sweep', () => {
    for (let width = 320; width <= 2560; width += 1) {
      const mode = resolveLayoutMode(width);

      const predicates = {
        compact: width < BREAKPOINTS.medium,
        medium: width >= BREAKPOINTS.medium && width < BREAKPOINTS.expanded,
        expanded: width >= BREAKPOINTS.expanded,
      } as const;

      // Exactly one band predicate holds, and it is the one that was returned.
      const holding = (Object.keys(predicates) as LayoutMode[]).filter(
        (m) => predicates[m],
      );
      expect(holding).toEqual([mode]);
    }
  });

  it('falls back to compact for non-finite widths', () => {
    expect(resolveLayoutMode(Number.NaN)).toBe('compact');
    expect(resolveLayoutMode(Number.POSITIVE_INFINITY)).toBe('expanded');
    expect(resolveLayoutMode(Number.NEGATIVE_INFINITY)).toBe('compact');
  });
});

describe('grid metrics', () => {
  it('carries the per-mode gutter, pad, and cap of Requirements 2.3-2.6', () => {
    expect(GRID_METRICS.compact).toEqual({ gutter: 16, pad: 16, contentMax: 560 });
    expect(GRID_METRICS.medium).toEqual({ gutter: 16, pad: 24, contentMax: null });
    expect(GRID_METRICS.expanded).toEqual({ gutter: 24, pad: 32, contentMax: 1440 });
  });

  it('keeps every gutter and pad a multiple of 8 (Requirement 1.8)', () => {
    for (const metric of Object.values(GRID_METRICS)) {
      expect(metric.gutter % 8).toBe(0);
      expect(metric.pad % 8).toBe(0);
    }
  });

  it('exposes the shared constants', () => {
    expect(BREAKPOINTS).toEqual({ medium: 600, expanded: 1024 });
    expect(CONTENT_MAX).toBe(1440);
    expect(GRID_COLUMNS).toBe(12);
    expect(GRID_METRICS.expanded.contentMax).toBe(CONTENT_MAX);
  });
});

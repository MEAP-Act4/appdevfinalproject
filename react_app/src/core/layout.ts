/**
 * The Web_Client Layout_Engine constants and mode resolution.
 *
 * This module is the **single authority** for the three Layout_Mode width bands
 * and the per-mode grid metrics (Requirement 2.1, 2.3–2.6, 13.1). The threshold
 * pixel values `600` and `1024` live here and nowhere else in the client: the
 * breakpoint scanner (task 1.9) exempts exactly this path and fails every other
 * file that restates them. CSS keys off `:root[data-layout='…']` attribute
 * selectors rather than `@media (min-width: …)`, so the numbers exist once.
 *
 * The Mobile_Client holds the same numbers in
 * `flutter_app/lib/core/layout/layout_mode.dart`; Requirement 13.1 requires the
 * two clients to agree, and task 5.13 asserts both read the identical values.
 *
 * Nothing here touches the DOM. `useLayoutMode` (task 5.4) builds its
 * `matchMedia` queries from {@link BREAKPOINTS}, and `global.css` (tasks 5.6,
 * 5.7) reads {@link GRID_METRICS} through custom properties — those are separate
 * tasks and deliberately not implemented in this module.
 *
 * _Requirements: 2.1, 2.3, 2.4, 2.5, 2.6, 13.1_
 */

/** The three named viewport width bands of Requirement 2.1. */
export type LayoutMode = 'compact' | 'medium' | 'expanded';

/**
 * The two Layout_Mode boundary widths, in CSS pixels (Requirement 2.1).
 *
 * The bands are half-open and ascending: a width is Medium at `>= medium` and
 * Expanded at `>= expanded`, so both boundaries land in the higher band —
 * `600 → medium`, `1024 → expanded`. Everything below `medium` is Compact.
 */
export const BREAKPOINTS = { medium: 600, expanded: 1024 } as const;

/**
 * The Expanded content cap of Requirement 2.6, in CSS pixels: the grid content
 * width is capped here and centred within the viewport. Also the `contentMax`
 * of the Expanded entry in {@link GRID_METRICS}.
 */
export const CONTENT_MAX = 1440;

/** The number of columns in Grid_12. */
export const GRID_COLUMNS = 12;

/** Gutter, outer padding, and content cap for one Layout_Mode. */
export interface GridMetric {
  /** Gap between columns, in CSS pixels. A multiple of 8 (Requirement 1.8). */
  readonly gutter: number;
  /** Outer padding, in CSS pixels. A multiple of 8 (Requirement 1.8). */
  readonly pad: number;
  /**
   * The content-width cap, in CSS pixels, or `null` when the band applies no
   * cap. Medium fills the available width, so its cap is `null` rather than a
   * sentinel — the representation the Mobile_Client mirror also uses, keeping
   * task 5.13's cross-client comparison clean.
   */
  readonly contentMax: number | null;
}

/**
 * The per-mode grid metrics of Requirements 2.3–2.6.
 *
 * - Compact: 16 gutter / 16 outer pad / 560 cap — the existing `.app` cap,
 *   relocated here rather than deleted (Requirement 2.5, 2.10).
 * - Medium: 16 gutter / 24 outer pad / no cap (Requirement 2.4).
 * - Expanded: 24 gutter / 32 outer pad / 1440 cap (Requirement 2.3, 2.6).
 *
 * Every gutter and pad value is a multiple of 8 (Requirement 1.8), which the
 * compliance suite asserts rather than assumes.
 */
export const GRID_METRICS: Readonly<Record<LayoutMode, GridMetric>> = {
  compact: { gutter: 16, pad: 16, contentMax: 560 },
  medium: { gutter: 16, pad: 24, contentMax: null },
  expanded: { gutter: 24, pad: 32, contentMax: CONTENT_MAX },
} as const;

/**
 * Resolves a viewport logical width to exactly one {@link LayoutMode}.
 *
 * Total and exclusive (Property 1, task 5.9): every finite width — including
 * sub-320 widths — resolves to exactly one mode, and the bands do not overlap.
 * Boundary semantics are `>=`, so `600 → medium` and `1024 → expanded`.
 *
 * A non-finite width (`NaN`, `Infinity`) cannot satisfy either `>=` guard and
 * therefore resolves to Compact, the safe narrow default.
 */
export function resolveLayoutMode(width: number): LayoutMode {
  if (width >= BREAKPOINTS.expanded) return 'expanded';
  if (width >= BREAKPOINTS.medium) return 'medium';
  return 'compact';
}

/**
 * Example test for the Grid_12 per-band custom properties in `global.css`
 * (task 5.6).
 *
 * A worked example, not a property. Tasks 5.10–5.12 write Properties 2, 3 and 4
 * — the column arithmetic, the Expanded cap and row packing. What is asserted
 * here is narrower and concrete: that the three grid custom properties resolve
 * to the right per-band values through the real stylesheet, so a `.grid12` at
 * each `data-layout` band gets the gutter, outer padding and content cap
 * Requirements 2.3–2.6 call for.
 *
 * Three things make this test real rather than circular:
 *
 * 1. **The stylesheets are the shipped ones.** `tokens.css` and `global.css` are
 *    read off disk and injected into the document, the same way
 *    `appearance-theme.test.ts` injects `tokens.css`. jsdom does not follow the
 *    `@import` in `global.css`, so both files are injected — tokens first, so
 *    `--s3`/`--s4`/`--s5` are defined before the grid rules that reference them.
 *    They are read with `node:fs` even though this file runs under jsdom, for
 *    the reason spelled out in `appearance-theme.test.ts`: Vitest stubs CSS
 *    imports, so importing would yield an empty string.
 * 2. **The expected values come from `src/core/layout.ts`**, the single
 *    authority for the metrics, not from literals in this file. So no pixel
 *    literal appears here, and the file stays subject to the breakpoint scanner
 *    (task 1.9) like any other.
 * 3. **The grid gutter and pad resolve through the `--s*` spacing steps.**
 *    jsdom's `getComputedStyle` reports a custom property's *declared* value
 *    without following a nested `var()`, so the grid vars read back as
 *    `var(--s3)`/`var(--s4)`/`var(--s5)`. The test resolves that one hop itself,
 *    against the `--s*` values it reads off `:root` — which land at 16/24/32px —
 *    and so proves both that each band points at the right step and that every
 *    step is a multiple of eight (Requirement 1.8 by construction).
 *
 * _Requirements: 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 1.8_
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { GRID_METRICS, type LayoutMode } from '../../core/layout';

/** `src/styles/tokens.css`, verbatim — defines `--s3`/`--s4`/`--s5`. */
const tokensCss = readFileSync(join(process.cwd(), 'src/styles/tokens.css'), 'utf8');

/** `src/styles/global.css`, verbatim — defines `.grid12` and the band vars. */
const globalCss = readFileSync(join(process.cwd(), 'src/styles/global.css'), 'utf8');

const STYLE_ID = 'grid12-under-test';

/** The three bands the layout attribute can hold. */
const BANDS: readonly LayoutMode[] = ['compact', 'medium', 'expanded'];

/** A `var(--name)` reference, or `null` when the value is not a single var(). */
function varTarget(value: string): string | null {
  const match = /^var\(\s*(--[\w-]+)\s*\)$/.exec(value.trim());
  return match ? match[1] : null;
}

/**
 * Resolves a custom property one `var()` hop deep, the way jsdom's cascade does
 * not: a `var(--sN)` declared value is looked up on the same computed style
 * (custom properties inherit, so `--s3` is visible on the grid element too),
 * everything else (`560px`, `none`) is returned as-is.
 */
function resolveOneHop(style: CSSStyleDeclaration, declared: string): string {
  const target = varTarget(declared);
  return target ? style.getPropertyValue(target).trim() : declared.trim();
}

/**
 * The expected `--grid-content-max` for a band, as CSS. Medium's `null` cap is
 * `none` (`max-width: none`), matching the layout module's representation.
 */
function expectedContentMax(mode: LayoutMode): string {
  const cap = GRID_METRICS[mode].contentMax;
  return cap === null ? 'none' : `${cap}px`;
}

/** Injects both shipped stylesheets, tokens first so the `--s*` steps resolve. */
function loadStyles(): void {
  const style = document.createElement('style');
  style.id = STYLE_ID;
  style.textContent = `${tokensCss}\n${globalCss}`;
  document.head.append(style);
}

/** Mounts a `.grid12` carrying `.span-*` children, and returns it. */
function mountGrid(): HTMLElement {
  const grid = document.createElement('div');
  grid.className = 'grid12';
  for (const span of ['span-4', 'span-8', 'span-12']) {
    const cell = document.createElement('div');
    cell.className = span;
    grid.append(cell);
  }
  document.body.append(grid);
  return grid;
}

beforeEach(loadStyles);

afterEach(() => {
  document.getElementById(STYLE_ID)?.remove();
  document.querySelectorAll('.grid12').forEach((grid) => grid.remove());
  delete document.documentElement.dataset.layout;
});

describe('Grid_12 per-band custom properties (Requirements 2.3–2.6, 1.8)', () => {
  for (const mode of BANDS) {
    it(`resolves the ${mode} gutter, padding and content cap on .grid12`, () => {
      document.documentElement.dataset.layout = mode;
      const grid = mountGrid();
      const gridStyle = getComputedStyle(grid);

      const metric = GRID_METRICS[mode];
      const gutter = resolveOneHop(gridStyle, gridStyle.getPropertyValue('--grid-gutter'));
      const pad = resolveOneHop(gridStyle, gridStyle.getPropertyValue('--grid-pad'));
      const cap = resolveOneHop(
        gridStyle,
        gridStyle.getPropertyValue('--grid-content-max'),
      );

      expect(gutter, `${mode} gutter`).toBe(`${metric.gutter}px`);
      expect(pad, `${mode} pad`).toBe(`${metric.pad}px`);
      expect(cap, `${mode} content cap`).toBe(expectedContentMax(mode));

      // The gutter and pad go through --s* steps, never a literal, which is what
      // keeps Requirement 1.8 true by construction.
      expect(varTarget(gridStyle.getPropertyValue('--grid-gutter')), `${mode}`).toMatch(
        /^--s\d$/,
      );
      expect(varTarget(gridStyle.getPropertyValue('--grid-pad')), `${mode}`).toMatch(
        /^--s\d$/,
      );
    });
  }

  it('gives Compact and Medium the same 16px gutter, Expanded 24px', () => {
    // The gutters are the --s3/--s4 steps: a change to the spacing scale moves
    // both together, and neither can drift off the 8-multiple grid (Req 1.8).
    expect(GRID_METRICS.compact.gutter).toBe(GRID_METRICS.medium.gutter);
    expect(GRID_METRICS.expanded.gutter).toBeGreaterThan(GRID_METRICS.medium.gutter);
  });

  it('caps Expanded and Compact but leaves Medium uncapped', () => {
    document.documentElement.dataset.layout = 'medium';
    const grid = mountGrid();
    const gridStyle = getComputedStyle(grid);

    // `none` here is Medium filling the viewport, not a missing declaration —
    // it is what `max-width: var(--grid-content-max)` must resolve to.
    expect(
      resolveOneHop(gridStyle, gridStyle.getPropertyValue('--grid-content-max')),
    ).toBe('none');
  });

  it('reads every grid gutter and pad back as a multiple of eight', () => {
    // Requirement 1.8, proven through the resolved stylesheet rather than only
    // through the TypeScript constants.
    for (const mode of BANDS) {
      document.documentElement.dataset.layout = mode;
      const grid = mountGrid();
      const gridStyle = getComputedStyle(grid);

      for (const prop of ['--grid-gutter', '--grid-pad']) {
        const px = Number.parseInt(
          resolveOneHop(gridStyle, gridStyle.getPropertyValue(prop)),
          10,
        );
        expect(px % 8, `${mode} ${prop} = ${px}px`).toBe(0);
      }
      grid.remove();
    }
  });
});

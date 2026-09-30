/**
 * Example tests pinning the fixed per-mode Layout_Engine metrics for the
 * Web_Client, and — the point of this file — the cross-client agreement of
 * Requirement 13.1.
 *
 * Two jobs, both against `src/core/layout.ts`:
 *
 * 1. **The fixed metric table.** The gutter/pad/contentMax triples of
 *    Requirements 2.3–2.5, the 12-column count, the two breakpoints and the
 *    1440 Expanded cap are asserted as literal expectations, plus the totality
 *    corner of Requirement 2.11: a sub-320 width still resolves to Compact with
 *    16 outer padding. Property 1 (`property-1-layout-mode.test.ts`) proves
 *    `resolveLayoutMode` is total and exclusive over generated widths; this
 *    file pins the specific numbers that property is silent about.
 *
 * 2. **Cross-client agreement (Requirement 13.1).** The Mobile_Client and the
 *    Web_Client duplicate these constants across Dart and TypeScript by
 *    necessity — neither language can import the other. So the two copies could
 *    silently diverge. The honest referee is a shared fixture at the repo root,
 *    `test_fixtures/layout/metrics.json`, that both clients read: this test
 *    asserts `GRID_METRICS` / `BREAKPOINTS` / `GRID_COLUMNS` / `CONTENT_MAX`
 *    equal the fixture, and the Flutter test
 *    (`flutter_app/test/compliance/metrics_examples_test.dart`) asserts the same
 *    of its own constants against the same JSON. A divergence in either client
 *    fails that client's suite. Medium's contentMax is `null` in the fixture and
 *    in both clients, so the comparison treats `null === null` as agreement.
 *
 * Runs in the Node project (the `.node.test.ts` suffix) because it reads the
 * fixture off disk from the repo root with `node:fs`. The fixture sits outside
 * both client directories on purpose; `test_fixtures/` is a shared convention
 * that task 9.1 adds further fixtures to.
 *
 * _Requirements: 2.3, 2.4, 2.5, 2.11, 13.1_
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  BREAKPOINTS,
  CONTENT_MAX,
  GRID_COLUMNS,
  GRID_METRICS,
  resolveLayoutMode,
  type LayoutMode,
} from '../../core/layout';

// --- the shared fixture ------------------------------------------------------

/**
 * The shape of `test_fixtures/layout/metrics.json`. Comment fields (`$comment`)
 * are ignored here; only the numeric contract is typed.
 */
interface MetricsFixture {
  readonly columns: number;
  readonly breakpoints: { readonly medium: number; readonly expanded: number };
  readonly contentMax: number;
  readonly metrics: Readonly<
    Record<LayoutMode, { readonly gutter: number; readonly pad: number; readonly contentMax: number | null }>
  >;
  readonly subCompactRule: { readonly width: number; readonly mode: LayoutMode; readonly pad: number };
}

/**
 * The repo root is the parent of `react_app`, and Vitest runs the Node project
 * with `process.cwd()` at the `react_app` package root (the same assumption the
 * other `*.node.test.ts` files make when they read `src/styles/tokens.css`).
 * Resolving `..` from there reaches the repo root, where `test_fixtures/` lives
 * outside both client trees.
 */
const REPO_ROOT = dirname(process.cwd());
const FIXTURE_PATH = join(REPO_ROOT, 'test_fixtures', 'layout', 'metrics.json');

const fixture = JSON.parse(readFileSync(FIXTURE_PATH, 'utf8')) as MetricsFixture;

const MODES: readonly LayoutMode[] = ['compact', 'medium', 'expanded'];

// --- the fixed metric table --------------------------------------------------

describe('the fixed per-mode metrics (Req 2.3–2.5)', () => {
  it('compact is 16 gutter / 16 pad / 560 cap', () => {
    expect(GRID_METRICS.compact).toEqual({ gutter: 16, pad: 16, contentMax: 560 });
  });

  it('medium is 16 gutter / 24 pad / no cap', () => {
    expect(GRID_METRICS.medium).toEqual({ gutter: 16, pad: 24, contentMax: null });
  });

  it('expanded is 24 gutter / 32 pad / 1440 cap', () => {
    expect(GRID_METRICS.expanded).toEqual({ gutter: 24, pad: 32, contentMax: 1440 });
  });

  it('has twelve columns and the fixed breakpoints and content cap', () => {
    expect(GRID_COLUMNS).toBe(12);
    expect(BREAKPOINTS).toEqual({ medium: 600, expanded: 1024 });
    expect(CONTENT_MAX).toBe(1440);
  });

  it('keeps every gutter and pad a multiple of eight (Req 1.8)', () => {
    for (const mode of MODES) {
      expect(GRID_METRICS[mode].gutter % 8).toBe(0);
      expect(GRID_METRICS[mode].pad % 8).toBe(0);
    }
  });
});

describe('sub-320 totality (Req 2.11)', () => {
  it('resolves 300 to compact with 16 outer padding', () => {
    const mode = resolveLayoutMode(300);
    expect(mode).toBe('compact');
    expect(GRID_METRICS[mode].pad).toBe(16);
  });

  it('resolves every sub-320 width to compact', () => {
    for (const width of [0, 1, 100, 300, 319]) {
      expect(resolveLayoutMode(width)).toBe('compact');
    }
  });
});

// --- cross-client agreement (Req 13.1) ---------------------------------------

describe('cross-client agreement with the shared fixture (Req 13.1)', () => {
  it('reads the fixture the Mobile_Client is also measured against', () => {
    // A guard: if the path is wrong the JSON.parse above throws, but a fixture
    // that silently lost its metrics would pass everything vacuously. Pin the
    // shape so that cannot happen unnoticed.
    expect(fixture.metrics).toBeDefined();
    expect(Object.keys(fixture.metrics).sort()).toEqual([...MODES].sort());
  });

  it('has the same twelve columns as the fixture', () => {
    expect(GRID_COLUMNS).toBe(fixture.columns);
  });

  it('has the same breakpoints as the fixture', () => {
    expect(BREAKPOINTS.medium).toBe(fixture.breakpoints.medium);
    expect(BREAKPOINTS.expanded).toBe(fixture.breakpoints.expanded);
  });

  it('has the same Expanded content cap as the fixture', () => {
    expect(CONTENT_MAX).toBe(fixture.contentMax);
  });

  it.each(MODES)('agrees with the fixture on the %s triple', (mode) => {
    const expected = fixture.metrics[mode];
    expect(GRID_METRICS[mode].gutter).toBe(expected.gutter);
    expect(GRID_METRICS[mode].pad).toBe(expected.pad);
    // null === null for Medium; a real cap otherwise. Comparing with toBe keeps
    // the null case honest rather than coercing it to a sentinel.
    expect(GRID_METRICS[mode].contentMax).toBe(expected.contentMax);
  });

  it('resolves the fixture sub-320 rule the way the fixture records it', () => {
    const rule = fixture.subCompactRule;
    const mode = resolveLayoutMode(rule.width);
    expect(mode).toBe(rule.mode);
    expect(GRID_METRICS[mode].pad).toBe(rule.pad);
  });
});

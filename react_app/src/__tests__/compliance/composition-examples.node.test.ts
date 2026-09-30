/**
 * Property 29 — Both clients agree on the Dashboard_View grid composition.
 * Web_Client half (task 9.14).
 *
 * Requirements 3.1, 3.2, 3.3, 3.4 fix the wide-viewport composition — the
 * KPI_Row of three `span 4` cells, then the Main_Chart and Alerts_Panel whose
 * spans differ by mode — and Requirement 13.1 requires the Web_Client and the
 * Mobile_Client to present the SAME column spans for every Layout_Mode.
 *
 * **Why a shared fixture is the referee.** Each client builds the composition
 * independently: the Web_Client's {@link dashboardCells} (TypeScript) and the
 * Mobile_Client's `dashboardComposition` (Dart). Neither can import the other,
 * so the two ordered cell lists could silently drift. The honest referee is a
 * single file at the repo root, `test_fixtures/layout/compositions.json`, that
 * BOTH clients read: this test asserts `dashboardCells(mode)` — the ordered
 * `{ role, span }` list — equals the fixture's `modes[mode].cells` exactly, in
 * order, and the Flutter suite
 * (`flutter_app/test/compliance/composition_examples_test.dart`) asserts the
 * same of its own composition against the same JSON. A divergence in either
 * client fails that client's suite, and because both are measured against one
 * file, the clients cannot disagree and both pass.
 *
 * **What is compared.** For a mode whose fixture entry has `grid: true`
 * (Medium, Expanded), the derived cells must equal the fixture's ordered cells,
 * role-for-role and span-for-span. For a mode with `grid: false` (Compact) the
 * client renders the Sensor_Carousel, not a Grid_12, so `dashboardCells` must be
 * empty and the fixture's `cells` empty too — a client that wrongly built a grid
 * in Compact fails against `grid: false`.
 *
 * **The property (Property 29).** `mode` ranges over the three Layout_Modes read
 * from the fixture — not hardcoded — with fast-check, and the invariant is
 * "`dashboardCells(mode)` as `{ role, span }` pairs equals the fixture's cells
 * for that mode, in order". Ranging over the modes the fixture actually declares
 * means a fixture that lost or renamed a mode cannot pass vacuously.
 *
 * Runs in the Node project (the `.node.test.ts` suffix) because it reads the
 * fixture off disk from the repo root with `node:fs`, the same way the other
 * `*.node.test.ts` parity tests do.
 *
 * _Requirements: 3.1, 3.2, 3.3, 3.4, 13.1_
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

import type { LayoutMode } from '../../core/layout';
import { dashboardCells } from '../../screens/DashboardView';

/** The design.md floor: 100 generated cases per property, both clients. */
const RUNS = { numRuns: 100 } as const;

// --- the shared fixture ------------------------------------------------------

/** One ordered cell in the fixture: a stable role id and its Grid_12 span. */
interface FixtureCell {
  readonly role: string;
  readonly span: number;
}

/** One Layout_Mode entry in the fixture. */
interface FixtureMode {
  readonly grid: boolean;
  readonly cells: readonly FixtureCell[];
}

/** The shape of `test_fixtures/layout/compositions.json` this test relies on. */
interface CompositionsFixture {
  readonly modes: Readonly<Record<string, FixtureMode>>;
}

/**
 * The repo root is the parent of `react_app`, and Vitest runs the Node project
 * with `process.cwd()` at the `react_app` package root — the same assumption
 * `metrics-examples.node.test.ts` makes. Resolving `..` reaches the repo root,
 * where `test_fixtures/` lives outside both client trees.
 */
const REPO_ROOT = dirname(process.cwd());
const FIXTURE_PATH = join(REPO_ROOT, 'test_fixtures', 'layout', 'compositions.json');

const fixture = JSON.parse(readFileSync(FIXTURE_PATH, 'utf8')) as CompositionsFixture;

/** The Layout_Mode keys read FROM the fixture, not hardcoded. */
const FIXTURE_MODES = Object.keys(fixture.modes) as LayoutMode[];

/** The fixture cells for a mode, as `{ role, span }` — the same shape dashboardCells yields. */
function fixtureCells(mode: LayoutMode): readonly FixtureCell[] {
  return fixture.modes[mode]!.cells.map((c) => ({ role: c.role, span: c.span }));
}

/** The Web_Client cells for a mode, as plain `{ role, span }` pairs. */
function clientCells(mode: LayoutMode): readonly FixtureCell[] {
  return dashboardCells(mode).map((c) => ({ role: c.role, span: c.span }));
}

// --- Property 29 -------------------------------------------------------------

describe('Property 29 — cross-client dashboard composition (Req 13.1)', () => {
  it('reads a fixture declaring exactly the three Layout_Modes', () => {
    // A guard against a vacuous pass: a fixture missing a mode would otherwise
    // make the property range over fewer cases silently.
    expect([...FIXTURE_MODES].sort()).toEqual(['compact', 'expanded', 'medium']);
  });

  it('has dashboardCells equal the fixture cells exactly, in order, for every mode', () => {
    fc.assert(
      fc.property(fc.constantFrom(...FIXTURE_MODES), (mode: LayoutMode) => {
        expect(clientCells(mode), `composition disagrees with the fixture for ${mode}`).toEqual(
          fixtureCells(mode),
        );
      }),
      RUNS,
    );
  });
});

describe('Property 29 — the Grid_12 / carousel split (Req 3.1–3.4)', () => {
  it('has Compact carry no grid composition and the fixture agree', () => {
    // Compact renders the Sensor_Carousel, so the cells are empty and the
    // fixture records grid:false with empty cells.
    expect(dashboardCells('compact')).toEqual([]);
    expect(fixture.modes.compact!.grid).toBe(false);
    expect(fixture.modes.compact!.cells).toEqual([]);
  });

  it('has Medium and Expanded carry grid compositions and the fixture agree', () => {
    for (const mode of ['medium', 'expanded'] as const) {
      expect(dashboardCells(mode).length).toBeGreaterThan(0);
      expect(fixture.modes[mode]!.grid).toBe(true);
    }
  });

  it('packs every grid mode into runs summing to 12 (Grid_12, Req 2.2)', () => {
    // Medium: 4+4+4 | 12 | 12. Expanded: 4+4+4 | 8+4.
    for (const mode of ['medium', 'expanded'] as const) {
      let run = 0;
      for (const cell of dashboardCells(mode)) {
        run += cell.span;
        expect(run, `${mode} run overflow`).toBeLessThanOrEqual(12);
        if (run === 12) run = 0;
      }
      expect(run, `${mode} left a partial run`).toBe(0);
    }
  });
});

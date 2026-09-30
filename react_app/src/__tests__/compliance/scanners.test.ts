/**
 * Unit tests for the Web_Client source scanners.
 *
 * Requirements 1.5 and 2.1 are statements about a scan *failing*, so the scan's
 * own behaviour has to be asserted rather than assumed — a detector that silently
 * matches nothing would let the whole compliance suite pass while the drift it
 * exists to catch goes through untouched. Every case below is a synthetic source
 * string, so nothing here depends on the state of the real tree; the live walk is
 * `scanners.node.test.ts`.
 *
 * ## Fixtures without literals
 *
 * This file is scanned by the very scanners it tests, and it is not exempt. So
 * every fixture is *constructed* — `hex('00e5ff')`, `fn('rgb', '0, 0, 0')`,
 * `px(1024)` — and the byte sequences the scanners hunt for never appear in this
 * source text. That is also a useful second assertion: if the constructors were
 * wrong, `scanners.node.test.ts` would report this file as a violation.
 *
 * _Requirements: 1.3, 1.5, 2.1_
 */
import { describe, expect, it } from 'vitest';

import {
  COLOR_SCAN_EXEMPT_FILES,
  formatViolation,
  isScannable,
  scanFileForBreakpoints,
  scanFileForColorLiterals,
  scanTextForBreakpoints,
  scanTextForColorLiterals,
  summarise,
  summariseKnown,
} from './scanners';

// --- fixture constructors ----------------------------------------------------

const HASH = '#';

/** A hex colour literal, assembled so it is absent from this file's text. */
const hex = (digits: string): string => HASH + digits;

/** A colour-function call, assembled for the same reason. */
const fn = (name: string, body: string): string => `${name}(${body})`;

/** A CSS pixel length, assembled for the same reason. */
const px = (value: number): string => `${value}px`;

/** A media query embedded in a `matchMedia` call, as `useLayoutMode` writes it. */
const matchMediaSource = (query: string): string =>
  `const mq = window.matchMedia(${JSON.stringify(query)});`;

const CSS = 'src/styles/global.css';
const TSX = 'src/components/primitives.tsx';

const rulesOf = (violations: readonly { rule: string }[]): string[] =>
  violations.map((violation) => violation.rule);

const textsOf = (violations: readonly { text: string }[]): string[] =>
  violations.map((violation) => violation.text);

// --- the literal-colour scan -------------------------------------------------

describe('literal-colour scanner', () => {
  it('flags a hex literal in a stylesheet', () => {
    const found = scanTextForColorLiterals(
      CSS,
      `.card {\n  color: ${hex('00e5ff')};\n}\n`,
    );

    expect(found).toHaveLength(1);
    expect(found[0]).toMatchObject({
      file: CSS,
      rule: 'hex-literal',
      line: 2,
      column: 10,
      text: hex('00e5ff'),
    });
  });

  it('flags all four hex forms: 3, 4, 6 and 8 digits', () => {
    const source = [
      `a { color: ${hex('abc')}; }`,
      `b { color: ${hex('abcd')}; }`,
      `c { color: ${hex('aabbcc')}; }`,
      `d { color: ${hex('aabbccdd')}; }`,
    ].join('\n');

    const found = scanTextForColorLiterals(CSS, source);

    expect(textsOf(found)).toEqual([
      hex('abc'),
      hex('abcd'),
      hex('aabbcc'),
      hex('aabbccdd'),
    ]);
    expect(found.map((violation) => violation.line)).toEqual([1, 2, 3, 4]);
  });

  it('flags hex in either case, and in TypeScript as readily as in CSS', () => {
    const found = scanTextForColorLiterals(
      TSX,
      `const fill = '${hex('FF453A')}'; // the alert accent\n`,
    );

    expect(rulesOf(found)).toEqual(['hex-literal']);
    expect(found[0].text).toBe(hex('FF453A'));
  });

  it('flags every functional notation, legacy and modern', () => {
    const source = [
      `a { color: ${fn('rgb', '0, 229, 255')}; }`,
      `b { color: ${fn('rgba', '0, 229, 255, 0.5')}; }`,
      `c { color: ${fn('rgb', '0 229 255 / 50%')}; }`,
      `d { color: ${fn('hsl', '187 100% 50%')}; }`,
      `e { color: ${fn('hsla', '187 100% 50% / 0.5')}; }`,
      `f { color: ${fn('rgb', '100% 0% 0%')}; }`,
    ].join('\n');

    const found = scanTextForColorLiterals(CSS, source);

    expect(rulesOf(found)).toEqual([
      'rgb-function',
      'rgb-function',
      'rgb-function',
      'hsl-function',
      'hsl-function',
      'rgb-function',
    ]);
    expect(found[0].text).toBe(fn('rgb', '0, 229, 255'));
    expect(found[0].column).toBe(12);
  });

  it('flags two literals on one line separately', () => {
    const source = `const bg = dark ? '${hex('121212')}' : '${hex('f4f5f7')}';`;
    const found = scanTextForColorLiterals(TSX, source);

    expect(found).toHaveLength(2);
    expect(found[0].column).toBeLessThan(found[1].column);
  });

  it('ignores hex runs that are not a colour length', () => {
    const source = [
      `a { grid-area: ${hex('12345')}; }`,
      `b { grid-area: ${hex('1234567')}; }`,
      `c { grid-area: ${hex('deadbeefcafe')}; }`,
    ].join('\n');

    expect(scanTextForColorLiterals(CSS, source)).toEqual([]);
  });

  it('ignores an SVG paint reference, which is an element id', () => {
    const source = [
      `<path fill="url(${hex('fade')})" />`,
      `.a { fill: url('${hex('fade')}'); }`,
      `.b { fill: url("${hex('abc')}"); }`,
    ].join('\n');

    expect(scanTextForColorLiterals(TSX, source)).toEqual([]);
  });

  it('ignores a hash-prefixed word that is not hex at all', () => {
    const source = `<a href="${hex('settings')}">go</a>\n`;

    expect(scanTextForColorLiterals(TSX, source)).toEqual([]);
  });

  it('ignores an identifier that merely ends in a colour-function name', () => {
    const source = [
      `export function ${fn('srgb', 'r: number, g: number, b: number')} {}`,
      `const parsed = ${fn('toRgb', '118')};`,
      `const scaled = ${fn('parseHsl', '0.5')};`,
    ].join('\n');

    expect(scanTextForColorLiterals(TSX, source)).toEqual([]);
  });

  it('ignores prose and patterns that name a notation without using one', () => {
    const source = [
      `// accepts ${fn('rgb', '')} and ${fn('rgba', '')} from getComputedStyle`,
      `// legacy ${fn('rgba', 'r, g, b, a')} carries alpha as a fourth part`,
      String.raw`const FUNCTIONAL = /^rgba?\(([^()]*)\)$/i;`,
    ].join('\n');

    expect(scanTextForColorLiterals(TSX, source)).toEqual([]);
  });

  it('ignores compliant code that reads colour from the registry', () => {
    const source = [
      '.card { color: var(--text-primary); border: 1px solid var(--border); }',
      '.title { font-weight: 600; color: var(--accent-text); }',
      "const fill = getComputedStyle(root).getPropertyValue('--accent');",
    ].join('\n');

    expect(scanTextForColorLiterals(CSS, source)).toEqual([]);
  });

  it('exempts exactly the two enumerated files', () => {
    const source = `a { color: ${hex('00e5ff')}; background: ${fn('rgba', '0, 0, 0, 0.6')}; }`;

    expect(COLOR_SCAN_EXEMPT_FILES).toEqual([
      'src/styles/tokens.css',
      'src/__tests__/compliance/fixtures/color-literals.ts',
    ]);

    for (const exempt of COLOR_SCAN_EXEMPT_FILES) {
      expect(scanFileForColorLiterals(exempt, source)).toEqual([]);
      // Windows separators resolve to the same exemption.
      expect(
        scanFileForColorLiterals(exempt.replace(/\//g, '\\'), source),
      ).toEqual([]);
    }
  });

  it('still scans the rest of the suite, so the exemption is not a wildcard', () => {
    const source = `const alert = '${hex('ff453a')}';`;

    for (const file of [
      'src/__tests__/compliance/contrast.test.ts',
      'src/__tests__/compliance/fixtures/other.ts',
      'src/__tests__/compliance/scanners.ts',
      'src/styles/global.css',
    ]) {
      expect(rulesOf(scanFileForColorLiterals(file, source))).toEqual([
        'hex-literal',
      ]);
    }
  });
});

// --- the breakpoint scan -----------------------------------------------------

describe('breakpoint scanner', () => {
  it('flags a width-based media query in a stylesheet', () => {
    const source = `@media (min-width: ${px(900)}) {\n  .app { padding: 0; }\n}\n`;
    const found = scanTextForBreakpoints(CSS, source);

    expect(rulesOf(found)).toEqual(['width-media-query']);
    expect(found[0]).toMatchObject({ line: 1, column: 9 });
  });

  it('flags max-width and compound queries', () => {
    const source = [
      `@media (max-width: ${px(899)}) { .a { display: none; } }`,
      `@media screen and (min-width: ${px(901)}) { .b { display: flex; } }`,
      `@media only screen and (max-device-width: ${px(902)}) { .c { gap: 0; } }`,
    ].join('\n');

    expect(rulesOf(scanTextForBreakpoints(CSS, source))).toEqual([
      'width-media-query',
      'width-media-query',
      'width-media-query',
    ]);
  });

  it('flags the media-query range form, where the length comes first', () => {
    const source = `@media (${px(900)} <= width < ${px(1200)}) { .a { gap: 0; } }`;

    expect(rulesOf(scanTextForBreakpoints(CSS, source))).toEqual([
      'width-media-query',
      'width-media-query',
    ]);
  });

  it('flags a matchMedia call built from a literal width', () => {
    const source = matchMediaSource(`(min-width: ${px(900)})`);

    expect(rulesOf(scanTextForBreakpoints(TSX, source))).toEqual([
      'width-media-query',
    ]);
  });

  it('flags a Layout_Mode threshold written as a pixel length anywhere', () => {
    const source = [
      `.app { max-width: ${px(600)}; }`,
      `.shell { width: ${px(1024)}; }`,
    ].join('\n');

    expect(rulesOf(scanTextForBreakpoints(CSS, source))).toEqual([
      'threshold-pixel-literal',
      'threshold-pixel-literal',
    ]);
  });

  it('reports both rules when a threshold is restated inside a query', () => {
    const source = `@media (min-width: ${px(1024)}) { .a { gap: 0; } }`;
    const found = scanTextForBreakpoints(CSS, source);

    expect(rulesOf(found)).toEqual([
      'width-media-query',
      'threshold-pixel-literal',
    ]);
  });

  it('ignores a media query with no width feature', () => {
    const source = [
      '@media (prefers-reduced-motion: reduce) {',
      '  * { transition-duration: 1ms; }',
      '}',
      '@media print { .sheet { display: none; } }',
      '@media (prefers-color-scheme: dark) { .a { gap: 0; } }',
    ].join('\n');

    expect(scanTextForBreakpoints(CSS, source)).toEqual([]);
  });

  it('ignores min-width and max-width as ordinary declarations', () => {
    const source = [
      '.row { min-width: 0; flex: 1 1 auto; }',
      '.bar { max-width: 55%; }',
      '.kpi { font-weight: 600; font-size: 32px; }',
    ].join('\n');

    expect(scanTextForBreakpoints(CSS, source)).toEqual([]);
  });

  it('ignores a width query whose value is interpolated from the constants', () => {
    // The shape `useLayoutMode` produces: the feature name is spelled out, the
    // number is not. The words are allowed; only the numbers are duplication.
    const source = [
      "const q = `(min-width: ${BREAKPOINTS.medium}px)`;",
      'const mq = window.matchMedia(q);',
      "document.documentElement.dataset.layout = mq.matches ? 'medium' : 'compact';",
    ].join('\n');

    expect(scanTextForBreakpoints(TSX, source)).toEqual([]);
  });

  it('ignores pixel lengths that are not Layout_Mode thresholds', () => {
    // The Grid_12 content caps included: design.md defines them as custom
    // property values on the data-layout selectors, which is task 5.6's job.
    const source = [
      `:root[data-layout='expanded'] { --grid-content-max: ${px(1440)}; }`,
      `:root[data-layout='compact'] { --grid-content-max: ${px(560)}; }`,
      `.chart { height: ${px(220)}; }`,
    ].join('\n');

    expect(scanTextForBreakpoints(CSS, source)).toEqual([]);
  });

  it('ignores threshold-valued numbers that are not lengths', () => {
    const source = [
      'if (bytes < 1024) return `${bytes} B`;',
      'const weight = 600;',
      'await new Promise((resolve) => setTimeout(resolve, 600));',
    ].join('\n');

    expect(scanTextForBreakpoints(TSX, source)).toEqual([]);
  });

  it('leaves the layout module alone, since it owns the thresholds', () => {
    const source = [
      'export const BREAKPOINTS = { medium: 600, expanded: 1024 } as const;',
      matchMediaSource(`(min-width: ${px(1024)})`),
    ].join('\n');

    expect(scanFileForBreakpoints('src/core/layout.ts', source)).toEqual([]);
    expect(
      scanFileForBreakpoints('src\\core\\layout.ts', source),
    ).toEqual([]);
    expect(
      rulesOf(scanFileForBreakpoints('src/hooks/useLayoutMode.ts', source)),
    ).toEqual(['width-media-query', 'threshold-pixel-literal']);
  });
});

// --- reporting helpers -------------------------------------------------------

describe('scanner reporting', () => {
  it('covers stylesheets and TypeScript, and nothing else', () => {
    expect(isScannable('src/styles/global.css')).toBe(true);
    expect(isScannable('src/core/units.ts')).toBe(true);
    expect(isScannable('src/App.tsx')).toBe(true);
    expect(isScannable('src/styles/token-registry.json')).toBe(false);
    expect(isScannable('src/assets/logo.svg')).toBe(false);
  });

  it('formats a violation as a jumpable location', () => {
    const [violation] = scanTextForColorLiterals(
      CSS,
      `.a { color: ${hex('00e5ff')}; }`,
    );

    expect(formatViolation(violation)).toBe(
      `${CSS}:1:13  hex-literal  ${hex('00e5ff')}`,
    );
  });

  it('summarises a scan and a baseline into the same comparable shape', () => {
    const found = [
      ...scanTextForColorLiterals(TSX, `'${hex('121212')}' '${hex('f4f5f7')}'`),
      ...scanTextForColorLiterals(CSS, `.a { background: ${fn('rgba', '0, 0, 0, 0.6')}; }`),
    ];

    // Sorted by path, then by rule, so a scan and a baseline compare directly.
    expect(summarise(found)).toEqual([
      { file: TSX, rule: 'hex-literal', count: 2 },
      { file: CSS, rule: 'rgb-function', count: 1 },
    ]);

    expect(
      summariseKnown([
        {
          file: TSX,
          rule: 'hex-literal',
          count: 2,
          site: 'a site',
          clearedBy: 'a later task',
        },
        {
          file: CSS,
          rule: 'rgb-function',
          count: 1,
          site: 'a site',
          clearedBy: 'a later task',
        },
      ]),
    ).toEqual(summarise(found));
  });
});

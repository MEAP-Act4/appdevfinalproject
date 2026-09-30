/**
 * The literal-colour and breakpoint scans, run over the real `react_app/src`
 * tree.
 *
 * This is the half of task 1.9 that has teeth: `scanners.test.ts` proves the
 * detectors work, and this file points them at the shipped source. It reads the
 * tree with `node:fs`, so it is named `*.node.test.ts` and runs in the Node
 * project of `vitest.config.ts` rather than under jsdom.
 *
 * ## The baseline is a ratchet, not an exemption
 *
 * The colour literals that predate this scan are recorded in
 * `KNOWN_COLOR_VIOLATIONS` with the task that clears each one, and the assertion
 * below is an *equality* against that record — so a new literal fails the suite,
 * and so does removing one without removing its entry. Nothing is suppressed:
 * the scanner still reports each one, and the report is printed on failure.
 *
 * Task 1.9 recorded two, and the baseline is now **empty**. Task 3.2 removed the
 * `.scrim` overlay fill from `src/styles/global.css` by giving it a token, and
 * task 3.6 removed the two `theme-color` values from `src/App.tsx` by reading the
 * resolved `--bg` off the computed style instead of naming a colour in
 * TypeScript. Each had to drop its entry in the same change that fixed it. So
 * the equality below now asserts the strongest form of Requirements 1.3 and 1.5:
 * no colour literal anywhere under `src/` outside the two declared exemptions.
 *
 * _Requirements: 1.3, 1.5, 2.1_
 */
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, relative } from 'node:path';

import { describe, expect, it } from 'vitest';

import type { Violation } from './scanners';
import {
  BREAKPOINT_AUTHORITY_FILE,
  COLOR_SCAN_EXEMPT_FILES,
  KNOWN_BREAKPOINT_VIOLATIONS,
  KNOWN_COLOR_VIOLATIONS,
  UNSCANNED_BY_DESIGN,
  formatViolation,
  isColorScanExempt,
  isScannable,
  scanFileForBreakpoints,
  scanFileForColorLiterals,
  summarise,
  summariseKnown,
  toPosix,
} from './scanners';

/** `react_app/`, resolved from this file rather than from the process cwd. */
const CLIENT_ROOT = fileURLToPath(new URL('../../../', import.meta.url));

/** Every file under `src/`, as paths relative to `react_app/`. */
const ALL_FILES = walk(join(CLIENT_ROOT, 'src')).sort();

/** The subset the scanners read. */
const SOURCE_FILES = ALL_FILES.filter(isScannable);

const read = (file: string): string =>
  readFileSync(join(CLIENT_ROOT, file), 'utf8');

const scanAll = <Rule extends string>(
  scan: (file: string, text: string) => Violation<Rule>[],
): Violation<Rule>[] => SOURCE_FILES.flatMap((file) => scan(file, read(file)));

const report = (violations: readonly Violation[]): string =>
  violations.length === 0
    ? '(none)'
    : violations.map(formatViolation).join('\n');

describe('source scan coverage', () => {
  it('finds the shipped source tree', () => {
    expect(SOURCE_FILES.length).toBeGreaterThan(20);
    expect(SOURCE_FILES).toContain('src/App.tsx');
    expect(SOURCE_FILES).toContain('src/styles/global.css');
    expect(SOURCE_FILES).toContain('src/styles/tokens.css');
  });

  it('either scans a file under src or names it as data', () => {
    const unscanned = ALL_FILES.filter((file) => !isScannable(file));

    // Widening this list is a decision, not a detail: anything non-source that
    // appears under src/ has to be justified here before the scan will pass.
    expect(unscanned).toEqual([...UNSCANNED_BY_DESIGN]);
  });

  it('keeps both colour exemptions pointing at files that exist', () => {
    for (const exempt of COLOR_SCAN_EXEMPT_FILES) {
      expect(SOURCE_FILES, `exempt path is stale: ${exempt}`).toContain(exempt);
    }
    expect(COLOR_SCAN_EXEMPT_FILES).toHaveLength(2);
  });

  it('leaves the breakpoint authority file subject to the colour scan', () => {
    // task 5.2 has not written it yet; the contract still holds in advance.
    expect(isScannable(BREAKPOINT_AUTHORITY_FILE)).toBe(true);
    expect(isColorScanExempt(BREAKPOINT_AUTHORITY_FILE)).toBe(false);
  });
});

describe('literal-colour scan over react_app/src', () => {
  const found = scanAll(scanFileForColorLiterals);

  it('matches the recorded baseline exactly', () => {
    expect(
      summarise(found),
      `literal colours found:\n${report(found)}\n\n` +
        'Colour values belong in src/styles/tokens.css and its registry mirror. ' +
        'If a pre-existing literal was just removed, drop its entry from ' +
        'KNOWN_COLOR_VIOLATIONS in scanners.ts.',
    ).toEqual(summariseKnown(KNOWN_COLOR_VIOLATIONS));
  });

  it('finds nothing outside the recorded baseline', () => {
    const baselined = new Set(KNOWN_COLOR_VIOLATIONS.map(({ file }) => file));
    const unexpected = found.filter(({ file }) => !baselined.has(file));

    expect(unexpected, `unrecorded literal colours:\n${report(unexpected)}`).toEqual(
      [],
    );
  });

  it('still reports each baselined file, so a fix forces the record to change', () => {
    for (const known of KNOWN_COLOR_VIOLATIONS) {
      const hits = found.filter(
        (violation) =>
          violation.file === known.file && violation.rule === known.rule,
      );

      expect(
        hits.length,
        `${known.file} — ${known.site}. Cleared by ${known.clearedBy}.`,
      ).toBe(known.count);
    }
  });

  it('does not trip on the scanners or their own tests', () => {
    const ownFiles = [
      'src/__tests__/compliance/scanners.ts',
      'src/__tests__/compliance/scanners.test.ts',
      'src/__tests__/compliance/scanners.node.test.ts',
    ];

    for (const file of ownFiles) {
      expect(existsSync(join(CLIENT_ROOT, file)), file).toBe(true);
      const hits = scanFileForColorLiterals(file, read(file));
      expect(hits, `${file} trips its own scanner:\n${report(hits)}`).toEqual([]);
    }
  });

  it('does not trip on the rest of the compliance suite either', () => {
    const suite = SOURCE_FILES.filter(
      (file) => file.startsWith('src/__tests__/') && !isColorScanExempt(file),
    );
    const hits = suite.flatMap((file) => scanFileForColorLiterals(file, read(file)));

    expect(suite.length).toBeGreaterThan(3);
    expect(hits, `compliance suite literals:\n${report(hits)}`).toEqual([]);
  });
});

describe('breakpoint scan over react_app/src', () => {
  const found = scanAll(scanFileForBreakpoints);

  it('finds no duplicated Layout_Mode threshold', () => {
    expect(
      summarise(found),
      `breakpoint duplication found:\n${report(found)}\n\n` +
        `The three thresholds live in ${BREAKPOINT_AUTHORITY_FILE}. CSS keys ` +
        "off :root[data-layout='…'] instead of restating them.",
    ).toEqual(summariseKnown(KNOWN_BREAKPOINT_VIOLATIONS));
  });

  it('leaves the reduced-motion media query alone', () => {
    // tokens.css carries the only @media rule in the client today, and it is a
    // preference query rather than a width query.
    const tokens = read('src/styles/tokens.css');

    expect(tokens).toContain('@media (prefers-reduced-motion: reduce)');
    expect(scanFileForBreakpoints('src/styles/tokens.css', tokens)).toEqual([]);
  });
});

/** Collects every file beneath `dir`, as POSIX paths relative to the client root. */
function walk(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else out.push(toPosix(relative(CLIENT_ROOT, full)));
  }
  return out;
}

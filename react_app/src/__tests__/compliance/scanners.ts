/**
 * Source scanners for the Web_Client compliance suite.
 *
 * Two independent scans live here, and neither knows anything about the file
 * system — they take a relative path and the file's text, and return the
 * violations they found. The walk itself lives in `scanners.node.test.ts`, so
 * every rule below is unit-testable against synthetic source strings
 * (`scanners.test.ts`) without touching the disk.
 *
 * 1. **The literal-colour scan** (Requirements 1.3, 1.5). Fails on hash-prefixed
 *    hex literals in the `#rgb` / `#rgba` / `#rrggbb` / `#rrggbbaa` forms, and on
 *    the `rgb()`, `rgba()`, `hsl()` and `hsla()` functional notations. Every
 *    colour must come from the Design_Token_Registry instead.
 * 2. **The breakpoint scan** (Requirements 1.3, 2.1). Fails on width-based media
 *    queries carrying a numeric literal, and on the Layout_Mode threshold values
 *    written as pixel lengths. `src/core/layout.ts` is the single authority for
 *    the three thresholds; CSS keys off `:root[data-layout='…']` instead of
 *    restating the numbers.
 *
 * ## Exemptions
 *
 * The literal-colour scan has **exactly two** exempt files, both enumerated by
 * full path in {@link COLOR_SCAN_EXEMPT_FILES} rather than by directory
 * wildcard. `src/styles/tokens.css` is the Design_Token_Registry itself.
 * `src/__tests__/compliance/fixtures/color-literals.ts` is the quarantine the
 * contrast helper's reference tests need — a colour parser has to be handed real
 * strings, and a published WCAG figure has to be pinned against itself rather
 * than against the registry it exists to check. Every other file under
 * `src/__tests__/**` stays subject to the scan and reads palette values from
 * `src/styles/token-registry.json`.
 *
 * The breakpoint scan has one authority file, {@link BREAKPOINT_AUTHORITY_FILE}
 * — a separate mechanism from the colour exemptions, not a third entry on that
 * list. It is the file the thresholds are *supposed* to live in.
 *
 * ## Why these scanners do not trip on themselves
 *
 * This module and its tests are scanned like any other file, and they are not
 * exempt. Every pattern is therefore written so its own source text cannot match
 * it: the hex pattern begins `#(`, which is a hash followed by a non-hex digit;
 * the functional-notation pattern spells the names as `rgba?` / `hsla?`, so the
 * byte sequences the pattern hunts for never appear; and the threshold pattern
 * interpolates {@link LAYOUT_THRESHOLDS_PX} instead of spelling the pixel
 * lengths out. The unit tests build their fixture strings with small
 * constructors (`hex('…')`, `fn('rgb', '…')`, `px(600)`) for the same reason.
 * The placeholder spelling used in prose above — the `#rgb` and `#rrggbb` forms
 * — is safe because `r` and `g` are not hex digits.
 *
 * _Requirements: 1.3, 1.5, 2.1_
 */

/** File extensions the scanners cover. Anything else under `src/` is data. */
export const SCANNED_EXTENSIONS = ['.css', '.ts', '.tsx'] as const;

/**
 * The only files exempt from the literal-colour scan. Exactly two, enumerated
 * by path. See the module docstring for why each one is here.
 */
export const COLOR_SCAN_EXEMPT_FILES = [
  'src/styles/tokens.css',
  'src/__tests__/compliance/fixtures/color-literals.ts',
] as const;

/**
 * Files under `src/` the scanners do not read because they are not source.
 *
 * `token-registry.json` is the machine-readable mirror of the
 * Design_Token_Registry (task 1.7). It holds the palette by definition, so
 * scanning it for colour values would be scanning the registry for being the
 * registry. It is *not* granted a colour exemption, because it is not scanned in
 * the first place — and task 1.11 asserts every value in it against
 * `tokens.css` bidirectionally, which is a stronger guarantee than the scan
 * gives any exempt file.
 *
 * The node test asserts this list matches the tree exactly, so a second
 * non-source file appearing under `src/` is a failure that has to be decided
 * deliberately rather than absorbed silently.
 */
export const UNSCANNED_BY_DESIGN = ['src/styles/token-registry.json'] as const;

/**
 * The single authority for the Layout_Mode thresholds (task 5.2). Exempt from
 * the breakpoint scan only; it is expected to contain the numbers.
 */
export const BREAKPOINT_AUTHORITY_FILE = 'src/core/layout.ts';

/**
 * The Layout_Mode boundary widths of Requirement 2.1, which no file other than
 * {@link BREAKPOINT_AUTHORITY_FILE} may spell as a pixel length.
 *
 * The Grid_12 content caps are deliberately absent. design.md's Grid_12 section
 * defines them as CSS custom-property values on the `data-layout` selectors
 * (`--grid-content-max`), which is the mechanism task 5.6 implements, so listing
 * them here would fail a file the design tells task 5.6 to write. The
 * thresholds are different: they are what `matchMedia` resolves, and CSS never
 * needs them at all.
 */
export const LAYOUT_THRESHOLDS_PX = [600, 1024] as const;

/** Which literal-colour rule a violation broke. */
export type ColorRuleId = 'hex-literal' | 'rgb-function' | 'hsl-function';

/** Which breakpoint rule a violation broke. */
export type BreakpointRuleId = 'width-media-query' | 'threshold-pixel-literal';

/** One scanner finding, located precisely enough to act on. */
export interface Violation<Rule extends string = string> {
  /** Path relative to `react_app/`, POSIX separators, e.g. `src/App.tsx`. */
  readonly file: string;
  /** 1-based line number. */
  readonly line: number;
  /** 1-based column number. */
  readonly column: number;
  /** The rule that was broken. */
  readonly rule: Rule;
  /** The offending text, trimmed to the end of its line. */
  readonly text: string;
}

/**
 * A violation that exists in the tree today and is cleared by a later task.
 *
 * This is a ratchet, not an exemption. The node test asserts the live tree
 * produces *exactly* these counts: a new literal in one of these files fails the
 * suite, and so does fixing one without removing its entry here. The offending
 * values are described rather than quoted, so this file stays free of colour
 * literals itself.
 */
export interface KnownViolation {
  /** Path relative to `react_app/`, POSIX separators. */
  readonly file: string;
  /** The rule the file breaks. */
  readonly rule: ColorRuleId;
  /** How many times, exactly. */
  readonly count: number;
  /** Where in the file, in words, since the value itself cannot be quoted. */
  readonly site: string;
  /** The task that removes the literal, and therefore this entry. */
  readonly clearedBy: string;
}

/**
 * The colour literals left in shipped Web_Client code: **none**.
 *
 * Task 1.9 recorded two entries and both have since been cleared, so the
 * baseline is empty and the equality below is now a plain "no literals
 * anywhere" assertion.
 *
 * - Task 3.2 cleared the `src/styles/global.css` entry: the `.scrim` overlay
 *   fill is now the `--scrim` Token_Extension, declared in `tokens.css` and
 *   mirrored in the registry, so the declaration reads `var(--scrim)`.
 * - Task 3.6 cleared the `src/App.tsx` entry. The `theme-color` meta tag still
 *   cannot take a `var()`, but the concrete value it needs no longer comes from
 *   TypeScript: `syncThemeColor` reads the resolved `--bg` off the computed
 *   style of the document element and writes that. Adding High_Contrast_Dark
 *   would otherwise have taken the count from two literals to three.
 *
 * The type and the machinery stay, because a baseline that can be re-populated
 * deliberately is the point of a ratchet. Adding an entry is a decision; the
 * empty list is the clean state.
 */
export const KNOWN_COLOR_VIOLATIONS: readonly KnownViolation[] = [];

/** Breakpoint violations in shipped code as of task 1.9: none. */
export const KNOWN_BREAKPOINT_VIOLATIONS: readonly KnownViolation[] = [];

// --- the literal-colour scan -------------------------------------------------

/**
 * Hash-prefixed hex runs of 3 to 8 digits, not butted against a further word
 * character. The length filter below narrows the catch to the four real colour
 * forms, so a 5- or 7-digit run is left alone as the malformed value it is.
 */
const HEX_RUN = /#([0-9a-fA-F]{3,8})(?![0-9a-zA-Z_-])/g;

/** Hex digit counts that denote a colour. */
const COLOUR_HEX_LENGTHS = new Set([3, 4, 6, 8]);

/**
 * A colour function opening its argument list with something numeric.
 *
 * The lookbehind rejects a name that is the tail of a longer identifier, so the
 * compliance helper's own `srgb(…)` constructor and `toRgb(…)` coercion do not
 * register. The lookahead requires the first argument to start as a number,
 * which is what keeps prose and regular expressions *about* these notations from
 * registering as uses of them.
 */
const COLOUR_FUNCTION = /(?<![\w$-])(rgba?|hsla?)\((?=\s*[-+]?[.\d])/gi;

/** An SVG paint reference. The hash introduces an element id, not a colour. */
const URL_REFERENCE = /url\(\s*['"]?$/i;

/**
 * Scans text for literal colour values, ignoring every exemption.
 *
 * Use {@link scanFileForColorLiterals} for the exemption-aware form.
 */
export function scanTextForColorLiterals(
  file: string,
  text: string,
): Violation<ColorRuleId>[] {
  const index = new LineIndex(text);
  const found: Violation<ColorRuleId>[] = [];

  for (const match of text.matchAll(HEX_RUN)) {
    const at = match.index;
    if (!COLOUR_HEX_LENGTHS.has(match[1].length)) continue;
    if (URL_REFERENCE.test(text.slice(Math.max(0, at - 8), at))) continue;
    found.push(index.locate(file, 'hex-literal', at, match[0]));
  }

  for (const match of text.matchAll(COLOUR_FUNCTION)) {
    const at = match.index;
    const rule: ColorRuleId = match[1].toLowerCase().startsWith('r')
      ? 'rgb-function'
      : 'hsl-function';
    found.push(index.locate(file, rule, at, callSnippet(text, at)));
  }

  return sortByPosition(found);
}

/**
 * Scans one file for literal colour values, honouring the two path exemptions.
 *
 * Returns an empty list for an exempt file even when literals are present —
 * that is the point of the exemption — and scans everything else.
 */
export function scanFileForColorLiterals(
  file: string,
  text: string,
): Violation<ColorRuleId>[] {
  return isColorScanExempt(file) ? [] : scanTextForColorLiterals(file, text);
}

/** True for the two files enumerated in {@link COLOR_SCAN_EXEMPT_FILES}. */
export function isColorScanExempt(file: string): boolean {
  const path = toPosix(file);
  return COLOR_SCAN_EXEMPT_FILES.some((exempt) => exempt === path);
}

// --- the breakpoint scan -----------------------------------------------------

/** An `@media` prelude: everything from the at-rule to its block or terminator. */
const MEDIA_PRELUDE = /@media\b([^{;]*)/gi;

/** A `matchMedia(…)` call and its argument text. */
const MATCH_MEDIA_CALL = /\bmatchMedia\s*\(([^)]*)\)?/gi;

/** A width media feature given a numeric value: `(min-width: 900px)`. */
const WIDTH_FEATURE_WITH_NUMBER =
  /\b(?:min-|max-)?(?:device-)?width\s*[:<>=]+\s*[-+]?\d*\.?\d+/gi;

/** The range form, where the length precedes the feature: `(900px <= width)`. */
const NUMBER_BEFORE_WIDTH =
  /[-+]?\d*\.?\d+\s*(?:px|em|rem|ch|vw)?\s*[<>=]+\s*(?:min-|max-)?width\b/gi;

/** A Layout_Mode threshold written as a pixel length, built from the constants. */
const THRESHOLD_PIXELS = new RegExp(
  String.raw`(?<![\w.])(` + LAYOUT_THRESHOLDS_PX.join('|') + String.raw`)px\b`,
  'gi',
);

/**
 * Scans text for duplicated breakpoint values, ignoring the authority file.
 *
 * Use {@link scanFileForBreakpoints} for the authority-aware form.
 *
 * A width feature whose value is interpolated rather than literal — the shape
 * `useLayoutMode` produces when it builds its queries from the TypeScript
 * constants — is not a violation. It is the intended mechanism: the words are
 * allowed, the numbers are not.
 */
export function scanTextForBreakpoints(
  file: string,
  text: string,
): Violation<BreakpointRuleId>[] {
  const index = new LineIndex(text);
  const found: Violation<BreakpointRuleId>[] = [];

  const queries = [
    ...text.matchAll(MEDIA_PRELUDE),
    ...text.matchAll(MATCH_MEDIA_CALL),
  ];

  for (const query of queries) {
    const prelude = query[1];
    const preludeAt = query.index + query[0].indexOf(prelude);
    for (const pattern of [WIDTH_FEATURE_WITH_NUMBER, NUMBER_BEFORE_WIDTH]) {
      for (const hit of prelude.matchAll(pattern)) {
        found.push(
          index.locate(
            file,
            'width-media-query',
            preludeAt + hit.index,
            hit[0].trim(),
          ),
        );
      }
    }
  }

  for (const match of text.matchAll(THRESHOLD_PIXELS)) {
    found.push(
      index.locate(file, 'threshold-pixel-literal', match.index, match[0]),
    );
  }

  return dedupeByPosition(sortByPosition(found));
}

/** Scans one file for duplicated breakpoint values, skipping the authority file. */
export function scanFileForBreakpoints(
  file: string,
  text: string,
): Violation<BreakpointRuleId>[] {
  return isBreakpointAuthority(file) ? [] : scanTextForBreakpoints(file, text);
}

/** True for {@link BREAKPOINT_AUTHORITY_FILE}. */
export function isBreakpointAuthority(file: string): boolean {
  return toPosix(file) === BREAKPOINT_AUTHORITY_FILE;
}

// --- shared helpers ----------------------------------------------------------

/** True when a path carries one of {@link SCANNED_EXTENSIONS}. */
export function isScannable(file: string): boolean {
  const path = toPosix(file);
  return SCANNED_EXTENSIONS.some((extension) => path.endsWith(extension));
}

/** Normalises Windows separators, so reports read the same on every platform. */
export function toPosix(file: string): string {
  return file.replace(/\\/g, '/');
}

/** One line per violation, in the shape an editor can jump to. */
export function formatViolation(violation: Violation): string {
  const { file, line, column, rule, text } = violation;
  return `${file}:${line}:${column}  ${rule}  ${text}`;
}

/**
 * Collapses violations into `{ file, rule, count }` triples, sorted, which is
 * the shape {@link KNOWN_COLOR_VIOLATIONS} is compared against.
 */
export function summarise(
  violations: readonly Violation[],
): { file: string; rule: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const violation of violations) {
    const key = `${violation.file}\u0000${violation.rule}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([key, count]) => {
      const [file, rule] = key.split('\u0000');
      return { file, rule, count };
    })
    .sort((a, b) => a.file.localeCompare(b.file) || a.rule.localeCompare(b.rule));
}

/** The same shape, taken from a baseline rather than from a scan. */
export function summariseKnown(
  known: readonly KnownViolation[],
): { file: string; rule: string; count: number }[] {
  return known
    .map(({ file, rule, count }) => ({ file, rule, count }))
    .sort((a, b) => a.file.localeCompare(b.file) || a.rule.localeCompare(b.rule));
}

/** Resolves byte offsets to 1-based line and column numbers, once per file. */
class LineIndex {
  private readonly starts: number[] = [0];

  constructor(text: string) {
    for (let i = 0; i < text.length; i += 1) {
      if (text[i] === '\n') this.starts.push(i + 1);
    }
  }

  locate<Rule extends string>(
    file: string,
    rule: Rule,
    offset: number,
    text: string,
  ): Violation<Rule> {
    let low = 0;
    let high = this.starts.length - 1;
    while (low < high) {
      const middle = Math.ceil((low + high) / 2);
      if (this.starts[middle] <= offset) low = middle;
      else high = middle - 1;
    }
    return {
      file: toPosix(file),
      line: low + 1,
      column: offset - this.starts[low] + 1,
      rule,
      text,
    };
  }
}

/** The call from `at` up to its closing parenthesis, never crossing a newline. */
function callSnippet(text: string, at: number): string {
  const lineEnd = text.indexOf('\n', at);
  const limit = lineEnd === -1 ? text.length : lineEnd;
  const close = text.indexOf(')', at);
  const end = close === -1 || close > limit ? limit : close + 1;
  return text.slice(at, end).trim();
}

function sortByPosition<Rule extends string>(
  violations: Violation<Rule>[],
): Violation<Rule>[] {
  return violations.sort((a, b) => a.line - b.line || a.column - b.column);
}

/**
 * Drops duplicates at the same position, which the two width-query patterns can
 * produce on a range query that reads in both directions. A threshold length
 * *inside* a width query is deliberately left as two findings: the query and the
 * duplicated number are two separate things to correct.
 */
function dedupeByPosition<Rule extends string>(
  violations: Violation<Rule>[],
): Violation<Rule>[] {
  const seen = new Set<string>();
  return violations.filter((violation) => {
    const key = `${violation.line}:${violation.column}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

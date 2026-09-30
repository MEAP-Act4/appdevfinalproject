/**
 * Bidirectional agreement between `src/styles/tokens.css` and
 * `src/styles/token-registry.json`.
 *
 * The registry is only worth having if it cannot drift from the stylesheet it
 * describes, so the relationship is asserted in both directions:
 *
 * - **registry → stylesheet:** every registry entry has a declaration in the
 *   `tokens.css` block its `selector` field names, carrying the recorded value;
 * - **stylesheet → registry:** every custom-property declaration in
 *   `tokens.css` reconciles against a registry entry.
 *
 * The second direction is the one with teeth. Without it a new token can be
 * added to the stylesheet and simply never documented, and Requirement 1.9's
 * rationale-and-consumer obligation becomes optional in practice.
 *
 * Task 1.7 established this by hand with a throwaway script; this file is the
 * permanent version. The reconciliation decomposes as
 * **72 declarations = 66 registry entries + 3 Reduce_Motion attribute overrides
 * + 3 mirrored in the `prefers-reduced-motion` media block**, and each of those
 * four numbers is pinned below, so a change to the stylesheet's shape — not
 * just to a value — has to be acknowledged here.
 *
 * Task 3.2 moved those figures from 67 / 61 / 3 / 3. Five declarations and five
 * registry entries arrived together: `--accent-text` in the base block and again
 * in the light block (Requirement 11.4), `--scrim` in the base block, and the
 * two High_Contrast_Dark overrides (Requirement 9.2). The Reduce_Motion pair
 * stayed at 3 and 3.
 *
 * Runs in the Node project because it reads the stylesheet off disk as text.
 * Parsing the file rather than loading it into a DOM is deliberate: a browser
 * would resolve `var()` indirection and collapse the `:root` blocks, which is
 * exactly the structure being checked.
 *
 * _Requirements: 1.6, 1.7, 1.9_
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  allEntries,
  highContrastDarkAbout,
  highContrastDarkExtensions,
  lightAppearanceAbout,
  normaliseCssValue,
  registry,
  requirement16Tokens,
  requirement17Tokens,
  selectorFor,
  valuesAgree,
  type NamedEntry,
} from './registry-model';

// --- the stylesheet ----------------------------------------------------------

/** One custom-property declaration, with the block it was found in. */
interface CssDeclaration {
  /** Custom-property name, including the leading double dash. */
  readonly name: string;
  /** Declaration value, verbatim and untrimmed of internal whitespace. */
  readonly value: string;
  /**
   * The prelude of the innermost enclosing block, with whitespace runs collapsed
   * to single spaces.
   *
   * A prelude, not a single selector: since task 3.2 the dark block names two
   * appearances, `:root[data-theme='dark'], :root[data-theme='hc-dark']`, and the
   * registry records that text verbatim. Collapsing whitespace is what lets the
   * stylesheet break the two selectors across lines — which is how CSS is
   * conventionally written, and how design.md writes it — without the registry
   * having to carry a newline inside a JSON string.
   */
  readonly selector: string;
  /** The enclosing at-rule prelude, or null at the top level. */
  readonly atRule: string | null;
  /** 1-based line number, so a failure points at the source. */
  readonly line: number;
}

/**
 * Extracts every custom-property declaration from a stylesheet.
 *
 * A deliberately small scanner rather than a CSS parser dependency. It tracks a
 * stack of block preludes so a declaration inside `@media { :root { … } }`
 * reports both its at-rule and its selector, and it ignores ordinary CSS
 * properties such as `color-scheme`, which are not part of the registry.
 *
 * `tokens.css` contains no strings holding braces or semicolons, and no
 * parenthesised value contains either, so a flat character scan is sufficient.
 */
function parseCustomProperties(css: string): CssDeclaration[] {
  const source = stripComments(css);
  const found: CssDeclaration[] = [];
  const preludes: string[] = [];
  let buffer = '';
  let bufferStart = 0;

  const flush = (endIndex: number): void => {
    const text = buffer.trim();
    buffer = '';
    if (text.length === 0 || preludes.length === 0) {
      return;
    }
    const colon = text.indexOf(':');
    if (colon === -1) {
      return;
    }
    const name = text.slice(0, colon).trim();
    if (!name.startsWith('--')) {
      return; // An ordinary property, e.g. `color-scheme`.
    }
    const atRule = preludes.find((prelude) => prelude.startsWith('@')) ?? null;
    found.push({
      name,
      value: text.slice(colon + 1).trim(),
      selector: preludes[preludes.length - 1],
      atRule,
      line: lineOf(source, Math.min(bufferStart, endIndex)),
    });
  };

  for (let i = 0; i < source.length; i += 1) {
    const char = source[i];
    if (char === '{') {
      preludes.push(collapseWhitespace(buffer));
      buffer = '';
      bufferStart = i + 1;
    } else if (char === '}') {
      flush(i);
      preludes.pop();
      bufferStart = i + 1;
    } else if (char === ';') {
      flush(i);
      bufferStart = i + 1;
    } else {
      if (buffer.length === 0) {
        // Drop leading whitespace so `bufferStart` lands on the first real
        // character of the declaration and the reported line is the right one.
        if (/\s/.test(char)) {
          continue;
        }
        bufferStart = i;
      }
      buffer += char;
    }
  }

  return found;
}

/**
 * Trims a block prelude and collapses its internal whitespace runs.
 *
 * Whitespace between the selectors of a grouped prelude is not semantic, so a
 * declaration reports the same enclosing block whether the stylesheet wrote the
 * group on one line or across several.
 */
function collapseWhitespace(prelude: string): string {
  return prelude.trim().replace(/\s+/g, ' ');
}

/** Removes `/* … *\/` comments, preserving line breaks so numbers stay right. */
function stripComments(css: string): string {
  return css.replace(/\/\*[\s\S]*?\*\//g, (comment) =>
    comment.replace(/[^\n]/g, ' '),
  );
}

function lineOf(source: string, index: number): number {
  let line = 1;
  for (let i = 0; i < index && i < source.length; i += 1) {
    if (source[i] === '\n') {
      line += 1;
    }
  }
  return line;
}

const STYLESHEET_PATH = join(process.cwd(), 'src', 'styles', 'tokens.css');

const stylesheet = readFileSync(STYLESHEET_PATH, 'utf8');
const declarations = parseCustomProperties(stylesheet);

// --- expected shape ---------------------------------------------------------

/** The prelude of the only at-rule `tokens.css` contains. */
const REDUCED_MOTION_AT_RULE = '@media (prefers-reduced-motion: reduce)';

/** Total custom-property declarations in `tokens.css`. */
const DECLARATION_COUNT = 72;

/**
 * Registry entries across `tokens`, `extensions`, the High_Contrast_Dark
 * overrides and the light palette.
 */
const REGISTRY_ENTRY_COUNT = 66;

/** The `--t-*` aliases, which are the only entries with a Reduce_Motion override. */
const MOTION_ALIASES = allEntries().filter(
  ({ entry }) => entry.reduceMotionSelector !== undefined,
);

/** Every declaration outside the `prefers-reduced-motion` block. */
const attributeScoped = declarations.filter(({ atRule }) => atRule === null);

/** Every declaration inside the `prefers-reduced-motion` block. */
const mediaScoped = declarations.filter(({ atRule }) => atRule !== null);

/** A `selector\u0000name` key, so lookups are scoped to the right block. */
function keyOf(selector: string, name: string): string {
  return `${selector}\u0000${name}`;
}

const bySelectorAndName = new Map<string, CssDeclaration[]>();
for (const declaration of attributeScoped) {
  const key = keyOf(declaration.selector, declaration.name);
  const bucket = bySelectorAndName.get(key);
  if (bucket === undefined) {
    bySelectorAndName.set(key, [declaration]);
  } else {
    bucket.push(declaration);
  }
}

/**
 * The declarations the registry accounts for: one per entry at its own
 * selector, plus one per motion alias at its Reduce_Motion selector.
 */
function expectedAttributeScopedKeys(): Set<string> {
  const keys = new Set<string>();
  for (const named of allEntries()) {
    keys.add(keyOf(selectorFor(named), named.name));
  }
  for (const { name, entry } of MOTION_ALIASES) {
    keys.add(keyOf(entry.reduceMotionSelector as string, name));
  }
  return keys;
}

// --- the scanner's own behaviour --------------------------------------------

describe('the custom-property scanner', () => {
  it('reports the selector, at-rule and line of each declaration', () => {
    const parsed = parseCustomProperties(
      [
        ':root {',
        '  --a: 8px;',
        '  color-scheme: dark;',
        '}',
        "@media (prefers-reduced-motion: reduce) {",
        '  :root { --a: 1ms }',
        '}',
      ].join('\n'),
    );

    expect(parsed).toHaveLength(2);
    expect(parsed[0]).toMatchObject({
      name: '--a',
      value: '8px',
      selector: ':root',
      atRule: null,
      line: 2,
    });
    expect(parsed[1]).toMatchObject({
      name: '--a',
      value: '1ms',
      selector: ':root',
      atRule: REDUCED_MOTION_AT_RULE,
      line: 6,
    });
  });

  it('ignores commented-out declarations without losing line numbers', () => {
    const parsed = parseCustomProperties(
      [':root {', '  /* --a: 8px; */', '  --b: 16px;', '}'].join('\n'),
    );

    expect(parsed.map(({ name }) => name)).toEqual(['--b']);
    expect(parsed[0].line).toBe(3);
  });

  it('keeps commas and parentheses inside a value intact', () => {
    const parsed = parseCustomProperties(
      ':root { --e: cubic-bezier(0.22, 1, 0.36, 1); }',
    );

    expect(parsed[0].value).toBe('cubic-bezier(0.22, 1, 0.36, 1)');
  });

  it('reports a grouped prelude identically however it is wrapped', () => {
    // The dark block names two appearances. Whether the group is written on one
    // line or broken across two is a formatting choice, and the registry records
    // one string for it either way.
    const oneLine = parseCustomProperties(":root[data-a], :root[data-b] { --x: 1px; }");
    const wrapped = parseCustomProperties(
      [':root[data-a],', ':root[data-b] {', '  --x: 1px;', '}'].join('\n'),
    );

    expect(oneLine[0].selector).toBe(':root[data-a], :root[data-b]');
    expect(wrapped[0].selector).toBe(oneLine[0].selector);
    expect(wrapped[0].line).toBe(3);
  });
});

// --- the shape of tokens.css ------------------------------------------------

describe('the shape of tokens.css', () => {
  it('declares seventy-two custom properties', () => {
    expect(declarations).toHaveLength(DECLARATION_COUNT);
  });

  it('decomposes into registry entries, overrides and the media mirror', () => {
    expect(allEntries()).toHaveLength(REGISTRY_ENTRY_COUNT);
    expect(MOTION_ALIASES).toHaveLength(3);
    expect(mediaScoped).toHaveLength(3);
    expect(attributeScoped).toHaveLength(
      REGISTRY_ENTRY_COUNT + MOTION_ALIASES.length,
    );
    expect(
      REGISTRY_ENTRY_COUNT + MOTION_ALIASES.length + mediaScoped.length,
    ).toBe(DECLARATION_COUNT);
  });

  it('uses exactly the block selectors the registry names', () => {
    const selectors = new Set(attributeScoped.map(({ selector }) => selector));
    const registrySelectors = new Set<string>();
    for (const named of allEntries()) {
      registrySelectors.add(selectorFor(named));
    }
    for (const { entry } of MOTION_ALIASES) {
      registrySelectors.add(entry.reduceMotionSelector as string);
    }
    expect([...selectors].sort()).toEqual([...registrySelectors].sort());
  });

  it('shares one block between Dark and High_Contrast_Dark', () => {
    // Requirement 9.2 keeps High_Contrast_Dark inside the WattVision §2 dark
    // family. Sharing the block by grouping the prelude is what makes that
    // structural rather than a promise: there is no second copy of the palette
    // to drift from the first.
    const darkBlock = registry.meta.groupedSelectors;
    const grouped = [...new Set(attributeScoped.map(({ selector }) => selector))].filter(
      (selector) => selector.includes(','),
    );
    expect(grouped).toHaveLength(1);
    expect(darkBlock).toContain(grouped[0]);

    const named = grouped[0].split(',').map((part) => part.trim());
    expect(named).toHaveLength(2);
    expect(named).toContain(highContrastDarkAbout.selector);
  });

  it('overrides exactly the two High_Contrast_Dark properties and nothing else', () => {
    const hcSelector = highContrastDarkAbout.selector;
    const declared = attributeScoped
      .filter(({ selector }) => selector === hcSelector)
      .map(({ name }) => name)
      .sort();

    expect(declared).toEqual(Object.keys(highContrastDarkExtensions).sort());

    // The surfaces have to stay byte-identical to Dark, so the high-contrast
    // block must not restate any of them. This is the half of Requirement 9.2
    // that a contrast comparison cannot see.
    for (const surface of ['--bg', '--surface', '--surface-raised']) {
      expect(
        declared,
        `${surface} is redefined for High_Contrast_Dark, which takes it outside ` +
          'the WattVision §2 dark family',
      ).not.toContain(surface);
    }
  });

  it('contains one at-rule, the reduced-motion preference block', () => {
    const atRules = new Set(mediaScoped.map(({ atRule }) => atRule));
    expect([...atRules]).toEqual([REDUCED_MOTION_AT_RULE]);
    expect(normaliseCssValue(stylesheet).split('@media').length - 1).toBe(1);
  });

  it('mirrors the reduced-motion preference onto the same three aliases', () => {
    // The attribute override and the media query have to say the same thing, or
    // a user whose platform asks for reduced motion gets a different result
    // from a user who asks for it in Settings.
    const aliasNames = MOTION_ALIASES.map(({ name }) => name).sort();
    expect(mediaScoped.map(({ name }) => name).sort()).toEqual(aliasNames);
    expect(new Set(mediaScoped.map(({ selector }) => selector))).toEqual(
      new Set([':root']),
    );
    for (const declaration of mediaScoped) {
      const alias = MOTION_ALIASES.find(({ name }) => name === declaration.name);
      expect(alias).toBeDefined();
      expect(
        valuesAgree(declaration.value, alias?.entry.reduceMotionValue as string),
        `${declaration.name} in the media block disagrees with its registry override`,
      ).toBe(true);
    }
  });

  it('declares each property at most once per block', () => {
    const duplicates = [...bySelectorAndName.entries()]
      .filter(([, bucket]) => bucket.length > 1)
      .map(([, bucket]) => `${bucket[0].selector} ${bucket[0].name}`);
    expect(duplicates).toEqual([]);
  });
});

// --- registry -> stylesheet -------------------------------------------------

describe('registry to stylesheet', () => {
  it.each(allEntries())(
    '$group $name is declared in tokens.css with the recorded value',
    (named: NamedEntry) => {
      const selector = selectorFor(named);
      const bucket = bySelectorAndName.get(keyOf(selector, named.name));
      expect(
        bucket,
        `${named.name} is registered under ${selector} but not declared there`,
      ).toBeDefined();

      const declaration = (bucket as CssDeclaration[])[0];
      expect(
        valuesAgree(declaration.value, named.entry.value),
        `${named.name} at ${selector}: tokens.css line ${declaration.line} has ` +
          `${JSON.stringify(declaration.value)}, the registry records ` +
          `${JSON.stringify(named.entry.value)}`,
      ).toBe(true);
    },
  );

  it.each(MOTION_ALIASES)(
    '$name is overridden for Reduce_Motion exactly as recorded',
    (named: NamedEntry) => {
      const selector = named.entry.reduceMotionSelector as string;
      const bucket = bySelectorAndName.get(keyOf(selector, named.name));
      expect(bucket, `${named.name} has no override under ${selector}`).toBeDefined();
      expect(
        valuesAgree(
          (bucket as CssDeclaration[])[0].value,
          named.entry.reduceMotionValue as string,
        ),
      ).toBe(true);
    },
  );
});

// --- stylesheet -> registry -------------------------------------------------

describe('stylesheet to registry', () => {
  it('leaves no declaration undocumented', () => {
    const accounted = expectedAttributeScopedKeys();
    const orphans = attributeScoped
      .filter(({ selector, name }) => !accounted.has(keyOf(selector, name)))
      .map(({ selector, name, line }) => `${name} at ${selector} (line ${line})`);

    // An undocumented token is the failure this whole file exists to produce.
    // Adding one to tokens.css without a registry entry lands here, which is
    // what gives the Requirement 1.9 rationale obligation its teeth.
    expect(orphans).toEqual([]);
  });

  it('leaves no registry entry undeclared', () => {
    const declared = new Set(
      attributeScoped.map(({ selector, name }) => keyOf(selector, name)),
    );
    const missing = [...expectedAttributeScopedKeys()]
      .filter((key) => !declared.has(key))
      .map((key) => {
        const [selector, name] = key.split('\u0000');
        return `${name} at ${selector}`;
      });
    expect(missing).toEqual([]);
  });

  it('reconciles every declaration exactly once, with no value mismatch', () => {
    const mismatches: string[] = [];
    const byName = new Map<string, NamedEntry>();
    for (const named of allEntries()) {
      byName.set(keyOf(selectorFor(named), named.name), named);
    }
    for (const { name, entry } of MOTION_ALIASES) {
      byName.set(keyOf(entry.reduceMotionSelector as string, name), {
        name,
        group: 'extensions',
        entry: { ...entry, value: entry.reduceMotionValue as string },
      });
    }

    for (const declaration of attributeScoped) {
      const named = byName.get(keyOf(declaration.selector, declaration.name));
      if (named === undefined) {
        mismatches.push(`${declaration.name} at ${declaration.selector}: no entry`);
        continue;
      }
      if (!valuesAgree(declaration.value, named.entry.value)) {
        mismatches.push(
          `${declaration.name} at ${declaration.selector} (line ${declaration.line}): ` +
            `stylesheet ${JSON.stringify(declaration.value)} vs registry ` +
            `${JSON.stringify(named.entry.value)}`,
        );
      }
    }

    expect(mismatches).toEqual([]);
  });
});

// --- the enumerated constants, in the stylesheet ----------------------------

describe('the enumerated constants reach the stylesheet', () => {
  it.each(requirement16Tokens())(
    '$name, one of the Requirement 1.6 eleven, is declared with its registry value',
    (named: NamedEntry) => {
      const bucket = bySelectorAndName.get(
        keyOf(selectorFor(named), named.name),
      );
      expect(bucket).toBeDefined();
      expect((bucket as CssDeclaration[])[0].value.toLowerCase()).toBe(
        named.entry.value.toLowerCase(),
      );
    },
  );

  it.each(requirement17Tokens())(
    '$name, one of the Requirement 1.7 six, is declared as its numeric plus its unit',
    (named: NamedEntry) => {
      const bucket = bySelectorAndName.get(
        keyOf(selectorFor(named), named.name),
      );
      expect(bucket).toBeDefined();
      expect((bucket as CssDeclaration[])[0].value).toBe(
        `${named.entry.numeric as number}${named.entry.unit as string}`,
      );
    },
  );

  it('keeps the light appearance from redefining the Requirement 1.7 numerics', () => {
    // Geometry and type sizes are appearance-independent, so none of the six may
    // be restated in the light block. A restatement there would mean the fixed
    // values are only fixed in one appearance.
    const lightSelector = lightAppearanceAbout.selector;
    const redefined = requirement17Tokens()
      .map(({ name }) => name)
      .filter((name) => bySelectorAndName.has(keyOf(lightSelector, name)));
    expect(redefined).toEqual([]);
  });

  it('names the stylesheet it is checked against', () => {
    // The registry records which file it mirrors. If that ever points somewhere
    // else, this test is reading the wrong file and silently passing.
    expect(registry.meta.stylesheet).toBe('react_app/src/styles/tokens.css');
  });
});

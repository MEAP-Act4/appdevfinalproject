/**
 * The colour-literal quarantine for the compliance suite.
 *
 * Requirement 1.5 forbids literal hex, `rgb()` and `hsl()` values anywhere
 * under `react_app/src` except `styles/tokens.css`. The contrast helper's own
 * reference tests cannot honour that without becoming untestable: a parser has
 * to be handed real strings, and a maths reference value has to be pinned
 * against a published figure rather than against the registry it is meant to
 * check.
 *
 * So every literal the suite needs lives in this one file, and nowhere else.
 *
 * **Note for task 1.9:** the React literal-colour scanner must exempt exactly
 * this path — `src/__tests__/compliance/fixtures/color-literals.ts` — in the
 * same explicit, enumerated way it exempts `src/styles/tokens.css`. It is a
 * second declared exemption, not a wildcard over `src/__tests__`: test files
 * outside this fixture module stay subject to the scan, and the palette values
 * they need come from `src/styles/token-registry.json` instead.
 *
 * Nothing here is a design token. These are parser inputs and published WCAG
 * reference values, and no application code may import this module.
 */

/** Pure white. Achromatic, luminance 1.0, the lighter half of the 21:1 pair. */
export const WHITE = '#ffffff';

/** Pure black. Achromatic, luminance 0.0, the darker half of the 21:1 pair. */
export const BLACK = '#000000';

/**
 * WebAIM's published boundary grey: 4.54:1 against white, the darkest grey that
 * still clears the 4.5:1 body-text threshold. The spot-check that proves the
 * linearisation is right rather than merely self-consistent.
 */
export const MID_GREY = '#767676';

/** Published reference: pure blue on white is 8.59:1. */
export const PURE_BLUE = '#0000ff';

/** Shorthand forms of {@link WHITE}, for the hex parser. */
export const WHITE_SHORTHAND = '#fff';
export const WHITE_SHORTHAND_HALF_ALPHA = '#fff8';

/** Eight-digit form of {@link WHITE} at 50% alpha, for the hex parser. */
export const WHITE_WITH_ALPHA = '#ffffff80';

/**
 * {@link MID_GREY} in every functional notation the parser must accept.
 * `getComputedStyle` in jsdom emits the legacy comma form; modern browsers and
 * hand-authored CSS use the space-and-slash form.
 */
export const MID_GREY_LEGACY = 'rgb(118, 118, 118)';
export const MID_GREY_LEGACY_ALPHA = 'rgba(118, 118, 118, 0.5)';
export const MID_GREY_MODERN = 'rgb(118 118 118)';
export const MID_GREY_MODERN_ALPHA = 'rgb(118 118 118 / 50%)';

/** Percentage channels, which resolve to pure red. */
export const PURE_RED_PERCENT = 'rgb(100% 0% 0%)';

/** Inputs the parser must reject rather than silently coerce. */
export const MALFORMED = [
  'not-a-colour',
  '',
  '#12345',
  '#gggggg',
  'hsl(190 100% 50%)',
  'rgb(1, 2)',
  'rgb(1 2 3 / 4 / 5)',
  'rgb(a, b, c)',
] as const;

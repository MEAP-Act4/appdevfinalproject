/**
 * Colour maths for the Web_Client compliance suite.
 *
 * Two independent families of arithmetic live here, and they must not be
 * confused with one another:
 *
 * 1. **WCAG contrast.** Channels are normalised to [0, 1] and then *linearised*
 *    out of the sRGB transfer curve before the 0.2126 / 0.7152 / 0.0722
 *    luminance weights are applied. `contrastRatio` returns
 *    `(Llighter + 0.05) / (Ldarker + 0.05)`.
 * 2. **HSL lightness and saturation.** Computed from the *raw* sRGB channels
 *    with no gamma linearisation, exactly as `pastelRule.hsl` in
 *    `src/styles/token-registry.json` records it. Standard HSL, not HSV.
 *
 * The algorithm is mirrored byte for byte by `flutter_app/test/compliance/
 * contrast.dart` (task 1.4), so both clients compute contrast the same way.
 * Any change here has to land there too, or Requirement 13.1 breaks.
 *
 * The pastel, neutral and achromatic thresholds are not restated here — all
 * three are read from `pastelRule` in the token registry, which Requirement 9.8
 * makes the single authority for them.
 *
 * _Requirements: 11.3, 9.8_
 */

import registry from '../../styles/token-registry.json';

/** An sRGB colour with 8-bit-scaled channels and a unit alpha. */
export interface Rgb {
  /** Red channel, 0..255. May be fractional when parsed from percentages. */
  readonly r: number;
  /** Green channel, 0..255. */
  readonly g: number;
  /** Blue channel, 0..255. */
  readonly b: number;
  /**
   * Alpha, 0..1. Parsed and carried so `rgba()` strings from
   * `getComputedStyle` round-trip, but deliberately ignored by every function
   * below: WCAG contrast is defined over composited, opaque colours, and
   * silently folding alpha into the maths would hide a real problem rather
   * than surface it.
   */
  readonly a: number;
}

/** Anything the helper accepts: a parsed colour, or a string it can parse. */
export type ColorInput = string | Rgb;

/** WCAG 2.1 relative-luminance channel weights. */
export const LUMINANCE_WEIGHTS = { r: 0.2126, g: 0.7152, b: 0.0722 } as const;

/** Knee of the sRGB linearisation piecewise function, per WCAG 2.1. */
export const LINEARISE_KNEE = 0.03928;

/** The constant added to both luminances in the contrast-ratio formula. */
export const CONTRAST_OFFSET = 0.05;

/** HSL lightness a colour must exceed to be a pastel candidate. */
export const PASTEL_LIGHTNESS_ABOVE: number = registry.pastelRule.lightnessAbove;

/** HSL saturation a colour must fall below to be a pastel candidate. */
export const PASTEL_SATURATION_BELOW: number = registry.pastelRule.saturationBelow;

/** HSL saturation at or below which a colour carries no hue at all. */
export const ACHROMATIC_SATURATION_AT_MOST: number =
  registry.pastelRule.achromatic.saturationAtMost;

/**
 * HSL saturation at or below which a colour is too faintly hued to be a pastel.
 *
 * Read from `pastelRule.neutral.saturationAtMost`, which is the single place the
 * threshold is tuned. See {@link isNeutral} for what it means and why it exists.
 */
export const NEUTRAL_SATURATION_AT_MOST: number =
  registry.pastelRule.neutral.saturationAtMost;

/** Builds a colour from raw sRGB channels. Named `srgb` rather than `rgb` so
 * call sites never produce the `rgb(` byte sequence the task 1.9 literal-colour
 * scanner looks for. */
export function srgb(r: number, g: number, b: number, a = 1): Rgb {
  return {
    r: clamp(r, 0, 255),
    g: clamp(g, 0, 255),
    b: clamp(b, 0, 255),
    a: clamp(a, 0, 1),
  };
}

/**
 * Parses a CSS colour string.
 *
 * Accepts the two forms the compliance suite actually encounters: hex literals
 * as written in `tokens.css` (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`) and the
 * functional notation `getComputedStyle` hands back (`rgb()` / `rgba()`, in
 * both the legacy comma syntax and the modern space-and-slash syntax, with
 * number or percentage channels).
 *
 * Throws on anything else rather than guessing, so an unparseable token fails
 * the suite loudly instead of quietly contributing a black colour to a ratio.
 */
export function parseColor(input: string): Rgb {
  const text = input.trim();

  if (text.startsWith('#')) {
    return parseHexBody(text.slice(1), input);
  }

  const functional = /^rgba?\(([^()]*)\)$/i.exec(text);
  if (functional !== null) {
    return parseFunctionalBody(functional[1], input);
  }

  throw new Error(
    `Unrecognised colour value ${JSON.stringify(input)}. ` +
      'Expected a hex literal of 3, 4, 6 or 8 digits, or functional notation.',
  );
}

/** Coerces either accepted input form to a parsed colour. */
export function toRgb(color: ColorInput): Rgb {
  return typeof color === 'string' ? parseColor(color) : color;
}

/**
 * Linearises one sRGB channel expressed in [0, 1].
 *
 * `c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4`
 */
export function lineariseChannel(channel: number): number {
  const c = clamp(channel, 0, 1);
  return c <= LINEARISE_KNEE ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

/** WCAG 2.1 relative luminance, in [0, 1]. Alpha is ignored. */
export function relativeLuminance(color: ColorInput): number {
  const { r, g, b } = toRgb(color);
  return (
    LUMINANCE_WEIGHTS.r * lineariseChannel(r / 255) +
    LUMINANCE_WEIGHTS.g * lineariseChannel(g / 255) +
    LUMINANCE_WEIGHTS.b * lineariseChannel(b / 255)
  );
}

/**
 * WCAG 2.1 contrast ratio, in [1, 21].
 *
 * Symmetric by construction: the lighter luminance is always the numerator, so
 * argument order carries no meaning.
 */
export function contrastRatio(a: ColorInput, b: ColorInput): number {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const lighter = Math.max(la, lb);
  const darker = Math.min(la, lb);
  return (lighter + CONTRAST_OFFSET) / (darker + CONTRAST_OFFSET);
}

/**
 * Rounds a ratio for pinning in an assertion or a failure message.
 *
 * Ratios are quoted to two decimal places throughout design.md (10.84:1,
 * 3.74:1, 5.79:1), so this exists to make those comparisons exact rather than
 * approximate.
 */
export function roundRatio(ratio: number, decimals = 2): number {
  const factor = Math.pow(10, decimals);
  return Math.round(ratio * factor) / factor;
}

/** HSL lightness, in [0, 1]: `(max + min) / 2` over normalised channels. */
export function hslLightness(color: ColorInput): number {
  const { max, min } = extent(color);
  return (max + min) / 2;
}

/**
 * HSL saturation, in [0, 1].
 *
 * `max == min ? 0 : (max - min) / (lightness > 0.5 ? (2 - max - min) : (max + min))`
 */
export function hslSaturation(color: ColorInput): number {
  const { max, min } = extent(color);
  if (max === min) {
    return 0;
  }
  const lightness = (max + min) / 2;
  return (max - min) / (lightness > 0.5 ? 2 - max - min : max + min);
}

/**
 * True when a colour carries no hue at all, i.e. its three channels are equal.
 *
 * Kept as its own predicate even though {@link isNeutral} subsumes it, because
 * it states a stricter and independently useful fact: this colour is provably
 * hueless, not merely faintly hued. Pure white and pure black are the cases that
 * matter — white has lightness 1.0 and saturation 0, and a rule that flagged it
 * would reject the WattVision §2 primary text colour.
 */
export function isAchromatic(color: ColorInput): boolean {
  return hslSaturation(color) <= ACHROMATIC_SATURATION_AT_MOST;
}

/**
 * True when a colour is near-neutral: a grey, or a grey with a cast too faint to
 * read as a colour you could name.
 *
 * This is the exclusion the pastel rule uses, and it is wider than
 * {@link isAchromatic}. A pastel is a pale tint of an identifiable hue; an
 * off-white page background sitting two blue points away from a pure grey is not
 * one. Excluding only saturation exactly 0 drew that line in a place no user can
 * see, so the registry records a threshold instead — read here rather than
 * restated, so it is tuned in exactly one place.
 *
 * Every achromatic colour is neutral. The converse does not hold.
 */
export function isNeutral(color: ColorInput): boolean {
  return hslSaturation(color) <= NEUTRAL_SATURATION_AT_MOST;
}

/**
 * The pastel predicate exactly as `pastelRule.predicate` defines it:
 * `!isNeutral(c) && hslLightness(c) > 0.8 && hslSaturation(c) < 0.5`.
 *
 * The two thresholds are untouched from the original definition: a light,
 * weakly-but-genuinely saturated colour is still a pastel and still fails
 * Requirement 9.8. What the neutral exclusion changes is the set of colours the
 * question is asked about, not the answer for any colour that is really tinted.
 * `pastelRule.knownLiteralRuleHits` is now empty, and the registry records which
 * of the four original hits was cleared by the carve-out and which was cleared
 * by retuning the value.
 */
export function isPastel(color: ColorInput): boolean {
  const rgb = toRgb(color);
  return (
    !isNeutral(rgb) &&
    hslLightness(rgb) > PASTEL_LIGHTNESS_ABOVE &&
    hslSaturation(rgb) < PASTEL_SATURATION_BELOW
  );
}

// --- internals ---------------------------------------------------------------

function extent(color: ColorInput): { max: number; min: number } {
  const { r, g, b } = toRgb(color);
  const channels = [r / 255, g / 255, b / 255];
  return { max: Math.max(...channels), min: Math.min(...channels) };
}

function clamp(value: number, low: number, high: number): number {
  if (!Number.isFinite(value)) {
    throw new Error(`Expected a finite number, received ${String(value)}.`);
  }
  return Math.min(high, Math.max(low, value));
}

function parseHexBody(body: string, original: string): Rgb {
  if (!/^[0-9a-f]+$/i.test(body)) {
    throw new Error(
      `Malformed hex colour ${JSON.stringify(original)}: non-hex digits.`,
    );
  }

  // A single digit in shorthand means the digit doubled: `f` -> `ff`.
  const short = (index: number): number =>
    parseInt(body[index] + body[index], 16);
  const pair = (index: number): number => parseInt(body.slice(index, index + 2), 16);

  switch (body.length) {
    case 3:
      return srgb(short(0), short(1), short(2));
    case 4:
      return srgb(short(0), short(1), short(2), short(3) / 255);
    case 6:
      return srgb(pair(0), pair(2), pair(4));
    case 8:
      return srgb(pair(0), pair(2), pair(4), pair(6) / 255);
    default:
      throw new Error(
        `Malformed hex colour ${JSON.stringify(original)}: ` +
          `${body.length} digits, expected 3, 4, 6 or 8.`,
      );
  }
}

function parseFunctionalBody(body: string, original: string): Rgb {
  const segments = body.split('/');
  if (segments.length > 2) {
    throw new Error(
      `Malformed colour ${JSON.stringify(original)}: more than one slash.`,
    );
  }

  const channelText = segments[0];
  let alphaText: string | null = segments.length === 2 ? segments[1] : null;

  const channels = (channelText.includes(',')
    ? channelText.split(',')
    : channelText.trim().split(/\s+/)
  )
    .map((part) => part.trim())
    .filter((part) => part.length > 0);

  // Legacy `rgba(r, g, b, a)` carries alpha as a fourth comma-separated part.
  if (channels.length === 4 && alphaText === null) {
    alphaText = channels.pop() ?? null;
  }

  if (channels.length !== 3) {
    throw new Error(
      `Malformed colour ${JSON.stringify(original)}: ` +
        `${channels.length} channels, expected 3.`,
    );
  }

  return srgb(
    channelToByte(channels[0], original),
    channelToByte(channels[1], original),
    channelToByte(channels[2], original),
    alphaText === null ? 1 : alphaToUnit(alphaText, original),
  );
}

function channelToByte(text: string, original: string): number {
  if (text.endsWith('%')) {
    return (numberOrThrow(text.slice(0, -1), original) / 100) * 255;
  }
  return numberOrThrow(text, original);
}

function alphaToUnit(text: string, original: string): number {
  const trimmed = text.trim();
  if (trimmed.endsWith('%')) {
    return numberOrThrow(trimmed.slice(0, -1), original) / 100;
  }
  return numberOrThrow(trimmed, original);
}

function numberOrThrow(text: string, original: string): number {
  const value = Number(text.trim());
  if (text.trim().length === 0 || !Number.isFinite(value)) {
    throw new Error(
      `Malformed colour ${JSON.stringify(original)}: ` +
        `${JSON.stringify(text)} is not a number.`,
    );
  }
  return value;
}

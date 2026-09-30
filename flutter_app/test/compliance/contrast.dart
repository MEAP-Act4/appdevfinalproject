/// Colour maths for the Mobile_Client compliance suite.
///
/// Two independent families of arithmetic live here, and they must not be
/// confused with one another:
///
/// 1. **WCAG contrast.** Channels are normalised to `[0, 1]` and then
///    *linearised* out of the sRGB transfer curve before the 0.2126 / 0.7152 /
///    0.0722 luminance weights are applied. [contrastRatio] returns
///    `(Llighter + 0.05) / (Ldarker + 0.05)`.
/// 2. **HSL lightness and saturation.** Computed from the *raw* sRGB channels
///    with no gamma linearisation, exactly as [kPastelRule] records it in
///    `lib/core/theme/token_registry.dart`. Standard HSL, not HSV.
///
/// The algorithm mirrors `react_app/src/__tests__/compliance/contrast.ts`
/// (task 1.5) byte for byte in behaviour, so both clients compute contrast the
/// same way. Any change here has to land there too, or Requirement 13.1
/// breaks. The one deliberate difference is the input surface: the React helper
/// parses CSS strings because `getComputedStyle` hands it `rgb()` and `rgba()`
/// text, whereas this side reads `0xAARRGGBB` ints straight off the token
/// registry. [Srgb.fromArgb] is therefore the primary entry point and
/// [Srgb.parseHex] exists for the places that genuinely hold hex text — the
/// `knownLiteralRuleHits` entries, and published WCAG reference values.
/// Malformed input throws instead of coercing to black, so an unparseable
/// value fails the suite loudly rather than quietly contributing a ratio.
///
/// The pastel, neutral and achromatic thresholds are not restated here — they
/// are read from [kPastelRule], which Requirement 9.8 makes the single
/// authority for them.
///
/// Requirements: 11.3, 9.8.
library;

import 'dart:math' as math;

import 'package:leakguard/core/theme/token_registry.dart';

/// WCAG 2.1 relative-luminance channel weights.
const ({double r, double g, double b}) kLuminanceWeights =
    (r: 0.2126, g: 0.7152, b: 0.0722);

/// Knee of the sRGB linearisation piecewise function, per WCAG 2.1.
const double kLineariseKnee = 0.03928;

/// The constant added to both luminances in the contrast-ratio formula.
const double kContrastOffset = 0.05;

/// HSL lightness a colour must exceed to be a pastel candidate.
final double kPastelLightnessAbove = kPastelRule.lightnessAbove;

/// HSL saturation a colour must fall below to be a pastel candidate.
final double kPastelSaturationBelow = kPastelRule.saturationBelow;

/// HSL saturation at or below which a colour carries no hue at all.
final double kAchromaticSaturationAtMost = kPastelRule.achromatic.saturationAtMost;

/// HSL saturation at or below which a colour reads as a grey rather than as a
/// colour, and so is carved out of the pastel rule.
final double kNeutralSaturationAtMost = kPastelRule.neutral.saturationAtMost;

/// An sRGB colour with 8-bit-scaled channels and a unit alpha.
class Srgb {
  /// Builds a colour from raw sRGB channels.
  ///
  /// Channels are `0..255` and may be fractional, so a colour can be
  /// constructed from a normalised value without a rounding step.
  Srgb.fromChannels(num r, num g, num b, {num a = 1})
      : r = _clamp(r, 0, 255),
        g = _clamp(g, 0, 255),
        b = _clamp(b, 0, 255),
        a = _clamp(a, 0, 1);

  /// Decodes a `0xAARRGGBB` integer, which is the form
  /// `lib/core/theme/token_registry.dart` records every colour in.
  factory Srgb.fromArgb(int argb) {
    return Srgb.fromChannels(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
      a: ((argb >> 24) & 0xFF) / 255,
    );
  }

  /// Parses a hex literal of 3, 4, 6 or 8 digits, with or without alpha.
  ///
  /// Throws a [FormatException] on anything else rather than guessing.
  factory Srgb.parseHex(String value) {
    final text = value.trim();
    if (!text.startsWith('#')) {
      throw FormatException(
        'Unrecognised colour value. Expected a hex literal of 3, 4, 6 or 8 '
        'digits beginning with #.',
        value,
      );
    }

    final body = text.substring(1);
    if (!_hexDigits.hasMatch(body)) {
      throw FormatException('Malformed hex colour: non-hex digits.', value);
    }

    // A single digit in shorthand means the digit doubled: `f` -> `ff`.
    int short(int index) => int.parse(body[index] * 2, radix: 16);
    int pair(int index) => int.parse(body.substring(index, index + 2), radix: 16);

    switch (body.length) {
      case 3:
        return Srgb.fromChannels(short(0), short(1), short(2));
      case 4:
        return Srgb.fromChannels(
          short(0),
          short(1),
          short(2),
          a: short(3) / 255,
        );
      case 6:
        return Srgb.fromChannels(pair(0), pair(2), pair(4));
      case 8:
        return Srgb.fromChannels(
          pair(0),
          pair(2),
          pair(4),
          a: pair(6) / 255,
        );
      default:
        throw FormatException(
          'Malformed hex colour: ${body.length} digits, expected 3, 4, 6 or 8.',
          value,
        );
    }
  }

  /// Red channel, `0..255`. May be fractional when built from a normalised
  /// value.
  final double r;

  /// Green channel, `0..255`.
  final double g;

  /// Blue channel, `0..255`.
  final double b;

  /// Alpha, `0..1`.
  ///
  /// Parsed and carried so an `0xAARRGGBB` value round-trips, but deliberately
  /// ignored by every function below: WCAG contrast is defined over
  /// composited, opaque colours, and silently folding alpha into the maths
  /// would hide a real problem rather than surface it.
  final double a;

  @override
  bool operator ==(Object other) {
    return other is Srgb &&
        other.r == r &&
        other.g == g &&
        other.b == b &&
        other.a == a;
  }

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'Srgb($r, $g, $b, a: $a)';
}

/// Builds a colour from raw sRGB channels.
///
/// Named `srgb` rather than `rgb` for parity with the React helper, whose call
/// sites must never produce the `rgb(` byte sequence its literal-colour
/// scanner looks for.
Srgb srgb(num r, num g, num b, [num a = 1]) =>
    Srgb.fromChannels(r, g, b, a: a);

/// Shorthand for [Srgb.fromArgb] — the entry point the token registry feeds.
Srgb argbColour(int argb) => Srgb.fromArgb(argb);

/// Shorthand for [Srgb.parseHex].
Srgb hexColour(String value) => Srgb.parseHex(value);

/// Linearises one sRGB channel expressed in `[0, 1]`.
///
/// `c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)`
double lineariseChannel(num channel) {
  final c = _clamp(channel, 0, 1);
  return c <= kLineariseKnee
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG 2.1 relative luminance, in `[0, 1]`. Alpha is ignored.
double relativeLuminance(Srgb colour) {
  return kLuminanceWeights.r * lineariseChannel(colour.r / 255) +
      kLuminanceWeights.g * lineariseChannel(colour.g / 255) +
      kLuminanceWeights.b * lineariseChannel(colour.b / 255);
}

/// WCAG 2.1 contrast ratio, in `[1, 21]`.
///
/// Symmetric by construction: the lighter luminance is always the numerator,
/// so argument order carries no meaning.
double contrastRatio(Srgb a, Srgb b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + kContrastOffset) / (darker + kContrastOffset);
}

/// Rounds a ratio for pinning in an assertion or a failure message.
///
/// Ratios are quoted to two decimal places throughout design.md (10.84:1,
/// 3.74:1, 5.79:1), so this exists to make those comparisons exact rather than
/// approximate.
double roundRatio(double ratio, {int decimals = 2}) {
  final factor = math.pow(10, decimals).toDouble();
  return (ratio * factor).round() / factor;
}

/// HSL lightness, in `[0, 1]`: `(max + min) / 2` over normalised channels.
double hslLightness(Srgb colour) {
  final extent = _extent(colour);
  return (extent.max + extent.min) / 2;
}

/// HSL saturation, in `[0, 1]`.
///
/// `max == min ? 0 : (max - min) / (lightness > 0.5 ? (2 - max - min) : (max + min))`
double hslSaturation(Srgb colour) {
  final extent = _extent(colour);
  final max = extent.max;
  final min = extent.min;
  if (max == min) {
    return 0;
  }
  final lightness = (max + min) / 2;
  return (max - min) / (lightness > 0.5 ? 2 - max - min : max + min);
}

/// True when a colour carries no hue at all, i.e. its three channels are equal.
///
/// Kept as its own predicate because it is a distinct, stricter fact than
/// [isNeutral]: this is arithmetic on the channels, with no threshold anyone
/// chose. Nothing in the pastel rule reads it directly any more — [isNeutral]
/// subsumes it — but "#FFFFFF has no hue" is worth being able to assert on its
/// own.
bool isAchromatic(Srgb colour) =>
    hslSaturation(colour) <= kAchromaticSaturationAtMost;

/// True when a colour reads as a grey rather than as a colour.
///
/// The carve-out [NeutralRuleSpec] records: saturation at or below 0.2 is a
/// faint cast, not a hue, so such a colour cannot be a pastel however light it
/// is. Strictly wider than [isAchromatic], which it contains — a colour with
/// saturation 0 is neutral too.
bool isNeutral(Srgb colour) =>
    hslSaturation(colour) <= kNeutralSaturationAtMost;

/// The pastel predicate exactly as [PastelRuleSpec.predicate] defines it:
/// `!isNeutral(c) && hslLightness(c) > 0.8 && hslSaturation(c) < 0.5`.
///
/// The two thresholds are the registry's and must not be loosened here. The
/// near-neutral carve-out is the only thing that changed: phase 1 recorded the
/// predicate flagging four light-palette values, three of which are
/// near-neutral off-whites that no reading of WattVision §6 is about. The
/// fourth was a genuine hit and the colour changed instead.
bool isPastel(Srgb colour) {
  return !isNeutral(colour) &&
      hslLightness(colour) > kPastelLightnessAbove &&
      hslSaturation(colour) < kPastelSaturationBelow;
}

// --- internals ---------------------------------------------------------------

final RegExp _hexDigits = RegExp(r'^[0-9a-fA-F]+$');

({double max, double min}) _extent(Srgb colour) {
  final r = colour.r / 255;
  final g = colour.g / 255;
  final b = colour.b / 255;
  return (
    max: math.max(r, math.max(g, b)),
    min: math.min(r, math.min(g, b)),
  );
}

double _clamp(num value, num low, num high) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'Expected a finite number');
  }
  return math.min(high.toDouble(), math.max(low.toDouble(), value.toDouble()));
}

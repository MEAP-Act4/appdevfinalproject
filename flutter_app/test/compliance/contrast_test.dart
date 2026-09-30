/// Reference tests for the colour maths in `contrast.dart`.
///
/// Thirty property tests are going to lean on these functions, so the maths
/// itself is pinned here against values that do not come from this codebase:
/// the 21:1 white-on-black extreme, the 1:1 identity, WebAIM's published
/// boundary grey, pure blue on white, and the 10.84:1 pair Requirement 11.3
/// names. If the linearisation were wrong, the ratios would still be internally
/// consistent — only the published figures catch it.
///
/// These are the same figures `react_app/src/__tests__/compliance/
/// contrast.test.ts` pins, deliberately, so a divergence between the two
/// clients is caught here rather than at the cross-client parity task (17.2).
///
/// Palette values are read from `lib/core/theme/token_registry.dart`, never
/// written as literals. The handful of literals the hex parser and the
/// published references genuinely need are declared in one block below; the
/// task 1.8 literal-colour scanner walks `lib/**/*.dart` only, so unlike the
/// React side this suite needs no separate quarantine module. Nothing here is
/// a design token.
///
/// `../support/props.dart` is deliberately not imported: these are plain
/// reference cases, and the property tests that need the harness belong to
/// later tasks.
///
/// Requirements: 11.3, 9.8.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/token_registry.dart';

import 'contrast.dart';

// --- parser inputs and published WCAG reference values -----------------------

/// Pure white. Achromatic, luminance 1.0, the lighter half of the 21:1 pair.
const String kWhite = '#ffffff';

/// Pure black. Achromatic, luminance 0.0, the darker half of the 21:1 pair.
const String kBlack = '#000000';

/// WebAIM's published boundary grey: 4.54:1 against white, the darkest grey
/// that still clears the 4.5:1 body-text threshold. The spot-check that proves
/// the linearisation is right rather than merely self-consistent.
const String kMidGrey = '#767676';

/// Published reference: pure blue on white is 8.59:1.
const String kPureBlue = '#0000ff';

/// Shorthand forms of [kWhite], for the hex parser.
const String kWhiteShorthand = '#fff';
const String kWhiteShorthandHalfAlpha = '#fff8';

/// Eight-digit form of [kWhite] at 50% alpha, for the hex parser.
const String kWhiteWithAlpha = '#ffffff80';

/// A grey carrying a cast too faint to read as a hue: HSL lightness 0.943,
/// saturation 0.103. Not achromatic, and not a pastel either.
const String kFaintlyTintedGrey = '#eff0f2';

/// The light-appearance OK box fill, as task 3.1 set it.
///
/// Written out here so the assertion compares a stated value against the
/// registry rather than the registry against itself. The Web_Client holds the
/// same value for `--normal-fill` — Requirements 13.1 and 13.2.
const String kLightNormalBoxFill = '#D8F5DF';

/// The four values phase 1 recorded as pastel hits, with the HSL saturation
/// each one actually carries now.
///
/// Three fall inside the near-neutral carve-out; the fourth is the changed
/// colour. Pinning the saturations is what stops a later value edit from
/// drifting one of them across the 0.2 floor or back under 0.5 unnoticed.
const Map<String, double> kResolvedPastelHits = <String, double>{
  'lightBackground': 0.1579,
  'lightSurfaceRaised': 0.1515,
  'lightBorder': 0.1515,
  'lightNormalBoxFill': 0.5918,
};

/// The three of those four that the carve-out clears, as opposed to the one
/// whose value changed.
const List<String> kCarvedOutByNeutrality = <String>[
  'lightBackground',
  'lightSurfaceRaised',
  'lightBorder',
];

/// Inputs the parser must reject rather than silently coerce.
const List<String> kMalformed = <String>[
  'not-a-colour',
  '',
  '#',
  '#12345',
  '#gggggg',
  '#1234567',
  'hsl(190 100% 50%)',
  'ffffff',
  '#ff ff ff',
];

// --- registry lookups --------------------------------------------------------

/// The `0xAARRGGBB` value of a WattVision token, by registry name.
Srgb _token(String name) {
  final spec = kWattVisionTokens.firstWhere(
    (TokenSpec token) => token.name == name,
    orElse: () => throw StateError('no WattVision token named $name'),
  );
  final argb = spec.argb;
  if (argb == null) {
    throw StateError('$name is not a colour token');
  }
  return argbColour(argb);
}

/// The `0xAARRGGBB` value of a Token_Extension, by registry name.
Srgb _extension(String name) {
  final spec = kTokenExtensions.firstWhere(
    (TokenExtensionSpec extension) => extension.name == name,
    orElse: () => throw StateError('no Token_Extension named $name'),
  );
  final argb = spec.argb;
  if (argb == null) {
    throw StateError('$name is not a colour extension');
  }
  return argbColour(argb);
}

void main() {
  /// The §2 primary accent, as the registry records it.
  final Srgb accent = _token('accent');

  /// The §2 card surface, as the registry records it.
  final Srgb cardSurface = _token('surface');

  /// The dark-appearance OK box fill: a dark, low-lightness green.
  final Srgb darkNormalFill = _extension('normalBoxFill');

  final Srgb white = hexColour(kWhite);
  final Srgb black = hexColour(kBlack);
  final Srgb midGrey = hexColour(kMidGrey);
  final Srgb pureBlue = hexColour(kPureBlue);

  group('colour construction', () {
    test('decodes the 0xAARRGGBB form the token registry records', () {
      expect(argbColour(0xFF00E5FF), equals(srgb(0, 229, 255)));
      expect(argbColour(0xFF121212), equals(srgb(18, 18, 18)));
      expect(argbColour(0x8032D74B).a, closeTo(128 / 255, 1e-12));
    });

    test('reads the six-digit hex form used throughout the palette', () {
      expect(hexColour(kWhite), equals(srgb(255, 255, 255)));
      expect(hexColour(kBlack), equals(srgb(0, 0, 0)));
      expect(hexColour(kMidGrey), equals(srgb(118, 118, 118)));
    });

    test('agrees with the argb form for the same colour', () {
      expect(hexColour('#00E5FF'), equals(argbColour(0xFF00E5FF)));
    });

    test('expands the three-digit shorthand by doubling each digit', () {
      expect(hexColour(kWhiteShorthand), equals(hexColour(kWhite)));
    });

    test('reads alpha from the four- and eight-digit hex forms', () {
      expect(hexColour(kWhiteWithAlpha).a, closeTo(0.5, 0.01));
      expect(hexColour(kWhiteShorthandHalfAlpha).a, closeTo(0.533, 0.001));
    });

    test('throws rather than guessing at an unparseable value', () {
      for (final bad in kMalformed) {
        expect(
          () => hexColour(bad),
          throwsFormatException,
          reason: 'expected "$bad" to throw',
        );
      }
    });
  });

  group('sRGB linearisation', () {
    test('fixes both endpoints', () {
      expect(lineariseChannel(0), 0);
      expect(lineariseChannel(1), closeTo(1, 1e-12));
    });

    test('uses the linear segment at and below the knee', () {
      expect(lineariseChannel(0.03928), closeTo(0.03928 / 12.92, 1e-12));
    });

    test('is monotonically increasing across the knee', () {
      var previous = -1.0;
      for (var step = 0; step <= 255; step++) {
        final value = lineariseChannel(step / 255);
        expect(value, greaterThan(previous));
        previous = value;
      }
    });

    test('weights the green channel most heavily', () {
      expect(kLuminanceWeights.g, greaterThan(kLuminanceWeights.r));
      expect(kLuminanceWeights.r, greaterThan(kLuminanceWeights.b));
      final sum =
          kLuminanceWeights.r + kLuminanceWeights.g + kLuminanceWeights.b;
      expect(sum, closeTo(1, 1e-12));
    });
  });

  group('relativeLuminance', () {
    test('spans the full unit interval between black and white', () {
      expect(relativeLuminance(black), closeTo(0, 1e-12));
      expect(relativeLuminance(white), closeTo(1, 1e-12));
    });

    test('reproduces the luminances behind the Requirement 11.3 pair', () {
      // design.md's research note quotes these as "L(accent) ~= 0.6327" and
      // "L(card) ~= 0.0130". The card value is exact to four places; the accent
      // value is a rounding slip in the prose — the WCAG computation gives
      // 0.632586, not 0.6327. The difference is 1.1e-4 of luminance and moves
      // the ratio by 0.002, so the 10.84:1 figure design.md pins is unaffected
      // and stands. The React suite asserts the same 0.6326 for the same
      // reason; recorded here rather than silently accommodated.
      expect(relativeLuminance(accent), closeTo(0.6326, 1e-4));
      expect(relativeLuminance(cardSurface), closeTo(0.013, 1e-4));
    });

    test('ignores alpha, because contrast is defined over composited colours',
        () {
      expect(
        relativeLuminance(hexColour(kWhiteWithAlpha)),
        closeTo(relativeLuminance(white), 1e-12),
      );
    });
  });

  group('contrastRatio', () {
    test('gives exactly 21:1 for white on black', () {
      expect(contrastRatio(white, black), closeTo(21, 1e-10));
    });

    test('gives exactly 1:1 for a colour against itself', () {
      for (final colour in <Srgb>[white, black, accent, cardSurface, midGrey]) {
        expect(contrastRatio(colour, colour), closeTo(1, 1e-12));
      }
    });

    test('is symmetric in its arguments', () {
      final pairs = <(Srgb, Srgb)>[
        (white, black),
        (accent, cardSurface),
        (midGrey, white),
        (pureBlue, white),
        (darkNormalFill, accent),
      ];
      for (final (a, b) in pairs) {
        expect(contrastRatio(a, b), closeTo(contrastRatio(b, a), 1e-12));
      }
    });

    test('never leaves the [1, 21] range', () {
      final palette = <Srgb>[
        white,
        black,
        accent,
        cardSurface,
        midGrey,
        pureBlue,
      ];
      for (final a in palette) {
        for (final b in palette) {
          final ratio = contrastRatio(a, b);
          expect(ratio, greaterThanOrEqualTo(1));
          expect(ratio, lessThanOrEqualTo(21));
        }
      }
    });

    test('matches the published figure for the WebAIM boundary grey on white',
        () {
      expect(roundRatio(contrastRatio(midGrey, white)), 4.54);
    });

    test('matches the published figure for pure blue on white', () {
      expect(roundRatio(contrastRatio(pureBlue, white)), 8.59);
    });

    test('pins the Requirement 11.3 pair at 10.84:1 and clears 4.5:1', () {
      final ratio = contrastRatio(accent, cardSurface);
      expect(roundRatio(ratio), 10.84);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('offsets both luminances by 0.05, so the floor is 1 and not infinity',
        () {
      expect(kContrastOffset, 0.05);
      expect(contrastRatio(black, black), closeTo(1, 1e-12));
    });
  });

  group('HSL lightness and saturation', () {
    test('reads lightness from the raw channels, not the linearised ones', () {
      // Mid grey sits at 118/255 of the way up the raw scale but only ~0.18 of
      // the way up the linearised one. Using the wrong one here would be
      // invisible in a contrast ratio and fatal to the pastel rule.
      expect(hslLightness(midGrey), closeTo(118 / 255, 1e-12));
      expect(relativeLuminance(midGrey), lessThan(0.25));
    });

    test('puts white at lightness 1 and black at lightness 0', () {
      expect(hslLightness(white), 1);
      expect(hslLightness(black), 0);
    });

    test('reports zero saturation when the three channels are equal', () {
      for (final grey in <Srgb>[white, black, midGrey]) {
        expect(hslSaturation(grey), 0);
        expect(isAchromatic(grey), isTrue);
      }
    });

    test('reports full saturation for a pure hue at mid lightness', () {
      expect(hslSaturation(pureBlue), closeTo(1, 1e-12));
      expect(hslLightness(pureBlue), closeTo(0.5, 1e-12));
      expect(isAchromatic(pureBlue), isFalse);
    });

    test('switches denominators either side of lightness 0.5', () {
      // Two colours with the same chroma spread (0.2), mirrored about mid
      // lightness: one at L = 0.8, one at L = 0.2. HSL saturation is symmetric
      // under that reflection and both come out at 0.5, which only holds if
      // the (2 - max - min) branch is wired up correctly. Using the
      // (max + min) denominator for both would give 0.25 and 0.5 instead.
      final light = srgb(0.9 * 255, 0.7 * 255, 0.7 * 255);
      final dark = srgb(0.3 * 255, 0.1 * 255, 0.1 * 255);
      expect(hslLightness(light), closeTo(0.8, 1e-12));
      expect(hslLightness(dark), closeTo(0.2, 1e-12));
      expect(hslSaturation(light), closeTo(0.5, 1e-12));
      expect(hslSaturation(dark), closeTo(0.5, 1e-12));
    });
  });

  group('the pastel rule', () {
    test('takes its thresholds from the registry rather than restating them',
        () {
      expect(kPastelLightnessAbove, kPastelRule.lightnessAbove);
      expect(kPastelSaturationBelow, kPastelRule.saturationBelow);
      expect(
        kAchromaticSaturationAtMost,
        kPastelRule.achromatic.saturationAtMost,
      );
      expect(kNeutralSaturationAtMost, kPastelRule.neutral.saturationAtMost);
    });

    test('keeps the two WattVision-derived thresholds where they were', () {
      // The neutral carve-out narrows what counts as a colour at all. It is
      // not licence to loosen either of the thresholds the rule is built on,
      // so both are pinned at their recorded values.
      expect(kPastelLightnessAbove, 0.8);
      expect(kPastelSaturationBelow, 0.5);
    });

    test('excludes achromatic colours, so white is not a pastel', () {
      expect(isPastel(white), isFalse);
      expect(isPastel(black), isFalse);
      expect(isPastel(midGrey), isFalse);
    });

    test('flags a light, weakly saturated colour', () {
      final pale = srgb(245, 230, 235);
      expect(hslLightness(pale), greaterThan(kPastelLightnessAbove));
      expect(hslSaturation(pale), lessThan(kPastelSaturationBelow));
      expect(isPastel(pale), isTrue);
    });

    test('clears a light colour that is strongly saturated', () {
      final vivid = srgb(255, 200, 200);
      expect(hslLightness(vivid), greaterThan(kPastelLightnessAbove));
      expect(
        hslSaturation(vivid),
        greaterThanOrEqualTo(kPastelSaturationBelow),
      );
      expect(isPastel(vivid), isFalse);
    });

    test('clears a weakly saturated colour that is not light', () {
      final muted = srgb(120, 130, 125);
      expect(hslLightness(muted), lessThan(kPastelLightnessAbove));
      expect(hslSaturation(muted), lessThan(kPastelSaturationBelow));
      expect(isPastel(muted), isFalse);
    });

    test('clears the dark-appearance palette values it is handed', () {
      final values = <String, Srgb>{
        'accent': accent,
        'surface': cardSurface,
        'normalBoxFill': darkNormalFill,
      };
      values.forEach((String name, Srgb colour) {
        expect(
          isPastel(colour),
          isFalse,
          reason: '$name should not read as pastel',
        );
      });
    });
  });

  group('the near-neutral carve-out', () {
    // The distinction this group exists to protect: achromatic is arithmetic,
    // neutral is a threshold someone chose. Collapsing the two, in either
    // direction, is the mistake that makes the rule unverifiable again.
    test('contains the achromatic set rather than replacing it', () {
      expect(
        kNeutralSaturationAtMost,
        greaterThan(kAchromaticSaturationAtMost),
        reason: 'a carve-out no wider than the achromatic case would carve '
            'nothing out',
      );
      for (final grey in <Srgb>[white, black, midGrey]) {
        expect(isAchromatic(grey), isTrue);
        expect(isNeutral(grey), isTrue, reason: 'achromatic implies neutral');
      }
    });

    test('is narrower than the pastel saturation threshold', () {
      // If the carve-out reached 0.5 it would swallow the rule whole: every
      // colour below the saturation threshold would be exempt from it.
      expect(kNeutralSaturationAtMost, lessThan(kPastelSaturationBelow));
    });

    test('admits a faintly tinted grey that is not achromatic', () {
      final faint = hexColour(kFaintlyTintedGrey);
      expect(hslSaturation(faint), lessThanOrEqualTo(kNeutralSaturationAtMost));
      expect(isAchromatic(faint), isFalse, reason: 'it does carry a cast');
      expect(isNeutral(faint), isTrue);
      expect(isPastel(faint), isFalse, reason: 'a grey with a cast is a grey');
    });

    test('leaves a colour just above the floor to the rule itself', () {
      // Saturation 0.25 at lightness 0.9: above the carve-out, below the
      // pastel threshold, and light. Exactly the shape §6 is about, so the
      // carve-out must not reach it.
      final chalky = srgb(0.925 * 255, 0.875 * 255, 0.875 * 255);
      expect(hslLightness(chalky), closeTo(0.9, 1e-3));
      expect(hslSaturation(chalky), closeTo(0.25, 1e-3));
      expect(isNeutral(chalky), isFalse);
      expect(isPastel(chalky), isTrue);
    });

    test('records who chose the threshold and what it replaced', () {
      // Requirement 9.8 makes the definition explicit; an unattributed
      // threshold is an undefined one wearing a number.
      expect(kPastelRule.neutral.decidedBy.trim(), isNotEmpty);
      expect(kPastelRule.neutral.reason.trim(), isNotEmpty);
      expect(kPastelRule.neutral.supersedes, contains('lightNormalBoxFill'));
      expect(kPastelRule.predicate, contains('isNeutral'));
      expect(kPastelRule.definition, contains('0.2'));
      expect(kPastelRule.thresholdProvenance, contains('0.2'));
    });
  });

  group('the light palette under the sharpened rule', () {
    /// Light-appearance colour values by registry name.
    final lightPalette = <String, int>{
      for (final spec in kLightAppearanceExtensions)
        if (spec.argb != null) spec.name: spec.argb!,
    };

    test('the record of known hits is empty, and says why', () {
      // Phase 1 recorded four. Task 3.1 resolved all four, so the list is
      // empty — kept rather than deleted, because "nothing is flagged" is a
      // claim worth being able to read.
      expect(kPastelRule.knownLiteralRuleHits.values, isEmpty);
      expect(
        kPastelRule.knownLiteralRuleHits.appearance,
        TokenAppearance.light,
      );
      for (final name in kResolvedPastelHits.keys) {
        expect(
          kPastelRule.knownLiteralRuleHits.note,
          contains(name),
          reason: '$name was a recorded hit, so its resolution should be '
              'readable from the registry',
        );
      }
    });

    test('the three near-neutral values are cleared by the carve-out', () {
      // Cleared *by the carve-out*, not by the thresholds: each is still light
      // and still weakly saturated, so if the carve-out were removed each
      // would be flagged again. That is the whole content of the decision.
      for (final name in kCarvedOutByNeutrality) {
        final colour = argbColour(lightPalette[name]!);
        expect(
          hslLightness(colour),
          greaterThan(kPastelLightnessAbove),
          reason: '$name lightness',
        );
        expect(
          hslSaturation(colour),
          lessThan(kPastelSaturationBelow),
          reason: '$name saturation',
        );
        expect(isAchromatic(colour), isFalse, reason: '$name carries a cast');
        expect(isNeutral(colour), isTrue, reason: '$name neutrality');
        expect(isPastel(colour), isFalse, reason: '$name pastel');
        expect(
          hslSaturation(colour),
          closeTo(kResolvedPastelHits[name]!, 5e-4),
          reason: '$name saturation is pinned, so a value edit that moves it '
              'across the carve-out cannot pass quietly',
        );
      }
    });

    test('the OK box fill is cleared by its saturation, not by the carve-out',
        () {
      // The fourth recorded hit sat at 0.429: above the carve-out and below the
      // threshold, so it was a real pastel and the colour changed rather than
      // the rule. #D8F5DF is the same green carrying enough chroma to clear
      // 0.5 outright.
      final fill = argbColour(lightPalette['lightNormalBoxFill']!);
      expect(fill, equals(hexColour(kLightNormalBoxFill)));
      expect(hslLightness(fill), greaterThan(kPastelLightnessAbove));
      expect(
        hslSaturation(fill),
        greaterThanOrEqualTo(kPastelSaturationBelow),
        reason: 'it has to clear the rule on saturation alone',
      );
      expect(
        hslSaturation(fill),
        closeTo(kResolvedPastelHits['lightNormalBoxFill']!, 5e-4),
      );
      expect(isNeutral(fill), isFalse);
      expect(isPastel(fill), isFalse);

      // And it now sits in the same family as the two siblings it was the odd
      // one out beside.
      for (final sibling in <String>[
        'lightAlertBoxFill',
        'lightWatchBoxFill',
      ]) {
        expect(
          hslSaturation(argbColour(lightPalette[sibling]!)),
          greaterThanOrEqualTo(kPastelSaturationBelow),
          reason: '$sibling was already strongly saturated',
        );
      }
    });

    test('no light-appearance colour is flagged at all', () {
      // The example form of the emptiness asserted above. Property 20 over
      // every appearance is task 3.11; this is the light palette, which is
      // where every recorded hit lived.
      final flagged = <String>[
        for (final entry in lightPalette.entries)
          if (isPastel(argbColour(entry.value))) entry.key,
      ];
      expect(
        flagged,
        isEmpty,
        reason: 'knownLiteralRuleHits is empty, so the palette has to be too',
      );
    });

    test('the primary and secondary text on the OK fill still clear 4.5:1', () {
      // Requirements 9.5 and 11.1. The fill got slightly darker, so the text
      // that sits on it is re-measured rather than assumed.
      final fill = argbColour(lightPalette['lightNormalBoxFill']!);
      final primary = argbColour(lightPalette['lightTextPrimary']!);
      final secondary = argbColour(lightPalette['lightTextSecondary']!);

      expect(roundRatio(contrastRatio(primary, fill)), 16.1);
      expect(roundRatio(contrastRatio(secondary, fill)), 5.51);
      expect(contrastRatio(primary, fill), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(secondary, fill), greaterThanOrEqualTo(4.5));
    });
  });

  group('the accent-as-text split', () {
    // Requirement 11.4, and the reason accentText exists. Pinned here because
    // the figures are the argument: 3.74:1 is why the split is needed and
    // 5.79:1 is why #00707F is the answer. Property 17 over every appearance is
    // task 3.10.
    Srgb ext(String name) => _extension(name);

    test('the dark text accent is the graphical accent, unchanged', () {
      expect(ext('accentText'), equals(accent));
      expect(roundRatio(contrastRatio(ext('accentText'), cardSurface)), 10.84);
      expect(
        contrastRatio(ext('accentText'), cardSurface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('the light graphical accent is the 3.74:1 failure it is recorded as',
        () {
      final lightSurface = ext('lightSurface');
      expect(roundRatio(contrastRatio(ext('lightAccent'), lightSurface)), 3.74);
      expect(contrastRatio(ext('lightAccent'), lightSurface), lessThan(4.5));
    });

    test('the light text accent clears 4.5:1 on all three light surfaces', () {
      final textAccent = ext('lightAccentText');
      final surfaces = <String, double>{
        'lightSurface': 5.79,
        'lightBackground': 5.31,
        'lightSurfaceRaised': 4.99,
      };
      surfaces.forEach((String name, double expected) {
        final ratio = contrastRatio(textAccent, ext(name));
        expect(roundRatio(ratio), expected, reason: name);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: name);
      });
    });
  });

  group('High_Contrast_Dark raises contrast without leaving the dark family',
      () {
    // Requirement 9.2. The full property over every token is task 3.12
    // (Property 26); these are the two overrides and the three surfaces they
    // are measured against, pinned so the appearance cannot be defined as a
    // no-op.
    test('secondary text and the hairline both strictly improve', () {
      for (final surface in <String>['surface', 'background']) {
        final behind = _token(surface);
        final base = contrastRatio(_token('textSecondary'), behind);
        final raised = contrastRatio(_extension('hcTextSecondary'), behind);
        expect(raised, greaterThan(base), reason: 'secondary text on $surface');

        final baseBorder = contrastRatio(_token('border'), behind);
        final raisedBorder = contrastRatio(_extension('hcBorder'), behind);
        expect(raisedBorder, greaterThan(baseBorder), reason: 'border on '
            '$surface');
      }
    });

    test('pins the measured figures on the card surface', () {
      expect(
        roundRatio(contrastRatio(_token('textSecondary'), cardSurface)),
        5.81,
      );
      expect(
        roundRatio(contrastRatio(_extension('hcTextSecondary'), cardSurface)),
        9.9,
      );
      expect(roundRatio(contrastRatio(_token('border'), cardSurface)), 1.2);
      expect(
        roundRatio(contrastRatio(_extension('hcBorder'), cardSurface)),
        1.83,
      );
    });

    test('and neither override is a pastel', () {
      for (final name in <String>['hcTextSecondary', 'hcBorder']) {
        expect(isPastel(_extension(name)), isFalse, reason: name);
      }
    });
  });
}

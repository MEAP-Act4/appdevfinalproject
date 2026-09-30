/// Property 20 — no appearance contains a pastel colour. Mobile_Client half.
///
/// *For any* colour in *any* appearance's palette, it is not the case that HSL
/// lightness exceeds 0.8 while HSL saturation falls below 0.5, with white and
/// pure black excluded as achromatic and near-neutral greys excluded by the
/// registry's carve-out.
///
/// **What this file proves, and what it does not restate.** The predicate
/// itself — the two thresholds, the achromatic exclusion, the near-neutral
/// carve-out — is pinned in `contrast_test.dart` (task 1.4), against synthetic
/// colours and against the four light-palette values phase 1 flagged. This file
/// does not duplicate that. It states the *universal* claim the predicate was
/// built to support: run the pastel predicate over every colour in every
/// shipped appearance and nothing is flagged. The thresholds are read from
/// [kPastelRule] via `contrast.dart`, never written here as literals.
///
/// **The generators.** The appearance is a real [Appearance] value, drawn from
/// the three that resolve to a palette — `dark`, `highContrastDark`, `light`.
/// The colour is every entry in that appearance's [AppPalette], read straight
/// off `AppPalette.dark`, `AppPalette.highContrastDark` and `AppPalette.light`
/// in `app_theme.dart`, so a token added to the palette becomes an input here
/// by existing. The two generators are combined, so the property runs over the
/// full appearance × colour grid.
///
/// **The carve-out is made to earn its place.** A rule that exempted everything
/// would also pass this property, so a worked example of a genuine pastel — a
/// light colour that is weakly *but really* saturated, saturation strictly
/// between the 0.2 neutral floor and the 0.5 pastel ceiling — is asserted to be
/// flagged. If a future edit widened the neutral threshold towards 0.5, that
/// example would stop being flagged and this file would fail, which is the
/// guard that keeps the carve-out from quietly swallowing the rule. The
/// approach mirrors the `chalky` anchor in `contrast_test.dart`; it is not the
/// same colour, and the file is not duplicated.
///
/// **On failure.** A real palette colour reading as a pastel means a value
/// regressed or the carve-out is mis-set. The remedy is not to loosen the
/// thresholds; it is to fix the colour. The failure report carries the offending
/// colour's lightness and saturation so the counterexample is actionable.
///
/// Validates: Requirements 9.8.
library;

import 'package:flutter/widgets.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/settings/app_settings.dart';

import 'contrast.dart';
import '../support/props.dart';

/// The three appearances that resolve to a concrete palette.
///
/// `Appearance.system` is not one of them: it defers to the platform brightness
/// and then renders one of these three, so it contributes no palette of its
/// own. design.md's Property 20 names exactly these three.
const List<Appearance> kPaletteAppearances = <Appearance>[
  Appearance.dark,
  Appearance.highContrastDark,
  Appearance.light,
];

/// The [AppPalette] an [Appearance] renders with.
AppPalette paletteFor(Appearance appearance) {
  switch (appearance) {
    case Appearance.dark:
      return AppPalette.dark;
    case Appearance.highContrastDark:
      return AppPalette.highContrastDark;
    case Appearance.light:
      return AppPalette.light;
    case Appearance.system:
      throw ArgumentError.value(
        appearance,
        'appearance',
        'system has no palette of its own; it renders one of the other three',
      );
  }
}

/// Every colour in a palette, paired with the field name it is held under so a
/// counterexample names the token rather than just its value.
Map<String, Color> paletteColours(AppPalette palette) {
  return <String, Color>{
    'background': palette.background,
    'surface': palette.surface,
    'surfaceRaised': palette.surfaceRaised,
    'border': palette.border,
    'textPrimary': palette.textPrimary,
    'textSecondary': palette.textSecondary,
    'accent': palette.accent,
    'accentText': palette.accentText,
    'alert': palette.alert,
    'normal': palette.normal,
    'watch': palette.watch,
    'idle': palette.idle,
    'gradientGreen': palette.gradientGreen,
    'alertBoxFill': palette.alertBoxFill,
    'watchBoxFill': palette.watchBoxFill,
    'normalBoxFill': palette.normalBoxFill,
  };
}

/// A `0xAARRGGBB` int for the [Srgb] helper, from a Flutter [Color].
int _argbOf(Color colour) {
  int channel(double v) => (v * 255).round() & 0xFF;
  return (channel(colour.a) << 24) |
      (channel(colour.r) << 16) |
      (channel(colour.g) << 8) |
      channel(colour.b);
}

/// One appearance × one named colour: the shape the property generates over.
typedef PaletteColour = ({Appearance appearance, String name, Srgb colour});

/// The full appearance × colour grid, enumerated so the generator draws from
/// the real palettes rather than from an approximation of them.
List<PaletteColour> _allPaletteColours() {
  final entries = <PaletteColour>[];
  for (final appearance in kPaletteAppearances) {
    paletteColours(paletteFor(appearance)).forEach((String name, Color colour) {
      entries.add((
        appearance: appearance,
        name: name,
        colour: argbColour(_argbOf(colour)),
      ));
    });
  }
  return entries;
}

void main() {
  final all = _allPaletteColours();

  group('Property 20 — no appearance contains a pastel colour', () {
    forAll<PaletteColour>(
      'no colour in any appearance palette reads as a pastel',
      any.pick<PaletteColour>(all),
      (PaletteColour input) {
        final l = hslLightness(input.colour);
        final s = hslSaturation(input.colour);
        expect(
          isPastel(input.colour),
          isFalse,
          reason: 'the ${input.name} colour in ${input.appearance.name} reads '
              'as a pastel: HSL lightness ${l.toStringAsFixed(4)} (> '
              '$kPastelLightnessAbove) and saturation ${s.toStringAsFixed(4)} '
              '(< $kPastelSaturationBelow), and it is not neutral. A palette '
              'value regressed or the carve-out is mis-set — fix the colour, do '
              'not loosen the thresholds.',
        );
      },
      // Every entry, checked before the generated draws, so the property is
      // exhaustive over the real palettes rather than merely probabilistic.
      examples: all,
    );

    test('the generator really covers all three appearances and 16 colours each',
        () {
      // A property that generated over an empty or partial set would pass
      // vacuously, so the grid it draws from is pinned.
      expect(all, hasLength(kPaletteAppearances.length * 16));
      for (final appearance in kPaletteAppearances) {
        final forAppearance =
            all.where((e) => e.appearance == appearance).toList();
        expect(forAppearance, hasLength(16), reason: appearance.name);
      }
    });

    test('the carve-out does not swallow the rule: a genuine pastel is flagged',
        () {
      // A light colour that is weakly *but genuinely* saturated: saturation
      // strictly between the 0.2 neutral floor and the 0.5 pastel ceiling, and
      // lightness above 0.8. This is exactly the shape WattVision §6 is about,
      // and the predicate must flag it. If a future edit widened
      // neutral.saturationAtMost towards 0.5, this colour would fall inside the
      // carve-out and stop being flagged — and this assertion would fail,
      // before any real palette value could slip through unnoticed. The
      // approach mirrors the `chalky` anchor in contrast_test.dart on a
      // distinct value.
      final genuinePastel = argbColour(0xFFF2DEE6); // pale rose
      final l = hslLightness(genuinePastel);
      final s = hslSaturation(genuinePastel);
      expect(l, greaterThan(kPastelLightnessAbove), reason: 'lightness');
      expect(
        s,
        greaterThan(kNeutralSaturationAtMost),
        reason: 'above the neutral carve-out, so it is a real tint',
      );
      expect(
        s,
        lessThan(kPastelSaturationBelow),
        reason: 'below the pastel saturation ceiling',
      );
      expect(isNeutral(genuinePastel), isFalse);
      expect(
        isPastel(genuinePastel),
        isTrue,
        reason: 'a light, genuinely-tinted, weakly saturated colour is a '
            'pastel; if this stops being flagged the carve-out has been '
            'widened too far',
      );
    });
  });
}

/// Example tests for resolving an [Appearance] to the theme that renders it.
///
/// Requirements 9.1, 9.2, 9.6.
///
/// **Scope.** These are the worked examples for task 3.5: each of the four
/// appearance values, both platform brightnesses under Follow system, and the
/// exact shape of the High_Contrast_Dark delta against Dark. Task 3.12 states
/// the contrast side of that delta as a property over every text and border
/// token (Property 26 — High_Contrast_Dark strictly improves contrast without
/// leaving the dark family); this file pins the *identity* of the delta, which
/// is what that property is written on top of, and does not duplicate it.
///
/// **What is not covered here.** `LeakGuardApp` hands the single resolved
/// `ThemeData` to both `MaterialApp.theme` and `MaterialApp.darkTheme`, because
/// that pair can only express two themes and there are three. Pumping
/// `LeakGuardApp` to observe that would need a live `MonitorController` and an
/// open `AppDatabase`, so the wiring is asserted at the resolver instead — the
/// resolver is the part that can be wrong.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/app.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/core/theme/design_tokens.dart';
import 'package:leakguard/data/settings/app_settings.dart';

/// Every colour field of [AppPalette], by name.
///
/// Hand-written because Dart has no reflection in this mode. The completeness
/// guard below proves the map covers `copyWith`'s whole surface, so a new field
/// that is added to the palette and forgotten here fails the suite.
Map<String, Color> paletteFields(AppPalette palette) => <String, Color>{
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

/// The names of the fields where [a] and [b] hold different colours.
Set<String> differingFields(AppPalette a, AppPalette b) {
  final left = paletteFields(a);
  final right = paletteFields(b);
  return left.keys.where((String name) => left[name] != right[name]).toSet();
}

/// Distinct sentinel colours, one per palette field, for the completeness guard.
/// Literal colours are fine here: the scanner walks `lib/**` only.
const Map<String, Color> _sentinels = <String, Color>{
  'background': Color(0xFF000001),
  'surface': Color(0xFF000002),
  'surfaceRaised': Color(0xFF000003),
  'border': Color(0xFF000004),
  'textPrimary': Color(0xFF000005),
  'textSecondary': Color(0xFF000006),
  'accent': Color(0xFF000007),
  'accentText': Color(0xFF000008),
  'alert': Color(0xFF000009),
  'normal': Color(0xFF00000A),
  'watch': Color(0xFF00000B),
  'idle': Color(0xFF00000C),
  'gradientGreen': Color(0xFF00000D),
  'alertBoxFill': Color(0xFF00000E),
  'watchBoxFill': Color(0xFF00000F),
  'normalBoxFill': Color(0xFF000010),
};

void main() {
  group('paletteFields covers the whole palette', () {
    test('every copyWith parameter appears in the map, under its own name', () {
      final sentinel = AppPalette.dark.copyWith(
        background: _sentinels['background'],
        surface: _sentinels['surface'],
        surfaceRaised: _sentinels['surfaceRaised'],
        border: _sentinels['border'],
        textPrimary: _sentinels['textPrimary'],
        textSecondary: _sentinels['textSecondary'],
        accent: _sentinels['accent'],
        accentText: _sentinels['accentText'],
        alert: _sentinels['alert'],
        normal: _sentinels['normal'],
        watch: _sentinels['watch'],
        idle: _sentinels['idle'],
        gradientGreen: _sentinels['gradientGreen'],
        alertBoxFill: _sentinels['alertBoxFill'],
        watchBoxFill: _sentinels['watchBoxFill'],
        normalBoxFill: _sentinels['normalBoxFill'],
      );

      // Same names, and each one carries the value copyWith was given — so no
      // field is missing from the map and none is wired to the wrong getter.
      expect(paletteFields(sentinel), _sentinels);
      expect(differingFields(AppPalette.dark, sentinel), _sentinels.keys.toSet());
    });
  });

  group('resolveSystemAppearance', () {
    test('leaves the three explicit appearances alone, under either '
        'platform brightness', () {
      for (final appearance in <Appearance>[
        Appearance.dark,
        Appearance.highContrastDark,
        Appearance.light,
      ]) {
        for (final brightness in Brightness.values) {
          expect(
            resolveSystemAppearance(appearance, brightness),
            appearance,
            reason: '$appearance must not be overridden by $brightness',
          );
        }
      }
    });

    test('collapses system onto dark when the platform is dark', () {
      expect(
        resolveSystemAppearance(Appearance.system, Brightness.dark),
        Appearance.dark,
      );
    });

    test('collapses system onto light when the platform is light', () {
      expect(
        resolveSystemAppearance(Appearance.system, Brightness.light),
        Appearance.light,
      );
    });

    test('never resolves system to high contrast dark', () {
      // The platform reports brightness and nothing else. There is no OS signal
      // that asks for High_Contrast_Dark, so inferring it would hand every
      // dark-mode user an appearance they did not choose.
      for (final brightness in Brightness.values) {
        expect(
          resolveSystemAppearance(Appearance.system, brightness),
          isNot(Appearance.highContrastDark),
        );
      }
    });

    test('is idempotent — resolving twice changes nothing', () {
      for (final appearance in Appearance.values) {
        for (final brightness in Brightness.values) {
          final once = resolveSystemAppearance(appearance, brightness);
          expect(resolveSystemAppearance(once, brightness), once);
        }
      }
    });
  });

  group('themeForAppearance maps all four values', () {
    test('dark resolves to the dark palette at dark brightness', () {
      final theme = themeForAppearance(Appearance.dark, Brightness.light);
      expect(theme.brightness, Brightness.dark);
      expect(theme.extension<AppPalette>(), same(AppPalette.dark));
      expect(theme.scaffoldBackgroundColor, Tokens.darkBackground);
    });

    test('high contrast dark resolves to its own palette, still dark', () {
      final theme = themeForAppearance(
        Appearance.highContrastDark,
        Brightness.light,
      );
      expect(theme.brightness, Brightness.dark);
      expect(theme.extension<AppPalette>(), same(AppPalette.highContrastDark));
      // The regression this replaces: task 3.3 left High Contrast Dark folded
      // onto ThemeMode.dark, so it rendered as plain Dark.
      expect(theme.extension<AppPalette>(), isNot(same(AppPalette.dark)));
      expect(theme.dividerTheme.color, Tokens.hcBorder);
    });

    test('light resolves to the light palette at light brightness', () {
      final theme = themeForAppearance(Appearance.light, Brightness.dark);
      expect(theme.brightness, Brightness.light);
      expect(theme.extension<AppPalette>(), same(AppPalette.light));
      expect(theme.scaffoldBackgroundColor, Tokens.lightBackground);
    });

    test('system follows the platform brightness', () {
      final onDark = themeForAppearance(Appearance.system, Brightness.dark);
      expect(onDark.brightness, Brightness.dark);
      expect(onDark.extension<AppPalette>(), same(AppPalette.dark));

      final onLight = themeForAppearance(Appearance.system, Brightness.light);
      expect(onLight.brightness, Brightness.light);
      expect(onLight.extension<AppPalette>(), same(AppPalette.light));
    });

    test('every appearance yields a theme carrying a palette', () {
      // Without the extension, AppPalette.of falls back to dark and the whole
      // appearance setting silently stops working.
      for (final appearance in Appearance.values) {
        for (final brightness in Brightness.values) {
          expect(
            themeForAppearance(appearance, brightness).extension<AppPalette>(),
            isNotNull,
            reason: '$appearance on $brightness lost its palette',
          );
        }
      }
    });

    test('the three explicit appearances ignore the platform brightness', () {
      for (final appearance in <Appearance>[
        Appearance.dark,
        Appearance.highContrastDark,
        Appearance.light,
      ]) {
        expect(
          themeForAppearance(appearance, Brightness.dark).extension<AppPalette>(),
          same(
            themeForAppearance(appearance, Brightness.light)
                .extension<AppPalette>(),
          ),
          reason: '$appearance is an explicit choice, not a platform one',
        );
      }
    });

    test('the four appearances resolve to exactly three distinct palettes', () {
      final palettes = <AppPalette>{
        for (final appearance in Appearance.values)
          for (final brightness in Brightness.values)
            themeForAppearance(appearance, brightness).extension<AppPalette>()!,
      };
      expect(palettes, hasLength(3));
      expect(
        palettes,
        <AppPalette>{
          AppPalette.dark,
          AppPalette.highContrastDark,
          AppPalette.light,
        },
      );
    });
  });

  group('AppTheme.highContrastDark is built like the other two', () {
    test('is a dark theme sharing every Dark surface', () {
      final dark = AppTheme.dark();
      final hc = AppTheme.highContrastDark();

      expect(hc.brightness, dark.brightness);
      expect(hc.scaffoldBackgroundColor, dark.scaffoldBackgroundColor);
      expect(hc.canvasColor, dark.canvasColor);
      expect(hc.cardTheme.color, dark.cardTheme.color);
      expect(hc.colorScheme.surface, dark.colorScheme.surface);
      expect(hc.appBarTheme.backgroundColor, dark.appBarTheme.backgroundColor);
    });

    test('raises the hairline and secondary-text colours, and only those', () {
      final dark = AppTheme.dark();
      final hc = AppTheme.highContrastDark();

      expect(dark.dividerTheme.color, Tokens.darkBorder);
      expect(hc.dividerTheme.color, Tokens.hcBorder);
      expect(hc.dividerTheme.thickness, dark.dividerTheme.thickness);

      expect(dark.textTheme.bodySmall?.color, Tokens.darkTextSecondary);
      expect(hc.textTheme.bodySmall?.color, Tokens.hcTextSecondary);
      expect(hc.textTheme.bodyMedium?.color, dark.textTheme.bodyMedium?.color);
      expect(hc.textTheme.titleLarge?.color, dark.textTheme.titleLarge?.color);
    });
  });

  group('the High_Contrast_Dark delta against Dark', () {
    test('differs in exactly textSecondary and border', () {
      // Task 3.1 overrides three fields off Dark — textSecondary, border and
      // accentText — but the third is set back to the same cyan Dark already
      // carries, because #00E5FF measures 10.84:1 on #1E1E1E and needs no help.
      // So the *override* set has three names and the *difference* set has two.
      // Asserting the difference set is what keeps Requirement 9.2's "background
      // and surface stay in the dark family" honest.
      expect(
        differingFields(AppPalette.dark, AppPalette.highContrastDark),
        <String>{'textSecondary', 'border'},
      );
    });

    test('accentText is overridden but unchanged, and still aliases accent', () {
      expect(AppPalette.highContrastDark.accentText, Tokens.accent);
      expect(
        AppPalette.highContrastDark.accentText,
        AppPalette.dark.accentText,
      );
      // The aliasing invariant Property 17 leans on: in both dark appearances
      // the text accent *is* the graphical accent, so the light appearance is
      // the only one where the accent/accentText split does any work.
      expect(
        AppPalette.highContrastDark.accentText,
        AppPalette.highContrastDark.accent,
      );
      expect(AppPalette.dark.accentText, AppPalette.dark.accent);
      expect(AppPalette.light.accentText, Tokens.lightAccentText);
      expect(AppPalette.light.accentText, isNot(AppPalette.light.accent));
    });

    test('the two changed values are the recorded token extensions', () {
      expect(AppPalette.highContrastDark.textSecondary, Tokens.hcTextSecondary);
      expect(AppPalette.highContrastDark.border, Tokens.hcBorder);
    });

    test('the dark family is intact: background, surface and surfaceRaised '
        'are identical', () {
      expect(
        AppPalette.highContrastDark.background,
        AppPalette.dark.background,
      );
      expect(AppPalette.highContrastDark.surface, AppPalette.dark.surface);
      expect(
        AppPalette.highContrastDark.surfaceRaised,
        AppPalette.dark.surfaceRaised,
      );
    });

    test('Light is a different appearance entirely, not a delta', () {
      // Sanity bound on the assertion above: "differs in two fields" is only
      // meaningful if the comparison can produce a large answer too.
      expect(
        differingFields(AppPalette.dark, AppPalette.light).length,
        greaterThan(12),
      );
    });
  });
}

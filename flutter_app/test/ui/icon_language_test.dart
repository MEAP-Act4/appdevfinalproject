/// Widget tests for the Icon_Language (task 15.8).
///
/// Requirements 10.1, 10.2, 10.3, 10.5.
///
/// What is asserted:
///
///   * each of the five [AppGlyph] domain glyphs renders — an [AppIcon] builds
///     a [CustomPaint] at the requested size and takes a token colour
///     (Requirements 10.1, 10.5);
///   * the domain glyph-key set is exactly `{droplet, valve, gauge, pipe,
///     wave}` AND equals the shared fixture `test_fixtures/icons/manifest.json`
///     that the Web_Client also reads, so the two clients cannot drift
///     (Requirement 10.3);
///   * the structural exempt set is exactly `{chevron, close, check, plus,
///     refresh, expand}` and every entry maps to a Material [IconData], so the
///     exemption is a real, closed declaration (Requirement 10.5 / design's
///     narrowing of 10.1);
///   * no lightbulb / illumination glyph is in the domain vocabulary
///     (Requirement 10.2).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/core/theme/design_tokens.dart';
import 'package:leakguard/ui/common/icon_language.dart';

/// Walks up from the current directory to the package root (the directory that
/// holds `pubspec.yaml`), so the shared fixture resolves whether `flutter test`
/// runs from `flutter_app/` or a parent directory.
Directory _packageRoot() {
  var directory = Directory.current;
  for (var depth = 0; depth < 8; depth++) {
    final sep = Platform.pathSeparator;
    if (File('${directory.path}${sep}pubspec.yaml').existsSync()) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate pubspec.yaml from ${Directory.current.path}');
}

/// The `glyphs` array from the shared manifest, as a set.
Set<String> _manifestGlyphKeys() {
  final sep = Platform.pathSeparator;
  final repoRoot = _packageRoot().parent;
  final file = File(
    '${repoRoot.path}${sep}test_fixtures${sep}icons${sep}manifest.json',
  );
  if (!file.existsSync()) {
    throw StateError('Missing shared fixture at ${file.path}');
  }
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final glyphs = (decoded['glyphs'] as List<dynamic>).cast<String>();
  return glyphs.toSet();
}

/// Wraps [child] in the minimal theme the widget needs so `AppPalette.of`
/// resolves.
Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[AppPalette.dark]),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('AppGlyph domain vocabulary', () {
    test('is exactly {droplet, valve, gauge, pipe, wave}', () {
      final keys = AppGlyph.values.map((g) => g.name).toSet();
      expect(keys, <String>{'droplet', 'valve', 'gauge', 'pipe', 'wave'});
    });

    test('matches the shared manifest fixture (Requirement 10.3)', () {
      final keys = AppGlyph.values.map((g) => g.name).toSet();
      expect(keys, _manifestGlyphKeys());
    });

    test('contains no lightbulb / illumination glyph (Requirement 10.2)', () {
      final keys = AppGlyph.values.map((g) => g.name).toSet();
      for (final banned in const <String>['bulb', 'light', 'lamp', 'bolt', 'flash']) {
        expect(
          keys.any((k) => k.contains(banned)),
          isFalse,
          reason: 'domain vocabulary must not contain "$banned"',
        );
      }
    });
  });

  group('AppIcon rendering (Requirements 10.1, 10.5)', () {
    for (final glyph in AppGlyph.values) {
      testWidgets('${glyph.name} renders a CustomPaint at the requested size',
          (tester) async {
        await tester.pumpWidget(
          _host(AppIcon(glyph, size: Tokens.s4, color: Tokens.accent)),
        );

        // A CustomPaint is present for this glyph.
        final paintFinder = find.descendant(
          of: find.byType(AppIcon),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter != null,
          ),
        );
        expect(paintFinder, findsWidgets);

        // It is laid out at the requested size.
        final size = tester.getSize(find.byType(AppIcon).first);
        expect(size.width, Tokens.s4);
        expect(size.height, Tokens.s4);
      });
    }

    testWidgets('named constructors resolve to their glyph', (tester) async {
      await tester.pumpWidget(_host(const AppIcon.gauge(size: 20)));
      final icon = tester.widget<AppIcon>(find.byType(AppIcon));
      expect(icon.glyph, AppGlyph.gauge);
      expect(icon.size, 20);
    });

    testWidgets('default colour resolves from the token palette, not a literal',
        (tester) async {
      await tester.pumpWidget(_host(const AppIcon(AppGlyph.wave)));
      // Builds without an explicit colour: the widget must resolve one from
      // AppPalette. If it threw or painted nothing this pump would fail.
      expect(find.byType(CustomPaint), findsWidgets);
      final icon = tester.widget<AppIcon>(find.byType(AppIcon));
      expect(icon.color, isNull);
      expect(icon.size, Tokens.s4);
    });

    testWidgets('exposes a semantic label when given one (Requirement 10.4)',
        (tester) async {
      await tester.pumpWidget(
        _host(const AppIcon(AppGlyph.droplet, semanticLabel: 'Inlet flow')),
      );
      expect(find.bySemanticsLabel('Inlet flow'), findsOneWidget);
    });
  });

  group('Structural exemption (Requirement 10.5)', () {
    test('is exactly {chevron, close, check, plus, refresh, expand}', () {
      final keys = StructuralGlyph.values.map((g) => g.name).toSet();
      expect(
        keys,
        <String>{'chevron', 'close', 'check', 'plus', 'refresh', 'expand'},
      );
    });

    test('is disjoint from the domain vocabulary', () {
      final domain = AppGlyph.values.map((g) => g.name).toSet();
      final structural = StructuralGlyph.values.map((g) => g.name).toSet();
      expect(domain.intersection(structural), isEmpty);
    });

    test('every structural glyph maps to a Material IconData', () {
      for (final g in StructuralGlyph.values) {
        expect(kStructuralIcons[g], isNotNull, reason: 'no icon for ${g.name}');
      }
      expect(kStructuralIcons.length, StructuralGlyph.values.length);
    });
  });
}

/// Example tests pinning the fixed per-mode Layout_Engine metrics for the
/// Mobile_Client, and — the point of this file — the cross-client agreement of
/// Requirement 13.1.
///
/// Task 5.1 already added `layout_mode_test.dart`, which pins the full
/// per-mode gutter/pad/contentMax table and the band boundaries as plain
/// example assertions. This file does **not** duplicate that table wholesale.
/// Its distinct job is the cross-client tie: the Mobile_Client (`layout_mode.dart`,
/// Dart) and the Web_Client (`src/core/layout.ts`, TypeScript) duplicate these
/// constants across two languages by necessity — neither can import the other —
/// so the two copies could silently drift. The honest referee is a shared
/// fixture at the repo root, `test_fixtures/layout/metrics.json`, that both
/// clients read. This test asserts `GridMetrics` / `Breakpoints` equal that
/// fixture; the React test
/// (`react_app/src/__tests__/compliance/metrics-examples.node.test.ts`) asserts
/// the same of its own constants against the same JSON. A divergence in either
/// client fails that client's suite, naming the fixture both were measured
/// against.
///
/// The one metric fact this file states directly rather than through the
/// fixture is the sub-320 corner of Requirement 2.11: `resolve(300)` is
/// [LayoutMode.compact] with 16 outer padding. Totality below 320 is the point,
/// so it is pinned here as an example as well as read from the fixture.
///
/// The fixture is found by resolving the repo root as the parent of the
/// package root — the package root is located by walking up to `pubspec.yaml`,
/// exactly as the literal-colour scanner's `resolvePackageRoot` does — so the
/// test works whether `flutter test` runs from `flutter_app/` or a parent
/// directory. `test_fixtures/` sits outside both client trees; it is a shared
/// convention that task 9.1 adds further fixtures to.
///
/// Requirements 2.3, 2.4, 2.5, 2.11, 13.1.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';

import 'literal_colour_scanner.dart' show resolvePackageRoot;

/// The parsed `test_fixtures/layout/metrics.json`, resolved from the repo root.
Map<String, dynamic> _loadFixture() {
  // The package root holds pubspec.yaml (flutter_app/); the repo root is its
  // parent, where test_fixtures/ lives alongside both client directories.
  final packageRoot = resolvePackageRoot();
  final repoRoot = packageRoot.parent;
  final sep = Platform.pathSeparator;
  final fixtureFile =
      File('${repoRoot.path}${sep}test_fixtures${sep}layout${sep}metrics.json');
  if (!fixtureFile.existsSync()) {
    throw StateError(
      'Expected the shared layout metrics fixture at ${fixtureFile.path}. The '
      'cross-client agreement test (Requirement 13.1) cannot report a pass '
      'without the fixture both clients are measured against.',
    );
  }
  return jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
}

/// Maps a fixture mode key to the [LayoutMode] it names.
LayoutMode _modeFor(String key) {
  switch (key) {
    case 'compact':
      return LayoutMode.compact;
    case 'medium':
      return LayoutMode.medium;
    case 'expanded':
      return LayoutMode.expanded;
    default:
      throw ArgumentError('Unknown layout mode key "$key" in the fixture.');
  }
}

void main() {
  final fixture = _loadFixture();

  group('sub-320 totality (Req 2.11)', () {
    test('resolve(300) is compact with 16 outer padding', () {
      final mode = Breakpoints.resolve(300);
      expect(mode, LayoutMode.compact);
      expect(GridMetrics.outerPaddingFor(mode), 16);
    });

    test('every sub-320 width resolves to compact', () {
      for (final width in <double>[0, 1, 100, 300, 319]) {
        expect(Breakpoints.resolve(width), LayoutMode.compact,
            reason: 'width $width');
      }
    });
  });

  group('cross-client agreement with the shared fixture (Req 13.1)', () {
    test('the fixture carries the metrics both clients are measured against',
        () {
      // A guard against a vacuous pass: a fixture that lost its metrics would
      // otherwise make every read below silently absent.
      final metrics = fixture['metrics'] as Map<String, dynamic>;
      expect(metrics.keys.toSet(), <String>{'compact', 'medium', 'expanded'});
    });

    test('the column count matches the fixture', () {
      expect(GridMetrics.columns, fixture['columns']);
      expect(GridMetrics.columns, 12);
    });

    test('the breakpoints match the fixture', () {
      final breakpoints = fixture['breakpoints'] as Map<String, dynamic>;
      expect(Breakpoints.medium, (breakpoints['medium'] as num).toDouble());
      expect(Breakpoints.expanded, (breakpoints['expanded'] as num).toDouble());
    });

    test('the Expanded content cap matches the fixture', () {
      expect(Breakpoints.contentMax, (fixture['contentMax'] as num).toDouble());
    });

    test('every per-mode triple matches the fixture', () {
      final metrics = fixture['metrics'] as Map<String, dynamic>;
      metrics.forEach((key, value) {
        final mode = _modeFor(key);
        final triple = value as Map<String, dynamic>;

        expect(GridMetrics.gutterFor(mode),
            (triple['gutter'] as num).toDouble(),
            reason: '$key gutter');
        expect(GridMetrics.outerPaddingFor(mode),
            (triple['pad'] as num).toDouble(),
            reason: '$key pad');

        // Medium's cap is null in both the fixture and the client; a real
        // width otherwise. Compare null-to-null and value-to-value directly so
        // the "no cap" case stays honest rather than coerced to a sentinel.
        final fixtureCap = triple['contentMax'];
        final clientCap = GridMetrics.contentMaxFor(mode);
        if (fixtureCap == null) {
          expect(clientCap, isNull, reason: '$key contentMax');
        } else {
          expect(clientCap, (fixtureCap as num).toDouble(),
              reason: '$key contentMax');
        }
      });
    });

    test('the fixture sub-320 rule resolves as recorded', () {
      final rule = fixture['subCompactRule'] as Map<String, dynamic>;
      final width = (rule['width'] as num).toDouble();
      final mode = Breakpoints.resolve(width);
      expect(mode, _modeFor(rule['mode'] as String));
      expect(GridMetrics.outerPaddingFor(mode),
          (rule['pad'] as num).toDouble());
    });
  });
}

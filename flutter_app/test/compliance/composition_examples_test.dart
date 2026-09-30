/// Property 29 — Both clients agree on the Dashboard_View grid composition.
/// Mobile_Client half (task 9.14).
///
/// Requirements 3.1, 3.2, 3.3, 3.4 fix the wide-viewport composition — the
/// KPI_Row of three `span: 4` cells, then the Main_Chart and Alerts_Panel whose
/// spans differ by mode — and Requirement 13.1 requires the Mobile_Client and
/// the Web_Client to present the SAME column spans for every Layout_Mode.
///
/// **Why a shared fixture is the referee.** Each client builds the composition
/// independently: the Mobile_Client's [dashboardComposition] (Dart) and the
/// Web_Client's `dashboardCells` (TypeScript). Neither can import the other, so
/// the two ordered cell lists could silently drift. The honest referee is a
/// single file at the repo root, `test_fixtures/layout/compositions.json`, that
/// BOTH clients read. This test asserts the Mobile_Client's composition — the
/// ordered `(role.id, span)` list — equals the fixture's `modes[mode].cells`
/// exactly, in order, including spans; the Web_Client suite
/// (`react_app/src/__tests__/compliance/composition-examples.node.test.ts`)
/// asserts the same of `dashboardCells` against the same JSON. A divergence in
/// either client fails that client's suite, and because both are measured
/// against one file, the clients cannot disagree and both pass.
///
/// **What is compared.** For a mode whose fixture entry has `grid: true`
/// (Medium, Expanded), the derived composition must be the fixture's ordered
/// cells, role-for-role and span-for-span. For a mode with `grid: false`
/// (Compact) the client renders the Sensor_Carousel, not a Grid_12, so the
/// composition must be empty and the fixture's `cells` must be empty too — a
/// client that wrongly built a grid in Compact fails against `grid: false`.
///
/// **The property (Property 29).** `mode` ranges over the three Layout_Modes
/// read from the fixture — not hardcoded — and the invariant is
/// "[dashboardComposition](mode) as `(id, span)` pairs equals the fixture's
/// cells for that mode, in order". Ranging over the modes the fixture actually
/// declares means a fixture that lost or renamed a mode cannot pass vacuously.
///
/// The fixture is found by resolving the repo root as the parent of the package
/// root (located by walking up to `pubspec.yaml`, exactly as the
/// literal-colour scanner's `resolvePackageRoot` does), so the test works
/// whether `flutter test` runs from `flutter_app/` or a parent directory.
///
/// Requirements: 3.1, 3.2, 3.3, 3.4, 13.1.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/ui/dashboard/dashboard_view.dart';

import '../support/props.dart';
import 'literal_colour_scanner.dart' show resolvePackageRoot;

/// The parsed `test_fixtures/layout/compositions.json`, resolved from the repo
/// root (the parent of the package root that holds `pubspec.yaml`).
Map<String, dynamic> _loadFixture() {
  final packageRoot = resolvePackageRoot();
  final repoRoot = packageRoot.parent;
  final sep = Platform.pathSeparator;
  final fixtureFile = File(
    '${repoRoot.path}${sep}test_fixtures${sep}layout${sep}compositions.json',
  );
  if (!fixtureFile.existsSync()) {
    throw StateError(
      'Expected the shared composition fixture at ${fixtureFile.path}. The '
      'cross-client agreement test (Property 29, Requirement 13.1) cannot '
      'report a pass without the fixture both clients are measured against.',
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

/// The fixture cells for [mode], as ordered `(role id, span)` pairs — the same
/// shape [dashboardComposition] reduces to, so the two compare directly.
List<(String, int)> _fixtureCells(Map<String, dynamic> modes, LayoutMode mode) {
  final entry = modes[mode.name] as Map<String, dynamic>;
  final cells = entry['cells'] as List<dynamic>;
  return <(String, int)>[
    for (final cell in cells.cast<Map<String, dynamic>>())
      (cell['role'] as String, (cell['span'] as num).toInt()),
  ];
}

/// The Mobile_Client composition for [mode], as ordered `(role id, span)`
/// pairs.
List<(String, int)> _clientCells(LayoutMode mode) => <(String, int)>[
      for (final spec in dashboardComposition(mode)) (spec.role.id, spec.span),
    ];

void main() {
  final fixture = _loadFixture();
  final modes = fixture['modes'] as Map<String, dynamic>;

  // The three Layout_Modes read FROM the fixture (not hardcoded), so Property
  // 29 ranges over exactly the modes the shared file declares.
  final List<LayoutMode> fixtureModes =
      modes.keys.map(_modeFor).toList(growable: false);

  group('Property 29 — cross-client dashboard composition (Req 13.1)', () {
    test('the fixture declares exactly the three Layout_Modes', () {
      // A guard against a vacuous pass: a fixture missing a mode would
      // otherwise make the property range over fewer cases silently.
      expect(
        fixtureModes.toSet(),
        <LayoutMode>{LayoutMode.compact, LayoutMode.medium, LayoutMode.expanded},
      );
      expect(fixtureModes, hasLength(3));
    });

    forAll<LayoutMode>(
      'each mode: dashboardComposition equals the fixture cells exactly, in '
      'order, including spans',
      any.pick<LayoutMode>(fixtureModes),
      (LayoutMode mode) {
        expect(
          _clientCells(mode),
          equals(_fixtureCells(modes, mode)),
          reason: 'composition disagrees with the fixture for ${mode.name}',
        );
      },
      // Range over the three modes exhaustively as well, so every mode is
      // checked at least once regardless of the generator's sampling.
      examples: fixtureModes,
    );
  });

  group('Property 29 — the Grid_12 / carousel split (Req 3.1–3.4)', () {
    test('Compact has no grid composition and the fixture agrees', () {
      // Compact renders the Sensor_Carousel, so the composition is empty and
      // the fixture records grid:false with empty cells.
      expect(dashboardComposition(LayoutMode.compact), isEmpty);

      final compact = modes['compact'] as Map<String, dynamic>;
      expect(compact['grid'], isFalse);
      expect(_fixtureCells(modes, LayoutMode.compact), isEmpty);
    });

    test('Medium and Expanded are grid compositions and the fixture agrees',
        () {
      for (final mode in <LayoutMode>[LayoutMode.medium, LayoutMode.expanded]) {
        expect(dashboardComposition(mode), isNotEmpty, reason: mode.name);
        final entry = modes[mode.name] as Map<String, dynamic>;
        expect(entry['grid'], isTrue, reason: mode.name);
      }
    });

    test('every grid mode packs its cells into runs summing to 12', () {
      // Requirement 2.2 / Grid_12: each run of cells fills the 12 columns.
      // Medium: 4+4+4 | 12 | 12. Expanded: 4+4+4 | 8+4.
      for (final mode in <LayoutMode>[LayoutMode.medium, LayoutMode.expanded]) {
        final spans =
            dashboardComposition(mode).map((s) => s.span).toList();
        var run = 0;
        for (final span in spans) {
          run += span;
          expect(run, lessThanOrEqualTo(12), reason: '${mode.name} run overflow');
          if (run == 12) run = 0;
        }
        expect(run, 0, reason: '${mode.name} left a partial run');
      }
    });
  });
}

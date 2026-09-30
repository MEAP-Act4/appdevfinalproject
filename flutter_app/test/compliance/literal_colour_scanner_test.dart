/// Tests for the literal-colour scanner, and the scan of the real `lib/` tree.
///
/// Requirement 1.4 is a statement about the *scanner* failing, so asserting
/// "the tree is clean" would verify nothing: a scanner that matched nothing
/// would pass that assertion forever. The bulk of this file therefore feeds
/// synthetic source strings to [scanDartSource] — sources that must trip it and
/// sources that must not — and only then turns it loose on `lib/`.
///
/// The fixtures below contain literal colours on purpose. They are strings in a
/// test file, and the scan walks `lib/**/*.dart` only, so they are outside its
/// own scope by construction and no quarantine module is needed.
///
/// No property test is added here. design.md enumerates thirty numbered
/// properties and task 1.8 owns none of them; inventing an unnumbered one would
/// contradict that, and the interesting inputs for a scanner are specific
/// syntactic shapes rather than a generated domain.
///
/// Requirements: 1.2, 1.4.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'literal_colour_scanner.dart';

/// A file whose literal colours are known, accepted for now, and owned by a
/// later task.
///
/// This is not a second exemption mechanism. An exempted file may hold literal
/// colours forever; a file recorded here is *failing* Requirement 1.2 today,
/// and the record exists so the count cannot grow quietly while the phases that
/// own these files are still ahead of us. Removing a literal means removing its
/// entry here, and the test fails either way if the two drift.
class KnownLiteralColourDebt {
  const KnownLiteralColourDebt({
    required this.path,
    required this.owner,
    required this.reason,
    required this.literals,
  });

  /// Package-relative posix path.
  final String path;

  /// The task that removes this debt.
  final String owner;

  /// Why task 1.8 leaves it in place.
  final String reason;

  /// `<kind> :: <literal>` for every hit in the file, one entry per
  /// occurrence, matching the tail of [LiteralColourHit.signature].
  final List<String> literals;

  /// The signatures these literals produce, to compare against the live scan.
  List<String> get signatures =>
      literals.map((String entry) => '$path :: $entry').toList();
}

/// Every literal colour that exists in `lib/` outside the two exempted files.
///
/// Task 1.8 recorded thirteen hits in three files. **Task 3.1 cleared the
/// eleven in `app_theme.dart`**: the nine `AppPalette.light` values moved into
/// `design_tokens.dart` as `lightAccent`, `lightAlert`, `lightNormal`,
/// `lightWatch`, `lightIdle`, `lightGradientGreen`, `lightAlertBoxFill`,
/// `lightWatchBoxFill` and `lightNormalBoxFill`, and the two `Colors.white`
/// became `Tokens.lightOnAccent`, the on-accent foreground the registry already
/// recorded. Two hits in two files remain, both owned by task 15.x.
///
/// Line numbers are deliberately absent. They were, when this was first
/// recorded: `app_theme.dart` 73-81 and 269 and 326 (now cleared),
/// `app_shell.dart` 101, `settings_tab.dart` 938. A baseline that pins line
/// numbers fails on an unrelated edit above them, which teaches people to
/// delete baselines instead of reading them.
const List<KnownLiteralColourDebt> kKnownLiteralColourDebt =
    <KnownLiteralColourDebt>[
  KnownLiteralColourDebt(
    path: 'lib/ui/shell/app_shell.dart',
    owner: 'Task 15.x',
    reason: 'The active-alarm FloatingActionButton sets foregroundColor: '
        'Colors.white against palette.alert. A token, not a palette name.',
    literals: <String>['materialPalette :: Colors.white'],
  ),
  KnownLiteralColourDebt(
    path: 'lib/ui/settings/settings_tab.dart',
    owner: 'Task 15.x',
    reason: 'The destructive-action button picks Colors.white or '
        'Tokens.darkBackground as its foreground. The Tokens half is already a '
        'token reference; the Colors.white half needs to become one.',
    literals: <String>['materialPalette :: Colors.white'],
  ),
];

/// Fixture: a source string with one literal on line 3, for position checks.
const String kSingleHitSource = '''
import 'package:flutter/material.dart';

const Color accent = Color(0xFF00E5FF);
''';

void main() {
  group('the declared exemptions', () {
    test('names exactly two files, both under lib/core/theme', () {
      expect(
        kLiteralColourFileExemptions
            .map((LiteralColourExemption e) => e.path)
            .toList(),
        <String>[
          'lib/core/theme/design_tokens.dart',
          'lib/core/theme/token_registry.dart',
        ],
      );
    });

    test('records a reason for each, so the list cannot grow silently', () {
      for (final exemption in kLiteralColourFileExemptions) {
        expect(
          exemption.reason.length,
          greaterThan(40),
          reason: '${exemption.path} needs a recorded reason',
        );
      }
    });

    test('exempts Colors.transparent and nothing else', () {
      expect(kMaterialColourMemberExemptions.keys, <String>['transparent']);
      expect(
        kMaterialColourMemberExemptions['transparent'],
        contains('surfaceTintColor'),
      );
    });

    test('matches on the whole path, not a directory or a basename', () {
      expect(exemptionFor('lib/core/theme/design_tokens.dart'), isNotNull);
      // The sibling in the same directory is in scope.
      expect(exemptionFor('lib/core/theme/app_theme.dart'), isNull);
      // A file that only shares the basename is in scope.
      expect(exemptionFor('lib/ui/design_tokens.dart'), isNull);
      // A near-miss path is in scope.
      expect(exemptionFor('lib/core/theme/design_tokens_light.dart'), isNull);
      expect(exemptionFor('lib/core/theme/'), isNull);
    });

    test('accepts a windows-style path for the same file', () {
      expect(
        exemptionFor(r'lib\core\theme\design_tokens.dart'),
        isNotNull,
      );
    });
  });

  group('sanitiseDartSource', () {
    test('preserves length and line structure so offsets still line up', () {
      const source = '''
// Color(0xFF00E5FF)
const String a = 'Colors.white';
/* Color(0xFF121212) */
''';
      final sanitised = sanitiseDartSource(source);
      expect(sanitised.length, source.length);
      expect(sanitised.split('\n').length, source.split('\n').length);
      for (var i = 0; i < source.length; i++) {
        if (source[i] == '\n') {
          expect(sanitised[i], '\n', reason: 'newline at $i should survive');
        }
      }
    });

    test('keeps ordinary code untouched', () {
      const source = 'final Color c = Tokens.accent;';
      expect(sanitiseDartSource(source), source);
    });

    test('handles nested block comments, which Dart permits', () {
      const source = '/* outer /* inner Color(0xFF00E5FF) */ still inside */ '
          'Colors.red';
      expect(sanitiseDartSource(source).trim(), 'Colors.red');
    });

    test('blanks raw and triple-quoted strings', () {
      const source = '''
final a = r'Color(0xFF00E5FF)';
final b = \'\'\'Colors.white
Color(0xFF121212)\'\'\';
''';
      final sanitised = sanitiseDartSource(source);
      expect(sanitised, isNot(contains('0xFF00E5FF')));
      expect(sanitised, isNot(contains('Colors.white')));
      expect(sanitised, isNot(contains('0xFF121212')));
    });

    test('keeps interpolated expressions, because they are code', () {
      const source = r"final s = 'tint ${Colors.white} end';";
      final sanitised = sanitiseDartSource(source);
      expect(sanitised, contains('Colors.white'));
      expect(sanitised, isNot(contains('tint')));
      expect(sanitised.length, source.length);
    });

    test('does not treat an escaped quote as the end of a string', () {
      const source = r"final s = 'it\'s Color(0xFF00E5FF) really';";
      final sanitised = sanitiseDartSource(source);
      expect(sanitised, isNot(contains('0xFF00E5FF')));
    });
  });

  group('sources that must trip the scanner', () {
    /// One fixture line, the kind it must produce and the text it must report.
    const cases = <({String source, LiteralColourKind kind, String text})>[
      (
        source: 'const c = Color(0xFF00E5FF);',
        kind: LiteralColourKind.colorHex,
        text: 'Color(0xFF00E5FF)',
      ),
      (
        source: 'const c = Color(0xff00e5ff);',
        kind: LiteralColourKind.colorHex,
        text: 'Color(0xff00e5ff)',
      ),
      (
        source: 'const c = Color( 0xFF121212 );',
        kind: LiteralColourKind.colorHex,
        text: 'Color(0xFF121212)',
      ),
      (
        // Six digits renders transparent, and is still an inline palette value.
        source: 'const c = Color(0x00E5FF);',
        kind: LiteralColourKind.colorHex,
        text: 'Color(0x00E5FF)',
      ),
      (
        source: 'final c = Color.fromARGB(255, 0, 229, 255);',
        kind: LiteralColourKind.colorFromArgb,
        text: 'Color.fromARGB(…)',
      ),
      (
        source: 'final c = Color.fromRGBO(0, 229, 255, 1);',
        kind: LiteralColourKind.colorFromRgbo,
        text: 'Color.fromRGBO(…)',
      ),
      (
        source: 'final c = Color.from(alpha: 1, red: 0, green: 0.9, blue: 1);',
        kind: LiteralColourKind.colorFromComponents,
        text: 'Color.from(…)',
      ),
      (
        source: 'final c = Colors.white;',
        kind: LiteralColourKind.materialPalette,
        text: 'Colors.white',
      ),
      (
        source: 'final c = Colors.black54;',
        kind: LiteralColourKind.materialPalette,
        text: 'Colors.black54',
      ),
      (
        source: 'final c = Colors.blueGrey850;',
        kind: LiteralColourKind.materialPalette,
        text: 'Colors.blueGrey850',
      ),
      (
        source: 'final c = Colors.red.shade700;',
        kind: LiteralColourKind.materialPalette,
        text: 'Colors.red',
      ),
      (
        source: 'final c = Colors.tealAccent.withValues(alpha: 0.2);',
        kind: LiteralColourKind.materialPalette,
        text: 'Colors.tealAccent',
      ),
      (
        // An unrecognised member is still a violation, not a pass.
        source: 'final c = Colors.wattVisionCyan;',
        kind: LiteralColourKind.materialUnknown,
        text: 'Colors.wattVisionCyan',
      ),
      (
        source: 'const int kAccentArgb = 0xFF00E5FF;',
        kind: LiteralColourKind.bareArgb,
        text: '0xFF00E5FF',
      ),
      (
        source: 'final c = Color(kFallback ?? 0xFF121212);',
        kind: LiteralColourKind.bareArgb,
        text: '0xFF121212',
      ),
      (
        source: r"final s = 'tint ${Colors.amber} here';",
        kind: LiteralColourKind.materialPalette,
        text: 'Colors.amber',
      ),
      (
        // Not a Color constructor, but the ARGB literal is caught anyway by the
        // bare-literal rule. Wrapping a palette value in another class is not
        // a way around the scan.
        source: 'final c = AlphaColor(0xFF00E5FF);',
        kind: LiteralColourKind.bareArgb,
        text: '0xFF00E5FF',
      ),
    ];

    for (final fixture in cases) {
      test('${fixture.kind.label}: ${fixture.source}', () {
        final hits = scanDartSource(fixture.source, path: 'lib/ui/widget.dart');
        expect(hits, hasLength(1), reason: 'expected exactly one hit');
        expect(hits.single.kind, fixture.kind);
        expect(hits.single.text, fixture.text);
        expect(hits.single.isExempt, isFalse);
      });
    }

    test('reports every hit in a file, in position order', () {
      const source = '''
final a = Colors.white;
final b = Color(0xFF121212);
final c = Color.fromARGB(255, 1, 2, 3);
''';
      final hits = scanDartSource(source, path: 'lib/ui/widget.dart');
      expect(
        hits.map((LiteralColourHit hit) => hit.kind).toList(),
        <LiteralColourKind>[
          LiteralColourKind.materialPalette,
          LiteralColourKind.colorHex,
          LiteralColourKind.colorFromArgb,
        ],
      );
      expect(hits.map((LiteralColourHit hit) => hit.line), <int>[1, 2, 3]);
    });

    test('counts a repeated literal once per occurrence', () {
      const source = 'final a = Colors.white; final b = Colors.white;';
      expect(scanDartSource(source, path: 'lib/ui/widget.dart'), hasLength(2));
    });
  });

  group('sources that must not trip the scanner', () {
    const cases = <({String label, String source})>[
      (label: 'a token reference', source: 'final c = Tokens.accent;'),
      (
        label: 'a palette reference with an alpha override',
        source: 'final c = palette.accent.withValues(alpha: 0.16);'
      ),
      (
        label: 'the transparent exemption',
        source: 'final c = Colors.transparent;'
      ),
      (
        label: 'transparent used four times, as the theme does',
        source: 'a: Colors.transparent, b: Colors.transparent, '
            'c: Colors.transparent, d: Colors.transparent,'
      ),
      (label: 'Color.lerp between two tokens', source: 'Color.lerp(a, b, t)!;'),
      (
        label: 'a Color built from a variable',
        source: 'final c = Color(spec.argb);'
      ),
      (
        label: 'a byte mask, as leak_protocol uses',
        source: 'final hi = (value >> 8) & 0xFF;'
      ),
      (
        label: 'a two-digit protocol byte',
        source: 'const int kFrameTerminator = 0x0A;'
      ),
      (
        label: 'a sixteen-bit mask',
        source: 'final low = checksum & 0xFFFF;'
      ),
      (
        label: 'a six-digit hex outside a Color call',
        source: 'const int kDeviceId = 0x00E5FF;'
      ),
      (
        label: 'a different class that happens to end in Colors',
        source: 'final c = AppColors.white;'
      ),
      (
        label: 'a member access on an instance named colors',
        source: 'final c = widget.colors.white;'
      ),
      (
        label: 'a constructor whose name ends in Color, fed a token',
        source: 'final c = AlphaColor(spec.argb);'
      ),
      (
        label: 'an identifier containing Colors without a member access',
        source: 'final map = kColorsByRole[role];'
      ),
      (
        label: 'a literal inside a line comment',
        source: '// use Color(0xFF00E5FF) here, or Colors.white'
      ),
      (
        label: 'a literal inside a doc comment',
        source: '/// The §2 accent, Color(0xFF00E5FF). See also Colors.cyan.'
      ),
      (
        label: 'a literal inside a block comment',
        source: '/* Color(0xFF00E5FF) and Colors.white */'
      ),
      (
        label: 'a literal inside a string',
        source: "final s = 'Color(0xFF00E5FF) Colors.white';"
      ),
      (
        label: 'a hex value quoted in prose about the registry',
        source: '/// Records each token as 0xAARRGGBB, e.g. 0xFF121212.'
      ),
      (label: 'an empty file', source: ''),
      (label: 'whitespace only', source: '\n\n  \n'),
    ];

    for (final fixture in cases) {
      test('${fixture.label}: ${fixture.source}', () {
        expect(
          scanDartSource(fixture.source, path: 'lib/ui/widget.dart'),
          isEmpty,
        );
      });
    }
  });

  group('positions and reporting', () {
    test('reports a one-based line and column pointing at the literal', () {
      final hits = scanDartSource(kSingleHitSource, path: 'lib/ui/widget.dart');
      expect(hits, hasLength(1));
      final hit = hits.single;
      expect(hit.line, 3);
      expect(hit.column, kSingleHitSource.split('\n')[2].indexOf('Color(0x') + 1);
      expect(hit.location, 'lib/ui/widget.dart:3:22');
      expect(hit.signature,
          'lib/ui/widget.dart :: colorHex :: Color(0xFF00E5FF)');
    });

    test('names the file, the pattern and the requirement in its report', () {
      final report = LiteralColourScanReport(
        filesScanned: const <String>['lib/ui/widget.dart'],
        hits: scanDartSource(kSingleHitSource, path: 'lib/ui/widget.dart'),
      );
      expect(report.isClean, isFalse);
      expect(report.violations, hasLength(1));
      expect(report.describe(), contains('lib/ui/widget.dart'));
      expect(report.describe(), contains('Color(0xFF00E5FF)'));
      expect(report.describe(), contains('Requirements 1.2, 1.4'));
    });

    test('says so plainly when there is nothing to report', () {
      final report = LiteralColourScanReport(
        filesScanned: const <String>['lib/ui/widget.dart'],
        hits: const <LiteralColourHit>[],
      );
      expect(report.isClean, isTrue);
      expect(report.describe(), contains('No literal colours'));
    });

    test('does not double-count the hex inside a Color call', () {
      final hits = scanDartSource(
        'const c = Color(0xFF00E5FF);',
        path: 'lib/ui/widget.dart',
      );
      expect(hits, hasLength(1));
      expect(hits.single.kind, LiteralColourKind.colorHex);
    });
  });

  group('exemption behaviour on identical sources', () {
    const source = 'const Color a = Color(0xFF121212);\n'
        'const int b = 0xFF1E1E1E;\n';

    test('the same source is a violation in an ordinary file', () {
      final hits = scanDartSource(source, path: 'lib/ui/sensors/sensor.dart');
      expect(hits, hasLength(2));
      expect(hits.every((LiteralColourHit hit) => hit.isExempt), isFalse);
    });

    test('and is exempt, with its reason attached, in the registry', () {
      for (final exemption in kLiteralColourFileExemptions) {
        final hits = scanDartSource(source, path: exemption.path);
        expect(hits, hasLength(2), reason: '${exemption.path} still reports');
        expect(hits.every((LiteralColourHit hit) => hit.isExempt), isTrue);
        expect(hits.first.exemption?.reason, exemption.reason);
      }
    });

    test('an exempt hit never becomes a violation', () {
      final report = LiteralColourScanReport(
        filesScanned: const <String>['lib/core/theme/design_tokens.dart'],
        hits: scanDartSource(
          source,
          path: 'lib/core/theme/design_tokens.dart',
        ),
      );
      expect(report.exemptHits, hasLength(2));
      expect(report.violations, isEmpty);
      expect(report.isClean, isTrue);
    });
  });

  group('the real lib/ tree', () {
    late LiteralColourScanReport report;

    setUpAll(() {
      report = scanLibraryForLiteralColours();
    });

    test('actually read the tree it is reporting on', () {
      expect(
        report.filesScanned.length,
        greaterThan(20),
        reason: 'a scan that read almost nothing would pass vacuously',
      );
      expect(
        report.filesScanned.every((String path) =>
            path.startsWith('lib/') && path.endsWith('.dart')),
        isTrue,
      );
      // The walk is rooted at lib/, so the suite's own fixtures are out of
      // scope. Task 1.4's contrast_test.dart depends on that.
      expect(
        report.filesScanned.any((String path) => path.startsWith('test/')),
        isFalse,
      );
    });

    test('every exempted file exists and is load-bearing', () {
      for (final exemption in kLiteralColourFileExemptions) {
        expect(
          report.filesScanned,
          contains(exemption.path),
          reason: '${exemption.path} was not scanned',
        );
        expect(
          report.exemptHits
              .where((LiteralColourHit hit) => hit.path == exemption.path),
          isNotEmpty,
          reason: '${exemption.path} holds no literal colours, so its '
              'exemption is stale and should be removed',
        );
      }
    });

    test('the transparent exemption is load-bearing too', () {
      final transparentUsers = report.filesScanned.where((String path) {
        final source = _sourceOf(path);
        return sanitiseDartSource(source).contains('Colors.transparent');
      }).toList();
      expect(
        transparentUsers,
        isNotEmpty,
        reason: 'if nothing uses Colors.transparent, drop the exemption',
      );
      expect(
        report.hits.where(
          (LiteralColourHit hit) => hit.text == 'Colors.transparent',
        ),
        isEmpty,
      );
    });

    test('holds exactly the literal colours the baseline records, and no others',
        () {
      final expected = kKnownLiteralColourDebt
          .expand((KnownLiteralColourDebt debt) => debt.signatures)
          .toList()
        ..sort();
      final actual =
          report.violations.map((LiteralColourHit hit) => hit.signature).toList()
            ..sort();
      expect(
        actual,
        expected,
        reason: 'The live scan and the recorded baseline disagree.\n'
            'A new literal colour must be replaced with a token, not added to '
            'kKnownLiteralColourDebt. A removed one must be deleted from the '
            'baseline.\n${report.describe()}',
      );
    });

    test('confines those literals to the files already scheduled for rewrite',
        () {
      expect(
        report.violationsByPath.keys.toList()..sort(),
        kKnownLiteralColourDebt
            .map((KnownLiteralColourDebt debt) => debt.path)
            .toList()
          ..sort(),
      );
      for (final debt in kKnownLiteralColourDebt) {
        expect(debt.owner, isNotEmpty);
        expect(debt.reason.length, greaterThan(40));
      }
    });

    test('finds nothing at all in every other file', () {
      final indebted = kKnownLiteralColourDebt
          .map((KnownLiteralColourDebt debt) => debt.path)
          .toSet();
      final exempt = kLiteralColourFileExemptions
          .map((LiteralColourExemption exemption) => exemption.path)
          .toSet();
      for (final path in report.filesScanned) {
        if (indebted.contains(path) || exempt.contains(path)) continue;
        expect(
          report.hits.where((LiteralColourHit hit) => hit.path == path),
          isEmpty,
          reason: '$path holds a literal colour',
        );
      }
    });
  });
}

/// Reads a scanned file back off disk, for the assertions that need its text.
String _sourceOf(String relativePath) =>
    File('${resolvePackageRoot().path}/$relativePath').readAsStringSync();

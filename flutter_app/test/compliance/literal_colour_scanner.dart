/// The Mobile_Client literal-colour scanner.
///
/// Requirement 1.2 says the Mobile_Client references colour exclusively through
/// the Design_Token_Registry, and Requirement 1.4 turns that into something
/// mechanical: the compliance suite *fails* if any Dart source file outside the
/// registry contains a literal colour value. This file is that scan. It walks
/// `lib/**/*.dart` with `dart:io` and reports every literal colour it finds,
/// tagging the ones that sit in a file allowed to hold them.
///
/// Requirement 1.5 is the Web_Client counterpart and is not implemented here —
/// it belongs to task 1.9, which scans `react_app/src/**`.
///
/// ## Scope: `lib/` only
///
/// The walk is rooted at `lib/` and never descends into `test/`. That is
/// deliberate and it is what lets the compliance suite itself hold the handful
/// of hex strings it genuinely needs: `contrast_test.dart` declares a block of
/// literals for the hex-parser inputs and the published WCAG reference values
/// (`#767676` at 4.54:1, `#0000ff` at 8.59:1), and those are reference data, not
/// design tokens. Unlike the React side, no quarantine module is needed here,
/// because the scan never looks at the suite.
///
/// ## The exempted files, enumerated
///
/// [kLiteralColourFileExemptions] lists exact paths, not a directory wildcard.
/// `lib/core/theme/` is *not* blanket-exempt: `app_theme.dart` lives there and
/// is fully in scope, which is how the nine light-palette literals it currently
/// holds get reported rather than waved through.
///
/// ## The one member exemption
///
/// [kMaterialColourMemberExemptions] holds `Colors.transparent` and nothing
/// else. It carries no palette meaning — it is the absence of paint — and the
/// theme needs it for `surfaceTintColor` on the app bar, navigation bar, dialog
/// and bottom sheet, plus `statusBarColor` on the system overlay style and the
/// `Material` under a tappable card. There is no token that could replace it.
///
/// ## What counts as a literal colour, and what deliberately does not
///
/// Every pattern in [LiteralColourKind] is matched against source that has had
/// its comments and string contents blanked out by [sanitiseDartSource], so a
/// hex code in a doc comment or inside a string is not a hit. Blanking is
/// index-preserving, so reported line and column numbers still point at the
/// real source.
///
/// Matched:
///
/// * `Color(0x…)` — any hex length, since `Color(0x00E5FF)` is still an attempt
///   to write a palette value inline even though it renders transparent.
/// * `Color.fromARGB(…)`, `Color.fromRGBO(…)` and `Color.from(…)`. The last one
///   is the float-component constructor; it is matched because leaving it out
///   would be an open door through which `Color.from(alpha: 1, red: 0, …)`
///   evades the scan entirely.
/// * `Colors.<member>` for any member except the exemption above, whether or
///   not the member is a name the Material palette actually publishes. An
///   unrecognised member is reported as [LiteralColourKind.materialUnknown]
///   rather than ignored, because the alternative is a scan that silently stops
///   working when the palette gains a name.
/// * A bare `0x········` integer literal — exactly eight hex digits — because
///   that is the `0xAARRGGBB` form, and a colour smuggled in as an `int` and
///   handed to `Color(value)` later is still a literal colour.
///
/// Not matched, each for a stated reason:
///
/// * Hex literals of any length other than eight when they appear outside a
///   `Color(…)` call. In this codebase those are protocol bytes and bit masks —
///   `0x0A` as the frame terminator in `leak_protocol.dart`, `& 0xFF` channel
///   masks — and flagging them would make the scan noise. The cost is that a
///   genuine 32-bit non-colour mask would be a false positive; if one ever
///   appears, the fix is to name it as a constant in a file added to
///   [kLiteralColourFileExemptions] with a recorded reason, not to loosen the
///   digit count. As of task 1.8 no eight-digit hex literal exists anywhere in
///   `lib/` outside the two exempted theme files, so the rule currently costs
///   nothing.
/// * `Color(someVariable)`, `Color.lerp(a, b, t)`, `palette.accent.withValues(…)`
///   and every other expression whose colour comes from elsewhere. Those are
///   token references, which is exactly what Requirement 1.2 asks for.
/// * `HSLColor.fromAHSL(…)` and `HSVColor.fromAHSV(…)`. Neither appears in the
///   codebase; recorded as a known gap rather than guessed at.
/// * Colours introduced through a third-party widget's own defaults. The scan
///   reads this package's source, not its dependencies.
///
/// Requirements: 1.2, 1.4.
library;

import 'dart:io';

// --- exemptions ---------------------------------------------------------------

/// A file allowed to hold literal colours, and why.
class LiteralColourExemption {
  const LiteralColourExemption({required this.path, required this.reason});

  /// Package-relative posix path, e.g. `lib/core/theme/design_tokens.dart`.
  ///
  /// Exact, never a prefix or a glob. Matching is on the whole path, so a file
  /// that merely shares a basename — `lib/ui/design_tokens.dart`, were someone
  /// to add one — is not exempt.
  final String path;

  /// Why this file is the legitimate home for literal colours.
  final String reason;
}

/// The only files in `lib/` allowed to declare literal colours.
///
/// Two, worked out from the code rather than assumed:
///
/// * `design_tokens.dart` is where every `Color(0x…)` value lives and is what
///   every widget reads a palette value from. It is the Design_Token_Registry
///   of Requirement 1.2, so by construction it is the one file the rule cannot
///   apply to.
/// * `token_registry.dart` (task 1.6) mirrors the same palette as compliance
///   metadata, recording each value as a bare `0xAARRGGBB` `int` alongside its
///   WattVision section, rationale and consumers. It declares no `Color` at
///   all, but its integers are the `0x········` form the bare-literal rule
///   catches, so it has to be named here too.
///
/// `app_theme.dart` is deliberately absent. It held nine light-palette literals
/// and two `Colors.white` when this list was written; those were a real
/// finding, not an exemption, and task 3.1 moved them into
/// `design_tokens.dart`. The file now reads every colour from a token, which is
/// why it needs no entry here.
const List<LiteralColourExemption> kLiteralColourFileExemptions =
    <LiteralColourExemption>[
  LiteralColourExemption(
    path: 'lib/core/theme/design_tokens.dart',
    reason: 'The Design_Token_Registry itself (Requirement 1.2). Every palette '
        'value in the app is declared here once and read from here everywhere '
        'else, so this is the one file whose job is to hold Color(0x…).',
  ),
  LiteralColourExemption(
    path: 'lib/core/theme/token_registry.dart',
    reason: 'The machine-readable compliance mirror of the same palette (task '
        '1.6). It records each token as a bare 0xAARRGGBB int with its '
        'WattVision section and rationale, which the bare-literal rule would '
        'otherwise flag. It declares no Color; duplicating the values here is '
        'the point, since the suite asserts the two agree.',
  ),
];

/// `Colors.<member>` names that are not palette values.
///
/// Exactly one entry. Anything added here needs the same justification:
/// the member must carry no colour meaning at all.
const Map<String, String> kMaterialColourMemberExemptions = <String, String>{
  'transparent': 'Not a colour but the absence of one, and no token can stand '
      'in for it. Needed for surfaceTintColor on the AppBar, NavigationBar, '
      'DialogTheme and BottomSheetTheme (which would otherwise tint the '
      'WattVision surfaces with Material 3 elevation overlay), for '
      'statusBarColor in the system overlay style, and for the Material under '
      'an InkWell-wrapped Surface_Card so the ripple draws over the card fill '
      'rather than a second opaque layer.',
};

/// Base names the Material palette publishes.
///
/// Held as bases rather than all ~350 members: a trailing shade number is
/// stripped before the lookup, so `red`, `red50`, `red900`, `grey350` and
/// `blueGrey850` all resolve to a base in this set. Used only to classify a hit
/// as [LiteralColourKind.materialPalette] or
/// [LiteralColourKind.materialUnknown] — both are violations either way, so an
/// out-of-date list can never turn a hit into a pass.
const Set<String> kMaterialPaletteBases = <String>{
  // Primary swatches.
  'red', 'pink', 'purple', 'deepPurple', 'indigo', 'blue', 'lightBlue', 'cyan',
  'teal', 'green', 'lightGreen', 'lime', 'yellow', 'amber', 'orange',
  'deepOrange', 'brown', 'grey', 'blueGrey',
  // Accent swatches.
  'redAccent', 'pinkAccent', 'purpleAccent', 'deepPurpleAccent',
  'indigoAccent', 'blueAccent', 'lightBlueAccent', 'cyanAccent', 'tealAccent',
  'greenAccent', 'lightGreenAccent', 'limeAccent', 'yellowAccent',
  'amberAccent', 'orangeAccent', 'deepOrangeAccent',
  // Neutrals and their opacity variants (black54, white70, …).
  'black', 'white',
  // The two published swatch lists.
  'primaries', 'accents',
};

// --- hits ---------------------------------------------------------------------

/// The shape a literal colour took in the source.
enum LiteralColourKind {
  /// `Color(0xFF00E5FF)` — a hex argument to the default constructor.
  colorHex('Color(0x…)'),

  /// `Color.fromARGB(255, 0, 229, 255)`.
  colorFromArgb('Color.fromARGB(…)'),

  /// `Color.fromRGBO(0, 229, 255, 1)`.
  colorFromRgbo('Color.fromRGBO(…)'),

  /// `Color.from(alpha: 1, red: 0, green: 0.9, blue: 1)` — the float-component
  /// constructor. Matched so it cannot be used to sidestep the hex rule.
  colorFromComponents('Color.from(…)'),

  /// `Colors.white` — a name the Material palette publishes.
  materialPalette('Colors.<palette name>'),

  /// `Colors.somethingElse` — a `Colors` member this scanner does not
  /// recognise. Still a violation: the registry, not `Colors`, is the palette.
  materialUnknown('Colors.<unrecognised member>'),

  /// A bare eight-digit `0xAARRGGBB` integer outside any `Color(…)` call.
  bareArgb('0x········ int literal');

  const LiteralColourKind(this.label);

  /// Human-readable pattern name, used in failure reports.
  final String label;
}

/// One literal colour found in one place.
class LiteralColourHit {
  const LiteralColourHit({
    required this.path,
    required this.line,
    required this.column,
    required this.kind,
    required this.text,
    required this.exemption,
  });

  /// Package-relative posix path of the file the hit was found in.
  final String path;

  /// One-based line number in the original source.
  final int line;

  /// One-based column number in the original source.
  final int column;

  final LiteralColourKind kind;

  /// The literal in normalised form — whitespace collapsed, arguments elided
  /// for the multi-argument constructors. Stable enough to record in a
  /// baseline, unlike a raw source slice.
  final String text;

  /// Set when the hit is in an exempted file, carrying the reason. Null for a
  /// violation.
  final LiteralColourExemption? exemption;

  /// True when this hit does not fail the scan.
  bool get isExempt => exemption != null;

  /// `lib/ui/foo.dart:12:7`.
  String get location => '$path:$line:$column';

  /// The signature a baseline records: path, kind and literal, but no line
  /// number. Line numbers move when unrelated code above them changes, and a
  /// baseline that breaks on a cosmetic edit teaches people to delete
  /// baselines.
  String get signature => '$path :: ${kind.name} :: $text';

  @override
  String toString() => '$location  $text  (${kind.label})';
}

/// What a scan found.
class LiteralColourScanReport {
  LiteralColourScanReport({required this.filesScanned, required this.hits});

  /// Package-relative posix paths actually read, sorted.
  final List<String> filesScanned;

  /// Every hit, exempt or not, in file then position order.
  final List<LiteralColourHit> hits;

  /// The hits that fail the scan.
  List<LiteralColourHit> get violations =>
      hits.where((LiteralColourHit hit) => !hit.isExempt).toList();

  /// The hits that an exemption covers.
  List<LiteralColourHit> get exemptHits =>
      hits.where((LiteralColourHit hit) => hit.isExempt).toList();

  /// True when nothing outside the exempted files holds a literal colour.
  bool get isClean => violations.isEmpty;

  /// Violations grouped by file, in scan order.
  Map<String, List<LiteralColourHit>> get violationsByPath {
    final grouped = <String, List<LiteralColourHit>>{};
    for (final hit in violations) {
      grouped.putIfAbsent(hit.path, () => <LiteralColourHit>[]).add(hit);
    }
    return grouped;
  }

  /// A report fit for a test failure message: every violation, its location and
  /// the pattern that caught it.
  String describe() {
    if (isClean) {
      return 'No literal colours outside '
          '${kLiteralColourFileExemptions.map((LiteralColourExemption e) => e.path).join(' and ')} '
          '(${filesScanned.length} files scanned).';
    }
    final lines = <String>[
      '${violations.length} literal colour(s) outside the Design_Token_Registry '
          'in ${violationsByPath.length} file(s), '
          '${filesScanned.length} files scanned:',
    ];
    violationsByPath.forEach((String path, List<LiteralColourHit> fileHits) {
      lines.add('  $path');
      for (final hit in fileHits) {
        lines.add('    ${hit.line}:${hit.column}  ${hit.text}  '
            '(${hit.kind.label})');
      }
    });
    lines.add('Every colour must come from the Design_Token_Registry '
        '(Requirements 1.2, 1.4).');
    return lines.join('\n');
  }
}

// --- the scan ------------------------------------------------------------------

/// The exemption covering [path], or null if there is none.
LiteralColourExemption? exemptionFor(String path) {
  final normalised = _posix(path);
  for (final exemption in kLiteralColourFileExemptions) {
    if (exemption.path == normalised) return exemption;
  }
  return null;
}

/// Scans one Dart source string.
///
/// [path] decides whether the hits come back exempt, so the same fixture can be
/// checked as an ordinary widget file and as the registry.
List<LiteralColourHit> scanDartSource(String source, {required String path}) {
  final normalisedPath = _posix(path);
  final exemption = exemptionFor(normalisedPath);
  final code = sanitiseDartSource(source);
  final lineStarts = _lineStarts(source);
  final hits = <LiteralColourHit>[];

  // Ranges already accounted for, so the eight-digit hex inside
  // `Color(0xFF00E5FF)` is reported once as a constructor call and not a second
  // time as a bare literal.
  final claimed = <({int start, int end})>[];

  void add(int start, int end, LiteralColourKind kind, String text) {
    claimed.add((start: start, end: end));
    final position = _positionOf(start, lineStarts);
    hits.add(LiteralColourHit(
      path: normalisedPath,
      line: position.line,
      column: position.column,
      kind: kind,
      text: text,
      exemption: exemption,
    ));
  }

  for (final match in _colorHexPattern.allMatches(code)) {
    final hex = match.group(1)!;
    add(match.start, match.end, LiteralColourKind.colorHex, 'Color($hex)');
  }

  const namedConstructors = <String, LiteralColourKind>{
    'fromARGB': LiteralColourKind.colorFromArgb,
    'fromRGBO': LiteralColourKind.colorFromRgbo,
    'from': LiteralColourKind.colorFromComponents,
  };
  for (final match in _colorNamedConstructorPattern.allMatches(code)) {
    final kind = namedConstructors[match.group(1)!];
    if (kind == null) continue;
    add(match.start, match.end, kind, kind.label);
  }

  for (final match in _materialColorsPattern.allMatches(code)) {
    final member = match.group(1)!;
    if (kMaterialColourMemberExemptions.containsKey(member)) continue;
    final base = member.replaceAll(_trailingDigits, '');
    final kind = kMaterialPaletteBases.contains(base)
        ? LiteralColourKind.materialPalette
        : LiteralColourKind.materialUnknown;
    add(match.start, match.end, kind, 'Colors.$member');
  }

  for (final match in _bareArgbPattern.allMatches(code)) {
    final inside = claimed.any(
      (({int start, int end}) range) =>
          match.start >= range.start && match.end <= range.end,
    );
    if (inside) continue;
    add(
      match.start,
      match.end,
      LiteralColourKind.bareArgb,
      match.group(0)!,
    );
  }

  hits.sort((LiteralColourHit a, LiteralColourHit b) {
    final byLine = a.line.compareTo(b.line);
    return byLine != 0 ? byLine : a.column.compareTo(b.column);
  });
  return hits;
}

/// Walks `lib/**/*.dart` under [packageRoot] and scans every file.
///
/// [packageRoot] defaults to the package the test is running in, found by
/// looking for `pubspec.yaml` from the current directory upwards, so the scan
/// works whether `flutter test` was launched from `flutter_app/` or from a
/// parent directory.
LiteralColourScanReport scanLibraryForLiteralColours({Directory? packageRoot}) {
  final root = packageRoot ?? resolvePackageRoot();
  final libDirectory = Directory('${root.path}${Platform.pathSeparator}lib');
  if (!libDirectory.existsSync()) {
    throw StateError(
      'Expected a lib/ directory at ${libDirectory.path}. The literal-colour '
      'scan cannot report a pass on a tree it never read.',
    );
  }

  final rootPrefix = _posix(root.path);
  final paths = <String>[];
  for (final entity in libDirectory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    var relative = _posix(entity.path);
    if (relative.startsWith('$rootPrefix/')) {
      relative = relative.substring(rootPrefix.length + 1);
    }
    paths.add(relative);
  }
  paths.sort();

  final hits = <LiteralColourHit>[];
  for (final path in paths) {
    final file = File('${root.path}${Platform.pathSeparator}'
        '${path.replaceAll('/', Platform.pathSeparator)}');
    hits.addAll(scanDartSource(file.readAsStringSync(), path: path));
  }

  return LiteralColourScanReport(filesScanned: paths, hits: hits);
}

/// The directory holding `pubspec.yaml`, searched from [from] upwards.
Directory resolvePackageRoot({Directory? from}) {
  var directory = from ?? Directory.current;
  for (var depth = 0; depth < 8; depth++) {
    if (File('${directory.path}${Platform.pathSeparator}pubspec.yaml')
        .existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError(
    'No pubspec.yaml found at or above ${(from ?? Directory.current).path}, '
    'so the package root could not be resolved.',
  );
}

// --- comment and string blanking -----------------------------------------------

/// Replaces comment bodies and string contents with spaces, character for
/// character, so offsets in the result still address the original source.
///
/// Why blank rather than match raw text: this codebase documents its palette in
/// prose. `token_registry.dart` writes `0xAARRGGBB` in a doc comment,
/// `app_theme.dart` explains in a comment why the light accent is darkened, and
/// a scan that read comments would report all of it. A colour inside a string
/// is blanked for the same reason — it is text, not a value the framework
/// paints with.
///
/// Newlines survive so line numbers do not shift. Interpolation expressions are
/// *not* blanked: `'${Colors.white}'` is real code and is reported. Brace depth
/// is counted to find the end of an interpolation, which is exact unless a
/// string nested inside the interpolation itself contains an unbalanced brace —
/// a case this accepts and does not handle.
///
/// Nested block comments are handled, because Dart permits them.
String sanitiseDartSource(String source) {
  final out = StringBuffer();
  var i = 0;

  void blank(int count) {
    for (var n = 0; n < count; n++) {
      out.write(' ');
    }
  }

  while (i < source.length) {
    final char = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';

    // Line comment, including `///` doc comments.
    if (char == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }

    // Block comment, nestable.
    if (char == '/' && next == '*') {
      var depth = 0;
      while (i < source.length) {
        if (source[i] == '/' && i + 1 < source.length && source[i + 1] == '*') {
          depth++;
          blank(2);
          i += 2;
          continue;
        }
        if (source[i] == '*' && i + 1 < source.length && source[i + 1] == '/') {
          depth--;
          blank(2);
          i += 2;
          if (depth == 0) break;
          continue;
        }
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }

    // String literal, raw or not, single or triple quoted.
    final isRaw = char == 'r' && (next == "'" || next == '"');
    final quoteIndex = isRaw ? i + 1 : i;
    final quote = quoteIndex < source.length ? source[quoteIndex] : '';
    if (quote == "'" || quote == '"') {
      final triple = source.startsWith(quote * 3, quoteIndex);
      final delimiter = triple ? quote * 3 : quote;
      if (isRaw) {
        out.write(' ');
        i++;
      }
      blank(delimiter.length);
      i += delimiter.length;

      while (i < source.length) {
        if (source.startsWith(delimiter, i)) {
          blank(delimiter.length);
          i += delimiter.length;
          break;
        }
        if (!isRaw && source[i] == r'\' && i + 1 < source.length) {
          out.write(' ');
          out.write(source[i + 1] == '\n' ? '\n' : ' ');
          i += 2;
          continue;
        }
        if (!isRaw &&
            source[i] == r'$' &&
            i + 1 < source.length &&
            source[i + 1] == '{') {
          // `${expr}` is code; copy it through so the patterns see it.
          out.write('  ');
          i += 2;
          var depth = 1;
          while (i < source.length && depth > 0) {
            if (source[i] == '{') depth++;
            if (source[i] == '}') {
              depth--;
              if (depth == 0) {
                out.write(' ');
                i++;
                break;
              }
            }
            out.write(source[i]);
            i++;
          }
          continue;
        }
        if (!triple && source[i] == '\n') {
          // Unterminated single-quoted string; stop rather than run away.
          out.write('\n');
          i++;
          break;
        }
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }

    out.write(char);
    i++;
  }

  return out.toString();
}

// --- internals -----------------------------------------------------------------

final RegExp _colorHexPattern =
    RegExp(r'(?<![\w$.])Color\s*\(\s*(0[xX][0-9a-fA-F]+)');

final RegExp _colorNamedConstructorPattern =
    RegExp(r'(?<![\w$.])Color\s*\.\s*(fromARGB|fromRGBO|from)\s*\(');

final RegExp _materialColorsPattern =
    RegExp(r'(?<![\w$.])Colors\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)');

final RegExp _bareArgbPattern =
    RegExp(r'(?<![\w$.])0[xX]([0-9a-fA-F]{8})(?![0-9a-fA-F])');

final RegExp _trailingDigits = RegExp(r'\d+$');

List<int> _lineStarts(String source) {
  final starts = <int>[0];
  for (var i = 0; i < source.length; i++) {
    if (source[i] == '\n') starts.add(i + 1);
  }
  return starts;
}

({int line, int column}) _positionOf(int offset, List<int> lineStarts) {
  var low = 0;
  var high = lineStarts.length - 1;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (lineStarts[mid] <= offset) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return (line: low + 1, column: offset - lineStarts[low] + 1);
}

String _posix(String path) => path.replaceAll(r'\', '/');

/// Property 30 — Both clients agree on every derived value for the same
/// telemetry. Mobile_Client half (task 17.2).
///
/// Requirement 13.2 requires that WHEN the same telemetry sequence is applied
/// to both clients, THE Mobile_Client and THE Web_Client SHALL present the same
/// Status, the same live readings, the same averages, and the same
/// Bs_Equivalence for each channel.
///
/// **Why a shared fixture is the referee.** Each client parses the wire
/// protocol and formats derived values independently — the Mobile_Client with
/// [LeakProtocol], [UnitFormatter] and [CostFormatter] (Dart), the Web_Client
/// with the TypeScript twins. Neither imports the other, so the two could
/// silently drift. The honest referee is a set of shared files at the repo
/// root, `test_fixtures/parity/*.json`, that BOTH clients read. Each file
/// records a settings configuration, a real recorded line sequence, pre-built
/// per-window statistics, and the FLAT, STRING-VALUED `expected` oracle. This
/// test asserts the Mobile_Client's formatted output equals every `expected`
/// string exactly; the Web_Client suite asserts the same of its own formatters
/// against the same JSON. A divergence in either client fails that client's
/// suite, and because both are measured against one file, the clients cannot
/// disagree and both pass.
///
/// **What is compared, per case.** The last Telemetry (`D,...`) line drives the
/// Status token (`LeakStatus.wire`) and the three live readings
/// (`UnitFormatter.flow` of each `flowLpm`). Each window (day / three-day /
/// week) contributes an average (`UnitFormatter.flow` of `averageLpm`), a total
/// (`UnitFormatter.volume` of `totalLitres`) and a cost
/// (`CostFormatter.format` of the canonical `totalLitres`). Comparing formatted
/// strings rather than floats is deliberate: it catches numeric divergence and
/// locale-formatting divergence in one assertion, and it is language-neutral,
/// which is what lets one fixture referee both Dart and TypeScript.
///
/// **The property (Property 30).** `case` ranges over every fixture loaded from
/// `test_fixtures/parity/*.json` (`any.pick`), 100 generated cases plus every
/// fixture as an explicit example so none is skipped. For each case, every
/// assertion point's formatted output must equal the fixture's `expected`
/// string.
///
/// The fixtures are found by resolving the repo root as the parent of the
/// package root (located by walking up to `pubspec.yaml`, exactly as the
/// literal-colour scanner's `resolvePackageRoot` does), so the test works
/// whether `flutter test` runs from `flutter_app/` or a parent directory.
///
/// **Validates: Requirements 13.2**
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:leakguard/core/money/cost_formatter.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/units/measurement_units.dart';

import '../support/props.dart';
import 'literal_colour_scanner.dart' show resolvePackageRoot;

/// Maps a fixture flow-unit wire token to the [FlowUnit] it names.
FlowUnit _flowUnitFor(String token) => switch (token) {
      'lpm' => FlowUnit.litresPerMinute,
      'lph' => FlowUnit.litresPerHour,
      'lps' => FlowUnit.litresPerSecond,
      'usgpm' => FlowUnit.usGallonsPerMinute,
      'ukgpm' => FlowUnit.ukGallonsPerMinute,
      'm3h' => FlowUnit.cubicMetresPerHour,
      _ => throw ArgumentError('Unknown flow-unit token "$token" in fixture.'),
    };

/// Maps a fixture volume-unit wire token to the [VolumeUnit] it names.
VolumeUnit _volumeUnitFor(String token) => switch (token) {
      'l' => VolumeUnit.litres,
      'm3' => VolumeUnit.cubicMetres,
      'usgal' => VolumeUnit.usGallons,
      'ukgal' => VolumeUnit.ukGallons,
      _ =>
        throw ArgumentError('Unknown volume-unit token "$token" in fixture.'),
    };

/// A single parity case loaded from a `test_fixtures/parity/*.json` file.
class ParityCase {
  ParityCase(this.name, this.json);

  final String name;
  final Map<String, dynamic> json;

  Map<String, dynamic> get _settings =>
      json['settings'] as Map<String, dynamic>;
  Map<String, dynamic> get _windowStats =>
      json['windowStats'] as Map<String, dynamic>;
  Map<String, dynamic> get expected => json['expected'] as Map<String, dynamic>;

  List<String> get lines =>
      (json['lines'] as List<dynamic>).cast<String>();

  FlowUnit get flowUnit => _flowUnitFor(_settings['flowUnit'] as String);
  VolumeUnit get volumeUnit =>
      _volumeUnitFor(_settings['volumeUnit'] as String);
  double get tariff =>
      (_settings['tariffBsPerCubicMetre'] as num).toDouble();
  String get locale => _settings['locale'] as String;

  UnitFormatter get formatter =>
      UnitFormatter(flowUnit: flowUnit, volumeUnit: volumeUnit);

  CostFormatter get cost => CostFormatter(
        tariffBsPerCubicMetre: tariff,
        locale: locale,
        enabled: true,
        isDefaultTariff: false,
      );

  /// Window statistics for [window] ('day' | 'threeDay' | 'week').
  ({double averageLpm, double totalLitres}) window(String window) {
    final entry = _windowStats[window] as Map<String, dynamic>;
    return (
      averageLpm: (entry['averageLpm'] as num).toDouble(),
      totalLitres: (entry['totalLitres'] as num).toDouble(),
    );
  }

  /// The last [Telemetry] packet decoded from [lines]. This is what drives the
  /// live readings and the Status, exactly as the running client does.
  Telemetry get lastTelemetry {
    Telemetry? last;
    for (final line in lines) {
      final packet = LeakProtocol.parse(line);
      if (packet is Telemetry) last = packet;
    }
    if (last == null) {
      throw StateError('Fixture "$name" has no Telemetry ("D,...") line.');
    }
    return last;
  }
}

/// Loads every `test_fixtures/parity/*.json` case from the repo root (the
/// parent of the package root that holds `pubspec.yaml`).
List<ParityCase> _loadCases() {
  final packageRoot = resolvePackageRoot();
  final repoRoot = packageRoot.parent;
  final sep = Platform.pathSeparator;
  final dir = Directory('${repoRoot.path}${sep}test_fixtures${sep}parity');
  if (!dir.existsSync()) {
    throw StateError(
      'Expected the shared parity fixtures at ${dir.path}. The cross-client '
      'agreement test (Property 30, Requirement 13.2) cannot report a pass '
      'without the fixtures both clients are measured against.',
    );
  }
  final cases = <ParityCase>[
    for (final entry in dir.listSync())
      if (entry is File && entry.path.toLowerCase().endsWith('.json'))
        ParityCase(
          entry.uri.pathSegments.last,
          jsonDecode(entry.readAsStringSync()) as Map<String, dynamic>,
        ),
  ]..sort((a, b) => a.name.compareTo(b.name));
  return cases;
}

/// Asserts every derived value for [c] matches the fixture's `expected` oracle.
void _assertParity(ParityCase c) {
  final expected = c.expected;
  final formatter = c.formatter;
  final cost = c.cost;
  final telemetry = c.lastTelemetry;

  // Status — the last Telemetry's LeakStatus wire token.
  expect(
    telemetry.status.wire,
    expected['status'],
    reason: '${c.name}: status',
  );

  // Live readings — UnitFormatter.flow of each channel's L/min.
  for (var i = 0; i < 3; i++) {
    expect(
      formatter.flow(telemetry.flowLpm[i]),
      expected['liveFlow$i'],
      reason: '${c.name}: liveFlow$i',
    );
  }

  // Per-window average / total / cost.
  for (final window in const <String>['day', 'threeDay', 'week']) {
    final stats = c.window(window);
    expect(
      formatter.flow(stats.averageLpm),
      expected['${window}Average'],
      reason: '${c.name}: ${window}Average',
    );
    expect(
      formatter.volume(stats.totalLitres),
      expected['${window}Total'],
      reason: '${c.name}: ${window}Total',
    );
    expect(
      cost.format(stats.totalLitres),
      expected['${window}Cost'],
      reason: '${c.name}: ${window}Cost',
    );
  }
}

void main() {
  // CostFormatter's NumberFormat and any locale-aware formatting need the
  // locale symbol data loaded under the test binding — the same setup the cost
  // and locale property suites use.
  TestWidgetsFlutterBinding.ensureInitialized();
  initializeDateFormatting();

  final cases = _loadCases();

  group('Property 30 — cross-client telemetry parity (Req 13.2)', () {
    test('the parity fixture directory exists and has at least five cases', () {
      // A guard against a vacuous pass: an empty or missing directory would
      // otherwise make the property range over nothing silently. The suite
      // ships five scenarios (slow-leak-es, slow-leak-en, idle, fault,
      // calibration).
      expect(
        cases,
        hasLength(greaterThanOrEqualTo(5)),
        reason: 'expected at least five parity fixtures under '
            'test_fixtures/parity/',
      );
    });

    forAll<ParityCase>(
      'each case: every derived value equals the fixture expected string '
      'exactly',
      any.pick<ParityCase>(cases),
      _assertParity,
      // Range over every fixture exhaustively as well, so each case is checked
      // at least once regardless of the generator's sampling.
      examples: cases,
    );
  });
}

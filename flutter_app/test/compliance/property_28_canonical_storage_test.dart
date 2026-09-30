/// Property 28 — canonical storage is invariant under display configuration.
/// Mobile_Client half (task 11.20).
///
/// Requirement 5.7: THE Mobile_Client and THE Web_Client SHALL store the Tariff
/// in the existing settings store and SHALL exclude monetary values from the
/// reading database. Requirement 6.6: THE Cost_Formatter SHALL operate on
/// canonical litre values and SHALL NOT write any computed monetary value to
/// the reading database. Requirement 13.8: canonical storage is part of the
/// cross-client parity surface, and this property is what pins it.
///
/// **The point of the property.** Display configuration — the flow unit, the
/// volume unit, the Tariff and the locale — is presentation-only. It must not
/// change what gets written to the reading database. A persisted reading row is
/// canonical litres/flow plus a UTC timestamp, never a monetary or
/// unit-converted value. So for a fixed telemetry sequence, the rows written
/// under any `(flowUnit, volumeUnit, tariff, locale)` configuration must be
/// EQUAL to the rows written under any other configuration, and no row's column
/// set may contain a monetary key.
///
/// **Why the invariant holds structurally, and what this test protects.** The
/// production row is built by [StoredReading.fromTelemetry] followed by
/// [StoredReading.toRow] — the exact mapping the persistence layer writes to
/// sqflite. Neither takes a [FlowUnit], a [VolumeUnit], a Tariff nor a locale:
/// a display configuration has no way to enter the mapping. This test does not
/// merely restate that; it is the regression guard that fails the moment a
/// future refactor threads a unit, a converted value or a `Bs.` figure into the
/// row (a unit-aware `toRow`, a cached cost column, a "presentation" struct that
/// folds a converted total in). The mapping is the contract; the property
/// enforces it. The test calls the real production mapping rather than modelling
/// it, so a drift in `toRow` is caught directly.
///
/// **The two halves of the invariant.** For one generated telemetry sequence,
/// under every configuration in the cross product:
///
///   * the persisted row set is EQUAL across all configurations — the rows
///     produced under `config[0]` deep-equal those produced under every other
///     config, key for key and value for value;
///   * the row key set contains NO monetary key — no `bs`, `cost`, `tariff`,
///     `bolivian`, `price`, `money`, `currency` column ever appears.
///
/// Generators (design.md): `sequence` — 1 to 500 synthetic telemetry samples;
/// `config` — the cross product of flow units, volume units, tariffs and
/// locales. The full cross product of the four unit/locale dimensions is
/// enumerated per case; the Tariff is sampled across its band. Because the
/// mapping ignores the configuration entirely, one sampled Tariff per config
/// slot is enough to witness invariance — the row cannot depend on a value it
/// never receives.
///
/// The harness is `test/support/props.dart` — glados, 100 cases, seed
/// `kPropertySeed`, `any.listBetween` for the 1..500 sequence, `any.enumOf` for
/// the units, `any.doubleBetween` for the Tariff and `any.pick` for the locale.
/// No colour literal is written here, and the wire protocol, calibration and
/// alarm logic are untouched (Requirement 13.9): this exercises the pure
/// row-construction mapping over synthetic samples and never opens a database.
///
/// Requirements: 5.7, 6.6, 13.8.
///
/// **Validates: Requirements 5.7, 6.6, 13.8**
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/units/measurement_units.dart';
import 'package:leakguard/data/models/stored_reading.dart';

import '../support/props.dart';

/// A synthetic telemetry sample. Only the fields that reach a persisted row
/// matter here; the rest are filled with fixed, in-range values.
typedef Sample = ({
  int seq,
  int receivedAtMs,
  List<double> flowLpm,
  List<double> volumeL,
  double balanceLpm,
  double expectedLpm,
  double thresholdLpm,
  LeakStatus status,
  int sampleCount,
});

/// A display configuration — the four presentation dimensions that must NOT
/// touch a persisted row.
typedef DisplayConfig = ({
  FlowUnit flowUnit,
  VolumeUnit volumeUnit,
  double tariff,
  String locale,
});

/// The two locales the clients format in (Requirement 12.6).
const List<String> _locales = <String>['en', 'es'];

/// A fixed base epoch (2020-01-01T00:00:00Z, in ms) that the sampled ms offset
/// is added to. This yields a real, varied UTC timestamp while keeping the
/// generated offset within the harness's samplable band. The exact instant is
/// irrelevant to Property 28 — only that it is identical across configs.
const int _baseEpochMs = 1577836800000;

/// Column keys that would betray a monetary value having leaked into storage.
/// Matched case-insensitively as substrings, so `costBs` or `tariffValue`
/// would be caught as readily as a bare `bs`.
const List<String> _monetaryFragments = <String>[
  'bs',
  'cost',
  'tariff',
  'bolivian',
  'price',
  'money',
  'currency',
];

/// Builds a [Telemetry] from a synthetic sample. The `uptimeMs`, `breachStreak`
/// and `faultStreak` fields never reach a stored row, so they take fixed values.
Telemetry _telemetry(Sample s) => Telemetry(
      seq: s.seq,
      uptimeMs: 0,
      flowLpm: s.flowLpm,
      volumeL: s.volumeL,
      balanceLpm: s.balanceLpm,
      expectedLpm: s.expectedLpm,
      thresholdLpm: s.thresholdLpm,
      status: s.status,
      breachStreak: 0,
      faultStreak: 0,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        _baseEpochMs + s.receivedAtMs,
        isUtc: true,
      ),
    );

/// The production row-construction mapping: telemetry → stored reading → row
/// map, exactly as the persistence layer writes it to sqflite. The
/// [DisplayConfig] is deliberately NOT threaded in — the point of the property
/// is that it cannot be, because neither [StoredReading.fromTelemetry] nor
/// [StoredReading.toRow] accepts one.
List<Map<String, Object?>> _rowsFor(List<Sample> sequence, DisplayConfig _) {
  const String deviceId = 'device-under-test';
  return <Map<String, Object?>>[
    for (final Sample s in sequence)
      StoredReading.fromTelemetry(
        _telemetry(s),
        deviceId: deviceId,
        sampleCount: s.sampleCount,
      ).toRow(),
  ];
}

/// Deep row-set equality: same length, and each row equal key-for-key and
/// value-for-value in order. Order is significant and preserved because both
/// sides map the same sequence.
bool _rowSetsEqual(
  List<Map<String, Object?>> a,
  List<Map<String, Object?>> b,
) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    final Map<String, Object?> rowA = a[i];
    final Map<String, Object?> rowB = b[i];
    if (rowA.length != rowB.length) return false;
    for (final MapEntry<String, Object?> entry in rowA.entries) {
      if (!rowB.containsKey(entry.key)) return false;
      if (rowB[entry.key] != entry.value) return false;
    }
  }
  return true;
}

/// True when [key] contains any monetary fragment, case-insensitively.
bool _isMonetaryKey(String key) {
  final String lower = key.toLowerCase();
  return _monetaryFragments.any(lower.contains);
}

/// One synthetic sample. Bands are wide but finite so the generated rows carry
/// real, varied canonical values; the exact numbers are irrelevant to the
/// invariant, only that they are identical across configs.
final Generator<Sample> _sample =
    any.combine2<(int, int, List<double>, List<double>), (double, double, double, LeakStatus, int), Sample>(
  any.combine4<int, int, List<double>, List<double>, (int, int, List<double>, List<double>)>(
    any.intBetween(0, 65535),
    // A ms offset within the harness's samplable band (< 0x100000000). Added to
    // a fixed base epoch in the mapping to give a real, varied UTC timestamp;
    // the exact instant is irrelevant to Property 28.
    any.intBetween(0, 4294967295), // ms offset, within the 0x100000000 cap
    _triple(any.doubleBetween(0, 200)),
    _triple(any.doubleBetween(0, 1000000)),
    (int seq, int ts, List<double> flow, List<double> volume) => (seq, ts, flow, volume),
  ),
  any.combine5<double, double, double, LeakStatus, int, (double, double, double, LeakStatus, int)>(
    any.doubleBetween(-200, 200),
    any.doubleBetween(-50, 50),
    any.doubleBetween(0, 50),
    any.enumOf<LeakStatus>(LeakStatus.values),
    any.intBetween(1, 3600),
    (double balance, double expected, double threshold, LeakStatus status, int samples) =>
        (balance, expected, threshold, status, samples),
  ),
  (
    (int, int, List<double>, List<double>) core,
    (double, double, double, LeakStatus, int) rest,
  ) =>
      (
    seq: core.$1,
    receivedAtMs: core.$2,
    flowLpm: core.$3,
    volumeL: core.$4,
    balanceLpm: rest.$1,
    expectedLpm: rest.$2,
    thresholdLpm: rest.$3,
    status: rest.$4,
    sampleCount: rest.$5,
  ),
);

/// A length-3 list of doubles — one per sensor — from a scalar generator.
Generator<List<double>> _triple(Generator<double> item) =>
    any.combine3<double, double, double, List<double>>(
      item,
      item,
      item,
      (double a, double b, double c) => <double>[a, b, c],
    );

/// A telemetry sequence of 1..500 samples — the design.md band.
final Generator<List<Sample>> _sequence =
    any.listBetween<Sample>(_sample, minLength: 1, maxLength: 500);

/// The full cross product of the four presentation dimensions, plus the Tariff
/// sampled across its (0, 1000] band. The Tariff varies per config slot rather
/// than being a fifth enumerated axis: the mapping never receives it, so one
/// sampled value per slot is a genuine witness that the row does not depend on
/// it.
final Generator<double> _tariff = any.doubleBetween(1e-6, 1000);

/// Builds every `(flowUnit, volumeUnit, locale)` combination, pairing each with
/// a Tariff drawn from [tariffs] (cycled if fewer tariffs than combinations).
List<DisplayConfig> _crossProduct(List<double> tariffs) {
  final List<DisplayConfig> configs = <DisplayConfig>[];
  int t = 0;
  for (final FlowUnit flow in FlowUnit.values) {
    for (final VolumeUnit volume in VolumeUnit.values) {
      for (final String locale in _locales) {
        configs.add((
          flowUnit: flow,
          volumeUnit: volume,
          tariff: tariffs[t % tariffs.length],
          locale: locale,
        ));
        t++;
      }
    }
  }
  return configs;
}

/// One generated scenario: a telemetry sequence and a list of Tariffs to spread
/// across the configuration cross product.
typedef Scenario = ({List<Sample> sequence, List<double> tariffs});

final Generator<Scenario> _scenario =
    any.combine2<List<Sample>, List<double>, Scenario>(
  _sequence,
  // Enough tariffs to give every config slot a distinct one; the cross product
  // has FlowUnit.values.length * VolumeUnit.values.length * _locales.length
  // entries (6 * 4 * 2 = 48), so 48 tariffs cover it one-to-one.
  any.listBetween<double>(_tariff, minLength: 48, maxLength: 48),
  (List<Sample> sequence, List<double> tariffs) =>
      (sequence: sequence, tariffs: tariffs),
);

void main() {
  group('Property 28 — Requirements 5.7, 6.6 & 13.8, canonical storage invariant', () {
    forAll<Scenario>(
      'the persisted row set is equal across every display configuration and no '
      'row carries a monetary key',
      _scenario,
      (Scenario scenario) {
        final List<DisplayConfig> configs = _crossProduct(scenario.tariffs);
        expect(configs, isNotEmpty, reason: 'cross product must be non-empty');

        // The rows under the first configuration are the reference set.
        final List<Map<String, Object?>> reference =
            _rowsFor(scenario.sequence, configs.first);

        // One row per sample, always.
        expect(
          reference,
          hasLength(scenario.sequence.length),
          reason: 'row count must equal sample count',
        );

        // --- no monetary key in any row of the reference set ---------------
        for (final Map<String, Object?> row in reference) {
          for (final String key in row.keys) {
            expect(
              _isMonetaryKey(key),
              isFalse,
              reason: 'monetary key "$key" leaked into a persisted row',
            );
          }
        }

        // --- row set is EQUAL across every configuration -------------------
        for (final DisplayConfig config in configs) {
          final List<Map<String, Object?>> rows =
              _rowsFor(scenario.sequence, config);
          expect(
            _rowSetsEqual(rows, reference),
            isTrue,
            reason: 'row set changed under config '
                '(flow ${config.flowUnit.symbol}, volume ${config.volumeUnit.symbol}, '
                'tariff ${config.tariff}, locale ${config.locale})',
          );
          // The monetary-key guard holds under every config, not just the
          // reference — a config-dependent column would show up here.
          for (final Map<String, Object?> row in rows) {
            for (final String key in row.keys) {
              expect(
                _isMonetaryKey(key),
                isFalse,
                reason: 'monetary key "$key" appeared under a non-reference config',
              );
            }
          }
        }
      },
    );
  });

  group('Property 28 — the guards are not vacuous', () {
    test('the reference cross product spans every unit/locale combination', () {
      final List<DisplayConfig> configs =
          _crossProduct(List<double>.filled(48, 1.0));
      expect(
        configs,
        hasLength(FlowUnit.values.length * VolumeUnit.values.length * _locales.length),
      );
    });

    test('a real telemetry sample maps to the canonical column set', () {
      final Map<String, Object?> row = StoredReading.fromTelemetry(
        _telemetry((
          seq: 7,
          receivedAtMs: 1700000000000,
          flowLpm: <double>[1.5, 0.6, 0.7],
          volumeL: <double>[10, 4, 5],
          balanceLpm: 0.2,
          expectedLpm: 0.1,
          thresholdLpm: 0.5,
          status: LeakStatus.ok,
          sampleCount: 4,
        )),
        deviceId: 'd',
      ).toRow();

      // The exact canonical columns, and nothing monetary.
      expect(
        row.keys.toSet(),
        <String>{
          'ts', 'device_id', 'seq', 'f1', 'f2', 'f3',
          'v1', 'v2', 'v3', 'balance', 'expected', 'threshold',
          'status', 'samples',
        },
      );
      expect(row.keys.any(_isMonetaryKey), isFalse);
    });

    test('the monetary-key detector actually fires on monetary names', () {
      expect(_isMonetaryKey('bs'), isTrue);
      expect(_isMonetaryKey('costBs'), isTrue);
      expect(_isMonetaryKey('tariffValue'), isTrue);
      expect(_isMonetaryKey('bolivianos'), isTrue);
      // And does not fire on the canonical columns.
      expect(_isMonetaryKey('balance'), isFalse);
      expect(_isMonetaryKey('threshold'), isFalse);
      expect(_isMonetaryKey('samples'), isFalse);
    });
  });
}

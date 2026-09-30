/// Feature: wattvision-ui-alignment — harness verification for task 1.3.
///
/// The compliance suite root. Every later property test in this directory
/// leans on `test/support/props.dart`, so the harness itself is asserted here:
/// the 100-case floor, seed determinism, shrinking to a minimal counterexample,
/// explicit examples, and a failure report that names the seed.
///
/// The real correctness properties (design.md Properties 1 to 30) belong to
/// later tasks; the smoke property below only proves the runner works.
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/props.dart';

void main() {
  group('property harness', () {
    // Smoke property: proves a declared property actually executes under
    // `flutter test` with the glados generators in place.
    forAll<int>(
      'smoke: intBetween never leaves its band',
      any.intBetween(320, 2560),
      (width) {
        expect(width, greaterThanOrEqualTo(320));
        expect(width, lessThanOrEqualTo(2560));
      },
      examples: <int>[320, 599, 600, 601, 1023, 1024, 1025, 2560],
    );

    test('runs 100 generated cases by default', () async {
      final seen = <int>[];
      final outcome = await checkProperty<int>(
        any.intBetween(0, 1000),
        seen.add,
      );

      expect(outcome.passed, isTrue);
      expect(seen.length, kPropertyCases);
      expect(kPropertyCases, 100);
    });

    test('examples are checked before the generated cases', () async {
      final seen = <int>[];
      final outcome = await checkProperty<int>(
        any.intBetween(0, 10),
        seen.add,
        examples: <int>[601, 602],
      );

      expect(outcome.passed, isTrue);
      expect(seen.take(2), <int>[601, 602]);
      expect(outcome.casesRun, kPropertyCases + 2);
    });

    test('a failing example is reported unshrunk', () async {
      final outcome = await checkProperty<int>(
        any.intBetween(0, 10),
        (value) => expect(value, isNot(601)),
        description: 'no input is 601',
        examples: <int>[601],
      );

      final failure = outcome.failure;
      expect(failure, isNotNull);
      expect(failure!.fromExample, isTrue);
      expect(failure.counterexample, 601);
      expect(failure.shrinkSteps, 0);
    });

    test('a failing property shrinks to the smallest counterexample', () async {
      final outcome = await checkProperty<int>(
        any.intBetween(0, 1000),
        (value) => expect(value, lessThan(50)),
        description: 'every value is below 50',
      );

      final failure = outcome.failure;
      expect(failure, isNotNull);
      // Halving towards 0 must land exactly on the boundary, not merely near
      // it — an off-by-one here would make every later counterexample suspect.
      expect(failure!.counterexample, 50);
      expect(failure.shrinkSteps, greaterThan(0));
      expect(failure.fromExample, isFalse);
    });

    test('the failure report carries the seed and the counterexample',
        () async {
      final outcome = await checkProperty<int>(
        any.intBetween(0, 1000),
        (value) => expect(value, lessThan(50)),
        description: 'every value is below 50',
      );

      final report = outcome.failure!.report;
      expect(report, contains('every value is below 50'));
      expect(report, contains('seed $kPropertySeed'));
      expect(report, contains('Counterexample: 50'));
    });

    test('the same seed replays the same inputs', () async {
      Future<List<int>> run(int seed) async {
        final seen = <int>[];
        await checkProperty<int>(any.intBetween(0, 1 << 20), seen.add,
            seed: seed);
        return seen;
      }

      expect(await run(kPropertySeed), await run(kPropertySeed));
      expect(await run(kPropertySeed), isNot(await run(kPropertySeed + 1)));
    });

    test('pick and enumOf stay inside their domain and shrink downwards',
        () async {
      final outcome = await checkProperty<TestBand>(
        any.enumOf<TestBand>(TestBand.values),
        (band) => expect(band, isNot(TestBand.expanded)),
        description: 'no band is expanded',
      );

      expect(outcome.failure!.counterexample, TestBand.expanded);
    });

    test('listBetween respects its length bounds', () async {
      final outcome = await checkProperty<List<int>>(
        any.listBetween<int>(any.intBetween(1, 12), maxLength: 30),
        (spans) {
          expect(spans.length, lessThanOrEqualTo(30));
          for (final span in spans) {
            expect(span, inInclusiveRange(1, 12));
          }
        },
      );

      expect(outcome.passed, isTrue);
    });

    test('doubleBetween stays in range and shrinks towards the simplest value',
        () async {
      final outcome = await checkProperty<double>(
        any.doubleBetween(1024, 2560),
        (width) => expect(width, lessThan(1500)),
        description: 'every width is below 1500',
      );

      final counterexample = outcome.failure!.counterexample;
      expect(counterexample, inInclusiveRange(1024, 2560));
      // Shrinking towards 1024 must stop just past the threshold rather than
      // wandering off to the top of the range.
      expect(counterexample, greaterThanOrEqualTo(1500));
      expect(counterexample, lessThan(1520));
    });
  });
}

/// Stand-in for a real enum domain (Layout_Mode arrives in phase 3).
enum TestBand { compact, medium, expanded }

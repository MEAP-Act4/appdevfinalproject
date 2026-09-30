/// Feature: wattvision-ui-alignment — Dart property-testing harness.
///
/// **Decision (task 1.3): `glados` 1.1.7 is the generator and shrinker.**
/// `flutter pub add --dev glados --dry-run` resolved cleanly against
/// `sdk: ^3.12.0` on Dart 3.13.4, and a probe property ran green under
/// `flutter test`, so the fallback hand-rolled harness described in design.md
/// is not needed. glados exports `package:test`, which collides with
/// `flutter_test`, so every glados symbol is imported and re-exported through
/// an explicit `show` clause and none of the colliding test primitives
/// (`test`, `expect`, `group`, `Timeout`) come from it.
///
/// What this file adds on top of glados:
///
/// * [forAll] / [forAll2] / [forAll3] — a runner that defaults to
///   [kPropertyCases] (100) generated cases per property and refuses fewer,
///   which is the floor design.md sets for both clients.
/// * A deterministic [kPropertySeed] that is reported in the test name and in
///   every failure report, so a counterexample is reproducible by re-running
///   the same test.
/// * `examples:` — values checked before the generated cases, for properties
///   whose generators are "biased to include" specific boundary inputs.
/// * [checkProperty] — the same runner as a plain function returning a
///   [PropertyOutcome] instead of failing the test, so the harness itself is
///   testable.
///
/// Shrinking comes from glados' [Shrinkable]s. The generators in
/// [WattVisionGenerators] shrink by halving towards the simplest in-range
/// value, so a failing width in [320, 2560] reports as a small number of
/// steps rather than a two-thousand-step decrement walk.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
// Deliberately narrow: `show` keeps glados' re-export of `package:test` out of
// scope so `test`, `expect` and friends resolve to `flutter_test`.
import 'package:glados/glados.dart'
    show Any, AnyUtils, CombinableAny, Generator, ListAnys, Shrinkable, any;

// The full generator surface, re-exported so a property test needs only
// `flutter_test` and this file. Still no `test`/`expect` from `package:test`.
export 'package:glados/glados.dart'
    show
        Any,
        AnyUtils,
        BoolAny,
        CombinableAny,
        DateTimeAnys,
        DoubleAnys,
        DurationAnys,
        Generator,
        GeneratorUtils,
        IntAnys,
        ListAnys,
        MapAnys,
        NullAny,
        SetAyns,
        Shrinkable,
        StringAnys,
        any;

/// The minimum — and default — number of generated cases per property.
///
/// design.md fixes this at 100 for both clients; the React suite gets it from
/// fast-check's default and this is the Dart counterpart.
const int kPropertyCases = 100;

/// The seed every property runs with unless it overrides it.
///
/// Fixed rather than random so a green run stays green and a red run can be
/// reproduced from the failure report alone. `0x57415454` is `WATT`.
const int kPropertySeed = 0x57415454;

/// Hard cap on shrink steps, so a slow-converging shrinker cannot hang a run.
const int kMaxShrinkSteps = 500;

/// A property body. Sync or async — persistence and database properties need
/// `await`, pure ones do not.
typedef PropertyBody<T> = FutureOr<void> Function(T input);

/// What a failing property run found.
class PropertyFailure<T> {
  PropertyFailure({
    required this.description,
    required this.counterexample,
    required this.error,
    required this.stackTrace,
    required this.casesRun,
    required this.shrinkSteps,
    required this.fromExample,
    required this.seed,
    required this.cases,
  });

  final String description;

  /// The smallest input the shrinker could still break the property with.
  final T counterexample;
  final Object error;
  final StackTrace stackTrace;
  final int casesRun;
  final int shrinkSteps;

  /// True when the failure came from an explicit `examples:` value rather than
  /// a generated one. Those are not shrunk — they are already minimal.
  final bool fromExample;
  final int seed;
  final int cases;

  /// The message handed to `fail()`. Carries the seed so the run is
  /// reproducible, and the shrunk counterexample so the input is obvious.
  String get report => <String>[
        'Property failed: $description',
        fromExample
            ? 'Failed on an explicit example after $casesRun checked.'
            : 'Explored $casesRun input(s), shrunk $shrinkSteps time(s).',
        'Counterexample: ${_describe(counterexample)}',
        'Reproduce with: seed $seed, $cases cases (harness default seed '
            '$kPropertySeed).',
        'Cause: $error',
        '$stackTrace',
      ].join('\n');
}

/// The result of a property run. [failure] is null when the property held.
class PropertyOutcome<T> {
  PropertyOutcome.passed(this.casesRun) : failure = null;
  PropertyOutcome.failed(PropertyFailure<T> this.failure, this.casesRun);

  final PropertyFailure<T>? failure;
  final int casesRun;

  bool get passed => failure == null;
}

class _Thrown {
  _Thrown(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

Future<_Thrown?> _attempt<T>(PropertyBody<T> body, T input) async {
  try {
    await body(input);
    return null;
  } catch (error, stackTrace) {
    return _Thrown(error, stackTrace);
  }
}

/// Runs a property and returns the outcome instead of failing the enclosing
/// test. [forAll] is the thin wrapper that turns a failure into a test failure;
/// this is the form the harness' own tests use.
Future<PropertyOutcome<T>> checkProperty<T>(
  Generator<T> generator,
  PropertyBody<T> body, {
  String description = 'property',
  int cases = kPropertyCases,
  int seed = kPropertySeed,
  List<T> examples = const <Never>[],
  int initialSize = 10,
  int maxShrinkSteps = kMaxShrinkSteps,
}) async {
  var casesRun = 0;

  PropertyFailure<T> failure(
    T counterexample,
    _Thrown thrown, {
    required bool fromExample,
    required int shrinkSteps,
  }) {
    return PropertyFailure<T>(
      description: description,
      counterexample: counterexample,
      error: thrown.error,
      stackTrace: thrown.stackTrace,
      casesRun: casesRun,
      shrinkSteps: shrinkSteps,
      fromExample: fromExample,
      seed: seed,
      cases: cases,
    );
  }

  for (final example in examples) {
    casesRun++;
    final thrown = await _attempt<T>(body, example);
    if (thrown != null) {
      return PropertyOutcome<T>.failed(
        failure(example, thrown, fromExample: true, shrinkSteps: 0),
        casesRun,
      );
    }
  }

  final random = Random(seed);
  var size = initialSize;

  for (var i = 0; i < cases; i++) {
    casesRun++;
    final candidate = generator(random, size);
    final thrown = await _attempt<T>(body, candidate.value);
    if (thrown != null) {
      var smallest = candidate;
      var smallestThrown = thrown;
      var steps = 0;

      shrinking:
      while (steps < maxShrinkSteps) {
        for (final shrunk in smallest.shrink()) {
          if (steps >= maxShrinkSteps) break shrinking;
          final shrunkThrown = await _attempt<T>(body, shrunk.value);
          if (shrunkThrown != null) {
            smallest = shrunk;
            smallestThrown = shrunkThrown;
            steps++;
            continue shrinking;
          }
        }
        break;
      }

      return PropertyOutcome<T>.failed(
        failure(
          smallest.value,
          smallestThrown,
          fromExample: false,
          shrinkSteps: steps,
        ),
        casesRun,
      );
    }
    size++;
  }

  return PropertyOutcome<T>.passed(casesRun);
}

/// Declares a property test over one generated input.
///
/// Runs [examples] first, then [cases] generated inputs (at least
/// [kPropertyCases]). On failure the test fails with the shrunk counterexample
/// and the seed.
void forAll<T>(
  String description,
  Generator<T> generator,
  PropertyBody<T> body, {
  int cases = kPropertyCases,
  int seed = kPropertySeed,
  List<T> examples = const <Never>[],
  int initialSize = 10,
  int maxShrinkSteps = kMaxShrinkSteps,
  Object? skip,
}) {
  assert(
    cases >= kPropertyCases,
    'a property must run at least $kPropertyCases cases, got $cases',
  );
  test(
    '$description [$cases cases, seed $seed]',
    () async {
      final outcome = await checkProperty<T>(
        generator,
        body,
        description: description,
        cases: cases,
        seed: seed,
        examples: examples,
        initialSize: initialSize,
        maxShrinkSteps: maxShrinkSteps,
      );
      final failure = outcome.failure;
      if (failure != null) {
        fail(failure.report);
      }
    },
    skip: skip,
  );
}

/// [forAll] over two generated inputs. Examples are `(a, b)` records.
void forAll2<A, B>(
  String description,
  Generator<A> firstGenerator,
  Generator<B> secondGenerator,
  FutureOr<void> Function(A first, B second) body, {
  int cases = kPropertyCases,
  int seed = kPropertySeed,
  List<(A, B)> examples = const <Never>[],
  int initialSize = 10,
  int maxShrinkSteps = kMaxShrinkSteps,
  Object? skip,
}) {
  forAll<(A, B)>(
    description,
    any.combine2<A, B, (A, B)>(
      firstGenerator,
      secondGenerator,
      (A first, B second) => (first, second),
    ),
    (input) => body(input.$1, input.$2),
    cases: cases,
    seed: seed,
    examples: examples,
    initialSize: initialSize,
    maxShrinkSteps: maxShrinkSteps,
    skip: skip,
  );
}

/// [forAll] over three generated inputs. Examples are `(a, b, c)` records.
void forAll3<A, B, C>(
  String description,
  Generator<A> firstGenerator,
  Generator<B> secondGenerator,
  Generator<C> thirdGenerator,
  FutureOr<void> Function(A first, B second, C third) body, {
  int cases = kPropertyCases,
  int seed = kPropertySeed,
  List<(A, B, C)> examples = const <Never>[],
  int initialSize = 10,
  int maxShrinkSteps = kMaxShrinkSteps,
  Object? skip,
}) {
  forAll<(A, B, C)>(
    description,
    any.combine3<A, B, C, (A, B, C)>(
      firstGenerator,
      secondGenerator,
      thirdGenerator,
      (A first, B second, C third) => (first, second, third),
    ),
    (input) => body(input.$1, input.$2, input.$3),
    cases: cases,
    seed: seed,
    examples: examples,
    initialSize: initialSize,
    maxShrinkSteps: maxShrinkSteps,
    skip: skip,
  );
}

/// The generators the 30 correctness properties share.
///
/// Added as an extension on glados' [Any] so they read like the built-ins:
/// `any.intBetween(320, 2560)`, `any.enumOf(LayoutMode.values)`.
extension WattVisionGenerators on Any {
  /// Uniform integers in `[min, max]`, both inclusive.
  ///
  /// glados' own `intInRange` grows with the run size and shrinks one step at
  /// a time; these properties want the whole band covered from the first case
  /// and a halving shrink, so widths and spans use this instead.
  Generator<int> intBetween(int min, int max) {
    assert(min <= max, 'intBetween($min, $max) is empty');
    final span = max - min + 1;
    assert(span <= 0x100000000, 'intBetween range is too wide to sample');
    final target = _simplestInRange(min.toDouble(), max.toDouble()).round();
    return simple<int>(
      generate: (random, size) => min + random.nextInt(span),
      shrink: (value) sync* {
        if (value == target) return;
        final half = target + (value - target) ~/ 2;
        if (half != value) yield half;
        final step = value > target ? value - 1 : value + 1;
        if (step != value && step != half) yield step;
      },
    );
  }

  /// Uniform doubles in `[min, max]`, shrinking by halving towards the
  /// simplest in-range value and then rounding off fractional noise.
  Generator<double> doubleBetween(double min, double max) {
    assert(min <= max, 'doubleBetween($min, $max) is empty');
    final target = _simplestInRange(min, max);
    return simple<double>(
      generate: (random, size) => min + random.nextDouble() * (max - min),
      shrink: (value) sync* {
        if (value == target) return;
        if ((value - target).abs() < 1e-6) {
          yield target;
          return;
        }
        final half = target + (value - target) / 2;
        if (half != value) yield half;
        for (final precision in <double>[1, 100]) {
          final rounded = (value * precision).roundToDouble() / precision;
          if (rounded != value && rounded >= min && rounded <= max) {
            yield rounded;
          }
        }
      },
    );
  }

  /// Uniform choice from [values], shrinking towards the first entry.
  ///
  /// glados' `choose` clamps its index by the run size, which under-samples
  /// the tail of a list early in a run; this does not.
  Generator<T> pick<T>(List<T> values) {
    assert(values.isNotEmpty, 'pick needs at least one value');
    return simple<T>(
      generate: (random, size) => values[random.nextInt(values.length)],
      shrink: (value) sync* {
        final index = values.indexOf(value);
        if (index <= 0) return;
        final half = index ~/ 2;
        if (half != index) yield values[half];
        if (index - 1 != half) yield values[index - 1];
      },
    );
  }

  /// Uniform choice from an enum's values — Layout_Mode, Appearance, Status,
  /// the unit enums.
  Generator<T> enumOf<T extends Enum>(List<T> values) => pick<T>(values);

  /// [base], with [edgeCases] injected at [probability].
  ///
  /// This is what "biased to include 599, 600, 601" means for a generator that
  /// also has to cover the whole band. Boundary values a property must always
  /// see belong in `examples:` instead, which is exhaustive rather than
  /// probabilistic.
  Generator<T> biasedTowards<T>(
    Generator<T> base,
    List<T> edgeCases, {
    double probability = 0.3,
  }) {
    if (edgeCases.isEmpty) return base;
    final edges = pick<T>(edgeCases);
    return (random, size) => random.nextDouble() < probability
        ? edges(random, size)
        : base(random, size);
  }

  /// Lists whose length is in `[minLength, maxLength]`, both inclusive.
  ///
  /// Shrinks by dropping elements and by shrinking the elements themselves,
  /// which is glados' `ShrinkableList` behaviour.
  Generator<List<T>> listBetween<T>(
    Generator<T> item, {
    int minLength = 0,
    int maxLength = 30,
  }) {
    assert(minLength >= 0, 'minLength must not be negative');
    assert(minLength <= maxLength, 'listBetween length range is empty');
    return listWithLengthInRange<T>(minLength, maxLength + 1, item);
  }
}

/// The value in `[min, max]` closest to zero — what "simplest" means for a
/// bounded numeric range, and therefore the target a shrinker walks towards.
double _simplestInRange(double min, double max) {
  if (min > 0) return min;
  if (max < 0) return max;
  return 0;
}

String _describe(Object? value) {
  if (value is String) return "'$value'";
  if (value is Iterable<Object?>) {
    return '[${value.map<String>(_describe).join(', ')}]';
  }
  return '$value';
}

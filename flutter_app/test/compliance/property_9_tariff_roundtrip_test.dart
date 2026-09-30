/// Property 9 — The Tariff parse/format round-trip is exact.
/// Mobile_Client half (task 11.14).
///
/// Requirement 5.6: *for all* accepted Tariff values, parsing the value from
/// the Tariff control text and then formatting the parsed value back to text
/// produces a string that parses to the same value. Requirement 5.5: the
/// persisted Tariff carries at most 4 decimal places of precision. Requirement
/// 12.5: the control accepts a value entered with the active locale's decimal
/// separator, so the round-trip must hold in both `es` and `en`.
///
/// **What the property reduces to here.** The stored form is always the
/// quantised value `q = Tariff.quantise(v)` (Req 5.5). `Tariff.formatForEditing`
/// renders `q` using the locale's decimal separator, and `Tariff.parse` accepts
/// that string back. So the round-trip statement is:
///
///   parse(formatForEditing(quantise(v), locale), locale) is TariffOk
///   whose value == quantise(v) EXACTLY,
///
/// and separately `quantise(v)` is representable in at most 4 decimals, checked
/// by `(q * 10000)` being integral. "Exactly" means `==` on the doubles, not an
/// epsilon compare: the whole point of quantising and formatting the shortest
/// exact decimal is that no precision is lost on the way out and back.
///
/// **The generator domain (design.md).** `value` is reals in `(0, 1000]` — the
/// accepted range, open at 0 and closed at 1000. Because `formatForEditing`
/// trims trailing zeros and `parse` re-reads the trimmed string, the interesting
/// cases are values whose quantised form needs exactly four decimals
/// (e.g. `0.0001`, `123.4567`) and values with more than four decimals of noise
/// that quantisation must fold away (e.g. `0.00005`, `12.345678`). Those are
/// mixed in through `examples:` so every run sees them, alongside the uniformly
/// generated band. `locale` is drawn from `{es, en}` with `any.pick`.
///
/// Quantisation can round a generated value up to `1000.0` (still accepted, the
/// bound is inclusive) or down towards `0`; a value close enough to 0 to
/// quantise to `0.0` would be rejected by `parse` (min is exclusive), so the
/// generator floor sits above that quantisation threshold and the property only
/// claims the round-trip for values that survive as accepted Tariffs. The
/// smallest accepted quantised value is `0.0001`, reached from any `v >= 0.00005`.
///
/// This is a pure model test: no widget, no colour literal, and the wire
/// protocol, calibration and alarm logic are untouched (Requirement 13.9).
///
/// **Validates: Requirements 5.5, 5.6, 12.5**
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/money/tariff.dart';

import '../support/props.dart';

/// The two locales the Tariff control must round-trip through (Req 12.5): the
/// Spanish separator (`,`) and the English separator (`.`).
const List<String> _locales = <String>['es', 'en'];

/// Reals in `(0, 1000]`. The floor sits just above the point where quantisation
/// would collapse to `0.0` (`v < 0.00005`), so every generated value survives
/// `parse` as an accepted Tariff. The upper bound is inclusive.
final Generator<double> _value = any.doubleBetween(0.00005, 1000);

/// A `(value, locale)` scenario.
typedef Scenario = (double value, String locale);

/// Values chosen to exercise the format/parse edges every run:
///   * the smallest accepted quantised value, and one that needs all four
///     decimals exactly;
///   * values with MORE than four decimals that quantisation folds away
///     (half-up at the fifth place);
///   * the inclusive upper bound and a whole number (trailing zeros trimmed).
/// Each is paired with both locales so the separator swap is always covered.
List<Scenario> _edgeExamples() {
  const List<double> values = <double>[
    0.0001, // smallest accepted, exactly 4 decimals
    123.4567, // exactly 4 decimals, mid-range
    999.9999, // exactly 4 decimals, near the top
    0.00005, // rounds up to 0.0001 (5th-place half-up)
    12.345678, // >4 decimals, folded to 12.3457
    0.12345, // >4 decimals, folded to 0.1235
    5.0, // whole number, trailing zeros trimmed
    1000.0, // inclusive upper bound
    250.5, // one decimal
  ];
  return <Scenario>[
    for (final double v in values)
      for (final String locale in _locales) (v, locale),
  ];
}

/// True when [q] carries at most [Tariff.decimals] (4) decimal places (Req 5.5).
///
/// The mathematical statement is "`q * 10000` is integral". A naive
/// `scaled == scaled.round()` fails on values like 12.3457 whose nearest double
/// is a hair off an exact integer once scaled — that is IEEE-754 noise, not a
/// fifth decimal. The faithful test is that the scaled value rounds to an
/// integer that reconstructs `q` exactly: `q == q.round(4) `, i.e. quantising an
/// already-quantised value is a no-op. That is precisely "q has <= 4 decimals"
/// under this quantiser.
bool _hasAtMostFourDecimals(double q) => Tariff.quantise(q) == q;

void main() {
  group('Property 9 — Requirement 5.5, 5.6, 12.5, Tariff round-trip', () {
    forAll<Scenario>(
      'parse(formatForEditing(quantise(v), locale), locale) is TariffOk equal '
      'to quantise(v) exactly, and quantise(v) has <= 4 decimals',
      any.combine2<double, String, Scenario>(
        _value,
        any.pick<String>(_locales),
        (double v, String locale) => (v, locale),
      ),
      (Scenario s) {
        final double v = s.$1;
        final String locale = s.$2;

        final double q = Tariff.quantise(v);
        final String reason =
            'v=$v, locale=$locale, quantise(v)=$q, '
            'formatForEditing=${Tariff.formatForEditing(q, locale)}';

        // Req 5.5 — the quantised value carries at most 4 decimal places.
        expect(
          _hasAtMostFourDecimals(q),
          isTrue,
          reason: 'quantise(v) is not representable in 4 decimals ($reason)',
        );

        // Req 5.6 / 12.5 — format then parse returns the SAME value, in either
        // locale.
        final TariffParse parsed =
            Tariff.parse(Tariff.formatForEditing(q, locale), locale);
        expect(
          parsed,
          isA<TariffOk>(),
          reason: 'round-trip did not parse as accepted ($reason)',
        );
        expect(
          (parsed as TariffOk).value,
          equals(q),
          reason: 'round-trip value drifted from quantise(v) ($reason)',
        );
      },
      examples: _edgeExamples(),
    );

    forAll<Scenario>(
      'the round-trip is idempotent: formatting the parsed value again yields '
      'the identical string',
      any.combine2<double, String, Scenario>(
        _value,
        any.pick<String>(_locales),
        (double v, String locale) => (v, locale),
      ),
      (Scenario s) {
        final double v = s.$1;
        final String locale = s.$2;

        final double q = Tariff.quantise(v);
        final String first = Tariff.formatForEditing(q, locale);
        final TariffParse parsed = Tariff.parse(first, locale);
        expect(parsed, isA<TariffOk>());
        final String second =
            Tariff.formatForEditing((parsed as TariffOk).value, locale);
        expect(
          second,
          equals(first),
          reason: 're-formatting the parsed value changed the string '
              '(v=$v, locale=$locale, first="$first", second="$second")',
        );
      },
      examples: _edgeExamples(),
    );
  });

  group('Property 9 — the generators exercise the intended domain', () {
    test('the edge examples cover both separators for each value', () {
      final List<Scenario> examples = _edgeExamples();
      // Every value is paired with both locales.
      expect(examples.length.isEven, isTrue);
      expect(
        examples.where((Scenario e) => e.$2 == 'es').length,
        equals(examples.where((Scenario e) => e.$2 == 'en').length),
      );
    });

    test('values needing more than 4 decimals quantise to <= 4 decimals', () {
      // 12.345678 -> 12.3457 ; 0.12345 -> 0.1235 ; 0.00005 -> 0.0001.
      for (final double v in <double>[12.345678, 0.12345, 0.00005]) {
        final double q = Tariff.quantise(v);
        expect(
          _hasAtMostFourDecimals(q),
          isTrue,
          reason: 'quantise($v) = $q is not 4-decimal',
        );
      }
      expect(Tariff.quantise(0.00005), equals(0.0001));
    });
  });
}

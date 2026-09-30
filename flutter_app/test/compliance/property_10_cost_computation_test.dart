/// Property 10 — Bs_Equivalence is the canonical volume in cubic metres times
/// the Tariff, at two decimals. Mobile_Client half.
///
/// design.md, Property 10:
///
/// > *For any* canonical litre volume and *any* Tariff in (0, 1000], the
/// > Cost_Formatter produces a string prefixed with `Bs.` and a space, whose
/// > numeric body equals litres divided by 1000 multiplied by the Tariff,
/// > rendered with exactly two fractional digits in the active locale.
///
/// Generators: `litres` — reals in [0, 10^7] including 0 and very small values;
/// `tariff` — reals in (0, 1000]; `locale` — `{es, en}`.
/// Invariant: the output matches the `Bs. ` prefix; parsing the numeric body
/// with the locale's separators recovers `litres / 1000 * tariff` rounded to
/// two decimals; the body has exactly two fractional digits.
///
/// _Validates: Requirements 6.3, 6.4_
///
/// ## Modelling decisions
///
/// **The formatter is exercised, not re-derived.** The property drives the real
/// [CostFormatter] from `lib/core/money/cost_formatter.dart` — the same object
/// the app renders — with `enabled: true` (Requirement 5.8's disabled path is
/// Property 12's concern, not this one). The expected value is computed
/// independently here from `litres / 1000 * tariff` so the test proves the
/// formatter agrees with the formula, not with a copy of its own output.
///
/// **Recovering the number from the string, not trusting a raw float.** The
/// invariant is stated on the *rendered* body, so the test strips the literal
/// `'Bs. '` prefix and reverses the locale's separators to recover a plain
/// numeric string, then compares that against the expected value formatted to
/// exactly two decimals. The comparison is `String == String` on the
/// two-decimal forms, never a raw double `==` — the caution the task calls out.
/// `es` groups with `.` and uses `,` for the decimal; `en` is the reverse, and
/// both carry the same `'Bs. '` prefix (Requirements 12.2–12.4).
///
/// **Exactly two fractional digits.** After recovering the body, the fractional
/// part is isolated by the locale's decimal separator and its length asserted
/// to be exactly 2 (Requirement 6.4). A body with no decimal separator, or one,
/// or three, fails.
///
/// **The `'--'` sentinel and `null` are out of range here.** litres is finite
/// and in `[0, 10^7]`, tariff is finite and in `(0, 1000]`, so the product is
/// finite and the formatter always returns a `'Bs. '` string. Non-finite input
/// (the sentinel) and disabled display (`null`) are covered by other
/// properties.
///
/// The `intl` `NumberFormat('#,##0.00', locale)` used by [CostFormatter] is the
/// same formatter the app renders through, so the separators recovered here are
/// the ones the user sees. The numbers written in this file — 1000, 10^7, 2 —
/// are the divisor, the litre band and the decimal-place count, not colours or
/// Layout thresholds.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:intl/intl.dart' show NumberFormat;
import 'package:leakguard/core/money/cost_formatter.dart';

import '../support/props.dart';

/// The literal prefix every Bs_Equivalence body carries (Requirement 12.4).
const String _bsPrefix = 'Bs. ';

/// The litres-per-cubic-metre divisor of the Bs_Equivalence formula (Req 6.3).
const double _litresPerCubicMetre = 1000.0;

/// The upper bound of the litre band Property 10 draws from: reals in [0, 10^7].
const double _maxLitres = 1e7;

/// The two supported locales this property ranges over.
const List<String> _locales = <String>['es', 'en'];

/// The grouping and decimal separators each locale renders the body with,
/// read from `intl`'s own symbols so the recovery inverse matches exactly what
/// [CostFormatter] emits rather than a hand-guessed pair.
({String group, String decimal}) _separators(String locale) {
  final symbols = NumberFormat('#,##0.00', locale).symbols;
  return (group: symbols.GROUP_SEP, decimal: symbols.DECIMAL_SEP);
}

/// Recovers the plain numeric string from a formatted body by removing the
/// locale's grouping separators and normalising its decimal separator to `.`.
///
/// This is the inverse of the locale formatting: `es`'s `1.234,56` becomes
/// `1234.56`, `en`'s `1,234.56` becomes the same.
String _recoverNumericString(String body, String locale) {
  final seps = _separators(locale);
  final withoutGroups = body.replaceAll(seps.group, '');
  return withoutGroups.replaceFirst(seps.decimal, '.');
}

/// The two-decimal string form of a value — the shape the body is compared to.
String _toTwoDecimals(double value) => value.toStringAsFixed(2);

void main() {
  // `intl` needs its locale data initialised before NumberFormat is used with
  // an explicit locale in a test binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  initializeDateFormatting();

  group('Property 10 — Bs_Equivalence equals litres/1000 * tariff at two '
      'decimals', () {
    forAll3<double, double, String>(
      'prefixes Bs. , recovers the formula value, and carries exactly two '
      'decimals',
      // litres — reals in [0, 10^7], including 0 and very small values.
      any.doubleBetween(0, _maxLitres),
      // tariff — reals in (0, 1000]. The generator's lower bound is a tiny
      // positive epsilon so 0 is excluded while very small tariffs are covered.
      any.doubleBetween(1e-9, 1000),
      any.pick(_locales),
      (litres, tariff, locale) {
        final formatter = CostFormatter(
          tariffBsPerCubicMetre: tariff,
          locale: locale,
          enabled: true,
        );

        final output = formatter.format(litres);

        // Enabled + finite input => always a 'Bs. ' string, never null/'--'.
        expect(
          output,
          isNotNull,
          reason: 'enabled formatter on finite litres=$litres, tariff=$tariff '
              'returned null instead of a Bs. string',
        );
        final text = output!;

        // 1) The literal 'Bs. ' prefix, in every locale (Requirement 12.4).
        expect(
          text.startsWith(_bsPrefix),
          isTrue,
          reason: "output '$text' does not start with '$_bsPrefix' "
              '(locale $locale)',
        );

        final body = text.substring(_bsPrefix.length);

        // 2) Parsing the body with the locale's separators recovers
        //    litres/1000 * tariff rounded to two decimals. The comparison is on
        //    two-decimal STRING forms, never raw double equality.
        final expected = litres / _litresPerCubicMetre * tariff;
        final recovered = _recoverNumericString(body, locale);
        expect(
          _toTwoDecimals(double.parse(recovered)),
          _toTwoDecimals(expected),
          reason: "body '$body' in $locale recovered to $recovered, expected "
              '${_toTwoDecimals(expected)} (litres/1000*tariff). The formatter '
              'drifted from the Requirement 6.3 formula.',
        );

        // 3) The body has exactly two fractional digits (Requirement 6.4).
        final decimal = _separators(locale).decimal;
        final parts = body.split(decimal);
        expect(
          parts.length,
          2,
          reason: "body '$body' in $locale has ${parts.length - 1} decimal "
              "separators '$decimal', expected exactly one",
        );
        expect(
          parts[1].length,
          2,
          reason: "body '$body' in $locale has a fractional part '${parts[1]}' "
              'of length ${parts[1].length}, expected exactly 2',
        );
      },
      // Boundary inputs the property must always see: litres 0 and a tiny
      // value, at both ends of the tariff band, in both locales.
      examples: <(double, double, String)>[
        for (final locale in _locales) ...<(double, double, String)>[
          (0, 1e-9, locale),
          (0, 1000, locale),
          (1e-6, 1e-9, locale),
          (1e-6, 1000, locale),
          (_maxLitres, 1000, locale),
        ],
      ],
    );

    test('renders the two locales with the parity prefix and mirrored decimal '
        'separators', () {
      // A pinned anchor above 999 so the recovery inverse is proven against a
      // known answer, and the two locales' mirrored decimal separators are
      // exercised directly. 1_234_567 litres * 1 Bs/m^3 = 1234.567 m^3.
      const litres = 1234567.0;
      const tariff = 1.0;
      final expected = _toTwoDecimals(litres / _litresPerCubicMetre * tariff);

      final es = CostFormatter(
        tariffBsPerCubicMetre: tariff,
        locale: 'es',
        enabled: true,
      ).format(litres)!;
      final en = CostFormatter(
        tariffBsPerCubicMetre: tariff,
        locale: 'en',
        enabled: true,
      ).format(litres)!;

      // Both prefixed identically (Requirement 12.4).
      expect(es.startsWith(_bsPrefix), isTrue);
      expect(en.startsWith(_bsPrefix), isTrue);

      final esBody = es.substring(_bsPrefix.length);
      final enBody = en.substring(_bsPrefix.length);

      // Mirrored decimal separators: es uses ',', en uses '.' (Req 12.2, 12.3).
      expect(esBody.endsWith('${_separators('es').decimal}57'), isTrue);
      expect(enBody.endsWith('${_separators('en').decimal}57'), isTrue);

      // The recovery inverse lands both on the same expected two-decimal value,
      // regardless of whether the locale inserted grouping separators.
      expect(_toTwoDecimals(double.parse(_recoverNumericString(esBody, 'es'))),
          expected);
      expect(_toTwoDecimals(double.parse(_recoverNumericString(enBody, 'en'))),
          expected);
    });
  });
}

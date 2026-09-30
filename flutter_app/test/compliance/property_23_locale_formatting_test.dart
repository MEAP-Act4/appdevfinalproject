/// Property 23 — The number body is locale-formatted and the currency prefix
/// is not. Mobile_Client half.
///
/// design.md, Property 23:
///
/// > *For any* amount and *any* locale in `{es, en}`, the Cost_Formatter
/// > produces a string whose number body carries the active locale's decimal
/// > and grouping separators, while the currency prefix stays a byte-identical
/// > `Bs. ` in every locale.
///
/// Generators: `amount` — reals in [0, 10^7] including values above 999 so
/// grouping appears; `locale` — `{es, en}`.
/// Invariant: in `es` the decimal separator is `,` and the grouping separator
/// is `.`; in `en` the two are reversed; in both, the output begins with the
/// literal `Bs. ` and that prefix is identical across the two locales.
///
/// _Validates: Requirements 12.1, 12.2, 12.3, 12.4_
///
/// ## Modelling decisions
///
/// **The amount is reached through the real formatter, never injected.** The
/// Bs_Equivalence is what the [CostFormatter] renders from a canonical litre
/// volume and a Tariff, so this property drives the same object the app uses
/// (`enabled: true`) with generated `litres` and `tariff` whose product lands
/// in `[0, 10^7]`. There is no way to hand the formatter a bare "amount"; the
/// litres/tariff pair *is* how an amount is produced, and asserting on the
/// separator *structure* of the resulting body — rather than a specific number
/// — is what makes the property total over the whole band.
///
/// **The separators are read from `intl`, not hand-guessed.** The expected
/// grouping and decimal separators come from
/// `NumberFormat('#,##0.00', locale).symbols` (`GROUP_SEP` / `DECIMAL_SEP`) —
/// the very symbols [CostFormatter] formats through. That guarantees `es` ⇒
/// (group `.`, decimal `,`) and `en` ⇒ (group `,`, decimal `.`) is checked
/// against the runtime the app renders in, not a copy of the assumption. The
/// property additionally pins those pairs to the literal characters the
/// requirements name (Req 12.2, 12.3), so a locale-data change that silently
/// swapped them would fail here.
///
/// **Grouping must actually appear above 999.** A separator claim is only
/// meaningful if the grouping separator is exercised, so the property asserts
/// that whenever the integer part of the body is four or more digits long the
/// locale's grouping separator is present, and the `examples:` force at least
/// one litres/tariff combination whose product exceeds 999 in each locale.
/// Below 1000 no grouping separator is expected, and the property checks that
/// too, so a formatter that spuriously inserted grouping into `12.34` fails.
///
/// **The prefix is not locale-formatted (Req 12.4).** The literal `'Bs. '` is
/// asserted byte-identical across `es` and `en` for the same input — the
/// concrete meaning of "the currency prefix is not locale-formatted". The ICU
/// currency symbol for BOB varies by locale; the deliberate use of a literal
/// prefix instead is exactly what this half of the property protects.
///
/// The numbers written in this file — 1000, 10^7 — are the grouping threshold
/// and the amount band, not colours or Layout thresholds.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:intl/intl.dart' show NumberFormat;
import 'package:leakguard/core/money/cost_formatter.dart';

import '../support/props.dart';

/// The literal prefix every Bs_Equivalence body carries, in every locale
/// (Requirement 12.4). Not an ICU currency symbol.
const String _bsPrefix = 'Bs. ';

/// The upper bound of the amount band Property 23 draws from: reals in [0,10^7].
const double _maxLitres = 1e7;

/// The two supported locales this property ranges over.
const List<String> _locales = <String>['es', 'en'];

/// The grouping and decimal separators each locale renders the body with, read
/// from `intl`'s own symbols so the assertion matches exactly what
/// [CostFormatter] emits rather than a hand-guessed pair.
({String group, String decimal}) _separators(String locale) {
  final symbols = NumberFormat('#,##0.00', locale).symbols;
  return (group: symbols.GROUP_SEP, decimal: symbols.DECIMAL_SEP);
}

/// The literal separators Requirements 12.2 and 12.3 name for each locale, used
/// to pin `intl`'s symbols to the characters the requirements demand.
const Map<String, ({String group, String decimal})> _requiredSeparators =
    <String, ({String group, String decimal})>{
  // Spanish: '.' groups thousands, ',' is the decimal separator (Req 12.2).
  'es': (group: '.', decimal: ','),
  // English: the reverse (Req 12.3).
  'en': (group: ',', decimal: '.'),
};

void main() {
  // `intl` needs its locale data initialised before NumberFormat is used with
  // an explicit locale in a test binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  initializeDateFormatting();

  group('Property 23 — the body is locale-formatted and the Bs. prefix is not',
      () {
    forAll3<double, double, String>(
      'body carries the locale separators, grouping appears above 999, and the '
      'Bs. prefix is byte-identical',
      // amount — driven through the formatter as litres in [0, 10^7]...
      any.doubleBetween(0, _maxLitres),
      // ...times a tariff in (0, 1000], so the product spans the band and some
      // cases exceed 999 (grouping) — biased towards a tariff of 1000 so a
      // large litres volume reliably produces a grouped amount.
      any.biasedTowards(any.doubleBetween(1e-9, 1000), <double>[1000]),
      any.pick(_locales),
      (litres, tariff, locale) {
        final seps = _separators(locale);
        final required = _requiredSeparators[locale]!;

        // `intl`'s symbols must match the characters Req 12.2 / 12.3 name.
        expect(
          seps.group,
          required.group,
          reason: "locale $locale grouping separator is '${seps.group}', "
              "Requirement demands '${required.group}'",
        );
        expect(
          seps.decimal,
          required.decimal,
          reason: "locale $locale decimal separator is '${seps.decimal}', "
              "Requirement demands '${required.decimal}'",
        );

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

        // 2) The body ends with exactly one decimal separator followed by two
        //    digits — the locale's decimal separator, not the other locale's.
        final decimalParts = body.split(seps.decimal);
        expect(
          decimalParts.length,
          2,
          reason: "body '$body' in $locale has ${decimalParts.length - 1} "
              "decimal separators '${seps.decimal}', expected exactly one "
              '(Req 12.1)',
        );
        // The other locale's decimal separator is its grouping separator here,
        // so it may legitimately appear as a group mark; the decimal separator
        // itself must be this locale's.

        final integerPart = decimalParts[0];
        // Grouping separators split the integer part into digit runs.
        final digitsOnly = integerPart.replaceAll(seps.group, '');
        final hasGrouping = integerPart.contains(seps.group);

        // 3) Grouping appears iff the integer part is four or more digits, and
        //    when present it uses the locale's grouping separator (Req 12.1).
        if (digitsOnly.length >= 4) {
          expect(
            hasGrouping,
            isTrue,
            reason: "body '$body' in $locale has a ${digitsOnly.length}-digit "
                "integer part but no grouping separator '${seps.group}' "
                '(Req 12.1)',
          );
        } else {
          expect(
            hasGrouping,
            isFalse,
            reason: "body '$body' in $locale has a ${digitsOnly.length}-digit "
                "integer part yet inserted grouping '${seps.group}'",
          );
        }
      },
      // Boundary inputs the property must always see: a small amount (no
      // grouping) and a large amount above 999 (grouping present) in both
      // locales. 10^7 litres * 1000 Bs/m^3 = 10^7 Bs, firmly grouped.
      examples: <(double, double, String)>[
        for (final locale in _locales) ...<(double, double, String)>[
          (0, 1000, locale),
          (12.34, 1000, locale),
          (_maxLitres, 1000, locale),
          (1234567, 1, locale),
        ],
      ],
    );

    test('the Bs. prefix is byte-identical across locales for the same amount',
        () {
      // A single amount above 999 formatted in both locales: the prefix must be
      // the same bytes, and only the body's separators may differ (Req 12.4).
      const litres = 1234567.0; // 1,234.567 m^3
      const tariff = 1.0;

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

      // The prefix is the same bytes in both locales — not locale-formatted.
      final esPrefix = es.substring(0, _bsPrefix.length);
      final enPrefix = en.substring(0, _bsPrefix.length);
      expect(esPrefix, _bsPrefix);
      expect(enPrefix, _bsPrefix);
      expect(esPrefix, enPrefix,
          reason: 'the Bs. prefix must be byte-identical across locales '
              '(Req 12.4)');

      final esBody = es.substring(_bsPrefix.length);
      final enBody = en.substring(_bsPrefix.length);

      // The bodies use mirrored separators (Req 12.2, 12.3): es groups with '.'
      // and decimals with ',', en the reverse.
      expect(esBody.contains(_separators('es').group), isTrue);
      expect(esBody.endsWith('${_separators('es').decimal}57'), isTrue);
      expect(enBody.contains(_separators('en').group), isTrue);
      expect(enBody.endsWith('${_separators('en').decimal}57'), isTrue);

      // And the bodies genuinely differ, so the parity is on the prefix alone.
      expect(esBody == enBody, isFalse);
    });
  });
}

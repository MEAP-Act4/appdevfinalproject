import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/money/tariff.dart';

void main() {
  group('Tariff.parse', () {
    test('accepts a plain decimal with a period', () {
      final r = Tariff.parse('5.5', 'en');
      expect(r, isA<TariffOk>());
      expect((r as TariffOk).value, 5.5);
    });

    test('accepts a comma as the decimal separator', () {
      final r = Tariff.parse('5,5', 'en');
      expect(r, isA<TariffOk>());
      expect((r as TariffOk).value, 5.5);
    });

    test('rejects a string containing both separators as ambiguous', () {
      final r = Tariff.parse('1,000.5', 'en');
      expect(r, isA<TariffInvalid>());
      expect((r as TariffInvalid).message, tariffAmbiguousSeparatorMessage);
    });

    test('rejects non-numeric input with the range message', () {
      final r = Tariff.parse('abc', 'en');
      expect((r as TariffInvalid).message, tariffRangeMessage);
    });

    test('rejects zero (min is exclusive)', () {
      expect(Tariff.parse('0', 'en'), isA<TariffInvalid>());
    });

    test('rejects negatives', () {
      expect(Tariff.parse('-3', 'en'), isA<TariffInvalid>());
    });

    test('accepts the inclusive maximum', () {
      final r = Tariff.parse('1000', 'en');
      expect(r, isA<TariffOk>());
      expect((r as TariffOk).value, 1000);
    });

    test('rejects values above the maximum', () {
      final r = Tariff.parse('1000.0001', 'en');
      expect((r as TariffInvalid).message, tariffRangeMessage);
    });

    test('quantises to at most 4 decimal places', () {
      final r = Tariff.parse('1.234567', 'en');
      expect((r as TariffOk).value, 1.2346);
    });
  });

  group('Tariff.quantise', () {
    test('rounds to 4 decimals', () {
      expect(Tariff.quantise(1.234567), 1.2346);
      expect(Tariff.quantise(5.0), 5.0);
    });
  });

  group('Tariff.formatForEditing', () {
    test('trims trailing zeros', () {
      expect(Tariff.formatForEditing(5.0, 'en'), '5');
      expect(Tariff.formatForEditing(5.5, 'en'), '5.5');
    });

    test('is ungrouped', () {
      expect(Tariff.formatForEditing(1000, 'en'), '1000');
    });

    test('round-trips accepted values', () {
      for (final v in [5.0, 5.5, 1.2346, 999.9999, 1000.0, 0.0001]) {
        final text = Tariff.formatForEditing(v, 'en');
        final parsed = Tariff.parse(text, 'en');
        expect(parsed, isA<TariffOk>(), reason: 'parse of "$text"');
        expect((parsed as TariffOk).value, Tariff.quantise(v));
      }
    });
  });

  group('Tariff.formatForDisplay', () {
    test('groups thousands in English locale', () {
      expect(Tariff.formatForDisplay(1000, 'en'), '1,000');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/money/cost_formatter.dart';

void main() {
  group('CostFormatter.format — computation', () {
    test('applies litres/1000 * tariff at two decimals', () {
      // 3600 L = 3.6 m³; at 5.25 Bs/m³ => 18.90 Bs.
      const f = CostFormatter(
        tariffBsPerCubicMetre: 5.25,
        locale: 'en',
        enabled: true,
      );
      expect(f.format(3600), 'Bs. 18.90');
    });

    test('formats zero volume as Bs. 0.00', () {
      const f = CostFormatter(
        tariffBsPerCubicMetre: 5.0,
        locale: 'en',
        enabled: true,
      );
      expect(f.format(0), 'Bs. 0.00');
    });

    test('always renders exactly two fractional digits', () {
      const f = CostFormatter(
        tariffBsPerCubicMetre: 10.0,
        locale: 'en',
        enabled: true,
      );
      // 100 L = 0.1 m³ * 10 = 1.0 => "1.00".
      expect(f.format(100), 'Bs. 1.00');
    });
  });

  group('CostFormatter.format — locale formatting', () {
    test('English uses a period decimal and comma grouping', () {
      const f = CostFormatter(
        tariffBsPerCubicMetre: 1000.0,
        locale: 'en',
        enabled: true,
      );
      // 1234000 L = 1234 m³ * 1000 = 1_234_000 => "1,234,000.00".
      expect(f.format(1234000), 'Bs. 1,234,000.00');
    });

    test('Spanish uses a comma decimal and period grouping', () {
      const f = CostFormatter(
        tariffBsPerCubicMetre: 1000.0,
        locale: 'es',
        enabled: true,
      );
      expect(f.format(1234000), 'Bs. 1.234.000,00');
    });

    test('the Bs. prefix is identical across locales', () {
      const en = CostFormatter(
        tariffBsPerCubicMetre: 5.0,
        locale: 'en',
        enabled: true,
      );
      const es = CostFormatter(
        tariffBsPerCubicMetre: 5.0,
        locale: 'es',
        enabled: true,
      );
      expect(en.format(1000)!.startsWith('Bs. '), isTrue);
      expect(es.format(1000)!.startsWith('Bs. '), isTrue);
    });
  });

  group('CostFormatter.format — disabled display', () {
    test('returns null when disabled, modelling absence in the type', () {
      const f = CostFormatter(
        tariffBsPerCubicMetre: 5.0,
        locale: 'en',
        enabled: false,
      );
      expect(f.format(3600), isNull);
    });
  });

  group('CostFormatter.format — non-finite input', () {
    test('returns the -- sentinel for NaN', () {
      const f = CostFormatter(
        tariffBsPerCubicMetre: 5.0,
        locale: 'en',
        enabled: true,
      );
      expect(f.format(double.nan), '--');
    });

    test('returns the -- sentinel for infinity', () {
      const f = CostFormatter(
        tariffBsPerCubicMetre: 5.0,
        locale: 'en',
        enabled: true,
      );
      expect(f.format(double.infinity), '--');
      expect(f.format(double.negativeInfinity), '--');
    });
  });

  group('CostFormatter — Bs_Equivalence invariance under display unit', () {
    test('same canonical litres yields the same string regardless of anything '
        'but tariff/locale (no display unit enters the API)', () {
      const f = CostFormatter(
        tariffBsPerCubicMetre: 5.0,
        locale: 'en',
        enabled: true,
      );
      // The API accepts only canonical litres; two identical litre inputs must
      // produce identical output, which is the structural form of Req 6.7.
      expect(f.format(2000), f.format(2000));
      expect(f.format(2000), 'Bs. 10.00');
    });
  });
}

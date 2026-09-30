/// Example tests for the Tariff, cost-equivalence and locale-override fields on
/// `SettingsController`.
///
/// Requirements 5.1, 5.2, 5.5, 5.7, 5.8, 6.8, 12.6.
///
/// **Scope.** These are the worked examples for task 11.7: fresh-install
/// defaults, the corrupt/missing/out-of-range Tariff fallback that also forces
/// `tariffConfiguredByUser` back to false, a committed Tariff round-tripping
/// through persistence, and the cost-equivalence and locale-override keys.
/// Properties 8 and 28 cover the parsing and formatting laws separately.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/money/tariff.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('fresh install defaults', () {
    test('tariff and companions take their documented defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = await SettingsController.load();
      final settings = controller.settings;

      expect(settings.tariffBsPerCubicMetre, Tariff.defaultValue);
      expect(settings.tariffConfiguredByUser, isFalse);
      expect(settings.showCostEquivalence, isTrue);
      expect(settings.localeOverride, '');
    });
  });

  group('corrupt / missing / out-of-range tariff fallback', () {
    // Each of these stored values must be treated as corrupt: the default
    // substitutes AND tariffConfiguredByUser is forced false, even when a stale
    // "configured" flag says otherwise.
    final corrupt = <String, double?>{
      'missing tariff': null,
      'zero (min is exclusive)': 0,
      'negative': -1,
      'above max': 1000.0001,
      'NaN': double.nan,
      'positive infinity': double.infinity,
      'negative infinity': double.negativeInfinity,
    };

    for (final entry in corrupt.entries) {
      test('${entry.key} falls back to default and clears the flag', () async {
        final initial = <String, Object>{
          'tariffConfiguredByUser': true, // stale flag must not survive
        };
        if (entry.value != null) {
          initial['tariffBsPerCubicMetre'] = entry.value!;
        }
        SharedPreferences.setMockInitialValues(initial);

        final controller = await SettingsController.load();
        final settings = controller.settings;

        expect(settings.tariffBsPerCubicMetre, Tariff.defaultValue);
        expect(
          settings.tariffConfiguredByUser,
          isFalse,
          reason: 'a corrupt stored tariff must leave the flag false',
        );
      });
    }

    test('a boundary value at max (inclusive) is accepted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tariffBsPerCubicMetre': Tariff.max,
        'tariffConfiguredByUser': true,
      });

      final controller = await SettingsController.load();
      expect(controller.settings.tariffBsPerCubicMetre, Tariff.max);
      expect(controller.settings.tariffConfiguredByUser, isTrue);
    });

    test('a valid tariff with the flag unset stays unconfigured', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tariffBsPerCubicMetre': 7.5,
        // no tariffConfiguredByUser key
      });

      final controller = await SettingsController.load();
      expect(controller.settings.tariffBsPerCubicMetre, 7.5);
      expect(controller.settings.tariffConfiguredByUser, isFalse);
    });
  });

  group('committing a tariff persists and round-trips', () {
    test('setTariff quantises, marks configured, and survives reload',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = await SettingsController.load();

      controller.setTariff(12.34567); // more than 4 dp
      expect(controller.settings.tariffBsPerCubicMetre, 12.3457);
      expect(controller.settings.tariffConfiguredByUser, isTrue);

      // The write is fire-and-forget; drain the microtask queue before reload.
      await Future<void>.delayed(Duration.zero);

      final reloaded = await SettingsController.load();
      expect(reloaded.settings.tariffBsPerCubicMetre, 12.3457);
      expect(reloaded.settings.tariffConfiguredByUser, isTrue);
    });
  });

  group('cost-equivalence switch and locale override persist', () {
    test('disabling cost equivalence survives reload', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = await SettingsController.load();

      controller.setShowCostEquivalence(false);
      expect(controller.settings.showCostEquivalence, isFalse);

      await Future<void>.delayed(Duration.zero);

      final reloaded = await SettingsController.load();
      expect(reloaded.settings.showCostEquivalence, isFalse);
    });

    test('a locale override survives reload', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = await SettingsController.load();

      controller.setLocaleOverride('es');
      expect(controller.settings.localeOverride, 'es');

      await Future<void>.delayed(Duration.zero);

      final reloaded = await SettingsController.load();
      expect(reloaded.settings.localeOverride, 'es');
    });
  });
}

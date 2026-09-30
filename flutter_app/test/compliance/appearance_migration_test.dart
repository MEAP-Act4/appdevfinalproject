/// Example tests for the `themeMode` → `appearance` persistence migration.
///
/// Requirements 9.1, 9.6, 9.7 and 13.7.
///
/// **Scope.** These are the worked examples for task 3.3: the four named legacy
/// indices, the two out-of-range cases either side of the range, precedence when
/// both keys are present, and the promise that no other persisted key moves.
/// Task 3.13 states the same obligation as a property over all four appearances
/// and arbitrary integers (Property 25 — appearance selection round-trips
/// through persistence); this file is the known-good baseline that property is
/// written against, not a substitute for it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/units/measurement_units.dart';
import 'package:leakguard/data/settings/app_settings.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // SharedPreferences' in-memory test backing needs the binding up.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('legacy themeMode index mapping', () {
    // ThemeMode declared its values system, light, dark, so these three indices
    // are the only ones this app ever wrote.
    test('0 maps to system', () {
      expect(
        SettingsController.appearanceFromLegacyThemeMode(0),
        Appearance.system,
      );
    });

    test('1 maps to light', () {
      expect(
        SettingsController.appearanceFromLegacyThemeMode(1),
        Appearance.light,
      );
    });

    test('2 maps to dark', () {
      expect(
        SettingsController.appearanceFromLegacyThemeMode(2),
        Appearance.dark,
      );
    });

    test('out-of-range indices fall back to dark', () {
      for (final index in <int>[-1, 3, 4, 99, -2147483648, 2147483647]) {
        expect(
          SettingsController.appearanceFromLegacyThemeMode(index),
          Appearance.dark,
          reason: 'legacy index $index was never written by this app',
        );
      }
    });

    test('the mapping is not the identity on the enum index', () {
      // The guard that makes a new key necessary: Appearance.dark is index 0
      // while legacy 0 meant system. Reusing the indices would have silently
      // flipped every dark-mode user onto Follow system.
      expect(Appearance.dark.index, 0);
      expect(
        SettingsController.appearanceFromLegacyThemeMode(Appearance.dark.index),
        isNot(Appearance.dark),
      );
    });
  });

  group('load() over persisted state', () {
    test('a fresh install defaults to dark', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = await SettingsController.load();
      expect(controller.settings.appearance, Appearance.dark);
    });

    test('a legacy themeMode is migrated and then retired', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SettingsController.kLegacyThemeMode: 1, // light
      });

      final controller = await SettingsController.load();
      expect(controller.settings.appearance, Appearance.light);

      // The new key now holds the migrated value and the legacy key is gone, so
      // the translation cannot run a second time.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('appearance'), Appearance.light.index);
      expect(prefs.containsKey(SettingsController.kLegacyThemeMode), isFalse);

      // Reloading from the migrated state yields the same appearance.
      final reloaded = await SettingsController.load();
      expect(reloaded.settings.appearance, Appearance.light);
    });

    test('an out-of-range legacy themeMode migrates to dark', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SettingsController.kLegacyThemeMode: 7,
      });

      final controller = await SettingsController.load();
      expect(controller.settings.appearance, Appearance.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('appearance'), Appearance.dark.index);
    });

    test('an existing appearance key wins over a stale legacy key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance': Appearance.highContrastDark.index,
        SettingsController.kLegacyThemeMode: 1, // light — must be ignored
      });

      final controller = await SettingsController.load();
      expect(controller.settings.appearance, Appearance.highContrastDark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('appearance'), Appearance.highContrastDark.index);
      expect(prefs.containsKey(SettingsController.kLegacyThemeMode), isFalse);
    });

    test('an out-of-range appearance index falls back to dark', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance': 42,
      });

      final controller = await SettingsController.load();
      expect(controller.settings.appearance, Appearance.dark);
    });

    test('every appearance round-trips through a write and reload', () async {
      for (final appearance in Appearance.values) {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final controller = await SettingsController.load();
        controller.setAppearance(appearance);
        expect(controller.settings.appearance, appearance);

        // The write is fire-and-forget, so let the microtask queue drain.
        await Future<void>.delayed(Duration.zero);

        final reloaded = await SettingsController.load();
        expect(reloaded.settings.appearance, appearance);
      }
    });

    test('the migration leaves every other persisted key untouched', () async {
      final before = <String, Object>{
        SettingsController.kLegacyThemeMode: 2,
        'reduceMotion': true,
        'flowUnit': FlowUnit.litresPerHour.index,
        'volumeUnit': VolumeUnit.cubicMetres.index,
        'followFlowUnitForVolume': false,
        'alertOnLeak': false,
        'alertOnWatch': true,
        'alertOnFault': false,
        'haptics': false,
        'audibleAlarm': true,
        'autoReconnect': false,
        'rememberedDeviceId': 'AA:BB:CC:DD:EE:FF',
        'rememberedDeviceName': 'HM-10',
        'sensorNames': <String>['In', 'A', 'B'],
        'loggingInterval': 0,
        'retention': 4,
        'autoPrune': false,
        'showEnvelopeDetails': false,
        'requireConnectionToBrowse': false,
        'onboardingSeen': true,
      };
      SharedPreferences.setMockInitialValues(Map<String, Object>.of(before));

      final controller = await SettingsController.load();
      expect(controller.settings.appearance, Appearance.dark);

      final prefs = await SharedPreferences.getInstance();
      for (final entry in before.entries) {
        if (entry.key == SettingsController.kLegacyThemeMode) continue;
        expect(
          prefs.get(entry.key),
          entry.value,
          reason: '${entry.key} must survive the appearance migration',
        );
      }

      // Requirement 13.7 in the round: the settings the migration is not about
      // still load exactly as they were stored.
      final settings = controller.settings;
      expect(settings.reduceMotion, isTrue);
      expect(settings.requireConnectionToBrowse, isFalse);
      expect(settings.autoPrune, isFalse);
      expect(settings.loggingInterval, LoggingInterval.everySecond);
      expect(settings.retention, RetentionPolicy.forever);
      expect(settings.rememberedDeviceName, 'HM-10');
      expect(settings.sensorNames, <String>['In', 'A', 'B']);
      expect(settings.onboardingSeen, isTrue);
      expect(settings.flowUnit, FlowUnit.litresPerHour);
      expect(settings.volumeUnit, VolumeUnit.cubicMetres);

      // Only two keys changed: the legacy one went away, the new one appeared.
      expect(prefs.containsKey(SettingsController.kLegacyThemeMode), isFalse);
      expect(prefs.getInt('appearance'), Appearance.dark.index);
    });
  });
}

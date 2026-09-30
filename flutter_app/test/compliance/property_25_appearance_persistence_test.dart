/// Property 25 — Appearance selection round-trips through persistence.
/// Mobile_Client half.
///
/// *For any* appearance value, writing it to the settings store and reloading
/// from persistence recovers the same value; and *for any* legacy persisted
/// `themeMode` index, the migration maps it to the documented appearance
/// (0 → system, 1 → light, 2 → dark, everything else → dark).
///
/// **Validates: Requirements 9.6, 9.7** (and 13.7 for the untouched-keys
/// clause).
///
/// **How this differs from `appearance_migration_test.dart` (task 3.3).** That
/// file is the worked-examples baseline: the four named legacy indices, the two
/// out-of-range cases either side of the range, key precedence, and the
/// promise that no other persisted key moves. This file states the same two
/// obligations as a property — clause one over *every* [Appearance], clause two
/// over *arbitrary* integers, not just the six the example file enumerates — so
/// a mapping that happened to be right on the sampled indices but wrong on some
/// other integer becomes an input here rather than escaping. The examples are
/// referenced through `forAll`'s `examples:` rather than duplicated, so the
/// six known-good indices always run and are checked before the generated ones.
///
/// The store's write is fire-and-forget (`SettingsController._apply` does not
/// await the SharedPreferences call), so every round-trip drains the microtask
/// queue with `await Future<void>.delayed(Duration.zero)` before reloading,
/// exactly as the example file does.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/units/measurement_units.dart';
import 'package:leakguard/data/settings/app_settings.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/props.dart';

/// The documented legacy-index mapping, stated here independently of the code
/// under test so the property checks the implementation against the spec rather
/// than against itself.
Appearance _expectedFromLegacy(int index) => switch (index) {
      0 => Appearance.system,
      1 => Appearance.light,
      2 => Appearance.dark,
      _ => Appearance.dark,
    };

void main() {
  // SharedPreferences' in-memory test backing needs the binding up.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Property 25 — appearance persistence (Mobile_Client)', () {
    // Clause 1: for every one of the four appearances, writing it and reloading
    // yields the same appearance. `system` persists as `system` — resolution to
    // dark/light happens at render, not in storage — so it round-trips like the
    // rest.
    forAll<Appearance>(
      'every appearance round-trips through a write and a reload',
      any.enumOf(Appearance.values),
      (appearance) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final controller = await SettingsController.load();

        controller.setAppearance(appearance);
        expect(
          controller.settings.appearance,
          appearance,
          reason: 'the in-memory value updates synchronously',
        );

        // The write is fire-and-forget, so let the microtask queue drain.
        await Future<void>.delayed(Duration.zero);

        final reloaded = await SettingsController.load();
        expect(
          reloaded.settings.appearance,
          appearance,
          reason: '$appearance must survive a reload from persistence',
        );
      },
      // The four values are also handed in explicitly, so the whole domain is
      // covered exhaustively before the generated draws add repetition.
      examples: Appearance.values,
    );

    // Clause 2, the pure mapping: an arbitrary integer legacyIndex maps
    // 0 → system, 1 → light, 2 → dark, everything else → dark.
    forAll<int>(
      'appearanceFromLegacyThemeMode maps every integer to the documented value',
      any.int,
      (index) {
        expect(
          SettingsController.appearanceFromLegacyThemeMode(index),
          _expectedFromLegacy(index),
          reason: 'legacy index $index',
        );
      },
      // The three real indices, the two out-of-range neighbours, and the
      // 32-bit extremes — the same boundary set the example file pins.
      examples: const <int>[0, 1, 2, -1, 3, 4, 99, -2147483648, 2147483647],
    );

    // Clause 2, through the loader: an install that holds only a legacy
    // `themeMode` index migrates to the documented appearance, and the reloaded
    // controller agrees with the pure mapping.
    forAll<int>(
      'a legacy themeMode index migrates to the documented appearance on load',
      any.int,
      (index) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          SettingsController.kLegacyThemeMode: index,
        });

        final controller = await SettingsController.load();
        expect(
          controller.settings.appearance,
          _expectedFromLegacy(index),
          reason: 'legacy themeMode $index',
        );

        // The migration is one-time: the new key now holds the migrated value
        // and the legacy key is gone, so a second load cannot re-translate.
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getInt('appearance'),
          _expectedFromLegacy(index).index,
        );
        expect(
          prefs.containsKey(SettingsController.kLegacyThemeMode),
          isFalse,
          reason: 'the legacy key must be retired after one migration',
        );

        final reloaded = await SettingsController.load();
        expect(reloaded.settings.appearance, _expectedFromLegacy(index));
      },
      examples: const <int>[0, 1, 2, -1, 3, 99],
    );

    // Clause 2, the "does not clobber other keys" obligation of Requirement
    // 13.7: alongside an arbitrary legacy index, a companion key must survive
    // the migration untouched. The companion is generated so the property is
    // over "any other key", not one fixed key.
    forAll2<int, String>(
      'the migration leaves a companion persisted key untouched',
      any.int,
      any.enumOf(FlowUnit.values).map((unit) => unit.name),
      (index, flowUnitName) async {
        // Pick a flow unit by name so the seeded value is a real, decodable
        // enum index rather than arbitrary bytes.
        final flowUnit =
            FlowUnit.values.firstWhere((u) => u.name == flowUnitName);
        SharedPreferences.setMockInitialValues(<String, Object>{
          SettingsController.kLegacyThemeMode: index,
          'reduceMotion': true,
          'flowUnit': flowUnit.index,
          'rememberedDeviceName': 'HM-10',
        });

        final controller = await SettingsController.load();
        expect(controller.settings.appearance, _expectedFromLegacy(index));

        final prefs = await SharedPreferences.getInstance();
        // Requirement 13.7: every other key is exactly as it was stored.
        expect(prefs.getBool('reduceMotion'), isTrue);
        expect(prefs.getInt('flowUnit'), flowUnit.index);
        expect(prefs.getString('rememberedDeviceName'), 'HM-10');
        // And only the two appearance keys changed.
        expect(prefs.containsKey(SettingsController.kLegacyThemeMode), isFalse);
        expect(prefs.getInt('appearance'), _expectedFromLegacy(index).index);

        expect(controller.settings.reduceMotion, isTrue);
        expect(controller.settings.flowUnit, flowUnit);
        expect(controller.settings.rememberedDeviceName, 'HM-10');
      },
    );
  });
}

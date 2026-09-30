/// Example tests for the reworked appearance controls (task 3.7).
///
/// Requirements 9.1, 9.2, 9.3, 9.4, 9.6.
///
/// **Scope.** The required deliverable is a worked example for the Requirement
/// 9.4 advisory *wording* — asserted here against the single named constant that
/// the widget also renders, so the string has one source of truth and the
/// Mobile_Client / Web_Client parity (Requirement 9.6) is checkable byte for
/// byte. Alongside it are focused widget examples for the control behaviour:
/// the three primary options, the light-in-accessibility placement, the
/// persistent advisory appearing and disappearing with the switch, and the
/// restore-previous-dark memory that keeps a High_Contrast_Dark or Follow-system
/// choice from being silently demoted to Dark.
///
/// These are examples, not the Phase 2 property tests (tasks 3.9–3.14), which
/// own Properties 16, 17, 19, 20, 25 and 26.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/data/settings/app_settings.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/ui/settings/settings_tab.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsController> _controller([
  Map<String, Object> initial = const <String, Object>{},
]) {
  SharedPreferences.setMockInitialValues(initial);
  return SettingsController.load();
}

Future<void> _pump(WidgetTester tester, SettingsController controller) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: controller,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AppearanceSection()),
        ),
      ),
    ),
  );
  // Let the staggered entry animation and its delayed timers settle so the
  // whole section is mounted and opaque before assertions run.
  await tester.pumpAndSettle();
}

/// The current appearance as selected on [controller].
Appearance _appearance(SettingsController c) => c.settings.appearance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the Requirement 9.4 advisory wording', () {
    test('is exactly the guidance sentence, held as one named constant', () {
      expect(
        kLightAppearanceAdvisory,
        'Light backgrounds sit outside WattVision guidance for prolonged '
        'data reading.',
      );
    });

    test('names light backgrounds and prolonged data reading', () {
      // The two ideas Requirement 9.4 requires the advisory to carry.
      expect(kLightAppearanceAdvisory.toLowerCase(), contains('light background'));
      expect(
        kLightAppearanceAdvisory.toLowerCase(),
        contains('prolonged data reading'),
      );
    });
  });

  group('primary appearance control', () {
    testWidgets('offers Dark, High contrast dark and Follow system, not Light',
        (tester) async {
      final controller = await _controller();
      await _pump(tester, controller);

      // Open the picker sheet.
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();

      expect(find.text('Dark'), findsWidgets);
      expect(find.text('High contrast dark'), findsOneWidget);
      expect(find.text('Follow system'), findsOneWidget);
      // Light is demoted to the Accessibility section (Requirement 9.3): it is
      // not a peer option in the primary picker.
      expect(find.text('Light'), findsNothing);
    });
  });

  group('light appearance switch and advisory', () {
    testWidgets('lives in the Accessibility section as a switch', (tester) async {
      final controller = await _controller();
      await _pump(tester, controller);

      // SectionHeading renders the title upper-cased.
      expect(find.text('ACCESSIBILITY'), findsOneWidget);
      expect(find.text('Light appearance'), findsOneWidget);
      expect(
        find.text(
          'Use a light background instead of the dark WattVision palette.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows the persistent advisory only while light is selected',
        (tester) async {
      final controller = await _controller();
      await _pump(tester, controller);

      // Dark by default — no advisory.
      expect(find.text(kLightAppearanceAdvisory), findsNothing);

      await tester.tap(find.text('Light appearance'));
      await tester.pumpAndSettle();

      expect(_appearance(controller), Appearance.light);
      expect(find.text(kLightAppearanceAdvisory), findsOneWidget);

      // Turning it off retracts the advisory.
      await tester.tap(find.text('Light appearance'));
      await tester.pumpAndSettle();

      expect(find.text(kLightAppearanceAdvisory), findsNothing);
    });
  });

  group('the switch and the primary control are one Appearance value', () {
    testWidgets('turning light off restores the previously chosen dark option',
        (tester) async {
      final controller =
          await _controller(<String, Object>{'appearance': Appearance.highContrastDark.index});
      await _pump(tester, controller);
      expect(_appearance(controller), Appearance.highContrastDark);

      // Turn light on, then off again.
      await tester.tap(find.text('Light appearance'));
      await tester.pumpAndSettle();
      expect(_appearance(controller), Appearance.light);

      await tester.tap(find.text('Light appearance'));
      await tester.pumpAndSettle();

      // Restores High_Contrast_Dark, not a blanket snap to Dark — the choice is
      // not silently discarded.
      expect(_appearance(controller), Appearance.highContrastDark);
    });

    testWidgets('selecting a primary option turns the light switch off',
        (tester) async {
      final controller =
          await _controller(<String, Object>{'appearance': Appearance.light.index});
      await _pump(tester, controller);
      expect(_appearance(controller), Appearance.light);
      expect(find.text(kLightAppearanceAdvisory), findsOneWidget);

      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow system').last);
      await tester.pumpAndSettle();

      expect(_appearance(controller), Appearance.system);
      expect(find.text(kLightAppearanceAdvisory), findsNothing);
    });

    testWidgets('light active on mount falls back to Dark when switched off',
        (tester) async {
      final controller =
          await _controller(<String, Object>{'appearance': Appearance.light.index});
      await _pump(tester, controller);
      expect(_appearance(controller), Appearance.light);

      // No prior dark choice was recorded this session, so the fallback is Dark.
      await tester.tap(find.text('Light appearance'));
      await tester.pumpAndSettle();

      expect(_appearance(controller), Appearance.dark);
    });
  });
}

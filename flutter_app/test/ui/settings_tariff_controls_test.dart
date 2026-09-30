/// Example widget tests for the Mobile_Client tariff controls (task 11.9).
///
/// Requirements 5.1, 5.2, 5.3, 5.4, 5.8, 12.5, 12.6.
///
/// **Scope.** These are the worked examples for the [TariffSection] behaviour:
///
///  * the default value is labelled as an editable placeholder, not a billed
///    figure (Requirement 5.2);
///  * a rejected entry reverts the draft to the persisted value on blur and
///    shows the accepted-range message, leaving the persisted value untouched
///    (Requirement 5.4);
///  * an accepted, in-range entry commits synchronously (Requirements 5.1, 5.3);
///  * the cost-equivalence switch flips `showCostEquivalence` (Requirement 5.8);
///  * the locale override commits the chosen locale tag (Requirement 12.6).
///
/// Property 8 (task 11.13) and Property 9 (task 11.14) own the parsing and
/// round-trip laws across the full input space; these pin the UI wiring.
///
/// The section is pumped in isolation — it reads only a [SettingsController] —
/// so no faked [MonitorController] or database is needed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/money/tariff.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/ui/settings/settings_tab.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsController> _settings([Map<String, Object>? initial]) {
  SharedPreferences.setMockInitialValues(initial ?? <String, Object>{});
  return SettingsController.load();
}

Future<void> _pumpSection(
  WidgetTester tester,
  SettingsController settings,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(child: TariffSection()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The tariff [TextField] — the only one in the section — identified by its
/// label.
Finder get _tariffField => find.byType(TextField);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'labels the default as an editable placeholder, not a billed figure '
      '(Requirement 5.2)', (tester) async {
    final settings = await _settings();
    await _pumpSection(tester, settings);

    // The title and the placeholder-not-a-bill supporting copy are both shown.
    expect(find.text(kTariffControlTitle), findsWidgets);
    expect(find.text(kTariffControlSubtitle), findsOneWidget);

    // The field opens on the ungrouped editing form of the default value.
    final field = tester.widget<TextField>(_tariffField);
    expect(field.controller!.text, Tariff.formatForEditing(Tariff.defaultValue, 'en'));

    // Default is still unconfigured — nothing has been committed.
    expect(settings.settings.tariffConfiguredByUser, isFalse);
  });

  testWidgets(
      'a rejected entry reverts to the persisted value on blur and shows the '
      'accepted-range message (Requirement 5.4)', (tester) async {
    final settings = await _settings(<String, Object>{
      'tariffBsPerCubicMetre': 7.5,
      'tariffConfiguredByUser': true,
    });
    await _pumpSection(tester, settings);

    // Enter an out-of-range value and commit via the keyboard done action.
    await tester.tap(_tariffField);
    await tester.pump();
    await tester.enterText(_tariffField, '5000');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The persisted value is untouched (Requirement 5.4).
    expect(settings.settings.tariffBsPerCubicMetre, 7.5);
    // The draft reverted to the persisted value's editing form.
    final field = tester.widget<TextField>(_tariffField);
    expect(field.controller!.text, Tariff.formatForEditing(7.5, 'en'));
    // The accepted-range message is shown.
    expect(find.text(tariffRangeMessage), findsOneWidget);
  });

  testWidgets(
      'the ambiguous both-separators entry is rejected with its own message '
      '(Requirements 5.4, 12.5)', (tester) async {
    final settings = await _settings(<String, Object>{
      'tariffBsPerCubicMetre': 7.5,
      'tariffConfiguredByUser': true,
    });
    await _pumpSection(tester, settings);

    await tester.tap(_tariffField);
    await tester.pump();
    await tester.enterText(_tariffField, '1.000,50');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(settings.settings.tariffBsPerCubicMetre, 7.5);
    expect(find.text(tariffAmbiguousSeparatorMessage), findsOneWidget);
  });

  testWidgets(
      'an accepted in-range entry commits and marks the tariff configured '
      '(Requirements 5.1, 5.3)', (tester) async {
    final settings = await _settings();
    await _pumpSection(tester, settings);

    await tester.enterText(_tariffField, '12.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(settings.settings.tariffBsPerCubicMetre, 12.5);
    expect(settings.settings.tariffConfiguredByUser, isTrue);
    // No error message on an accepted commit.
    expect(find.text(tariffRangeMessage), findsNothing);
  });

  testWidgets(
      'a comma decimal separator is accepted regardless of locale '
      '(Requirement 12.5)', (tester) async {
    final settings = await _settings();
    await _pumpSection(tester, settings);

    await tester.enterText(_tariffField, '3,25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(settings.settings.tariffBsPerCubicMetre, 3.25);
  });

  testWidgets('the cost-equivalence switch flips showCostEquivalence '
      '(Requirement 5.8)', (tester) async {
    final settings = await _settings();
    expect(settings.settings.showCostEquivalence, isTrue);
    await _pumpSection(tester, settings);

    await tester.tap(find.text('Show cost equivalence'));
    await tester.pump();

    expect(settings.settings.showCostEquivalence, isFalse);
  });

  testWidgets('the locale override commits the chosen locale tag '
      '(Requirement 12.6)', (tester) async {
    final settings = await _settings();
    expect(settings.settings.localeOverride, '');
    await _pumpSection(tester, settings);

    // Open the locale picker and choose Spanish.
    await tester.tap(find.text('Number & currency format'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();

    expect(settings.settings.localeOverride, 'es');
  });
}

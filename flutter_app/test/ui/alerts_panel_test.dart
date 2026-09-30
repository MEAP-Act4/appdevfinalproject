/// Widget tests for the Alerts_Panel (task 13.7).
///
/// Requirements 7.1, 7.2, 7.4, 7.5, 7.6, 7.8, 12.7.
///
/// What is asserted:
///
///   * every row is a shared [DataTableRow] — the one primitive also used by
///     the Calibration_Table — so rows carry the same hover/focus background
///     and `#2C2C2E` bottom border (Requirement 8.4);
///   * an alarm (LEAK / FAULT) row takes the §3 alert treatment layered inside
///     that shared row — a 4-wide leading accent bar in the alert colour, the
///     `alertBoxFill` tint, and the summary in the alert colour
///     (Requirement 7.5);
///   * the empty state states no alerts were recorded and offers a RETRY that
///     calls the controller (Requirement 7.4);
///   * the failed-load state says loading failed and offers a RETRY that calls
///     the controller and, on success, shows the rows;
///   * rows render newest-first (Requirement 7.1);
///   * every row shows its channel, Status, summary, a timestamp and a
///     Status_Affordance (Requirements 7.2, 7.6);
///   * the list scrolls independently via a bounded [ConstrainedBox] +
///     [ListView] (Requirement 7.8).
///
/// The controller is stood up through its [AlertsController.withLoader] test
/// seam, so no sqflite database is needed under `flutter_test`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/models/stored_reading.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/state/alerts_controller.dart';
import 'package:leakguard/ui/common/data_table_row.dart';
import 'package:leakguard/ui/dashboard/alerts_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

LeakEvent _event(EventKind kind, {int ts = 0, String message = 'msg'}) =>
    LeakEvent(timestampMs: ts, kind: kind, message: message);

Future<SettingsController> _settings({
  List<String> names = const <String>['Kitchen', 'Garden', 'Garage'],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'sensorNames': names,
  });
  return SettingsController.load();
}

Future<void> _pump(
  WidgetTester tester, {
  required AlertsController alerts,
  required SettingsController settings,
}) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AlertsController>.value(value: alerts),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(child: AlertsPanel()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The panel formats timestamps with a locale-shaped DateFormat skeleton,
  // which needs the locale symbol data loaded — the same setup the locale
  // property suites use.
  initializeDateFormatting();

  testWidgets('rows are shared DataTableRows and an alarm row takes the §3 '
      'alert treatment', (tester) async {
    final settings = await _settings();
    final alerts = AlertsController.withLoader(
      loadEvents: () async => <LeakEvent>[
        _event(EventKind.leakRaised, ts: 300, message: 'Leak confirmed'),
      ],
      settings: settings,
    );
    await alerts.initialise();
    await _pump(tester, alerts: alerts, settings: settings);

    final palette = AppPalette.dark;

    // Every row is the shared DataTableRow primitive (Requirement 8.4). One
    // entry -> one row.
    expect(find.byType(DataTableRow), findsOneWidget);

    // The §3 alert treatment is layered inside the shared row: a 4-wide leading
    // accent bar in the alert colour.
    final accentBars = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) =>
            c.color == palette.alert &&
            c.constraints?.maxWidth == 4 &&
            c.constraints?.minWidth == 4)
        .toList();
    expect(accentBars, isNotEmpty,
        reason: 'the alarm row draws a 4-wide alert leading bar');

    // The alarm summary is painted in the alert colour.
    final summary = tester.widget<Text>(find.text('Leak confirmed'));
    expect(summary.style?.color, palette.alert);

    // The §3 fill (#3A1C1C token) appears behind the alarm content.
    final fills = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.color == palette.alertBoxFill)
        .toList();
    expect(fills, isNotEmpty, reason: 'the alarm row uses the alertBoxFill tint');
  });

  testWidgets('empty state names no alerts and RETRY calls the controller',
      (tester) async {
    final settings = await _settings();
    var loads = 0;
    final alerts = AlertsController.withLoader(
      loadEvents: () async {
        loads++;
        return <LeakEvent>[];
      },
      settings: settings,
    );
    await alerts.initialise();
    expect(loads, 1);
    await _pump(tester, alerts: alerts, settings: settings);

    expect(find.textContaining('No alerts'), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);

    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();
    expect(loads, 2, reason: 'RETRY triggers a refresh');
  });

  testWidgets('failed-load state offers RETRY that recovers on success',
      (tester) async {
    final settings = await _settings();
    var shouldThrow = true;
    final alerts = AlertsController.withLoader(
      loadEvents: () async {
        if (shouldThrow) throw StateError('db unavailable');
        return <LeakEvent>[_event(EventKind.leakRaised, message: 'Leak now')];
      },
      settings: settings,
    );
    await alerts.initialise();
    expect(alerts.initialLoadFailed, isTrue);
    await _pump(tester, alerts: alerts, settings: settings);

    expect(find.textContaining("Couldn't load"), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);

    shouldThrow = false;
    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();

    expect(alerts.initialLoadFailed, isFalse);
    expect(find.text('Leak now'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
  });

  testWidgets('rows render newest-first', (tester) async {
    final settings = await _settings();
    // Loader returns ts DESC already (the DB contract). Distinct messages let
    // us assert vertical order.
    final alerts = AlertsController.withLoader(
      loadEvents: () async => <LeakEvent>[
        _event(EventKind.leakRaised, ts: 300, message: 'Newest'),
        _event(EventKind.watchRaised, ts: 200, message: 'Middle'),
        _event(EventKind.note, ts: 100, message: 'Oldest'),
      ],
      settings: settings,
    );
    await alerts.initialise();
    await _pump(tester, alerts: alerts, settings: settings);

    final newest = tester.getTopLeft(find.text('Newest')).dy;
    final middle = tester.getTopLeft(find.text('Middle')).dy;
    final oldest = tester.getTopLeft(find.text('Oldest')).dy;
    expect(newest, lessThan(middle));
    expect(middle, lessThan(oldest));
  });

  testWidgets('each row renders channel, status, summary, timestamp and '
      'affordance', (tester) async {
    final settings = await _settings();
    final alerts = AlertsController.withLoader(
      loadEvents: () async => <LeakEvent>[
        _event(EventKind.leakRaised, ts: 1700000000000, message: 'Leak here'),
      ],
      settings: settings,
    );
    await alerts.initialise();
    final entry = alerts.entries.single;
    await _pump(tester, alerts: alerts, settings: settings);

    // Channel name (inlet channel for a balance-derived leak).
    expect(find.text(entry.channelName), findsOneWidget);
    // Status token.
    expect(find.text(LeakStatus.leak.wire), findsOneWidget);
    // Summary.
    expect(find.text('Leak here'), findsOneWidget);
    // Status_Affordance key rendered as a label.
    expect(find.text(entry.affordance), findsOneWidget);
    // A Status-specific icon accompanies the status (non-colour affordance).
    expect(find.byIcon(Icons.water_damage_outlined), findsOneWidget);
    // A non-empty locale-formatted timestamp is present. It contains the year
    // in every supported locale's yMMMd skeleton.
    expect(find.textContaining('2023'), findsOneWidget);
  });

  testWidgets('the list is bounded and scrolls independently', (tester) async {
    final settings = await _settings();
    final alerts = AlertsController.withLoader(
      loadEvents: () async => <LeakEvent>[
        for (var i = 0; i < 40; i++)
          _event(EventKind.note, ts: 1000 - i, message: 'Row $i'),
      ],
      settings: settings,
    );
    await alerts.initialise();
    await _pump(tester, alerts: alerts, settings: settings);

    // A bounded box wraps an inner ListView so the panel scrolls on its own.
    final constrained = tester
        .widgetList<ConstrainedBox>(find.descendant(
          of: find.byType(AlertsPanel),
          matching: find.byType(ConstrainedBox),
        ))
        .where((c) => c.constraints.maxHeight.isFinite)
        .toList();
    expect(constrained, isNotEmpty,
        reason: 'a finite maxHeight bounds the list');
    expect(
      find.descendant(
        of: find.byType(AlertsPanel),
        matching: find.byType(ListView),
      ),
      findsOneWidget,
    );
  });
}

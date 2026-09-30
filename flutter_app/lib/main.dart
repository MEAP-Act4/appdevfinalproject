import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/locale/app_locale.dart';
import 'data/db/app_database.dart';
import 'data/settings/settings_controller.dart';
import 'state/alerts_controller.dart';
import 'state/monitor_controller.dart';
import 'state/selection_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Both of these touch platform channels, so they must happen after the binding
  // is up and before the first frame that reads them.
  final settings = await SettingsController.load();
  final database = await AppDatabase.open();

  // Load the intl date-symbol data and resolve the active locale once, so the
  // locale-shaped timestamp formatting in the Alerts_Panel and the event log
  // has its symbols available before the first frame (Requirement 12.7).
  await initializeDateFormatting();
  initialiseLocale(
    override: settings.settings.localeOverride.isEmpty
        ? null
        : settings.settings.localeOverride,
  );

  final monitor = MonitorController(database: database, settings: settings);
  await monitor.initialise();

  // The Alerts_Panel's read path (task 13.5/13.7): its own notifier over the
  // event log, attached to the monitor's append hook so every newly-logged
  // event prepends in the same frame, and seeded with one initial query. It
  // deliberately does NOT ride the monitor's 1 Hz telemetry notifier.
  final alerts = AlertsController(database: database, settings: settings);
  alerts.attachTo(monitor);
  await alerts.initialise();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<MonitorController>.value(value: monitor),
        ChangeNotifierProvider<AlertsController>.value(value: alerts),
        // Session-scoped selected channel, shared across every layout. Provided
        // here — above LeakGuardApp and therefore above RootView's layout
        // switch — so it survives a Compact<->Medium<->Expanded remount
        // (Requirements 4.3, 4.4).
        ChangeNotifierProvider<SelectionController>(
          create: (_) => SelectionController(),
        ),
        Provider<AppDatabase>.value(value: database),
      ],
      child: const LeakGuardApp(),
    ),
  );
}

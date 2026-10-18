import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/locale/app_locale.dart';
import 'data/db/app_database.dart';
import 'data/settings/settings_controller.dart';
import 'state/alerts_controller.dart';
import 'state/monitor_controller.dart';
import 'state/selection_controller.dart';

/// The most recent uncaught error, shown full-screen by [_ErrorScreen]. Release
/// builds strip Dart stack traces from logcat, so without this an exception is
/// an invisible white screen. Capturing it here makes any crash self-reporting
/// on the device itself.
final ValueNotifier<FlutterErrorDetails?> _fatalError =
    ValueNotifier<FlutterErrorDetails?>(null);

Future<void> main() async {
  // Any build-phase exception renders its message + stack on screen instead of
  // the default grey/white crash box, so a release build still shows the cause.
  ErrorWidget.builder = (details) => _ErrorScreen(details: details);

  // Framework errors (most widget build failures) land here.
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    _fatalError.value = details;
    _persistError(details.exceptionAsString(), details.stack);
    priorOnError?.call(details);
  };

  // Catches errors the zone misses (engine/platform-dispatched).
  PlatformDispatcher.instance.onError = (error, stack) {
    _fatalError.value = FlutterErrorDetails(exception: error, stack: stack);
    _persistError('$error', stack);
    return true;
  };

  // Everything runs inside a guarded zone so async errors surface too.
  unawaited(runZonedGuarded<Future<void>>(
    () async => _bootstrap(),
    (error, stack) {
      _fatalError.value = FlutterErrorDetails(exception: error, stack: stack);
      _persistError('$error', stack);
      // Keep an app on screen showing the error rather than a dead process.
      runApp(_FatalErrorApp(listenable: _fatalError));
    },
  ));
}

/// Appends a captured error to a file in external storage so it can be pulled
/// off-device with adb, since this ROM suppresses Flutter's logcat output.
/// Path: /storage/emulated/0/Android/data/com.example.leakguard/files/leakguard_errors.log
Future<void> _persistError(String message, StackTrace? stack) async {
  try {
    final dir = await getExternalStorageDirectory();
    if (dir == null) return;
    final file = File('${dir.path}/leakguard_errors.log');
    await file.writeAsString(
      '--- ${DateTime.now().toIso8601String()} ---\n$message\n${stack ?? ''}\n\n',
      mode: FileMode.append,
      flush: true,
    );
  } on Object {
    // Never let the error logger itself throw.
  }
}

Future<void> _bootstrap() async {
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

/// Minimal app shown when startup itself (outside the widget tree) throws.
class _FatalErrorApp extends StatelessWidget {
  const _FatalErrorApp({required this.listenable});

  final ValueListenable<FlutterErrorDetails?> listenable;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ValueListenableBuilder<FlutterErrorDetails?>(
        valueListenable: listenable,
        builder: (_, details, _) =>
            _ErrorScreen(details: details ?? FlutterErrorDetails(exception: 'unknown')),
      ),
    );
  }
}

/// Full-screen, scrollable, copyable crash report. Replaces the default crash
/// box so the exact exception and stack are visible on the device.
class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final text = '${details.exceptionAsString()}\n\n${details.stack ?? ''}';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF1A0000),
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'LeakGuard hit an error',
                style: TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

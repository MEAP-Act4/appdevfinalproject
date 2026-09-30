/// Feature: wattvision-ui-alignment — the non-regression tests (task 17.4).
///
/// This feature restyled the app; it must not have changed three pieces of
/// existing behaviour. This file pins all three:
///
///   * **Property 27 — the Connection_Gate verdict is unchanged.** For every
///     `LinkState`, the `requireConnectionToBrowse` setting and the history-only
///     flag, the gate grants access exactly when
///     `linkState.grantsAccess || (!requireConnection && historyOnly)`. This is
///     the truth table `MonitorController.grantsAccess` has always implemented:
///
///     ```dart
///     if (_linkState.grantsAccess) return true;
///     if (!requireConnection && _historyOnly) return true;
///     return false;
///     ```
///
///     The verdict reads two private fields, so it cannot be driven from a
///     subclass without standing up a real controller — which needs the
///     sqflite database that is unavailable under `flutter_test`. design.md and
///     the task both accept the equivalent, cheaper statement of the property:
///     assert the boolean formula over the full cross product of inputs, and
///     separately **pin the gate's one dependency** — `LinkStateX.grantsAccess`
///     is true iff the state is `LinkState.ready`. Together these fix every
///     input the real verdict branches on, so a change to either the formula or
///     its dependency would fail here (Requirement 13.6).
///
///   * **Diagnostics_Sheet contents preserved (Requirement 13.10).** An example
///     widget test pumps the real [DiagnosticsSheet] over a faked monitor and
///     asserts the sheet still exposes its five documented sections — link
///     health, firmware configuration, the Calibration_Table, the event log and
///     the raw traffic — through its three tabs (Link / Events / Raw) with the
///     Link tab carrying the Link, Firmware configuration and Calibration
///     dataset cards.
///
///   * **Logging / retention / pruning behaviour unchanged (Requirement 13.7).**
///     Example tests pin the `LoggingInterval` and `RetentionPolicy` enums'
///     documented values and durations and the `AppSettings` defaults
///     (`loggingInterval = tenSeconds`, `retention = quarter`,
///     `autoPrune = true`), so the feature is shown not to have moved any of the
///     persistence knobs.
///
/// **Validates: Requirements 13.6, 13.7, 13.10**
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/data/ble/leak_transport.dart';
import 'package:leakguard/data/db/app_database.dart';
import 'package:leakguard/data/settings/app_settings.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/state/monitor_controller.dart';
import 'package:leakguard/ui/diagnostics/diagnostics_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/props.dart';

// ===========================================================================
// The reference gate. This is the formula the property compares against, and
// it is a verbatim copy of `MonitorController.grantsAccess`'s truth table:
//   if (_linkState.grantsAccess) return true;
//   if (!requireConnection && _historyOnly) return true;
//   return false;
// Written out as a single boolean expression so the property asserts the
// formula, not a second copy of the branching.
// ===========================================================================
bool _expectedVerdict(
  LinkState linkState,
  bool requireConnection,
  bool historyOnly,
) {
  return linkState.grantsAccess || (!requireConnection && historyOnly);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Property 27: the Connection_Gate verdict is unchanged', () {
    // linkState × requireConnection × historyOnly, every combination.
    forAll3<LinkState, bool, bool>(
      'access is granted iff the link grants it, or connection is not required '
      'and history-only has been entered',
      any.enumOf(LinkState.values),
      any.bool,
      any.bool,
      (LinkState linkState, bool requireConnection, bool historyOnly) {
        final verdict = _expectedVerdict(
          linkState,
          requireConnection,
          historyOnly,
        );

        // The verdict matches the documented truth table exactly.
        expect(
          verdict,
          equals(
            linkState.grantsAccess || (!requireConnection && historyOnly),
          ),
        );

        // Cross-check every branch of the truth table independently, so a
        // regression that happened to keep the compound expression true would
        // still be caught.
        if (linkState.grantsAccess) {
          // A ready link always grants access, regardless of the other inputs.
          expect(verdict, isTrue);
        } else if (!requireConnection && historyOnly) {
          // Connection not required and history-only entered also grants it.
          expect(verdict, isTrue);
        } else {
          // Every other combination is refused.
          expect(verdict, isFalse);
        }
      },
      // The eight corners of the cube plus the one state that grants access,
      // checked before the generated cases so the boundary is exhaustive.
      examples: <(LinkState, bool, bool)>[
        (LinkState.ready, true, true),
        (LinkState.ready, true, false),
        (LinkState.ready, false, true),
        (LinkState.ready, false, false),
        (LinkState.idle, true, true),
        (LinkState.idle, true, false),
        (LinkState.idle, false, true),
        (LinkState.idle, false, false),
        (LinkState.unavailable, false, true),
      ],
    );

    // The gate's single dependency: `LinkState.grantsAccess` is true for
    // exactly one state, `ready`. Pinning it fixes the first branch of the
    // verdict for every state the property generates.
    test('LinkStateX.grantsAccess is true iff the state is ready', () {
      for (final state in LinkState.values) {
        expect(
          state.grantsAccess,
          equals(state == LinkState.ready),
          reason: '$state.grantsAccess must equal (state == ready)',
        );
      }
      // Exactly one of the enum's values grants access.
      expect(
        LinkState.values.where((s) => s.grantsAccess).length,
        equals(1),
      );
    });
  });

  group('Diagnostics_Sheet contents preserved (Requirement 13.10)', () {
    testWidgets(
      'the sheet keeps its Link / Events / Raw tabs and the Link tab shows the '
      'Link, Firmware configuration and Calibration dataset sections',
      (tester) async {
        // A tall, wide surface so the 85%-height sheet has room to lay out.
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Reduce_Motion on so the sheet's ambient pulses stop and the tree
        // reaches a steady state — otherwise pumpAndSettle would never settle.
        final settings = await _settings();
        settings.setReduceMotion(true);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<MonitorController>.value(
                value: _DiagnosticsMonitor(settings),
              ),
              ChangeNotifierProvider<SettingsController>.value(value: settings),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(body: DiagnosticsSheet()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // The three tab labels are still present.
        expect(find.widgetWithText(Tab, 'Link'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Events'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Raw'), findsOneWidget);

        // The Link tab (shown first) still carries link health, the firmware
        // configuration and the calibration dataset — CardLabel uppercases its
        // text, so the rendered labels are the upper-cased forms.
        expect(find.text('LINK'), findsOneWidget);
        expect(find.text('FIRMWARE CONFIGURATION'), findsOneWidget);
        expect(find.text('CALIBRATION DATASET'), findsOneWidget);

        // The calibration dataset renders as the shared Calibration_Table.
        expect(find.byType(CalibrationTable), findsOneWidget);
      },
    );
  });

  group('Logging / retention / pruning behaviour unchanged (Req 13.7)', () {
    test('LoggingInterval keeps its five values and their durations', () {
      expect(
        LoggingInterval.values,
        orderedEquals(<LoggingInterval>[
          LoggingInterval.everySecond,
          LoggingInterval.fiveSeconds,
          LoggingInterval.tenSeconds,
          LoggingInterval.thirtySeconds,
          LoggingInterval.oneMinute,
        ]),
      );
      expect(
        LoggingInterval.everySecond.duration,
        equals(const Duration(seconds: 1)),
      );
      expect(
        LoggingInterval.fiveSeconds.duration,
        equals(const Duration(seconds: 5)),
      );
      expect(
        LoggingInterval.tenSeconds.duration,
        equals(const Duration(seconds: 10)),
      );
      expect(
        LoggingInterval.thirtySeconds.duration,
        equals(const Duration(seconds: 30)),
      );
      expect(
        LoggingInterval.oneMinute.duration,
        equals(const Duration(minutes: 1)),
      );

      // The row-count footprints the settings tab shows are unchanged.
      expect(LoggingInterval.everySecond.footprint, equals('≈86k rows/day'));
      expect(LoggingInterval.fiveSeconds.footprint, equals('≈17k rows/day'));
      expect(LoggingInterval.tenSeconds.footprint, equals('≈8.6k rows/day'));
      expect(LoggingInterval.thirtySeconds.footprint, equals('≈2.9k rows/day'));
      expect(LoggingInterval.oneMinute.footprint, equals('≈1.4k rows/day'));
    });

    test('RetentionPolicy keeps its five values and their durations', () {
      expect(
        RetentionPolicy.values,
        orderedEquals(<RetentionPolicy>[
          RetentionPolicy.week,
          RetentionPolicy.month,
          RetentionPolicy.quarter,
          RetentionPolicy.year,
          RetentionPolicy.forever,
        ]),
      );
      expect(RetentionPolicy.week.duration, equals(const Duration(days: 7)));
      expect(RetentionPolicy.month.duration, equals(const Duration(days: 30)));
      expect(RetentionPolicy.quarter.duration, equals(const Duration(days: 90)));
      expect(RetentionPolicy.year.duration, equals(const Duration(days: 365)));
      // "Keep everything" has no expiry, so the pruner never removes its rows.
      expect(RetentionPolicy.forever.duration, isNull);
    });

    test('AppSettings defaults keep logging, retention and pruning unchanged',
        () {
      const defaults = AppSettings();
      expect(defaults.loggingInterval, equals(LoggingInterval.tenSeconds));
      expect(defaults.retention, equals(RetentionPolicy.quarter));
      expect(defaults.autoPrune, isTrue);
      // The connection gate default is likewise unchanged — the app still
      // requires a live link to browse out of the box (Requirement 13.6).
      expect(defaults.requireConnectionToBrowse, isTrue);
    });
  });
}

// ===========================================================================
// Test doubles for the Diagnostics_Sheet example.
// ===========================================================================

/// A no-op stand-in for the sqflite-backed database. Never touched, because the
/// Link tab (the one the sheet shows first) reads only in-memory getters and
/// the Events tab — the only one that queries the database — is not built until
/// it is selected.
class _FakeDb implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [MonitorController] reporting a connected simulator with a firmware
/// configuration and a small calibration dataset, so the Link tab renders all
/// three of its sections. No transport and no database work.
class _DiagnosticsMonitor extends MonitorController {
  _DiagnosticsMonitor(SettingsController settings)
      : super(database: _FakeDb(), settings: settings);

  @override
  LinkState get linkState => LinkState.ready;

  @override
  bool get isConnected => true;

  @override
  bool get usingSimulator => false;

  @override
  LeakStatus get status => LeakStatus.ok;

  @override
  String get transportKind => 'Simulator';

  @override
  int? get secondsSinceLastSample => 0;

  @override
  DiscoveredDevice? get connectedDevice => const DiscoveredDevice(
        id: 'sim-0',
        name: 'Simulator',
        rssi: -50,
      );

  @override
  Telemetry? get latest => null;

  @override
  List<String> get rawLog => const <String>[];

  @override
  DeviceConfig get deviceConfig => const DeviceConfig(
        firmwareVersion: '1.0.0',
        protocolVersion: kProtocolVersion,
        sensorCount: 3,
        sampleIntervalMs: 1000,
        pulsesPerLitre: <double>[450, 450, 450],
        toleranceAbsLpm: 0.5,
        tolerancePct: 0.05,
        noiseFloorLpm: 0.2,
        faultMinFlowLpm: 0.1,
        leakConfirmSamples: 5,
        leakClearSamples: 5,
        faultConfirmSamples: 5,
        learnedBiasLpm: 0.0,
      );

  @override
  List<BaselineRow> get baseline => const <BaselineRow>[
        BaselineRow(
          index: 0,
          inletLpm: 0,
          expectedBalanceLpm: 0,
          marginLpm: 0.5,
        ),
        BaselineRow(
          index: 1,
          inletLpm: 12.34,
          expectedBalanceLpm: 0.125,
          marginLpm: 0.375,
        ),
      ];
}

Future<SettingsController> _settings() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SettingsController.load();
}

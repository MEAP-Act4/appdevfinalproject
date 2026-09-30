/// Unit tests for the Alerts_Panel projection and [AlertsController]
/// (task 13.5).
///
/// Requirements 7.1, 7.2, 7.4, 7.9.
///
/// These examples pin the projection contract:
///
///   1. filtering excludes connection noise (CONNECTED / DISCONNECTED) and the
///      bare WATCH marker, and keeps the alert-worthy kinds;
///   2. severity mapping — LEAK_RAISED / FAULT_RAISED → alarm, WATCH_RAISED →
///      warning, the rest → info;
///   3. the reload path is bounded at 200 with the oldest evicted;
///   4. entries stay newest-first, both on reload and on append;
///   5. an event with an empty message projects with the raw kind token as its
///      summary rather than being dropped;
///   6. the controller notifies on append and reload, and NOT when an append is
///      filtered out;
///   7. a failed initial query raises `initialLoadFailed`, which a later
///      successful `refresh` clears.
///
/// The property tests (13.11–13.13) cover the universal laws separately.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/data/models/stored_reading.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/state/alerts_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

LeakEvent _event(EventKind kind, {int ts = 0, String message = 'msg'}) =>
    LeakEvent(timestampMs: ts, kind: kind, message: message);

Future<SettingsController> _settings({
  List<String> names = const <String>['Main Inlet', 'Outlet A', 'Outlet B'],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'sensorNames': names,
  });
  return SettingsController.load();
}

void main() {
  const names = <String>['Kitchen', 'Garden', 'Garage'];

  group('AlertEntry.project — filtering', () {
    test('excludes connection noise and the bare WATCH marker', () {
      for (final kind in <EventKind>[
        EventKind.connected,
        EventKind.disconnected,
        EventKind.watch,
      ]) {
        expect(
          AlertEntry.project(_event(kind), sensorNames: names),
          isNull,
          reason: '$kind should be filtered out',
        );
        expect(AlertEntry.isAlertWorthy(kind), isFalse);
      }
    });

    test('keeps every alert-worthy kind', () {
      for (final kind in <EventKind>[
        EventKind.leakRaised,
        EventKind.leakCleared,
        EventKind.faultRaised,
        EventKind.faultCleared,
        EventKind.watchRaised,
        EventKind.calibration,
        EventKind.configChanged,
        EventKind.note,
      ]) {
        expect(
          AlertEntry.project(_event(kind), sensorNames: names),
          isNotNull,
          reason: '$kind should be kept',
        );
      }
    });
  });

  group('AlertEntry.project — severity mapping', () {
    test('LEAK_RAISED and FAULT_RAISED map to alarm', () {
      expect(
        AlertEntry.project(_event(EventKind.leakRaised), sensorNames: names)!
            .severity,
        AlertSeverity.alarm,
      );
      expect(
        AlertEntry.project(_event(EventKind.faultRaised), sensorNames: names)!
            .severity,
        AlertSeverity.alarm,
      );
    });

    test('WATCH_RAISED maps to warning', () {
      expect(
        AlertEntry.project(_event(EventKind.watchRaised), sensorNames: names)!
            .severity,
        AlertSeverity.warning,
      );
    });

    test('clears, calibration, config and note map to info', () {
      for (final kind in <EventKind>[
        EventKind.leakCleared,
        EventKind.faultCleared,
        EventKind.calibration,
        EventKind.configChanged,
        EventKind.note,
      ]) {
        expect(
          AlertEntry.project(_event(kind), sensorNames: names)!.severity,
          AlertSeverity.info,
          reason: '$kind should be info',
        );
      }
    });
  });

  group('AlertEntry.project — status and affordance', () {
    test('status derives from kind', () {
      expect(
        AlertEntry.project(_event(EventKind.leakRaised), sensorNames: names)!
            .status,
        LeakStatus.leak,
      );
      expect(
        AlertEntry.project(_event(EventKind.faultRaised), sensorNames: names)!
            .status,
        LeakStatus.fault,
      );
      expect(
        AlertEntry.project(_event(EventKind.watchRaised), sensorNames: names)!
            .status,
        LeakStatus.watch,
      );
      expect(
        AlertEntry.project(_event(EventKind.calibration), sensorNames: names)!
            .status,
        LeakStatus.calibrating,
      );
    });

    test('affordance is non-empty and distinct across statuses', () {
      final byStatus = <LeakStatus, String>{};
      for (final kind in AlertEntry.alertWorthyKinds) {
        final entry = AlertEntry.project(_event(kind), sensorNames: names)!;
        expect(entry.affordance, isNotEmpty);
        byStatus[entry.status] = entry.affordance;
      }
      // Distinct statuses carry distinct affordances.
      final affordances = byStatus.values.toList();
      expect(affordances.toSet().length, affordances.length);
    });
  });

  group('AlertEntry.project — channel naming and summary', () {
    test('balance-derived entries are named with the inlet channel', () {
      final entry =
          AlertEntry.project(_event(EventKind.leakRaised), sensorNames: names)!;
      expect(entry.channelName, 'Kitchen'); // index 0 = inlet
    });

    test('an empty message falls back to the raw kind token', () {
      final entry = AlertEntry.project(
        _event(EventKind.note, message: '   '),
        sensorNames: names,
      )!;
      expect(entry.summary, EventKind.note.wire);
    });

    test('a non-empty message is used verbatim as the summary', () {
      final entry = AlertEntry.project(
        _event(EventKind.leakRaised, message: 'Leak confirmed'),
        sensorNames: names,
      )!;
      expect(entry.summary, 'Leak confirmed');
    });
  });

  group('AlertsController — reload', () {
    test('projects, filters and orders newest-first', () async {
      final settings = await _settings();
      // db.events returns ts DESC already; include noise to prove it is dropped.
      final batch = <LeakEvent>[
        _event(EventKind.leakRaised, ts: 300),
        _event(EventKind.connected, ts: 250),
        _event(EventKind.watchRaised, ts: 200),
        _event(EventKind.disconnected, ts: 150),
        _event(EventKind.note, ts: 100),
      ];
      final controller = AlertsController.withLoader(
        loadEvents: () async => batch,
        settings: settings,
      );

      await controller.initialise();

      final entries = controller.entries;
      expect(entries.map((e) => e.kind), <EventKind>[
        EventKind.leakRaised,
        EventKind.watchRaised,
        EventKind.note,
      ]);
      // Non-increasing timestamps.
      for (var i = 1; i < entries.length; i++) {
        expect(entries[i].timestampMs <= entries[i - 1].timestampMs, isTrue);
      }
      expect(controller.isLoaded, isTrue);
      expect(controller.initialLoadFailed, isFalse);
    });

    test('bounds the in-memory list at 200 with the oldest evicted', () async {
      final settings = await _settings();
      // 250 alert-worthy events, newest first (ts DESC).
      final batch = <LeakEvent>[
        for (var i = 0; i < 250; i++)
          _event(EventKind.leakRaised, ts: 100000 - i),
      ];
      final controller = AlertsController.withLoader(
        loadEvents: () async => batch,
        settings: settings,
      );

      await controller.initialise();

      expect(controller.entries.length, AlertsController.maxEntries);
      // Kept the 200 newest — the oldest (smallest ts) were evicted.
      expect(controller.entries.first.timestampMs, 100000);
      expect(controller.entries.last.timestampMs, 100000 - 199);
    });

    test('notifies on reload', () async {
      final settings = await _settings();
      final controller = AlertsController.withLoader(
        loadEvents: () async => <LeakEvent>[_event(EventKind.leakRaised)],
        settings: settings,
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.initialise();
      expect(notifications, 1);

      await controller.refresh();
      expect(notifications, 2);
    });
  });

  group('AlertsController — append hook', () {
    test('prepends an alert-worthy event and notifies', () async {
      final settings = await _settings();
      final controller = AlertsController.withLoader(
        loadEvents: () async => <LeakEvent>[_event(EventKind.note, ts: 50)],
        settings: settings,
      );
      await controller.initialise();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.debugAppend(_event(EventKind.leakRaised, ts: 500));

      expect(notifications, 1);
      expect(controller.entries.first.kind, EventKind.leakRaised);
      expect(controller.entries.first.timestampMs, 500);
    });

    test('a filtered-out append does not notify or add a row', () async {
      final settings = await _settings();
      final controller = AlertsController.withLoader(
        loadEvents: () async => <LeakEvent>[_event(EventKind.note, ts: 50)],
        settings: settings,
      );
      await controller.initialise();
      final before = controller.entries.length;
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.debugAppend(_event(EventKind.connected, ts: 500));

      expect(notifications, 0);
      expect(controller.entries.length, before);
    });

    test('append keeps the list bounded and newest-first', () async {
      final settings = await _settings();
      final batch = <LeakEvent>[
        for (var i = 0; i < 200; i++) _event(EventKind.note, ts: 1000 - i),
      ];
      final controller = AlertsController.withLoader(
        loadEvents: () async => batch,
        settings: settings,
      );
      await controller.initialise();
      expect(controller.entries.length, 200);

      controller.debugAppend(_event(EventKind.leakRaised, ts: 5000));

      expect(controller.entries.length, AlertsController.maxEntries);
      expect(controller.entries.first.timestampMs, 5000);
    });
  });

  group('AlertsController — initial load failure', () {
    test('raises initialLoadFailed, cleared by a successful refresh', () async {
      final settings = await _settings();
      var shouldThrow = true;
      final controller = AlertsController.withLoader(
        loadEvents: () async {
          if (shouldThrow) throw StateError('db unavailable');
          return <LeakEvent>[_event(EventKind.leakRaised)];
        },
        settings: settings,
      );

      await controller.initialise();
      expect(controller.initialLoadFailed, isTrue);
      expect(controller.isLoaded, isTrue);
      expect(controller.entries, isEmpty);

      shouldThrow = false;
      await controller.refresh();
      expect(controller.initialLoadFailed, isFalse);
      expect(controller.entries.length, 1);
    });
  });
}

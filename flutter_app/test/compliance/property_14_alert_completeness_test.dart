/// Property 14 — Every Alert_Entry carries a complete, non-empty presentation.
/// Mobile_Client / Flutter half.
///
/// design.md, Property 14:
///
/// > *For any* event record of any kind, the projected Alert_Entry has a
/// > non-empty formatted timestamp, a non-empty channel name, a Status drawn
/// > from the device vocabulary, a non-empty summary, and a Status_Affordance.
///
/// Generators: `event` — records across every `EventKind`, with empty and very
/// long message strings, missing optional balance and threshold values, and
/// every sensor-name configuration.
/// Invariant: all five fields are present and non-empty; `status` is a member
/// of the Status vocabulary.
///
/// _Validates: Requirements 7.2, 7.6_
///
/// ## Modelling decisions
///
/// **The projection is driven, not re-implemented.** The subject is the real
/// [AlertEntry.project] from the alerts controller (task 13.5). The property
/// hands it a generated [LeakEvent] and a generated three-name sensor list and
/// asserts on the entry it returns — never a hand-rolled copy of the mapping.
///
/// **Kept entries versus filtered kinds.** `project` returns `null` for the
/// three kinds the panel deliberately drops (`connected`, `disconnected`, the
/// bare `watch` marker — Requirement 13.10). Property 14 is about the *kept*
/// entries, so the property splits: for a filtered kind it asserts the
/// projection is `null`, and for a kept kind it asserts the entry is complete.
/// That way every `EventKind` is exercised and the completeness claim is only
/// made where an entry actually exists.
///
/// **"Non-empty formatted timestamp" is checked through `intl`.** The panel
/// formats [AlertEntry.timestamp] with a locale `DateFormat` (Requirement
/// 12.7); the entry itself carries the `DateTime`, not a string. So the
/// property asserts the entry's `timestamp` round-trips its epoch and that a
/// locale `DateFormat.yMMMd(locale).add_jm()` of that `DateTime` yields a
/// non-empty string in both `es` and `en` — the same formatter surface the
/// panel uses. `initializeDateFormatting()` is called in `main()` so the
/// locale data is present under the test binding.
///
/// **channelName, summary and affordance are all non-empty by construction.**
/// The projection falls back to a non-empty inlet name when the sensor list is
/// empty or blank, folds an empty message to the raw kind token, and maps every
/// status to a stable affordance key — so the property drives empty, blank and
/// 5000-character messages, missing balance/threshold, and blank/empty sensor
/// names to prove none of those inputs can produce a blank field.
///
/// **`status` is drawn from the vocabulary.** The entry's `status` must be a
/// member of `LeakStatus.values` — the device Status vocabulary — which the
/// property asserts directly.
///
/// The only numbers written here are the samplable timestamp cap
/// (0..4294967295) and the very-long message length (5000), neither a colour
/// nor a Layout threshold.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:intl/intl.dart' show DateFormat;
import 'package:leakguard/core/protocol/leak_protocol.dart' show LeakStatus;
import 'package:leakguard/data/models/stored_reading.dart'
    show EventKind, LeakEvent;
import 'package:leakguard/state/alerts_controller.dart' show AlertEntry;

import '../support/props.dart';

/// The two supported locales a timestamp is rendered in (Requirement 12.7).
const List<String> _locales = <String>['es', 'en'];

/// The samplable timestamp band — epoch milliseconds in `[0, 2^32 - 1]`. The
/// upper bound is the sampler's cap, well inside a valid [DateTime].
const int _maxTimestampMs = 4294967295;

/// A very long message, to prove length never breaks completeness.
final String _longMessage = 'x' * 5000;

/// The message shapes Property 14 must see: empty, whitespace-only, a normal
/// string, and a 5000-character string.
final List<String> _messages = <String>[
  '',
  '   ',
  'Balance exceeded threshold on the inlet',
  _longMessage,
];

/// Sensor-name configurations: default-ish names, blank names, empty-string
/// names, and a mix — every configuration the projection's channel resolution
/// has to survive.
final List<List<String>> _sensorNameConfigs = <List<String>>[
  <String>['Main Inlet', 'Kitchen', 'Bathroom'],
  <String>['', '', ''],
  <String>['   ', 'Kitchen', ''],
  <String>['Inlet', '', '   '],
  <String>['Línea Principal', 'Cocina', 'Baño'],
];

/// One generated event scenario: the event under projection and the sensor
/// list resolved against it.
typedef _Scenario = ({LeakEvent event, List<String> sensorNames});

/// Nullable finite doubles — `null` (a missing optional) or a finite value.
/// The sentinel `double.nan` marks "absent", since the generator surface has no
/// direct nullable primitive; it is mapped back to `null` when the event is
/// built, so both a missing and a finite optional are exercised.
final Generator<double?> _nullableDouble =
    any.combine2<bool, double, double?>(
  any.bool,
  any.doubleBetween(-1000, 1000),
  (present, value) => present ? value : null,
);

/// The event generator: every [EventKind], every message shape, any timestamp
/// in the samplable band, and missing-or-present balance/threshold.
///
/// Composed as an outer [combine2] whose first arm is a [combine3] over the
/// kind/message/timestamp triple and whose second arm is a [combine2] over the
/// optional balance/threshold pair — glados' methods are on [Any] and take at
/// most four generators, so a nested composition covers the six inputs.
final Generator<LeakEvent> _eventGen = any.combine2<
    (EventKind, String, int), (double?, double?), LeakEvent>(
  any.combine3<EventKind, String, int, (EventKind, String, int)>(
    any.enumOf<EventKind>(EventKind.values),
    any.pick<String>(_messages),
    any.intBetween(0, _maxTimestampMs),
    (kind, message, ts) => (kind, message, ts),
  ),
  any.combine2<double?, double?, (double?, double?)>(
    _nullableDouble,
    _nullableDouble,
    (balance, threshold) => (balance, threshold),
  ),
  (base, balances) => LeakEvent(
    timestampMs: base.$3,
    kind: base.$1,
    message: base.$2,
    balanceLpm: balances.$1,
    thresholdLpm: balances.$2,
  ),
);

/// The full scenario generator: an event × a sensor-name configuration.
final Generator<_Scenario> _scenario =
    any.combine2<LeakEvent, List<String>, _Scenario>(
  _eventGen,
  any.pick<List<String>>(_sensorNameConfigs),
  (event, sensorNames) => (event: event, sensorNames: sensorNames),
);

void main() {
  // A locale DateFormat needs its locale data loaded before use under the test
  // binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  initializeDateFormatting();

  group('Property 14 — every kept Alert_Entry is complete and non-empty', () {
    forAll<_Scenario>(
      'a filtered kind projects to null; a kept kind yields a complete entry '
      'with a non-empty timestamp, channel, status, summary and affordance',
      _scenario,
      (scenario) {
        final event = scenario.event;
        final entry = AlertEntry.project(
          event,
          sensorNames: scenario.sensorNames,
        );

        if (!AlertEntry.isAlertWorthy(event.kind)) {
          // The three panel-filtered kinds must project to nothing.
          expect(
            entry,
            isNull,
            reason: 'filtered kind ${event.kind} must project to null, '
                'got $entry',
          );
          return;
        }

        // A kept kind must yield a fully-populated entry.
        expect(
          entry,
          isNotNull,
          reason: 'alert-worthy kind ${event.kind} projected to null',
        );
        final alert = entry!;

        // 1) Status is a member of the device vocabulary.
        expect(
          LeakStatus.values,
          contains(alert.status),
          reason: 'status ${alert.status} is not a LeakStatus member',
        );

        // 2) The channel name is present and non-empty.
        expect(
          alert.channelName.trim(),
          isNotEmpty,
          reason: 'channelName was blank for kind ${event.kind}, '
              'sensorNames=${scenario.sensorNames}',
        );

        // 3) The summary is present and non-empty (Req 7.2).
        expect(
          alert.summary.trim(),
          isNotEmpty,
          reason: 'summary was blank for kind ${event.kind}, '
              "message='${event.message}'",
        );

        // 4) The Status_Affordance is present and non-empty (Req 7.6).
        expect(
          alert.affordance.trim(),
          isNotEmpty,
          reason: 'affordance was blank for status ${alert.status}',
        );

        // 5) The timestamp round-trips its epoch, and a locale DateFormat of
        //    it yields a non-empty string in every supported locale (Req 7.2 /
        //    12.7). This is the panel's own formatter surface.
        expect(
          alert.timestamp.millisecondsSinceEpoch,
          event.timestampMs,
          reason: 'timestamp does not round-trip the event epoch',
        );
        for (final locale in _locales) {
          final formatted =
              DateFormat.yMMMd(locale).add_jm().format(alert.timestamp);
          expect(
            formatted.trim(),
            isNotEmpty,
            reason: 'formatted timestamp was empty in locale $locale for '
                'ts=${event.timestampMs}',
          );
        }
      },
      // Boundary inputs the property must always see: every kind at the epoch
      // extremes, with an empty message and a blank sensor list (the hardest
      // case for a non-empty channel and summary), and a very long message.
      examples: <_Scenario>[
        for (final kind in EventKind.values) ...<_Scenario>[
          (
            event: LeakEvent(timestampMs: 0, kind: kind, message: ''),
            sensorNames: const <String>['', '', ''],
          ),
          (
            event: LeakEvent(
              timestampMs: _maxTimestampMs,
              kind: kind,
              message: '   ',
            ),
            sensorNames: const <String>[],
          ),
          (
            event: LeakEvent(
              timestampMs: 1700000000000,
              kind: kind,
              message: 'x' * 5000,
              balanceLpm: 1.5,
              thresholdLpm: 0.8,
            ),
            sensorNames: const <String>['Línea Principal', 'Cocina', 'Baño'],
          ),
        ],
      ],
    );
  });
}

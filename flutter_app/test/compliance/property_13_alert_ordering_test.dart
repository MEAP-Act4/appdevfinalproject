/// Property 13 — the Alerts_Panel is ordered newest-first and loses nothing.
/// Mobile_Client half (task 13.11).
///
/// Requirement 7.1: THE Alerts_Panel SHALL present the retained events
/// newest-first. Requirement 7.9: the Alerts_Panel is a read projection — the
/// device-reported Status and the alarm interpretation are never altered, and
/// no alert-worthy event is dropped or reordered away.
///
/// **The point of the property.** For *any* batch of event records with
/// arbitrary timestamps — duplicates and out-of-order arrival included — the
/// projected Alert_Entry list must be:
///
///   1. non-increasing in timestamp (`ts[i] >= ts[i+1]` for every adjacent
///      pair) — the panel is newest-first; and
///   2. exactly a permutation of the alert-worthy subset of the input — the
///      output multiset (keyed by kind + timestamp) equals the input filtered
///      to [AlertEntry.alertWorthyKinds], so nothing alert-worthy is lost and
///      nothing is invented; and
///   3. free of any excluded kind — `CONNECTED`, `DISCONNECTED` and the bare
///      `WATCH` marker never appear (they belong in the Diagnostics_Sheet).
///
/// **Why this exercises the real production path.** The database returns events
/// `ts DESC`, but Property 13 generates arbitrary order, so this feeds an
/// unordered batch through the genuine [AlertsController] reload
/// ([AlertsController.withLoader] + [AlertsController.initialise]) and asserts
/// against `controller.entries`. That means the controller — not the query —
/// must establish the newest-first order: `AlertsController._replaceFrom` sorts
/// the projected entries by timestamp descending before applying the 200-entry
/// bound. This test is the contract for that sort. It never opens a database,
/// touches the wire protocol, or changes any status/threshold/alarm value
/// (Requirement 13.9): it reorders and filters projected read models only.
///
/// **The 200-entry bound and the multiset.** The controller caps at
/// [AlertsController.maxEntries] (200) newest rows. The generator draws 0..200
/// events so the whole batch survives the bound and the multiset comparison is
/// exact against every alert-worthy input. (The bound-and-evict behaviour for
/// over-200 batches is pinned by the unit tests in
/// `test/state/alerts_controller_test.dart`; here the batch is at or under the
/// cap so no eviction can perturb the multiset.)
///
/// Generators (design.md): `events` — lists of 0..200 records drawn from EVERY
/// [EventKind], with timestamps in arbitrary order including equal values. The
/// harness is `test/support/props.dart` — glados, 100 cases, seed
/// `kPropertySeed`, `any.listBetween` 0..200, `any.enumOf(EventKind.values)`,
/// `any.intBetween(0, 4294967295)` for timestamps (within the 0x100000000
/// samplable cap). `examples:` supplies the boundary batches a generator might
/// otherwise never hit: empty, a single equal-timestamp pair across kinds, and
/// an all-excluded batch. No colour literal is written here.
///
/// Requirements: 7.1, 7.9.
///
/// **Validates: Requirements 7.1, 7.9**
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/data/models/stored_reading.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/state/alerts_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/props.dart';

/// A generated event: a kind drawn from the full enum and a timestamp anywhere
/// in the samplable band. The message is a fixed non-empty string — the summary
/// is Property 14's concern, not this one — so ordering and membership are what
/// vary.
typedef GenEvent = ({EventKind kind, int ts});

/// The three excluded kinds: connection noise plus the bare WATCH marker. None
/// of these may ever appear in the projected list.
const Set<EventKind> _excludedKinds = <EventKind>{
  EventKind.connected,
  EventKind.disconnected,
  EventKind.watch,
};

/// A single event across the full kind space and the full samplable timestamp
/// band. Equal timestamps arise naturally as the band is sampled uniformly and
/// the `examples:` batches force at least one exact tie.
final Generator<GenEvent> _event =
    any.combine2<EventKind, int, GenEvent>(
  any.enumOf<EventKind>(EventKind.values),
  // Within the harness's samplable cap (< 0x100000000); a prior bug exceeded it.
  any.intBetween(0, 4294967295),
  (EventKind kind, int ts) => (kind: kind, ts: ts),
);

/// 0..200 events in arbitrary order — the design.md band, at or under the
/// controller's 200-entry cap so the whole batch survives for the multiset
/// check.
final Generator<List<GenEvent>> _events =
    any.listBetween<GenEvent>(_event, minLength: 0, maxLength: 200);

/// Boundary batches the generator might not reliably produce: the empty list,
/// an exact equal-timestamp tie spanning two kept kinds, a tie that mixes a
/// kept and an excluded kind, and a batch made entirely of excluded kinds.
const List<List<GenEvent>> _examples = <List<GenEvent>>[
  <GenEvent>[],
  <GenEvent>[
    (kind: EventKind.leakRaised, ts: 500),
    (kind: EventKind.faultRaised, ts: 500),
  ],
  <GenEvent>[
    (kind: EventKind.note, ts: 42),
    (kind: EventKind.connected, ts: 42),
    (kind: EventKind.watch, ts: 42),
  ],
  <GenEvent>[
    (kind: EventKind.connected, ts: 1),
    (kind: EventKind.disconnected, ts: 2),
    (kind: EventKind.watch, ts: 3),
  ],
];

LeakEvent _toLeakEvent(GenEvent e) =>
    LeakEvent(timestampMs: e.ts, kind: e.kind, message: 'event');

/// A settings controller with fixed sensor names — the projection needs an
/// inlet name, and the channel name has no bearing on ordering or membership.
Future<SettingsController> _settings() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'sensorNames': <String>['Main Inlet', 'Outlet A', 'Outlet B'],
  });
  return SettingsController.load();
}

/// A membership key that identifies an entry by (kind, timestamp) — enough to
/// distinguish the events this property generates and to compare multisets
/// without depending on projected presentation fields.
typedef MemberKey = (EventKind, int);

/// A multiset of [MemberKey]s as a count map, so duplicate (kind, ts) pairs are
/// counted rather than collapsed.
Map<MemberKey, int> _multiset(Iterable<MemberKey> keys) {
  final Map<MemberKey, int> counts = <MemberKey, int>{};
  for (final MemberKey key in keys) {
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

bool _multisetsEqual(Map<MemberKey, int> a, Map<MemberKey, int> b) {
  if (a.length != b.length) return false;
  for (final MapEntry<MemberKey, int> entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

void main() {
  group('Property 13 — Requirements 7.1 & 7.9, newest-first and lossless', () {
    forAll<List<GenEvent>>(
      'the projected list is non-increasing in timestamp and is exactly the '
      'alert-worthy subset of the input, with no excluded kind',
      _events,
      (List<GenEvent> events) async {
        final SettingsController settings = await _settings();
        final AlertsController controller = AlertsController.withLoader(
          loadEvents: () async =>
              <LeakEvent>[for (final GenEvent e in events) _toLeakEvent(e)],
          settings: settings,
        );

        // The genuine reload path establishes the ordering — the arbitrary
        // input order is deliberately NOT pre-sorted.
        await controller.initialise();
        final List<AlertEntry> entries = controller.entries;

        // (1) newest-first: every adjacent pair is non-increasing.
        for (int i = 0; i + 1 < entries.length; i++) {
          expect(
            entries[i].timestampMs >= entries[i + 1].timestampMs,
            isTrue,
            reason: 'entries must be newest-first at index $i: '
                '${entries[i].timestampMs} < ${entries[i + 1].timestampMs}',
          );
        }

        // (3) no excluded kind appears.
        for (final AlertEntry entry in entries) {
          expect(
            _excludedKinds.contains(entry.kind),
            isFalse,
            reason: 'excluded kind ${entry.kind} leaked into the panel',
          );
          expect(
            AlertEntry.isAlertWorthy(entry.kind),
            isTrue,
            reason: '${entry.kind} is not alert-worthy yet appeared',
          );
        }

        // (2) the output multiset equals the input filtered to the
        // alert-worthy kinds — nothing lost, nothing invented. The generated
        // batch is at or under the 200 cap, so no eviction can perturb this.
        final Map<MemberKey, int> expected = _multiset(<MemberKey>[
          for (final GenEvent e in events)
            if (AlertEntry.isAlertWorthy(e.kind)) (e.kind, e.ts),
        ]);
        final Map<MemberKey, int> actual = _multiset(<MemberKey>[
          for (final AlertEntry entry in entries) (entry.kind, entry.timestampMs),
        ]);
        expect(
          _multisetsEqual(actual, expected),
          isTrue,
          reason: 'projected multiset $actual != alert-worthy input $expected',
        );

        controller.dispose();
      },
      examples: _examples,
    );
  });

  group('Property 13 — the guards are not vacuous', () {
    test('the excluded set is exactly the non-alert-worthy kinds', () {
      final Set<EventKind> nonWorthy = EventKind.values
          .where((EventKind k) => !AlertEntry.isAlertWorthy(k))
          .toSet();
      expect(nonWorthy, _excludedKinds);
    });

    test('an all-excluded batch projects to an empty list', () async {
      final SettingsController settings = await _settings();
      final AlertsController controller = AlertsController.withLoader(
        loadEvents: () async => <LeakEvent>[
          _toLeakEvent((kind: EventKind.connected, ts: 3)),
          _toLeakEvent((kind: EventKind.disconnected, ts: 1)),
          _toLeakEvent((kind: EventKind.watch, ts: 2)),
        ],
        settings: settings,
      );
      await controller.initialise();
      expect(controller.entries, isEmpty);
      controller.dispose();
    });

    test('an arbitrary-order kept batch is reordered newest-first', () async {
      final SettingsController settings = await _settings();
      final AlertsController controller = AlertsController.withLoader(
        loadEvents: () async => <LeakEvent>[
          _toLeakEvent((kind: EventKind.note, ts: 10)),
          _toLeakEvent((kind: EventKind.leakRaised, ts: 300)),
          _toLeakEvent((kind: EventKind.calibration, ts: 100)),
        ],
        settings: settings,
      );
      await controller.initialise();
      expect(
        controller.entries.map((AlertEntry e) => e.timestampMs).toList(),
        <int>[300, 100, 10],
      );
      controller.dispose();
    });
  });
}

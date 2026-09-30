/// Property 18 — every Status presentation carries a non-colour affordance.
/// Mobile_Client half.
///
/// design.md, Property 18:
///
/// > *For any* Status value and *any* status-presenting component — the status
/// > pill, the status banner, the KPI card, the Alert_Entry row — the rendered
/// > output contains a text label, a shape or an icon that distinguishes the
/// > Status without reference to colour.
/// >
/// > Generators: `status` — the six Status values plus the unknown state;
/// > `component` — the four status-presenting components.
/// > Invariant: the rendered output contains a non-empty affordance token; and
/// > for any two distinct Status values the affordances differ.
///
/// _Validates: Requirements 1.11, 7.6, 11.5_
///
/// ## What the criteria demand
///
/// * **Requirement 1.11** — when a Status is presented in WATCH, a
///   Status_Affordance is rendered *alongside* the amber colour, so amber is
///   never the only signal.
/// * **Requirement 7.6** — every Alert_Entry row renders a Status_Affordance.
/// * **Requirement 11.5** — every Status presentation is accompanied by a
///   Status_Affordance.
///
/// A Status_Affordance is defined in requirements.md as "the non-colour signal
/// that accompanies every Status presentation — a text label, a shape, or an
/// icon — so that Status is never conveyed by colour alone." So the property
/// asserts two things for every Status and every component:
///
///   1. the affordance token is **present and non-empty** (existence); and
///   2. two **distinct** Status values never share an affordance (distinctness)
///      — a shared token would make the two states indistinguishable once
///      colour is removed, which is exactly what the affordance exists to
///      prevent.
///
/// ## Which affordance source covers which component
///
/// The four status-presenting components draw their non-colour affordance from
/// one of two sources in the app:
///
/// * **Status pill, status banner, KPI card** — all three render from
///   [StatusVisuals] (`lib/ui/common/status_visuals.dart`). The pill shows its
///   `label` (e.g. 'LEAK'), the banner its `headline`, the KPI card its `label`
///   and `icon`. `StatusVisuals` carries a non-colour `label` (a text token)
///   and an `icon` ([IconData]) for **all seven** [LeakStatus] values, so those
///   three components are covered across the whole Status vocabulary — the six
///   named states plus `unknown`.
///
/// * **Alert_Entry row** — renders from [AlertEntry.affordance]
///   (`lib/state/alerts_controller.dart`), a short non-colour text key the
///   panel maps to a glyph or label. `AlertEntry` is only ever produced for
///   *alert-worthy* [EventKind]s, and those kinds map onto a subset of the
///   Status vocabulary: leak, fault, watch, calibrating, ok (a cleared alarm)
///   and idle (a config-change or note). It never carries `unknown`. So the
///   Alert_Entry affordance is asserted across exactly the statuses
///   [AlertEntry] can actually produce; `unknown` is out of that source's range
///   by construction and is covered for the other three components via
///   [StatusVisuals].
///
/// The distinctness invariant is therefore asserted per source over that
/// source's realisable Status set:
///
///   * [StatusVisuals] `label` and `icon` — distinct across all seven statuses;
///   * [AlertEntry] `affordance` — distinct across the six statuses it produces.
///
/// ## How the affordance is read without a live widget tree
///
/// [StatusVisuals.of] takes a [BuildContext] because its *colours* come from
/// the theme palette. Its `label`, `headline` and `icon` — the non-colour
/// affordances this property cares about — do not depend on the palette.
/// [AppPalette.of] falls back to the dark palette when no theme extension is
/// installed, so a single pumped [BuildContext] resolves every status' visuals
/// with real values. The context is captured once inside a `testWidgets`
/// block; the property loop then runs against the captured visuals via the
/// harness' [checkProperty], which honours the 100-case floor and the fixed
/// [kPropertySeed] just as [forAll] does.
///
/// The [AlertEntry] affordance is read by projecting a representative
/// [LeakEvent] whose [EventKind] maps to the target status through
/// [AlertEntry.project] — the same path the panel uses — so the value asserted
/// is the one the row would actually show, not a copy.
///
/// If this property fails, it means a Status lost its non-colour signal or two
/// states collapsed onto the same one. It must not be made to pass by relaxing
/// the non-empty or distinctness checks — that would reintroduce a
/// colour-only Status presentation, the accessibility defect the affordance
/// exists to rule out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/data/models/stored_reading.dart';
import 'package:leakguard/state/alerts_controller.dart';
import 'package:leakguard/ui/common/status_visuals.dart';

import '../support/props.dart';

// --- StatusVisuals affordance source ----------------------------------------

/// The whole Status vocabulary — the six named states plus `unknown`. The
/// pill, banner and KPI card all resolve their non-colour affordance from
/// [StatusVisuals] for every one of these.
const List<LeakStatus> _allStatuses = LeakStatus.values;

/// The non-colour affordance a [StatusVisuals] carries: its short `label` and
/// its `icon`. Captured per status so the property can read them without a
/// live widget tree.
class _VisualAffordance {
  const _VisualAffordance(this.label, this.icon);

  final String label;
  final IconData icon;
}

// --- AlertEntry affordance source -------------------------------------------

/// The event kinds that produce each Status an [AlertEntry] can carry, paired
/// with the status they project to. This is the realisable range of the
/// Alert_Entry affordance source — `unknown` is deliberately absent because no
/// alert-worthy [EventKind] maps to it.
///
/// The status each kind maps to mirrors [AlertEntry]'s own `_statusFor`, and is
/// verified against a projected entry below rather than assumed.
const Map<LeakStatus, EventKind> _alertStatusKinds = <LeakStatus, EventKind>{
  LeakStatus.leak: EventKind.leakRaised,
  LeakStatus.fault: EventKind.faultRaised,
  LeakStatus.watch: EventKind.watchRaised,
  LeakStatus.calibrating: EventKind.calibration,
  LeakStatus.ok: EventKind.leakCleared,
  LeakStatus.idle: EventKind.note,
};

/// The statuses the Alert_Entry source can actually present.
final List<LeakStatus> _alertStatuses = _alertStatusKinds.keys.toList();

/// Projects a representative event for [status] into an [AlertEntry] and
/// returns it, using the same [AlertEntry.project] path the panel uses.
AlertEntry _entryFor(LeakStatus status) {
  final kind = _alertStatusKinds[status]!;
  final entry = AlertEntry.project(
    LeakEvent(
      timestampMs: 1000,
      kind: kind,
      message: 'representative ${kind.wire}',
    ),
    sensorNames: const <String>['Main Inlet', 'Outlet A', 'Outlet B'],
  );
  // Every kind in _alertStatusKinds is alert-worthy, so project never returns
  // null here; assert rather than swallow so a mapping drift is caught.
  expect(
    entry,
    isNotNull,
    reason: '${kind.wire} is expected to be alert-worthy and project to a row',
  );
  return entry!;
}

void main() {
  // A single pumped context resolves every status' StatusVisuals. AppPalette.of
  // falls back to the dark palette without a theme extension, so the labels and
  // icons come back with real values.
  final Map<LeakStatus, _VisualAffordance> visuals =
      <LeakStatus, _VisualAffordance>{};

  testWidgets('capture StatusVisuals for every status', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    for (final status in _allStatuses) {
      final v = StatusVisuals.of(captured, status);
      visuals[status] = _VisualAffordance(v.label, v.icon);
    }
    expect(visuals, hasLength(_allStatuses.length));
  });

  group('Property 18 — every Status carries a non-colour affordance', () {
    // Existence, StatusVisuals source: for every status the pill/banner/KPI
    // affordance (label + icon) is present. 100 generated cases over the seven
    // statuses, plus every status pinned as an example so none is skipped by
    // sampling.
    testWidgets(
      'StatusVisuals label and icon are non-empty for every status',
      (tester) async {
        final outcome = await checkProperty<LeakStatus>(
          any.pick(_allStatuses),
          (status) {
            final v = visuals[status]!;
            expect(
              v.label.trim(),
              isNotEmpty,
              reason: '$status has an empty StatusVisuals label — the pill, '
                  'banner and KPI card would show no non-colour token',
            );
            // A real glyph, not the empty/placeholder codepoint 0.
            expect(
              v.icon.codePoint,
              greaterThan(0),
              reason: '$status has no StatusVisuals icon',
            );
          },
          description: 'StatusVisuals affordance exists for every status',
          examples: _allStatuses,
        );
        expect(outcome.passed, isTrue,
            reason: outcome.failure?.report ?? 'property failed');
      },
    );

    // Existence, AlertEntry source: for every status the row can present, the
    // affordance key is non-empty. 100 cases over the six alert statuses.
    testWidgets(
      'AlertEntry affordance is non-empty for every status it presents',
      (tester) async {
        final outcome = await checkProperty<LeakStatus>(
          any.pick(_alertStatuses),
          (status) {
            final entry = _entryFor(status);
            expect(
              entry.status,
              status,
              reason: 'the representative event for $status projected to '
                  '${entry.status}; the kind->status mapping drifted',
            );
            expect(
              entry.affordance.trim(),
              isNotEmpty,
              reason: '$status projects to an Alert_Entry with an empty '
                  'affordance — the row would convey Status by colour alone',
            );
          },
          description: 'AlertEntry affordance exists for every status it carries',
          examples: _alertStatuses,
        );
        expect(outcome.passed, isTrue,
            reason: outcome.failure?.report ?? 'property failed');
      },
    );

    // Distinctness, StatusVisuals source: any two DISTINCT statuses have
    // DIFFERENT labels and DIFFERENT icons. forAll2 over status x status, 100
    // cases; equal-status pairs are the trivial case and are skipped.
    testWidgets(
      'distinct statuses have distinct StatusVisuals labels and icons',
      (tester) async {
        final outcome = await checkProperty<(LeakStatus, LeakStatus)>(
          any.combine2<LeakStatus, LeakStatus, (LeakStatus, LeakStatus)>(
            any.pick(_allStatuses),
            any.pick(_allStatuses),
            (a, b) => (a, b),
          ),
          (pair) {
            final (a, b) = pair;
            if (a == b) return; // distinctness is only claimed for a != b
            final va = visuals[a]!;
            final vb = visuals[b]!;
            expect(
              va.label,
              isNot(vb.label),
              reason: '$a and $b share the StatusVisuals label "${va.label}" — '
                  'the two states are indistinguishable without colour',
            );
            expect(
              va.icon,
              isNot(vb.icon),
              reason: '$a and $b share a StatusVisuals icon — the two states '
                  'are indistinguishable without colour',
            );
          },
          description: 'distinct statuses => distinct StatusVisuals affordance',
          examples: <(LeakStatus, LeakStatus)>[
            for (var i = 0; i < _allStatuses.length; i++)
              for (var j = 0; j < _allStatuses.length; j++)
                (_allStatuses[i], _allStatuses[j]),
          ],
        );
        expect(outcome.passed, isTrue,
            reason: outcome.failure?.report ?? 'property failed');
      },
    );

    // Distinctness, AlertEntry source: any two DISTINCT statuses the row can
    // present have DIFFERENT affordance keys. forAll2 over the six alert
    // statuses, 100 cases.
    testWidgets(
      'distinct statuses have distinct AlertEntry affordances',
      (tester) async {
        final outcome = await checkProperty<(LeakStatus, LeakStatus)>(
          any.combine2<LeakStatus, LeakStatus, (LeakStatus, LeakStatus)>(
            any.pick(_alertStatuses),
            any.pick(_alertStatuses),
            (a, b) => (a, b),
          ),
          (pair) {
            final (a, b) = pair;
            if (a == b) return;
            final aff = _entryFor(a).affordance;
            final bff = _entryFor(b).affordance;
            expect(
              aff,
              isNot(bff),
              reason: '$a and $b share the Alert_Entry affordance "$aff" — the '
                  'rows would be indistinguishable without colour',
            );
          },
          description: 'distinct statuses => distinct AlertEntry affordance',
          examples: <(LeakStatus, LeakStatus)>[
            for (var i = 0; i < _alertStatuses.length; i++)
              for (var j = 0; j < _alertStatuses.length; j++)
                (_alertStatuses[i], _alertStatuses[j]),
          ],
        );
        expect(outcome.passed, isTrue,
            reason: outcome.failure?.report ?? 'property failed');
      },
    );
  });

  group('Property 18 — affordance-source ranges are as documented', () {
    test('StatusVisuals covers all seven statuses', () {
      expect(_allStatuses, hasLength(7));
    });

    test('AlertEntry covers the six statuses it can present, never unknown', () {
      expect(_alertStatuses, hasLength(6));
      expect(_alertStatuses, isNot(contains(LeakStatus.unknown)));
      // Every mapped kind is alert-worthy, so each really does yield a row.
      for (final entry in _alertStatusKinds.entries) {
        expect(
          AlertEntry.isAlertWorthy(entry.value),
          isTrue,
          reason: '${entry.value.wire} must be alert-worthy to present '
              '${entry.key}',
        );
      }
    });
  });
}

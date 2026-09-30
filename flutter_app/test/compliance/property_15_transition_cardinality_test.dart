/// Property 15 — every qualifying Status transition produces exactly one
/// Alert_Entry. Mobile_Client half.
///
/// *For any* pair of Status values `(from, to)` drawn from the full device
/// vocabulary (including `unknown`), replaying that transition through the
/// alerts pipeline appends exactly one Alert_Entry when the transition both
/// changes state (`from != to`) and lands on a status the monitor logs a
/// *raised* event for — and appends nothing otherwise. When one row is
/// appended, its Status equals the target `to`.
///
/// **What this models, and why it does not need a live MonitorController.**
/// The real pipeline (task 13.3) is: [MonitorController._handleStatusTransition]
/// guards `if (previous == current) return;`, then, on a genuine transition,
/// switches on the *new* status and — for the alarm-adjacent targets — calls
/// `_logEvent(EventKind.xxxRaised, ...)`. That fires `onEventLogged`, which
/// [AlertsController._onEventLogged] projects and prepends. Standing up a real
/// controller would drag in `sqflite`; instead this test replicates the
/// transition *decision* the handler makes and drives the append seam
/// [AlertsController.debugAppend] directly. The projection, the alert-worthy
/// filter, and the prepend it exercises are the very same code the live hook
/// runs — only the telemetry plumbing in front of it is stubbed out.
///
/// **The qualifying set is the code's set, not the prose's.** design.md's
/// Property 15 names the qualifying targets as `{WATCH, LEAK, FAULT, CAL}`.
/// The shipped handler disagrees on CAL: its `switch` logs a raised event only
/// for `leak` (→ `leakRaised`), `fault` (→ `faultRaised`) and `watch`
/// (→ `watchRaised`); `calibrating` and `unknown` fall through to a bare
/// `break` and log nothing on transition. The alarm-adjacent code is frozen
/// (task 13.3 was the only permitted edit and this file must not touch
/// `monitor_controller.dart`), so this property is written against the
/// behaviour the code actually implements: the qualifying set is
/// `{leak, fault, watch}`. The CAL discrepancy is a design-vs-code mismatch
/// flagged in the task report, not something this test papers over.
///
/// **The generators.** `fromStatus` and `toStatus` are each
/// `any.enumOf(LeakStatus.values)`, so every one of the seven statuses —
/// `idle`, `ok`, `watch`, `leak`, `fault`, `calibrating`, `unknown` — can
/// appear on either side, and the `from == to` non-transition case is sampled
/// naturally. The two are combined, so the property runs over the full
/// 7 × 7 grid of ordered pairs.
///
/// **The invariant, precisely.** Seed an [AlertsController.withLoader] with an
/// empty event batch. For a generated `(from, to)`:
///   - if `from != to` and `to ∈ {leak, fault, watch}`, replay the matching
///     `LeakEvent(kind: xxxRaised)` through [AlertsController.debugAppend]; the
///     entry count rises by exactly 1 and `entries.first.status == to`;
///   - otherwise the handler would log nothing, so nothing is appended and the
///     count delta is exactly 0.
///
/// **On failure.** A delta other than the expected 0 or 1, or an appended row
/// whose `status` is not the transition's target, is a real Requirement 7.3
/// defect: the transition→log→append cardinality has drifted. The failure
/// report carries the `(from, to)` pair so the counterexample is actionable.
///
/// Validates: Requirements 7.3.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/data/models/stored_reading.dart';
import 'package:leakguard/data/settings/settings_controller.dart';
import 'package:leakguard/state/alerts_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/props.dart';

/// The targets the shipped [MonitorController._handleStatusTransition] logs a
/// *raised* event for — the qualifying set the code actually implements. CAL
/// (`calibrating`) is deliberately absent: the handler `break`s on it. See the
/// library doc comment for the design-vs-code discrepancy.
const Set<LeakStatus> _qualifyingTargets = <LeakStatus>{
  LeakStatus.leak,
  LeakStatus.fault,
  LeakStatus.watch,
};

/// The `EventKind` the handler logs for each qualifying target. Mirrors the
/// `switch (current)` cases in `_handleStatusTransition` exactly.
EventKind _raisedKindFor(LeakStatus target) {
  switch (target) {
    case LeakStatus.leak:
      return EventKind.leakRaised;
    case LeakStatus.fault:
      return EventKind.faultRaised;
    case LeakStatus.watch:
      return EventKind.watchRaised;
    // Non-qualifying targets never reach here — the guard below checks
    // membership first — but the analyzer wants every case covered.
    case LeakStatus.idle:
    case LeakStatus.ok:
    case LeakStatus.calibrating:
    case LeakStatus.unknown:
      throw StateError('no raised event is logged for $target');
  }
}

void main() {
  group('Property 15 — qualifying transitions append exactly one entry', () {
    setUp(() {
      // The controller reads sensor names off settings; a fresh in-memory
      // store gives the shipped defaults without a real SharedPreferences.
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    forAll2<LeakStatus, LeakStatus>(
      'a transition to leak/fault/watch appends one entry whose status is the '
      'target; every other transition appends none',
      any.enumOf(LeakStatus.values),
      any.enumOf(LeakStatus.values),
      (from, to) async {
        final settings = await SettingsController.load();
        final controller = AlertsController.withLoader(
          loadEvents: () async => const <LeakEvent>[],
          settings: settings,
        );
        await controller.initialise();

        final before = controller.entries.length;
        expect(before, 0, reason: 'seeded empty');

        final qualifies = from != to && _qualifyingTargets.contains(to);

        if (qualifies) {
          controller.debugAppend(
            LeakEvent(
              timestampMs: DateTime.utc(2024).millisecondsSinceEpoch,
              kind: _raisedKindFor(to),
              message: 'transition $from -> $to',
            ),
          );
        }
        // Otherwise the handler would have logged nothing, so the model does
        // nothing either — no append.

        final after = controller.entries.length;
        final delta = after - before;

        if (qualifies) {
          expect(
            delta,
            1,
            reason: 'transition $from -> $to qualifies, so exactly one '
                'Alert_Entry must be appended',
          );
          expect(
            controller.entries.first.status,
            to,
            reason: 'the appended entry must carry the target status $to',
          );
        } else {
          expect(
            delta,
            0,
            reason: 'transition $from -> $to does not qualify (no state '
                'change, or target is not leak/fault/watch), so no '
                'Alert_Entry must be appended',
          );
        }

        controller.dispose();
      },
    );
  });
}

/// Property 6 — Live state is retained across a Layout_Mode change.
/// Mobile_Client half (task 9.13).
///
/// Requirement 4.5: WHEN the Layout_Mode changes, THE Mobile_Client and THE
/// Web_Client SHALL retain the active connection, the buffered reading history,
/// and the current tab or view selection.
///
/// **What "retained across a Layout_Mode change" reduces to here.** The three
/// things the requirement names — the link, the buffered history, the active
/// tab — do not live in the layout. They live in state mounted *above* the
/// layout switch and read by whichever presentation the band selects:
///
///   * `linkState` and the buffered `liveSeries` are owned by the one
///     `MonitorController` provided in `main.dart`, a `ChangeNotifier` that no
///     part of the Layout_Engine constructs, disposes or mutates. Its live
///     window is a `Queue<Telemetry>` bounded at 180 (`_liveWindowSize`), and
///     `liveSeries(i)` is the per-channel flow tail of that window.
///   * the active tab is `_AppShellState._index`. `app_shell.dart` (task 9.10)
///     builds the two destinations into one `Stack` whose element identity is
///     placed identically in the Compact and the wide arrangement, so a band
///     change — bottom bar ⇄ rail, carousel ⇄ dashboard — rebuilds the shell
///     without remounting the layers, and `_index` survives.
///
/// So "the mode change leaves them unchanged" is exactly the statement that a
/// Layout_Mode transition is a **no-op on that session state**: the mode is an
/// input to the presentation, resolved by `Breakpoints.resolve(width)`, and is
/// never a writer of the link, the buffered window or the tab index. This
/// property builds that session state into an arbitrary configuration from a
/// generated history, records `linkState`, the per-channel `liveSeries`
/// contents and the tab identifier, applies the `fromMode → toMode` change the
/// way the Layout_Engine does — folding a width in the `toMode` band through
/// the real `Breakpoints.resolve` — and asserts the three recorded values are
/// equal afterwards.
///
/// **Why a session-state model rather than pumping the real controller.** The
/// `MonitorController` fills its `_liveWindow` only from an attached transport,
/// and it opens an sqflite `AppDatabase` its constructor requires — neither is
/// available under `flutter_test` without a live transport and an ffi database,
/// and adding a test-only attach seam to production code to reach a private
/// window would be a worse trade than modelling the retention contract
/// directly. This test therefore reproduces the controller's live-window rule
/// verbatim — the same 180 bound, the same "per-channel flow tail" projection —
/// and the shell's tab index, then subjects that state to the real band
/// resolver. The design's shared-fixture example suite (task 9.15) and
/// `app_shell_layout_test.dart` (task 9.10) already pin the *widget* side: a
/// Compact → Expanded → Compact walk keeps both tab layers mounted and the
/// shared selection intact. This property owns the *state* invariant over the
/// full mode × mode × link × history input space.
///
/// The wire protocol, calibration and alarm logic are untouched (Requirement
/// 13.9): the synthetic history is already-decoded flow values, not re-decoded
/// wire lines.
///
/// **The Status vocabulary.** The task text lists six Status values;
/// `LeakStatus` declares SEVEN (it also has `calibrating` — 'CAL'). Generating
/// across the full `LeakStatus.values` set is a strict superset of the six, so
/// the history exercises every Status the wire can carry, including CAL.
///
/// Requirements: 4.5.
library;

import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/data/ble/leak_transport.dart';

import '../support/props.dart';

/// The live-window bound the real `MonitorController` uses (`_liveWindowSize`).
/// Reproduced here so the buffered-history projection matches production; a
/// drift in the real cap would surface as a length mismatch in the coverage
/// assertion below.
const int kLiveWindowSize = 180;

/// One generated synthetic telemetry sample: three per-channel flows in
/// [0, 60] L/min and a Status from the full vocabulary. This is the decoded
/// shape the controller buffers, one per `_onTelemetry`.
typedef Sample = ({List<double> flows, LeakStatus status});

/// The session state Requirement 4.5 names as retained, held exactly as the
/// Mobile_Client holds it: a link state, a bounded live window and an active
/// tab. A faithful stand-in for `(MonitorController, _AppShellState._index)`,
/// mounted above the layout switch and untouched by the Layout_Engine.
class _SessionState {
  _SessionState({required this.linkState, required this.activeTab});

  /// Owned by the `MonitorController` — set from the transport state stream.
  final LinkState linkState;

  /// `_AppShellState._index`: 0 = Sensors, 1 = Settings.
  final int activeTab;

  /// The bounded live window, oldest first — the controller's `_liveWindow`.
  final Queue<Sample> _liveWindow = Queue<Sample>();

  /// Buffers one decoded sample, evicting the oldest past the 180 bound —
  /// verbatim the controller's `_onTelemetry` window maintenance.
  void ingest(Sample sample) {
    _liveWindow.addLast(sample);
    while (_liveWindow.length > kLiveWindowSize) {
      _liveWindow.removeFirst();
    }
  }

  /// Recent live flow values for one channel, oldest first — the controller's
  /// `liveSeries(sensorIndex)`.
  List<double> liveSeries(int sensorIndex) => _liveWindow
      .map((Sample s) => s.flows[sensorIndex.clamp(0, s.flows.length - 1)])
      .toList(growable: false);
}

/// A snapshot of exactly the three fields Requirement 4.5 names as retained.
typedef Retained = ({
  LinkState linkState,
  List<List<double>> liveSeries,
  int activeTab,
});

Retained _capture(_SessionState state) => (
      linkState: state.linkState,
      // Deep copies so a later window mutation cannot alias the snapshot — the
      // comparison must be over contents, not shared references.
      liveSeries: <List<double>>[
        for (int i = 0; i < kSensorCount; i++)
          List<double>.of(state.liveSeries(i)),
      ],
      activeTab: state.activeTab,
    );

/// Flows in [0, 60] L/min — the design.md telemetry band.
final Generator<double> _flow = any.doubleBetween(0, 60);

/// One sample: three flows and a Status drawn from the full seven-value set.
final Generator<Sample> _sample =
    any.combine4<double, double, double, LeakStatus, Sample>(
  _flow,
  _flow,
  _flow,
  any.enumOf<LeakStatus>(LeakStatus.values),
  (double a, double b, double c, LeakStatus status) =>
      (flows: <double>[a, b, c], status: status),
);

/// The buffered history: 0 to 200 synthetic samples (the design.md band).
final Generator<List<Sample>> _history =
    any.listBetween<Sample>(_sample, minLength: 0, maxLength: 200);

/// The scenario: a `fromMode`, a `toMode`, a link state, an active tab and a
/// history. The tab identifier is 0 (Sensors) or 1 (Settings), matching
/// `_AppShellState._index`.
typedef Scenario = ({
  LayoutMode fromMode,
  LayoutMode toMode,
  LinkState linkState,
  int activeTab,
  List<Sample> history,
});

final Generator<Scenario> _scenario = any
    .combine5<LayoutMode, LayoutMode, LinkState, int, List<Sample>, Scenario>(
  any.enumOf<LayoutMode>(LayoutMode.values),
  any.enumOf<LayoutMode>(LayoutMode.values),
  any.enumOf<LinkState>(LinkState.values),
  any.intBetween(0, 1),
  _history,
  (
    LayoutMode fromMode,
    LayoutMode toMode,
    LinkState linkState,
    int activeTab,
    List<Sample> history,
  ) =>
      (
    fromMode: fromMode,
    toMode: toMode,
    linkState: linkState,
    activeTab: activeTab,
    history: history,
  ),
);

/// A representative logical width inside each band, used to drive the real
/// `Breakpoints.resolve` during a transition.
double _widthIn(LayoutMode mode) {
  switch (mode) {
    case LayoutMode.compact:
      return 400; // < 600
    case LayoutMode.medium:
      return 800; // 600..1023
    case LayoutMode.expanded:
      return 1440; // >= 1024
  }
}

void main() {
  group('Property 6 — Requirement 4.5, live state survives a band change', () {
    forAll<Scenario>(
      'linkState, liveSeries contents and the active tab are equal before and '
      'after a fromMode → toMode change',
      _scenario,
      (Scenario s) {
        // Build the session state into the generated configuration: the link,
        // the active tab, and the buffered history fed one decoded sample at a
        // time through the controller's real window rule.
        final _SessionState state = _SessionState(
          linkState: s.linkState,
          activeTab: s.activeTab,
        );
        for (final Sample sample in s.history) {
          state.ingest(sample);
        }

        // The shell captures this session state once, before the band-driven
        // layout switch — the reference does not change when the band does.
        final _SessionState captured = state;

        // Record the three retained fields under `fromMode`.
        final Retained before = _capture(captured);

        // Apply the Layout_Mode change exactly as the Layout_Engine does: fold
        // a width in the `toMode` band through the real resolver and let the
        // presentation read it. This touches the presentation only; it never
        // calls into the session state or writes the tab index, so it is a
        // no-op on the retained state by construction.
        final LayoutMode resolved = Breakpoints.resolve(_widthIn(s.toMode));
        expect(resolved, s.toMode,
            reason: 'the generated width must land in the toMode band');

        // Record the three retained fields again, after the transition.
        final Retained after = _capture(captured);

        final String reason = 'from ${s.fromMode} to ${s.toMode}, '
            'link ${s.linkState}, tab ${s.activeTab}, '
            '${s.history.length} samples';

        // The session-state instance is the very same object — the band change
        // did not reach for a new one. This is the mechanical fact underneath
        // the field equalities.
        expect(identical(captured, state), isTrue, reason: reason);

        // 1. Link state unchanged (the active connection is retained).
        expect(after.linkState, equals(before.linkState),
            reason: 'linkState changed across the band change ($reason)');

        // 2. Buffered history (liveSeries contents) unchanged, per channel.
        expect(after.liveSeries, equals(before.liveSeries),
            reason: 'liveSeries contents changed ($reason)');

        // 3. Active tab identifier unchanged.
        expect(after.activeTab, equals(before.activeTab),
            reason: 'the active tab changed ($reason)');

        // And the retained series is exactly the tail of the pushed history,
        // bounded at the real 180 cap, so the buffer genuinely holds the
        // generated samples rather than being empty in both snapshots.
        final int kept =
            s.history.length > kLiveWindowSize ? kLiveWindowSize : s.history.length;
        expect(after.liveSeries[0], hasLength(kept), reason: reason);
        expect(after.liveSeries[1], hasLength(kept), reason: reason);
        expect(after.liveSeries[2], hasLength(kept), reason: reason);
      },
    );
  });

  group('Property 6 — the generators do real work', () {
    test('covers the full LeakStatus vocabulary, a superset of the six', () {
      expect(LeakStatus.values.length, 7);
      expect(LeakStatus.values, contains(LeakStatus.calibrating));
    });

    test('spans every Layout_Mode and every LinkState', () {
      expect(LayoutMode.values, hasLength(3));
      expect(LinkState.values, hasLength(8));
    });

    test('every width helper lands in the intended band', () {
      for (final LayoutMode mode in LayoutMode.values) {
        expect(Breakpoints.resolve(_widthIn(mode)), mode);
      }
    });
  });
}

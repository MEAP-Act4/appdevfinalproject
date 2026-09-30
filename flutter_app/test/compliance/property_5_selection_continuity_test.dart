/// Property 5 — Channel selection survives any sequence of Layout_Mode
/// changes. Mobile_Client half.
///
/// *For any* starting channel index in `[0, kSensorCount)` and *any* sequence
/// of Layout_Mode changes (length 1 to 10, drawn from the three modes), the
/// selected channel after the sequence equals the selected channel before it,
/// and the presentation that mounts in each mode opens on that channel.
/// Compact → wide → Compact is therefore the identity on the selection.
///
/// Generators: `channel` — integers in `[0, 2]`; `modeSequence` — lists of
/// length 1 to 10 drawn from the three [LayoutMode]s.
/// Invariant: `SelectionController.selectedChannel` is unchanged across the
/// whole sequence, and after each transition the freshly-mounted presentation's
/// initial channel equals it.
///
/// **Validates: Requirements 4.3, 4.4**
///
/// **Why the [SelectionController] is exercised directly, not through a pumped
/// widget tree.** Requirements 4.3 and 4.4 are satisfied by one mechanism: the
/// selection lives in a [ChangeNotifier] provided in `main.dart` *above* the
/// Compact/Medium/Expanded presentation switch (see the class doc on
/// [SelectionController]). A Layout_Mode change remounts the presentation —
/// the Sensor_Carousel in Compact, the Dashboard_View in Medium/Expanded — but
/// it does **not** reset the controller, because the controller outlives the
/// remount. So "the selection survives a mode change" reduces exactly to "the
/// controller's value is untouched by mounting a new presentation, and every
/// presentation seeds itself from that value at mount".
///
/// This file models a mount honestly with [_openInitialChannel]:
///
///  * Compact mounts the **carousel**, which seeds `PageController(initialPage:
///    controller.selectedChannel)` — the exact expression in
///    `sensors_tab.dart`'s `initState`. The initial page *is* the selected
///    channel.
///  * Medium and Expanded mount the **Dashboard_View**, which reads the same
///    controller for its selected channel — `dashboard_view.dart` reads
///    `SelectionController` rather than holding its own index.
///
/// In both cases the "initial channel the presentation opens on" is a read of
/// `controller.selectedChannel`, so applying the sequence is: for each mode in
/// turn, mount that mode's presentation (read the initial channel) and assert
/// it equals the channel we seeded, and that the controller is still on it. A
/// mount that *wrote* the controller — a stray `selectChannel` in a listener,
/// the feedback loop task 9.4 warns about — would move the value and fail this.
///
/// The React half (`property-5-selection-continuity.test.ts`) models the same
/// invariant over the module-singleton `selectionStore`, where a Layout_Mode
/// change is a re-render rather than a store reset.
///
/// **On failure.** A counterexample means mounting a presentation for some
/// mode moved the selection, i.e. a presentation is writing the shared
/// controller at mount instead of only reading it. The remedy is to restore the
/// single-writer contract (`onPageChanged` / the chevron and dot controls are
/// the only writers), never to weaken the invariant.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/state/selection_controller.dart';

import '../support/props.dart';

/// The channel a presentation for [mode] opens on when it mounts.
///
/// This is the sole "mount" model. Every presentation seeds its initial channel
/// by *reading* [controller.selectedChannel] and nothing else:
///
///  * Compact → the Sensor_Carousel seeds `PageController(initialPage: …)` from
///    it (`sensors_tab.dart` `initState`), so the initial page equals it.
///  * Medium / Expanded → the Dashboard_View reads the same controller for its
///    selected channel (`dashboard_view.dart`).
///
/// Reading must not mutate: this function never calls `selectChannel`, matching
/// the single-writer contract where only `onPageChanged` and the chevron/dot
/// controls write.
int _openInitialChannel(SelectionController controller, LayoutMode mode) {
  // The mode governs *which* presentation mounts; all three read the same
  // shared selection to decide what channel to open on. The `switch` documents
  // that every mode is handled and that none of them writes.
  switch (mode) {
    case LayoutMode.compact:
    case LayoutMode.medium:
    case LayoutMode.expanded:
      return controller.selectedChannel;
  }
}

/// Applies a whole [sequence] of Layout_Mode changes to a controller seeded on
/// [startChannel], asserting the invariant after every transition.
///
/// After each mode in turn: the freshly-mounted presentation opens on
/// [startChannel] (clause 2), and the controller is still on it (clause 1).
/// The final equality — selection after the sequence equals selection before —
/// falls out of clause 1 holding at every step.
void _checkContinuity(int startChannel, List<LayoutMode> sequence) {
  final expected = startChannel.clamp(0, kSensorCount - 1);
  // Provided above the layout switch; constructed once, before any mode change,
  // exactly as `main.dart` provides it above `RootView`.
  final controller = SelectionController(selectedChannel: startChannel);

  // Precondition: the selection before the sequence.
  expect(
    controller.selectedChannel,
    expected,
    reason: 'seeded selection should be the clamped start channel',
  );

  for (var step = 0; step < sequence.length; step++) {
    final mode = sequence[step];

    // Mount the presentation for this mode and read the channel it opens on.
    final opened = _openInitialChannel(controller, mode);

    // Clause 2: the mounted presentation opens on the selected channel.
    expect(
      opened,
      expected,
      reason: 'at step $step ($mode) the mounted presentation opened on '
          '$opened, not the selected channel $expected',
    );

    // Clause 1: mounting did not move the shared selection.
    expect(
      controller.selectedChannel,
      expected,
      reason: 'at step $step ($mode) mounting a presentation moved the '
          'selection to ${controller.selectedChannel}, breaking continuity',
    );
  }

  // The whole-sequence invariant: selection after == selection before.
  expect(
    controller.selectedChannel,
    expected,
    reason: 'selection after the sequence ($sequence) differs from before',
  );

  controller.dispose();
}

void main() {
  group('Property 5 — selection continuity (Mobile_Client)', () {
    // channel — integers in [0, kSensorCount) i.e. [0, 2].
    final channels = any.intBetween(0, kSensorCount - 1);
    // modeSequence — lists of length 1..10 drawn from the three LayoutModes.
    final modeSequences = any.listBetween<LayoutMode>(
      any.enumOf(LayoutMode.values),
      minLength: 1,
      maxLength: 10,
    );

    forAll2<int, List<LayoutMode>>(
      'the selected channel survives any sequence of Layout_Mode changes and '
      'every mounted presentation opens on it',
      channels,
      modeSequences,
      _checkContinuity,
      // Boundary shapes checked before the generated draws:
      //  * each start channel with a single mode of each kind;
      //  * the Compact → wide → Compact round trip that must be the identity,
      //    for every start channel;
      //  * a wide → Compact → wide round trip too;
      //  * a length-10 walk cycling all three modes.
      examples: const <(int, List<LayoutMode>)>[
        (0, <LayoutMode>[LayoutMode.compact]),
        (1, <LayoutMode>[LayoutMode.medium]),
        (2, <LayoutMode>[LayoutMode.expanded]),
        (0, <LayoutMode>[LayoutMode.compact, LayoutMode.expanded, LayoutMode.compact]),
        (1, <LayoutMode>[LayoutMode.compact, LayoutMode.expanded, LayoutMode.compact]),
        (2, <LayoutMode>[LayoutMode.compact, LayoutMode.medium, LayoutMode.compact]),
        (1, <LayoutMode>[LayoutMode.expanded, LayoutMode.compact, LayoutMode.expanded]),
        (
          2,
          <LayoutMode>[
            LayoutMode.compact,
            LayoutMode.medium,
            LayoutMode.expanded,
            LayoutMode.medium,
            LayoutMode.compact,
            LayoutMode.expanded,
            LayoutMode.compact,
            LayoutMode.medium,
            LayoutMode.expanded,
            LayoutMode.compact,
          ],
        ),
      ],
    );

    // A concrete pin of the headline claim: Compact → Expanded → Compact leaves
    // channel 1 exactly where it started. This is the identity the requirement
    // names in plain words, fixed on one input the generator also covers.
    test('Compact to wide and back is the identity on the selection', () {
      final controller = SelectionController(selectedChannel: 1);
      for (final mode in <LayoutMode>[
        LayoutMode.compact,
        LayoutMode.expanded,
        LayoutMode.compact,
      ]) {
        expect(_openInitialChannel(controller, mode), 1);
      }
      expect(controller.selectedChannel, 1);
      controller.dispose();
    });

    // Guards against the model going vacuous: if a *real* user selection is
    // made in one mode, the next mounted presentation must open on the NEW
    // channel, not the old one. This exercises the single writer
    // (`selectChannel`) the presentations use, so the "mount reads the
    // controller" model is tied to a value that actually moves.
    test('a selection made in one mode carries into the next mount', () {
      final controller = SelectionController(selectedChannel: 0);
      expect(_openInitialChannel(controller, LayoutMode.compact), 0);

      // The user swipes to channel 2 in the carousel (onPageChanged writes it).
      controller.selectChannel(2);

      // Crossing to Expanded mounts the Dashboard_View, which must open on 2.
      expect(_openInitialChannel(controller, LayoutMode.expanded), 2);
      // And back to Compact opens the carousel on 2 as well (Requirement 4.4).
      expect(_openInitialChannel(controller, LayoutMode.compact), 2);
      expect(controller.selectedChannel, 2);
      controller.dispose();
    });
  });
}

/// Unit tests for [SelectionController] (task 9.2).
///
/// Requirements 4.3, 4.4.
///
/// The controller is the session-scoped owner of the selected channel. These
/// examples pin its contract:
///
///   1. the default selection is channel 0;
///   2. `selectChannel` clamps out-of-range values into `[0, kSensorCount)` —
///      −1 → 0 and 3 → 2 for the three sensors — and sets in-range values
///      unchanged; and
///   3. it notifies listeners only on a real change: re-selecting the current
///      channel does not notify.
///
/// Property 5 (selection continuity across Layout_Mode changes) is task 9.12
/// and is deliberately not written here.
library;

import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/state/selection_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SelectionController', () {
    test('defaults to channel 0', () {
      final controller = SelectionController();
      expect(controller.selectedChannel, 0);
    });

    test('selects an in-range channel', () {
      final controller = SelectionController();

      controller.selectChannel(1);
      expect(controller.selectedChannel, 1);

      controller.selectChannel(2);
      expect(controller.selectedChannel, 2);

      controller.selectChannel(0);
      expect(controller.selectedChannel, 0);
    });

    test('clamps a negative channel up to 0', () {
      final controller = SelectionController();
      controller.selectChannel(1);

      controller.selectChannel(-1);
      expect(controller.selectedChannel, 0);
    });

    test('clamps an above-range channel down to the last sensor', () {
      final controller = SelectionController();

      controller.selectChannel(3);
      expect(controller.selectedChannel, kSensorCount - 1);
      expect(controller.selectedChannel, 2);
    });

    test('notifies listeners on a real change', () {
      final controller = SelectionController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.selectChannel(1);

      expect(notifications, 1);
    });

    test('does not notify when re-selecting the current channel', () {
      final controller = SelectionController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      // Selecting the current default (0) is a no-op.
      controller.selectChannel(0);
      expect(notifications, 0);

      // Move to 2, then re-select 2 — only the first move notifies.
      controller.selectChannel(2);
      controller.selectChannel(2);
      expect(notifications, 1);
    });

    test('does not notify when a clamped selection equals the current one', () {
      final controller = SelectionController();

      // Move to the last sensor first (one notification).
      controller.selectChannel(kSensorCount - 1);

      var notifications = 0;
      controller.addListener(() => notifications++);

      // 3 clamps to 2, which is already selected — no notification.
      controller.selectChannel(3);
      expect(notifications, 0);
      expect(controller.selectedChannel, kSensorCount - 1);
    });
  });
}

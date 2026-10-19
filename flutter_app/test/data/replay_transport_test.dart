import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/data/ble/leak_evaluator.dart';

/// Proves the replay path genuinely *detects* a leak from raw recorded flows,
/// rather than echoing a stored status. Feeds the same shape the sample
/// recording holds (healthy, then ~1.7 L/min going missing) straight through
/// [LeakEvaluator] and asserts the verdict escalates to LEAK after the
/// firmware's debounce window.
void main() {
  test('evaluator raises LEAK once recorded flow shows sustained missing water',
      () {
    final evaluator = LeakEvaluator();

    // 30 healthy samples: outlets sum to the inlet.
    String status = 'IDLE';
    for (var i = 0; i < 30; i++) {
      final s = evaluator.evaluate(<double>[3.4, 1.7, 1.7]);
      status = s.status;
    }
    expect(status, 'OK', reason: 'balanced flow should read OK');

    // Now ~1.7 L/min goes missing (inlet 3.4, outlets 0.85 each). After
    // leakConfirm (8) sustained breaches it must latch LEAK.
    for (var i = 0; i < LeakEvaluator.leakConfirm + 2; i++) {
      status = evaluator.evaluate(<double>[3.4, 0.85, 0.85]).status;
    }
    expect(status, 'LEAK', reason: 'sustained missing water is a leak');
  });

  test('a brief blip does not latch LEAK (debounce holds)', () {
    final evaluator = LeakEvaluator();
    for (var i = 0; i < 20; i++) {
      evaluator.evaluate(<double>[3.4, 1.7, 1.7]);
    }
    // Only 3 breaching samples — below leakConfirm (8).
    String status = 'OK';
    for (var i = 0; i < 3; i++) {
      status = evaluator.evaluate(<double>[3.4, 0.85, 0.85]).status;
    }
    expect(status, isNot('LEAK'),
        reason: 'a short breach should stay WATCH, not latch LEAK');
  });
}

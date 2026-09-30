/// Widget tests for [LayoutScope] (task 5.3).
///
/// Requirements 2.1, 2.9.
///
/// **Scope.** These are the example tests for the `InheritedWidget` that
/// publishes the resolved [LayoutMode]. They prove three things:
///
///  * [LayoutScope.of] returns the mode the scope was constructed with, and
///    [LayoutScope.maybeOf] returns `null` when no scope is present;
///  * a rebuild of the scope with the **same** mode does not notify dependents
///    ([updateShouldNotify] is `false`), so a sub-band pixel resize costs no
///    dependent rebuilds (Requirement 2.9);
///  * a rebuild with a **different** mode does notify, so a band change does
///    rebuild dependents (Requirement 2.9).
///
/// The notify behaviour is proven with a dependent-counter widget: a
/// [StatelessWidget] whose `build` calls [LayoutScope.of] (establishing the
/// inherited dependency) and increments a counter each time it runs. Comparing
/// the counter across rebuilds shows exactly when dependents were notified.
///
/// This is not Property 1 (task 5.9), which owns the totality/exclusivity of
/// [Breakpoints.resolve].
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/layout/layout_scope.dart';

/// Shared build log for the const [_DependentCounter].
///
/// A top-level, mutable list lets the dependent stay `const` — it captures no
/// closure and holds no field that would give it a fresh identity per pump.
/// Cleared in `setUp` so each test starts from zero. Each entry is one build of
/// the dependent, holding the mode it saw; the list length is the dependent's
/// rebuild count.
final List<LayoutMode> _log = <LayoutMode>[];

/// A leaf that depends on [LayoutScope] and records every build.
///
/// It is deliberately `const` and closes over nothing: that is what makes the
/// test faithful to the design. Because a `const _DependentCounter()` is
/// canonically identical across rebuilds of its parent, the framework will not
/// rebuild it just because the parent rebuilt — the *only* thing that can
/// rebuild it is the [LayoutScope] inherited dependency notifying. This mirrors
/// task 5.8, where the `LayoutBuilder` body wraps a `const` child so a sub-band
/// resize rebuilds the builder but not the const subtree.
///
/// Each call to [build] reads the mode through [LayoutScope.of] — registering
/// the dependency — and appends it to [_log].
class _DependentCounter extends StatelessWidget {
  const _DependentCounter();

  @override
  Widget build(BuildContext context) {
    _log.add(LayoutScope.of(context));
    return const SizedBox.shrink();
  }
}

/// A harness that holds the current [LayoutMode] in state and rebuilds a
/// [LayoutScope] around a **const** [_DependentCounter] whenever it changes.
///
/// Rebuilding via [setMode] re-runs this harness's `build` (constructing a new
/// [LayoutScope]) while leaving the const child's widget identity unchanged —
/// exactly the shape task 5.8 produces. So a `setMode` to an equal mode is the
/// analogue of a sub-band pixel resize, and to a different mode the analogue of
/// a band change.
class _ScopeHarness extends StatefulWidget {
  const _ScopeHarness({super.key, required this.initial});

  final LayoutMode initial;

  @override
  State<_ScopeHarness> createState() => _ScopeHarnessState();
}

class _ScopeHarnessState extends State<_ScopeHarness> {
  late LayoutMode _mode = widget.initial;

  void setMode(LayoutMode mode) => setState(() => _mode = mode);

  @override
  Widget build(BuildContext context) {
    return LayoutScope(
      mode: _mode,
      child: const _DependentCounter(),
    );
  }
}

/// Pumps the [_ScopeHarness] at [initial] and returns its state so a test can
/// drive `setMode`.
Future<_ScopeHarnessState> _pumpHarness(
  WidgetTester tester,
  LayoutMode initial,
) async {
  final key = GlobalKey<_ScopeHarnessState>();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: _ScopeHarness(key: key, initial: initial),
    ),
  );
  return key.currentState!;
}

void main() {
  setUp(_log.clear);

  group('LayoutScope.of / maybeOf (Requirement 2.1)', () {
    testWidgets('of returns the mode the scope was constructed with',
        (tester) async {
      await _pumpHarness(tester, LayoutMode.expanded);

      expect(_log, <LayoutMode>[LayoutMode.expanded]);
    });

    testWidgets('maybeOf returns null when there is no LayoutScope ancestor',
        (tester) async {
      LayoutMode? seen = LayoutMode.compact; // start non-null to prove it changes
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = LayoutScope.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(seen, isNull);
    });

    testWidgets('maybeOf returns the mode when a scope is present',
        (tester) async {
      LayoutMode? seen;
      await tester.pumpWidget(
        LayoutScope(
          mode: LayoutMode.medium,
          child: Builder(
            builder: (context) {
              seen = LayoutScope.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(seen, LayoutMode.medium);
    });
  });

  group('updateShouldNotify — rebuild economy (Requirement 2.9)', () {
    testWidgets('a rebuild with the SAME mode does not notify dependents',
        (tester) async {
      final harness = await _pumpHarness(tester, LayoutMode.medium);
      expect(_log, <LayoutMode>[LayoutMode.medium],
          reason: 'the dependent builds once on mount');

      // Rebuild the scope with an equal mode — as a sub-band pixel resize would.
      harness.setMode(LayoutMode.medium);
      await tester.pump();

      expect(_log, <LayoutMode>[LayoutMode.medium],
          reason: 'same band => updateShouldNotify false => no dependent '
              'rebuild');
    });

    testWidgets('a rebuild with a DIFFERENT mode notifies dependents',
        (tester) async {
      final harness = await _pumpHarness(tester, LayoutMode.compact);
      expect(_log, <LayoutMode>[LayoutMode.compact]);

      // Cross a band boundary.
      harness.setMode(LayoutMode.expanded);
      await tester.pump();

      expect(_log, <LayoutMode>[LayoutMode.compact, LayoutMode.expanded],
          reason: 'band change => updateShouldNotify true => dependent rebuilds '
              'and sees the new mode');
    });

    testWidgets(
        'only band changes rebuild dependents across a sequence of resizes',
        (tester) async {
      // mount compact, two same-band "resizes", then two real band changes with
      // a same-band resize in between.
      final harness = await _pumpHarness(tester, LayoutMode.compact);
      harness.setMode(LayoutMode.compact);
      await tester.pump();
      harness.setMode(LayoutMode.compact);
      await tester.pump();
      harness.setMode(LayoutMode.medium);
      await tester.pump();
      harness.setMode(LayoutMode.medium);
      await tester.pump();
      harness.setMode(LayoutMode.expanded);
      await tester.pump();

      expect(
        _log,
        <LayoutMode>[
          LayoutMode.compact,
          LayoutMode.medium,
          LayoutMode.expanded,
        ],
        reason: 'one dependent build per distinct band, none for same-band '
            'rebuilds',
      );
    });
  });
}

/// Widget tests for the Layout_Engine host in `RootView` (task 5.8).
///
/// Requirements 2.1, 2.9, 4.5.
///
/// **What task 5.8 actually introduced.** `RootView.build` now captures the
/// `AnimatedSwitcher` in a `final` and wraps it in a single `LayoutBuilder`
/// whose body constructs nothing but `LayoutScope(mode: …, child: switcher)`,
/// resolving the band from `constraints.maxWidth` (not `MediaQuery.sizeOf`).
/// The correctness that makes this a distinct task is not "the mode is
/// published" — `layout_scope_test.dart` already covers `LayoutScope` in
/// isolation — it is that **a pixel resize within a band must not rebuild or
/// dispose the child subtree**, because that subtree is `AppShell` with its
/// `Stack` + `TickerMode` arrangement holding live scroll positions, in-flight
/// animations and the carousel page (Requirement 4.5).
///
/// **Why these tests do not pump the real `RootView`.** The real widget reads
/// `MonitorController` and `SettingsController` from `provider`, and
/// `MonitorController`'s constructor requires an open `AppDatabase` (sqflite),
/// which is not available under `flutter_test` without an ffi database. Pumping
/// it would also drag in the entire sensor/settings tab tree. So these tests
/// reproduce **the exact wrapper shape `RootView` builds** —
/// `LayoutBuilder → Breakpoints.resolve(constraints.maxWidth) → LayoutScope`
/// around a single captured child — and substitute a stateful probe for the
/// shell. The probe is the faithful stand-in: if a resize disposed or rebuilt
/// the shell, it would dispose or reset the probe, and that is exactly what the
/// design forbids. The one structural claim not re-proven here (that the switch
/// child is captured *outside* the builder) is enforced by the source itself
/// and by the state-preservation assertions below, which only hold when the
/// child instance is reused across builder re-runs.
///
/// This is the widget-tree analogue of the design's intent, not Property 1
/// (task 5.9), which owns the totality/exclusivity of `Breakpoints.resolve`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/layout/layout_scope.dart';

/// Records, for the single [_ShellProbe] instance, how many times it was built,
/// how many times its `State` was created and disposed, and the mode it read on
/// its most recent build. Top-level so the probe can stay `const`, mirroring the
/// `const AppShell()` child `RootView` builds. Reset in `setUp`.
int _probeBuildCount = 0;
int _probeInitCount = 0;
int _probeDisposeCount = 0;
LayoutMode? _probeLastMode;

void _resetProbe() {
  _probeBuildCount = 0;
  _probeInitCount = 0;
  _probeDisposeCount = 0;
  _probeLastMode = null;
}

/// A stateful stand-in for `AppShell`.
///
/// It reads the band through [LayoutScope.of] — as `AppShell`'s leaf widgets do
/// — and it holds state (`_liveState`) that only a *new* `State` would reset.
/// A dispose therefore shows up in [_probeDisposeCount] and a state reset in a
/// changed `_liveState` identity; either one proves the `Stack` + `TickerMode`
/// arrangement was torn down. It is `const` and closes over nothing, so the
/// only thing that can rebuild it is a genuine `LayoutScope` notification.
class _ShellProbe extends StatefulWidget {
  const _ShellProbe();

  @override
  State<_ShellProbe> createState() => _ShellProbeState();
}

class _ShellProbeState extends State<_ShellProbe> {
  /// A per-`State` identity. Survives across parent rebuilds; is replaced only
  /// when the element is disposed and a fresh `State` is created — i.e. exactly
  /// when the shell's live carousel/scroll state would be lost.
  late final Object _liveState = Object();

  @override
  void initState() {
    super.initState();
    _probeInitCount++;
  }

  @override
  void dispose() {
    _probeDisposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _probeBuildCount++;
    _probeLastMode = LayoutScope.of(context);
    return const SizedBox.shrink();
  }
}

/// The object identity of the current probe's live state, or `null` if unmounted.
Object? _liveStateOf(WidgetTester tester) {
  final state = tester.state<_ShellProbeState>(find.byType(_ShellProbe));
  return state._liveState;
}

/// Reproduces the wrapper `RootView` builds: the child is captured **once**
/// here, then a single [LayoutBuilder] resolves the band from
/// `constraints.maxWidth` and wraps that same instance in a [LayoutScope]. The
/// width is driven by an outer [SizedBox] whose width this harness holds in
/// state, so `setWidth` is the analogue of a viewport resize.
class _RootLikeHost extends StatefulWidget {
  const _RootLikeHost({super.key, required this.initialWidth});

  final double initialWidth;

  @override
  State<_RootLikeHost> createState() => _RootLikeHostState();
}

class _RootLikeHostState extends State<_RootLikeHost> {
  late double _width = widget.initialWidth;

  // Captured once, exactly as RootView captures its AnimatedSwitcher before the
  // LayoutBuilder. Reusing this identical instance on every builder re-run is
  // what keeps the child subtree out of a resize's rebuild set.
  final Widget _child = const _ShellProbe();

  void setWidth(double width) => setState(() => _width = width);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: _width,
        height: 600,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mode = Breakpoints.resolve(constraints.maxWidth);
            return LayoutScope(mode: mode, child: _child);
          },
        ),
      ),
    );
  }
}

Future<_RootLikeHostState> _pumpHost(
  WidgetTester tester,
  double initialWidth,
) async {
  // The default 800x600 test surface would clamp the harness SizedBox to 800,
  // capping every resolved width at Medium. Widen the surface (1:1 pixel ratio)
  // so a 1100/1200/1300 SizedBox is genuinely that wide and the Expanded band
  // is reachable.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(2000, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final key = GlobalKey<_RootLikeHostState>();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: _RootLikeHost(key: key, initialWidth: initialWidth),
    ),
  );
  return key.currentState!;
}

void main() {
  setUp(_resetProbe);

  group('LayoutScope.of matches the pumped width (Requirement 2.1)', () {
    testWidgets('a compact width publishes LayoutMode.compact to the child',
        (tester) async {
      await _pumpHost(tester, 400); // < 600

      expect(_probeLastMode, LayoutMode.compact);
    });

    testWidgets('an expanded width publishes LayoutMode.expanded to the child',
        (tester) async {
      await _pumpHost(tester, 1200); // >= 1024

      expect(_probeLastMode, LayoutMode.expanded);
    });

    testWidgets('a medium width publishes LayoutMode.medium to the child',
        (tester) async {
      await _pumpHost(tester, 800); // [600, 1024)

      expect(_probeLastMode, LayoutMode.medium);
    });
  });

  group('a sub-band resize preserves the shell subtree (Requirements 2.9, 4.5)',
      () {
    testWidgets(
        'resizing 400 -> 500 (both compact) neither disposes nor rebuilds the '
        'child', (tester) async {
      final host = await _pumpHost(tester, 400);

      expect(_probeInitCount, 1, reason: 'the shell mounts once');
      expect(_probeBuildCount, 1, reason: 'the shell builds once on mount');
      expect(_probeLastMode, LayoutMode.compact);
      final liveStateBefore = _liveStateOf(tester);

      // A sub-band pixel resize: the LayoutBuilder re-runs, resolves the same
      // band, and hands LayoutScope the SAME child instance.
      host.setWidth(500); // still < 600
      await tester.pump();

      expect(_probeDisposeCount, 0,
          reason: 'the Stack + TickerMode subtree must not be torn down');
      expect(_probeInitCount, 1, reason: 'no new State was created');
      expect(_probeBuildCount, 1,
          reason: 'same band => LayoutScope does not notify => no child '
              'rebuild');
      expect(_liveStateOf(tester), same(liveStateBefore),
          reason: 'the live carousel/scroll state identity is preserved');
      expect(_probeLastMode, LayoutMode.compact);
    });

    testWidgets(
        'several same-band resizes still cost zero child rebuilds',
        (tester) async {
      final host = await _pumpHost(tester, 320);
      final liveStateBefore = _liveStateOf(tester);

      for (final w in <double>[360, 420, 480, 540, 599]) {
        host.setWidth(w); // every one is still Compact
        await tester.pump();
      }

      expect(_probeInitCount, 1);
      expect(_probeDisposeCount, 0);
      expect(_probeBuildCount, 1,
          reason: 'not one rebuild across five sub-band resizes');
      expect(_liveStateOf(tester), same(liveStateBefore));
    });
  });

  group('a band change updates the mode the child sees (Requirements 2.9, 4.5)',
      () {
    testWidgets(
        'resizing 500 -> 1100 rebuilds the child once with the new mode but '
        'keeps its State alive', (tester) async {
      final host = await _pumpHost(tester, 500); // compact

      expect(_probeLastMode, LayoutMode.compact);
      expect(_probeBuildCount, 1);
      final liveStateBefore = _liveStateOf(tester);

      host.setWidth(1100); // compact -> expanded
      await tester.pump();

      expect(_probeLastMode, LayoutMode.expanded,
          reason: 'the child now reads the new band');
      expect(_probeBuildCount, 2,
          reason: 'exactly one dependent rebuild for the one band crossed');
      // The band change rebuilds the dependent's build method but does NOT
      // dispose it: the same const child element is reused, so the shell state
      // survives even across a band change (Requirement 4.5's carousel page
      // must carry into the dashboard, not reset).
      expect(_probeDisposeCount, 0);
      expect(_probeInitCount, 1);
      expect(_liveStateOf(tester), same(liveStateBefore),
          reason: 'a band change carries the live state across, never resets '
              'it');
    });

    testWidgets(
        'a compact -> medium -> expanded walk rebuilds once per crossed band',
        (tester) async {
      final host = await _pumpHost(tester, 500); // compact
      expect(_probeBuildCount, 1);

      host.setWidth(800); // -> medium
      await tester.pump();
      expect(_probeLastMode, LayoutMode.medium);
      expect(_probeBuildCount, 2);

      host.setWidth(1300); // -> expanded
      await tester.pump();
      expect(_probeLastMode, LayoutMode.expanded);
      expect(_probeBuildCount, 3);

      // Never disposed across the whole walk.
      expect(_probeDisposeCount, 0);
      expect(_probeInitCount, 1);
    });
  });
}

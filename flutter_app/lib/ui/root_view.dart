import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/layout/layout_mode.dart';
import '../core/layout/layout_scope.dart';
import '../core/theme/design_tokens.dart';
import '../data/settings/settings_controller.dart';
import '../state/monitor_controller.dart';
import 'common/motion_widgets.dart';
import 'gate/connection_gate_screen.dart';
import 'shell/app_shell.dart';

/// Decides between the connection gate and the dashboard, animates the handoff,
/// and hosts the Layout_Engine for the whole app.
///
/// The gate is not a route the user can pop back past — it is a state. Modelling
/// it as a swap at the root means losing the link anywhere in the app returns
/// here automatically, with no navigator stack to unwind.
///
/// **Hosting the Layout_Engine (task 5.8, Requirements 2.1, 2.9, 4.5).** A
/// single [LayoutBuilder] wraps the [AnimatedSwitcher] here, so both the
/// Connection_Gate and the [AppShell] read the same resolved [LayoutMode]
/// through [LayoutScope]. This is the one resolution site in the app.
///
/// Constraints come from [LayoutBuilder], deliberately **not**
/// `MediaQuery.sizeOf`. `MediaQuery` reports the whole window; the builder
/// reports the width actually handed to this subtree, which is what matters in
/// an Android split-screen pane or a resized desktop window, and it keeps the
/// Flutter reading equivalent to the Web_Client's CSS-pixel element width
/// rather than the window width.
///
/// **Why the switcher is built once, above the builder.** [LayoutBuilder]
/// re-runs its builder callback on every pixel of a drag-resize. If the
/// [AnimatedSwitcher] (and therefore `const AppShell()` and both `_TabLayer`s)
/// were constructed *inside* that callback, a resize would hand the element
/// tree freshly-built widgets every frame. Here the switcher is captured in a
/// `final` before the builder and the closure passes that identical instance to
/// [LayoutScope], so the child subtree is not even a candidate for rebuild on a
/// resize — the framework short-circuits on widget identity. Combined with
/// [LayoutScope.updateShouldNotify] gating dependents on the enum, a sub-band
/// resize rebuilds nothing below the scope, and the `Stack` + `TickerMode`
/// arrangement in [AppShell] — the live scroll positions, in-flight animations
/// and carousel page it protects (Requirement 4.5) — survives untouched. Only a
/// genuine band change reaches the leaf widgets that call [LayoutScope.of].
class RootView extends StatelessWidget {
  const RootView({super.key});

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;

    final unlocked = monitor.grantsAccess(
      requireConnection: settings.requireConnectionToBrowse,
    );

    // Built exactly once per RootView.build. `unlocked`, `reduceMotion` and the
    // `Motion` tokens all come from state watched above, never from the layout
    // constraints — so the LayoutBuilder callback below can re-run on a resize
    // without reconstructing this subtree. The gate↔shell children stay `const`
    // and keyed, preserving the existing transition behaviour unchanged.
    final Widget switcher = AnimatedSwitcher(
      duration: motionFor(reduceMotion: settings.reduceMotion, full: Motion.slow),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        children: <Widget>[
          ...previousChildren,
          ?currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        if (settings.reduceMotion) {
          return FadeTransition(opacity: animation, child: child);
        }
        // The dashboard eases up and in; the gate fades back. Reads as the lock
        // releasing rather than a page push.
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.04, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Motion.enter),
            ),
            child: child,
          ),
        );
      },
      child: unlocked
          ? const AppShell(key: ValueKey<String>('shell'))
          : const ConnectionGateScreen(key: ValueKey<String>('gate')),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final mode = Breakpoints.resolve(constraints.maxWidth);
        // Nothing but a LayoutScope around the already-built switcher. Passing
        // the same `switcher` instance every re-run is what keeps the shell
        // subtree out of the resize's rebuild set.
        return LayoutScope(mode: mode, child: switcher);
      },
    );
  }
}

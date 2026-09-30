import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/layout/layout_mode.dart';
import '../../core/layout/layout_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/settings/settings_controller.dart';
import '../../state/monitor_controller.dart';
import '../common/motion_widgets.dart';
import '../dashboard/dashboard_view.dart';
import '../sensors/sensors_tab.dart';
import '../settings/settings_tab.dart';

/// The two-destination shell shown once the gate is cleared.
///
/// **Both tabs stay mounted (Requirement 4.5).** The two destinations live in a
/// [Stack] whose offscreen layers are wrapped in `TickerMode`, so switching back
/// does not reset scroll position, restart the sensor carousel, or drop the
/// buffered reading history — and their animations are paused rather than
/// burning frames while offscreen.
///
/// **The navigation chrome is a *sibling* of that `Stack`, never a parent
/// (Requirement 4.5).** In Compact the two destinations are reachable from a
/// bottom [NavigationBar]; in Medium and Expanded they move to a left
/// [NavigationRail] with the same two destinations (Requirement 4.2 keeps the
/// bottom bar to exactly two tabs in Compact). Because the chrome is a sibling
/// rather than an ancestor of the mounted layers, changing the [LayoutMode] —
/// which swaps bottom bar for rail — never puts the tab layers behind a widget
/// that only exists in one mode, so they are not remounted by the swap. The one
/// `Stack` instance is built once per [build] and placed identically in both
/// the Compact and the wide arrangement, so its element identity (and therefore
/// the mounted `State` below it) survives a band change.
///
/// **Tab 1 swaps presentation by band (Requirements 4.1, 3.10).** Inside the
/// first layer, an [AnimatedSwitcher] keyed on the [LayoutMode] shows the
/// [SensorsTab] carousel in Compact and the [DashboardView] in Medium/Expanded.
/// The switcher reuses the shared [Motion] tokens and, under Reduce_Motion,
/// falls back to a plain fade with no positional or size interpolation
/// (Requirements 4.7, 4.8). The active destination, the link and the buffered
/// history all survive that swap because tab 1's presentations read the same
/// shared controllers, and the layers themselves are never unmounted.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _select(int next) {
    if (next == _index) return;
    final settings = context.read<SettingsController>().settings;
    if (settings.hapticsEnabled) HapticFeedback.selectionClick();
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final monitor = context.watch<MonitorController>();
    final reduced = context.select<SettingsController, bool>(
      (c) => c.settings.reduceMotion,
    );
    // The current band. Reading it here (not inside the tab layers) is what
    // keeps the layers themselves independent of the LayoutScope: the shell
    // rebuilds on a band change, but the `Stack` and its layers keep their
    // identity, so nothing below them remounts.
    final mode = LayoutScope.of(context);
    final wide = mode != LayoutMode.compact;

    final alarming = monitor.status.isAlarm;

    // Built exactly once per build and placed identically in both the Compact
    // and the wide arrangement below, so the framework short-circuits on widget
    // identity and never remounts the mounted tab layers on a band change.
    final Widget layers = Stack(
      children: <Widget>[
        _TabLayer(
          active: _index == 0,
          reduced: reduced,
          fromLeft: true,
          // Tab 1 swaps its whole presentation by band: the Sensor_Carousel in
          // Compact, the Dashboard_View in Medium/Expanded. Keyed on the mode so
          // the switcher animates the handoff; both presentations read the same
          // shared controllers, so the link and buffered history survive.
          child: AnimatedSwitcher(
            duration: motionOf(context, Motion.base),
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.center,
              children: <Widget>[
                ...previousChildren,
                ?currentChild,
              ],
            ),
            transitionBuilder: (child, animation) {
              // Reduce_Motion: a plain fade with no positional/size
              // interpolation (Requirement 4.8). motionOf already collapses the
              // duration to zero, so this is effectively instant.
              if (reduced) {
                return FadeTransition(opacity: animation, child: child);
              }
              // Otherwise cross-fade with a slight scale settle, using the
              // shared motion tokens (Requirement 4.7).
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1).animate(
                    CurvedAnimation(parent: animation, curve: Motion.enter),
                  ),
                  child: child,
                ),
              );
            },
            child: wide
                ? const DashboardView(key: ValueKey<String>('tab1-dashboard'))
                : const SensorsTab(key: ValueKey<String>('tab1-sensors')),
          ),
        ),
        _TabLayer(
          active: _index == 1,
          reduced: reduced,
          fromLeft: false,
          child: const SettingsTab(),
        ),
      ],
    );

    final Widget? fab = (alarming && _index == 1)
        ? FloatingActionButton.extended(
            onPressed: () => _select(0),
            backgroundColor: palette.alert,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Active alarm'),
          )
        : null;

    if (wide) {
      // Medium/Expanded: the left NavigationRail is a sibling of the Stack in a
      // Row, and there is no bottomNavigationBar. Requirement 4.2's two-bottom-
      // tabs rule is a Compact rule; here the same two destinations live on the
      // rail.
      return Scaffold(
        backgroundColor: palette.background,
        body: Row(
          children: <Widget>[
            _ShellRail(
              index: _index,
              alarming: alarming,
              onSelect: _select,
            ),
            Expanded(child: layers),
          ],
        ),
        floatingActionButton: fab,
      );
    }

    // Compact: the Stack alone, with the bottom NavigationBar as a sibling.
    return Scaffold(
      backgroundColor: palette.background,
      body: layers,
      bottomNavigationBar: _ShellBottomBar(
        index: _index,
        alarming: alarming,
        onSelect: _select,
      ),
      floatingActionButton: fab,
    );
  }
}

/// The bottom [NavigationBar] shown in Compact — exactly the two destinations
/// Sensors and Settings (Requirement 4.2).
class _ShellBottomBar extends StatelessWidget {
  const _ShellBottomBar({
    required this.index,
    required this.alarming,
    required this.onSelect,
  });

  final int index;
  final bool alarming;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        destinations: <Widget>[
          NavigationDestination(
            // The badge keeps an active alarm visible even while the user is
            // deep in the settings tab.
            icon: Badge(
              isLabelVisible: alarming,
              backgroundColor: palette.alert,
              child: const Icon(Icons.water_drop_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: alarming,
              backgroundColor: palette.alert,
              child: const Icon(Icons.water_drop),
            ),
            label: 'Sensors',
            tooltip: 'Live flow readings for all three sensors',
            key: const ValueKey<String>('tab-sensors'),
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
            tooltip: 'Units, alerts, detection tuning and storage',
            key: ValueKey<String>('tab-settings'),
          ),
        ],
      ),
    );
  }
}

/// The left [NavigationRail] shown in Medium and Expanded — the same two
/// destinations as the Compact bottom bar (Requirement 4.2), placed as a
/// sibling of the mounted tab `Stack`.
class _ShellRail extends StatelessWidget {
  const _ShellRail({
    required this.index,
    required this.alarming,
    required this.onSelect,
  });

  final int index;
  final bool alarming;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: NavigationRail(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        labelType: NavigationRailLabelType.all,
        backgroundColor: palette.background,
        destinations: <NavigationRailDestination>[
          NavigationRailDestination(
            // The same alarm badge as the bottom bar keeps an active alarm
            // visible from the Settings destination.
            icon: Badge(
              isLabelVisible: alarming,
              backgroundColor: palette.alert,
              child: const Icon(Icons.water_drop_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: alarming,
              backgroundColor: palette.alert,
              child: const Icon(Icons.water_drop),
            ),
            label: const Text('Sensors'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: Text('Settings'),
          ),
        ],
      ),
    );
  }
}

/// One tab in the stack. Slides and fades in, and is fully inert when inactive.
class _TabLayer extends StatelessWidget {
  const _TabLayer({
    required this.active,
    required this.reduced,
    required this.fromLeft,
    required this.child,
  });

  final bool active;
  final bool reduced;
  final bool fromLeft;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final offset = active
        ? Offset.zero
        : Offset(fromLeft ? -0.04 : 0.04, 0);

    return IgnorePointer(
      ignoring: !active,
      child: TickerMode(
        enabled: active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: motionFor(reduceMotion: reduced, full: Motion.fast),
          curve: active ? Motion.enter : Motion.exit,
          child: AnimatedSlide(
            offset: reduced ? Offset.zero : offset,
            duration: motionFor(reduceMotion: reduced, full: Motion.base),
            curve: Motion.enter,
            child: child,
          ),
        ),
      ),
    );
  }
}

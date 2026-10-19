import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/leak_protocol.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/settings/settings_controller.dart';
import '../../state/monitor_controller.dart';
import '../../state/selection_controller.dart';
import '../common/alert_banner.dart';
import '../common/icon_language.dart';
import '../common/motion_widgets.dart';
import '../dashboard/alerts_panel.dart';
import '../diagnostics/diagnostics_sheet.dart';
import 'widgets/sensor_page.dart';

/// Tab 1 — the live sensor carousel.
///
/// Three dedicated pages, one per flow sensor, reachable by tapping the chevrons
/// either side of the sensor name or by swiping. Navigation stays inside this tab
/// as required, so the bottom bar never changes while moving between sensors.
class SensorsTab extends StatefulWidget {
  const SensorsTab({super.key});

  @override
  State<SensorsTab> createState() => _SensorsTabState();
}

class _SensorsTabState extends State<SensorsTab> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    // Seed the carousel from the shared selection *once*, at mount. When the
    // Layout_Mode crosses back to Compact the carousel opens on the channel the
    // Dashboard_View left selected (Requirement 4.4). From here on the
    // SelectionController is the single source of truth: `onPageChanged` is the
    // sole writer, so there is no listener driving the page and therefore no
    // notify -> animate -> write-back feedback loop.
    final selected = context.read<SelectionController>().selectedChannel;
    _pageController = PageController(initialPage: selected);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    final target = index.clamp(0, kSensorCount - 1);
    if (target == context.read<SelectionController>().selectedChannel) return;
    final settings = context.read<SettingsController>().settings;
    if (settings.hapticsEnabled) HapticFeedback.selectionClick();
    // Animate the page; `onPageChanged` fires as the swipe settles and is what
    // records the new selection on the controller. `_goTo` never writes the
    // controller directly, keeping the single-writer contract intact.
    _pageController.animateToPage(
      target,
      duration: motionFor(reduceMotion: settings.reduceMotion, full: Motion.base),
      curve: Motion.enter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final monitor = context.watch<MonitorController>();
    // Rebuild only when the selected channel changes, not on every controller
    // notification.
    final page = context.select<SelectionController, int>(
      (controller) => controller.selectedChannel,
    );

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        titleSpacing: Tokens.s3,
        title: const Text('Live flow'),
        actions: <Widget>[
          const _LinkChip(),
          IconButton(
            tooltip: 'Alerts',
            onPressed: () => _showAlertsSheet(context),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'Diagnostics',
            onPressed: () => DiagnosticsSheet.show(context),
            icon: AppIcon(AppGlyph.gauge, color: palette.accentText),
          ),
          const SizedBox(width: Tokens.s1),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: monitor.refreshAggregates,
        color: palette.accent,
        backgroundColor: palette.surface,
        child: Column(
          children: <Widget>[
            const _StatusStrip(),
            _SensorSwitcherBar(
              page: page,
              onPrevious: () => _goTo(page - 1),
              onNext: () => _goTo(page + 1),
              onSelect: _goTo,
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: kSensorCount,
                onPageChanged: (index) =>
                    context.read<SelectionController>().selectChannel(index),
                itemBuilder: (context, index) => SensorPage(sensorIndex: index),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the Alerts_Panel as a scroll-controlled modal bottom sheet.
///
/// Compact keeps exactly two bottom tabs — Sensors and Settings (Requirement
/// 4.2) — so the Alert_Entry list, which has no tab of its own, is reached from
/// the Sensors tab through this modal (Requirement 7.7). Pushing a modal route
/// leaves the shell's [NavigationBar] untouched, so the two-tab contract holds.
///
/// The sheet mirrors [DiagnosticsSheet.show]: scroll-controlled, a rounded top,
/// the surface fill from the palette, a titled header and a [SafeArea] body.
/// `const AlertsPanel()` reads its rows from the app-wide [AlertsController] and
/// already bounds its own scroll, so it only needs padding here.
Future<void> _showAlertsSheet(BuildContext context) {
  final palette = AppPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.radiusCard)),
    ),
    builder: (sheetContext) {
      final sheetPalette = AppPalette.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.notifications_none_rounded,
                    color: sheetPalette.accentText,
                  ),
                  const SizedBox(width: Tokens.s2),
                  Text(
                    'Alerts',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: Tokens.s3),
              const Flexible(child: AlertsPanel()),
            ],
          ),
        ),
      );
    },
  );
}

/// Connection chip in the app bar. Doubles as the disconnect control.
class _LinkChip extends StatelessWidget {
  const _LinkChip();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    final connected = monitor.isConnected;
    final colour = connected
        ? palette.normal
        : monitor.isStale
            ? palette.watch
            : palette.idle;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s2),
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        onTap: () => DiagnosticsSheet.show(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s2),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
            border: Border.all(color: colour.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PulseDot(color: colour, size: 6, active: connected),
              Text(
                monitor.usingReplay
                    ? 'REPLAY'
                    : monitor.usingSimulator
                        ? 'DEMO'
                        : connected
                            ? 'LIVE'
                            : monitor.isStale
                                ? 'STALE'
                                : 'OFFLINE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colour,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: Tokens.s1),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banners that apply to the whole system rather than one sensor.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final palette = AppPalette.of(context);

    final banners = <Widget>[];

    if (monitor.usingSimulator) {
      banners.add(
        NoticeBanner(
          key: const ValueKey<String>('sim'),
          title: 'Demo data',
          message:
              'These readings come from the built-in simulator, not from your '
              'Arduino. Connect the module for real measurements.',
          icon: Icons.science_outlined,
          // NoticeBanner spends this on its title, message and icon, with only
          // a 4px bar and a 10% wash besides, so it is a text colour here.
          accent: palette.accentText,
        ),
      );
    }

    if (monitor.usingReplay) {
      banners.add(
        NoticeBanner(
          key: const ValueKey<String>('replay'),
          title: 'Replaying recorded data',
          message:
              'These are real recorded readings played back and re-evaluated by '
              'the live detection logic — not a live Arduino link. Leaks are '
              'detected here exactly as they would be in real time.',
          icon: Icons.play_circle_outline,
          accent: palette.accentText,
        ),
      );
    }

    if (monitor.leakInjected) {
      banners.add(
        NoticeBanner(
          key: const ValueKey<String>('injected'),
          title: 'SIMULATED leak (demo)',
          message:
              'A demo leak injection is armed, so the leak shown below is forced '
              'for the presentation and is not a real hardware detection. Turn it '
              'off in Diagnostics to show the genuine live reading.',
          icon: Icons.warning_amber_rounded,
          accent: palette.alert,
        ),
      );
    }

    if (monitor.isStale) {
      final seconds = monitor.secondsSinceLastSample ?? 0;
      banners.add(
        NoticeBanner(
          key: const ValueKey<String>('stale'),
          title: 'Link has gone quiet',
          message:
              'No telemetry for ${seconds}s. The values below are the last known '
              'readings. Check that the module still has power and is in range.',
          icon: Icons.signal_wifi_statusbar_connected_no_internet_4_outlined,
          accent: palette.watch,
        ),
      );
    }

    final status = monitor.status;
    if (status.isAlarm && !monitor.alarmAcknowledged) {
      banners.add(
        AlertBanner(
          key: const ValueKey<String>('alarm'),
          status: status,
          onAcknowledge: monitor.acknowledgeAlarm,
          onAction: () => DiagnosticsSheet.show(context),
          actionLabel: 'Details',
        ),
      );
    }

    return AnimatedSize(
      duration: motionOf(context, Motion.base),
      curve: Motion.enter,
      alignment: Alignment.topCenter,
      child: banners.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s3,
                0,
                Tokens.s3,
                Tokens.s2,
              ),
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < banners.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: Tokens.s2),
                    FadeSlideIn(index: i, offset: 8, child: banners[i]),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Prev / next chevrons flanking the current sensor name, plus tappable dots.
/// This is the in-tab navigation the brief asks for.
class _SensorSwitcherBar extends StatelessWidget {
  const _SensorSwitcherBar({
    required this.page,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final int page;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final settings = context.watch<SettingsController>().settings;
    final monitor = context.watch<MonitorController>();
    final theme = Theme.of(context);

    final canGoBack = page > 0;
    final canGoForward = page < kSensorCount - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s2),
      child: Row(
        children: <Widget>[
          _ArrowButton(
            icon: Icons.chevron_left_rounded,
            tooltip: canGoBack
                ? 'Previous sensor: ${settings.sensorNames[page - 1]}'
                : 'Already at the first sensor',
            enabled: canGoBack,
            onPressed: onPrevious,
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                SoftSwitcher(
                  child: Column(
                    key: ValueKey<int>(page),
                    children: <Widget>[
                      Text(
                        settings.sensorNames[page],
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Sensor ${page + 1} of $kSensorCount',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Tokens.s2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (var i = 0; i < kSensorCount; i++)
                      _PageDot(
                        selected: i == page,
                        flowing: monitor.flowFor(i) > 0,
                        onTap: () => onSelect(i),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _ArrowButton(
            icon: Icons.chevron_right_rounded,
            tooltip: canGoForward
                ? 'Next sensor: ${settings.sensorNames[page + 1]}'
                : 'Already at the last sensor',
            enabled: canGoForward,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: AnimatedOpacity(
        duration: motionOf(context, Motion.fast),
        opacity: enabled ? 1 : 0.32,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: tooltip,
          child: Material(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusControl),
              side: BorderSide(color: palette.border),
            ),
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(Tokens.radiusControl),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(icon, size: 26, color: palette.accentText),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDot extends StatelessWidget {
  const _PageDot({
    required this.selected,
    required this.flowing,
    required this.onTap,
  });

  final bool selected;
  final bool flowing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final colour = selected
        ? palette.accent
        : flowing
            ? palette.gradientGreen
            : palette.border;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: Tokens.s1),
        child: AnimatedContainer(
          duration: motionOf(context, Motion.base),
          curve: Motion.enter,
          width: selected ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
          ),
        ),
      ),
    );
  }
}

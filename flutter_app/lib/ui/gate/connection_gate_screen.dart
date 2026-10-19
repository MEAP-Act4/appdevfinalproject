import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/ble/leak_transport.dart';
import '../../data/settings/settings_controller.dart';
import '../../state/monitor_controller.dart';
import '../common/alert_banner.dart';
import '../common/motion_widgets.dart';
import '../common/surface_card.dart';
import 'replay_picker.dart';

/// The gate. Until the board is talking, this is the whole app.
///
/// Requirement: the user must connect to the Arduino module before getting full
/// access. Rather than a dead-end warning, this screen does the work — it
/// explains the prerequisite, checks it, scans, and hands off as soon as the
/// first valid telemetry line decodes.
class ConnectionGateScreen extends StatefulWidget {
  const ConnectionGateScreen({super.key});

  @override
  State<ConnectionGateScreen> createState() => _ConnectionGateScreenState();
}

class _ConnectionGateScreenState extends State<ConnectionGateScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  bool _autoAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_tryAutoConnect());
    });
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  /// Silent one-shot reconnect to the remembered module, so a returning user
  /// usually never sees this screen for more than a moment.
  Future<void> _tryAutoConnect() async {
    if (_autoAttempted) return;
    _autoAttempted = true;

    final settings = context.read<SettingsController>().settings;
    if (!settings.autoReconnect || !settings.hasRememberedDevice) return;

    await context.read<MonitorController>().connectToRemembered();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;
    final theme = Theme.of(context);
    final reduced = settings.reduceMotion;

    final state = monitor.linkState;
    final devices = monitor.discovered;

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: <Widget>[
          if (!reduced) _AmbientBackdrop(controller: _ambient),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s4,
                    vertical: Tokens.s5,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - Tokens.s5 * 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Spacer(),
                        FadeSlideIn(
                          index: 0,
                          child: _GateMark(controller: _ambient, state: state),
                        ),
                        const SizedBox(height: Tokens.s5),
                        FadeSlideIn(
                          index: 1,
                          child: Text(
                            'Connect your LeakGuard module',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(height: Tokens.s2),
                        FadeSlideIn(
                          index: 2,
                          child: Text(
                            'The app reads live flow straight from the Arduino over '
                            'the HM-10 Bluetooth link. Until that link is up there '
                            'is nothing to monitor, so the dashboard stays locked.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: palette.textSecondary),
                          ),
                        ),
                        const SizedBox(height: Tokens.s4),
                        FadeSlideIn(
                          index: 3,
                          child: _PreflightChecklist(state: state),
                        ),
                        if (monitor.lastError != null) ...<Widget>[
                          const SizedBox(height: Tokens.s3),
                          NoticeBanner(
                            title: 'Could not connect',
                            message: monitor.lastError!,
                            icon: Icons.error_outline,
                            accent: palette.alert,
                          ),
                        ],
                        const SizedBox(height: Tokens.s3),
                        SoftSwitcher(
                          child: devices.isEmpty
                              ? const SizedBox.shrink()
                              : _DeviceList(devices: devices),
                        ),
                        const Spacer(),
                        const SizedBox(height: Tokens.s4),
                        FadeSlideIn(index: 4, child: _GateActions(state: state)),
                        const SizedBox(height: Tokens.s3),
                        FadeSlideIn(
                          index: 5,
                          child: Text(
                            'Wiring and calibration steps are in the project '
                            'README. Default HM-10 pairing code is 000000.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Slow drifting radial washes behind the gate. Purely decorative, disabled under
/// reduce-motion.
class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value * math.pi * 2;
        return IgnorePointer(
          child: Stack(
            children: <Widget>[
              Positioned(
                left: -80 + math.sin(t) * 24,
                top: -60 + math.cos(t) * 18,
                child: _Wash(color: palette.accent, size: 320),
              ),
              Positioned(
                right: -100 + math.cos(t * 0.8) * 26,
                bottom: -80 + math.sin(t * 0.8) * 22,
                child: _Wash(color: palette.gradientGreen, size: 280),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Wash extends StatelessWidget {
  const _Wash({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            color.withValues(alpha: 0.13),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

/// Concentric sonar rings around a droplet, with the ring speed reflecting the
/// link state: still when idle, sweeping while scanning or connecting.
class _GateMark extends StatelessWidget {
  const _GateMark({required this.controller, required this.state});

  final AnimationController controller;
  final LinkState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final busy = state.isBusy;
    final failed = state == LinkState.failed || state == LinkState.unavailable;
    // Two colours, not one: [accent] paints the sonar rings, the badge outline
    // and its glow, all graphics; [glyph] paints the icon inside, which is read
    // like text and so takes the text accent — Requirement 11.4. They are the
    // same value in both dark appearances.
    final accent = failed ? palette.alert : palette.accent;
    final glyph = failed ? palette.alert : palette.accentText;
    final reduced = reduceMotionOf(context);

    return SizedBox(
      height: 168,
      child: Center(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                if (!reduced)
                  for (var i = 0; i < 3; i++)
                    _SonarRing(
                      progress: ((controller.value + i / 3) % 1),
                      color: accent,
                      active: busy,
                    ),
                AnimatedContainer(
                  duration: motionFor(reduceMotion: reduced, full: Motion.slow),
                  curve: Motion.enter,
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.surface,
                    border: Border.all(
                      color: accent.withValues(alpha: busy ? 0.7 : 0.35),
                      width: 1.5,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: accent.withValues(alpha: busy ? 0.24 : 0.10),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: SoftSwitcher(
                      child: Icon(
                        switch (state) {
                          LinkState.unavailable => Icons.bluetooth_disabled,
                          LinkState.scanning => Icons.bluetooth_searching,
                          LinkState.connecting ||
                          LinkState.handshaking ||
                          LinkState.reconnecting =>
                            Icons.bluetooth_connected,
                          LinkState.failed => Icons.error_outline,
                          LinkState.ready => Icons.water_drop,
                          LinkState.idle => Icons.water_drop_outlined,
                        },
                        key: ValueKey<LinkState>(state),
                        size: 40,
                        color: glyph,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SonarRing extends StatelessWidget {
  const _SonarRing({
    required this.progress,
    required this.color,
    required this.active,
  });

  final double progress;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeOut.transform(progress);
    final size = 96 + eased * 72;
    final opacity = active ? (1 - eased) * 0.5 : 0.08;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: opacity)),
      ),
    );
  }
}

/// Three prerequisites, each with its own state. Gives the user something
/// actionable instead of a spinner.
class _PreflightChecklist extends StatelessWidget {
  const _PreflightChecklist({required this.state});

  final LinkState state;

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final bluetoothReady = state != LinkState.unavailable;
    final foundSomething = monitor.discovered.isNotEmpty;
    final linked = state == LinkState.handshaking || state.grantsAccess;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s3,
        vertical: Tokens.s2,
      ),
      child: Column(
        children: <Widget>[
          _CheckRow(
            label: 'Bluetooth is on and permitted',
            done: bluetoothReady,
            busy: false,
            hint: 'Enable Bluetooth and allow nearby-device access',
          ),
          Divider(height: Tokens.s3, color: AppPalette.of(context).border),
          _CheckRow(
            label: 'LeakGuard module powered and in range',
            done: foundSomething,
            busy: state == LinkState.scanning,
            hint: 'The HM-10 LED blinks while unpaired, solid once connected',
          ),
          Divider(height: Tokens.s3, color: AppPalette.of(context).border),
          _CheckRow(
            label: 'Telemetry stream decoded',
            done: state.grantsAccess,
            busy: linked && !state.grantsAccess,
            hint: 'Waiting for the first 1 Hz data line from the Arduino',
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.done,
    required this.busy,
    required this.hint,
  });

  final String label;
  final bool done;
  final bool busy;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    // Paints the step's glyph — a tick, an outline circle, or a 15px spinner in
    // the same icon slot. All icon, so the text accent applies.
    final colour = done
        ? palette.normal
        : busy
            ? palette.accentText
            : palette.textSecondary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 22,
          height: 22,
          child: SoftSwitcher(
            child: done
                ? Icon(Icons.check_circle, size: 18, color: colour)
                : busy
                    ? SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(colour),
                        ),
                      )
                    : Icon(Icons.circle_outlined, size: 17, color: colour),
          ),
        ),
        const SizedBox(width: Tokens.s2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: done ? palette.textPrimary : palette.textSecondary,
                  fontWeight: done ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
              AnimatedSize(
                duration: motionOf(context, Motion.base),
                curve: Motion.enter,
                child: done
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices});

  final List<DiscoveredDevice> devices;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final monitor = context.read<MonitorController>();
    final theme = Theme.of(context);

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s3,
              vertical: Tokens.s1,
            ),
            child: CardLabel(
              'Nearby devices · ${devices.length}',
              trailing: Text(
                'tap to connect',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          for (var i = 0; i < math.min(devices.length, 6); i++)
            FadeSlideIn(
              index: i,
              offset: 10,
              child: _DeviceRow(
                device: devices[i],
                onTap: () => monitor.connectTo(devices[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onTap});

  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final likely = device.advertisesLeakService;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3,
          vertical: Tokens.s2,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (likely ? palette.accent : palette.textSecondary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                likely ? Icons.sensors : Icons.bluetooth,
                size: 18,
                color: likely ? palette.accentText : palette.textSecondary,
              ),
            ),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    device.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    likely ? 'Serial service detected' : device.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          likely ? palette.accentText : palette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            _SignalBars(bars: device.bars, color: palette.textSecondary),
            const SizedBox(width: Tokens.s2),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.bars, required this.color});

  final int bars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: AnimatedContainer(
              duration: motionOf(context, Motion.fast),
              width: 3,
              height: 5 + i * 3,
              decoration: BoxDecoration(
                color: color.withValues(alpha: i < bars ? 0.9 : 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}

class _GateActions extends StatelessWidget {
  const _GateActions({required this.state});

  final LinkState state;

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;
    final palette = AppPalette.of(context);

    final busy = state.isBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          onPressed: busy ? null : () => monitor.startScan(),
          icon: SoftSwitcher(
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Tokens.darkBackground,
                    ),
                  )
                : const Icon(Icons.bluetooth_searching, size: 20),
          ),
          label: Text(
            switch (state) {
              LinkState.scanning => 'Scanning for modules…',
              LinkState.connecting => 'Connecting…',
              LinkState.handshaking => 'Reading firmware…',
              LinkState.reconnecting => 'Reconnecting…',
              _ => 'Scan for LeakGuard module',
            },
          ),
        ),
        if (settings.hasRememberedDevice) ...<Widget>[
          const SizedBox(height: Tokens.s2),
          OutlinedButton.icon(
            onPressed: busy ? null : () => monitor.connectToRemembered(),
            icon: const Icon(Icons.history, size: 18),
            label: Text('Reconnect to ${settings.rememberedDeviceName}'),
          ),
        ],
        const SizedBox(height: Tokens.s3),
        Row(
          children: <Widget>[
            Expanded(
              child: TextButton.icon(
                onPressed: busy ? null : () => monitor.startSimulator(),
                icon: const Icon(Icons.science_outlined, size: 18),
                label: const Text('Explore with demo data'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.textSecondary,
                ),
              ),
            ),
            if (!settings.requireConnectionToBrowse)
              Expanded(
                child: TextButton.icon(
                  onPressed: monitor.enterHistoryOnlyMode,
                  icon: const Icon(Icons.history_toggle_off, size: 18),
                  label: const Text('Stored history'),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Tokens.s1),
        // Replay a real recorded dataset through the live detection pipeline.
        // Distinct from demo data: these are real readings, re-evaluated so the
        // app actually detects the leak rather than replaying a stored label.
        TextButton.icon(
          onPressed: busy ? null : () => ReplayPicker.show(context),
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: const Text('Replay recorded data'),
          style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
        ),
      ],
    );
  }
}

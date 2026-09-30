import 'package:flutter/material.dart';

import '../../core/protocol/leak_protocol.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import 'motion_widgets.dart';
import 'status_visuals.dart';

/// The alert treatment from DESIGN.md §3: tinted fill, coloured text and a 4px
/// left bar. Reused for every severity by swapping the accent.
class AlertBanner extends StatelessWidget {
  const AlertBanner({
    super.key,
    required this.status,
    this.title,
    this.message,
    this.onAcknowledge,
    this.onAction,
    this.actionLabel,
    this.dense = false,
  });

  final LeakStatus status;
  final String? title;
  final String? message;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onAction;
  final String? actionLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visuals = StatusVisuals.of(context, status);
    final theme = Theme.of(context);

    return _BannerShell(
      accent: visuals.color,
      fill: visuals.fill,
      icon: visuals.icon,
      pulse: visuals.isAlarm,
      dense: dense,
      title: title ?? visuals.headline,
      message: message ?? visuals.detail,
      trailing: <Widget>[
        if (onAction != null && actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: visuals.color),
            child: Text(actionLabel!),
          ),
        if (onAcknowledge != null)
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onAcknowledge,
            icon: Icon(Icons.close_rounded, size: 18, color: visuals.color),
            visualDensity: VisualDensity.compact,
          ),
      ],
      textTheme: theme.textTheme,
    );
  }
}

/// Generic banner used for connection problems that are not a firmware status.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.accent,
    this.onAction,
    this.actionLabel,
    this.onDismiss,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color? accent;
  final VoidCallback? onAction;
  final String? actionLabel;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final colour = accent ?? palette.watch;
    return _BannerShell(
      accent: colour,
      fill: colour.withValues(alpha: 0.10),
      icon: icon,
      pulse: false,
      dense: false,
      title: title,
      message: message,
      textTheme: Theme.of(context).textTheme,
      trailing: <Widget>[
        if (onAction != null && actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: colour),
            child: Text(actionLabel!),
          ),
        if (onDismiss != null)
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: Icon(Icons.close_rounded, size: 18, color: colour),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _BannerShell extends StatelessWidget {
  const _BannerShell({
    required this.accent,
    required this.fill,
    required this.icon,
    required this.pulse,
    required this.dense,
    required this.title,
    required this.message,
    required this.trailing,
    required this.textTheme,
  });

  final Color accent;
  final Color fill;
  final IconData icon;
  final bool pulse;
  final bool dense;
  final String title;
  final String message;
  final List<Widget> trailing;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: motionOf(context, Motion.base),
      curve: Motion.enter,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: Tokens.s3,
        vertical: dense ? Tokens.s2 : Tokens.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: pulse
                ? PulseDot(color: accent, size: 9)
                : Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: Tokens.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(color: accent),
                ),
                if (!dense) ...<Widget>[
                  const SizedBox(height: Tokens.s1),
                  Text(
                    message,
                    style: textTheme.bodySmall?.copyWith(
                      color: accent.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// Compact status pill. Shows a breathing dot while live.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.status,
    this.live = false,
    this.compact = false,
  });

  final LeakStatus status;

  /// When true the dot breathes, signalling a fresh 1 Hz feed.
  final bool live;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visuals = StatusVisuals.of(context, status);
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: motionOf(context, Motion.base),
      curve: Motion.enter,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Tokens.s2 : Tokens.s3,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: visuals.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: visuals.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PulseDot(color: visuals.color, size: compact ? 6 : 7, active: live),
          SizedBox(width: compact ? 2 : Tokens.s1),
          Text(
            visuals.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: visuals.color,
              letterSpacing: 1,
              fontSize: compact ? 10 : 11,
            ),
          ),
        ],
      ),
    );
  }
}

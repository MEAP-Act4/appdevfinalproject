import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import 'motion_widgets.dart';

/// The card from DESIGN.md §3: 16px radius, `#1E1E1E` fill, 20px padding and a
/// 1px `#2C2C2E` hairline border. Everything on a screen sits in one of these.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.accent,
    this.raised = false,
    this.onTap,
    this.leadingAccentBar = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// When set, the border picks up this colour — used to tint a card by status.
  final Color? accent;

  final bool raised;
  final VoidCallback? onTap;

  /// Draws the 4px left bar used by the alert treatment in DESIGN.md §3.
  final bool leadingAccentBar;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final borderColor = accent?.withValues(alpha: 0.45) ?? palette.border;

    final decoration = BoxDecoration(
      color: raised ? palette.surfaceRaised : palette.surface,
      borderRadius: BorderRadius.circular(Tokens.radiusCard),
      border: Border.all(color: borderColor, width: Tokens.hairline),
    );

    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(Tokens.cardPadding),
      child: child,
    );

    if (leadingAccentBar && accent != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(width: 4, color: accent),
          Expanded(child: content),
        ],
      );
    }

    final card = AnimatedContainer(
      duration: motionOf(context, Motion.base),
      curve: Motion.enter,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Tokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        splashColor: (accent ?? palette.accent).withValues(alpha: 0.08),
        highlightColor: (accent ?? palette.accent).withValues(alpha: 0.05),
        child: card,
      ),
    );
  }
}

/// Small uppercase grey caption used above every metric.
class CardLabel extends StatelessWidget {
  const CardLabel(this.text, {super.key, this.trailing, this.color});

  final String text;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final label = Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color ?? palette.textSecondary,
            letterSpacing: 1.1,
          ),
    );
    if (trailing == null) return label;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[label, trailing!],
    );
  }
}

/// Section heading used on the settings tab.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.subtitle, this.icon});

  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: Tokens.s1,
        bottom: Tokens.s2,
        top: Tokens.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            // Icon and title are both read as text, so both take the text
            // accent — Requirement 11.4.
            Icon(icon, size: 16, color: palette.accentText),
            const SizedBox(width: Tokens.s2),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.accentText,
                    letterSpacing: 1.2,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: Tokens.s1),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

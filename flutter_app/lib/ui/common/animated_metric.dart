import 'package:flutter/material.dart';

import '../../core/money/cost_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import 'motion_widgets.dart';

/// A numeric readout that interpolates to its new value instead of snapping.
///
/// Framework note: `TweenAnimationBuilder` keeps the currently displayed value and
/// re-targets `end` on rebuild, so passing the same tween each frame is exactly
/// what produces the sweep from the old number to the new one.
///
/// DESIGN.md §4 requires a monospaced face for metrics. Combined with a fixed
/// decimal count that keeps the glyph box stable, so a value crossing 9.99 to
/// 10.01 does not shift the layout.
class AnimatedMetric extends StatelessWidget {
  const AnimatedMetric({
    super.key,
    required this.value,
    required this.format,
    this.unit,
    this.size = Tokens.kpiSize,
    this.color,
    this.unitColor,
    this.weight = FontWeight.w700,
    this.duration = Motion.base,
    this.semanticsLabel,
  });

  /// Target value in canonical units.
  final double value;

  /// Turns the interpolated double into the display string. Usually a
  /// `UnitFormatter` call, so conversion happens per frame and the digits animate
  /// in whichever unit the user picked.
  final String Function(double) format;

  final String? unit;
  final double size;
  final Color? color;
  final Color? unitColor;
  final FontWeight weight;
  final Duration duration;

  /// The accessible name of this readout (Requirement 11.8). When set, the
  /// whole metric is wrapped in a [Semantics] node so a screen reader announces
  /// `label, value unit` — e.g. "Main Inlet flow, 5.2 L/min" — with the
  /// live formatted number as the semantic value. `null` leaves the readout's
  /// default semantics (the raw text) untouched, so existing call sites are
  /// unchanged.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final reduced = reduceMotionOf(context);
    final safeValue = value.isFinite ? value : 0.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: safeValue),
      duration: reduced ? Duration.zero : duration,
      curve: Motion.value,
      builder: (context, animated, _) {
        final numeral = format(animated);
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Scale the numeral down at large text scales rather than letting
            // it clip, and keep it on intrinsic height so a 200% scale grows
            // the run instead of overflowing (Requirement 11.10). Flexible
            // gives the FittedBox a bounded width to shrink within when the
            // metric sits in a Row/Column with constrained cross-axis room.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  numeral,
                  style: AppText.mono(
                    size: size,
                    weight: weight,
                    color: color ?? palette.textPrimary,
                  ),
                ),
              ),
            ),
            if (unit != null) ...<Widget>[
              const SizedBox(width: Tokens.s2),
              Padding(
                padding: EdgeInsets.only(bottom: size * 0.08),
                child: Text(
                  unit!,
                  style: AppText.mono(
                    size: size * 0.42,
                    weight: FontWeight.w500,
                    color: unitColor ?? palette.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        );

        if (semanticsLabel == null) return row;

        // Announce "<label>, <value> <unit>" as one node, hiding the split
        // numeral/unit text children so the reader speaks the whole readout
        // once (Requirement 11.8).
        final spokenValue = unit == null ? numeral : '$numeral ${unit!}';
        return Semantics(
          label: semanticsLabel,
          value: spokenValue,
          container: true,
          child: ExcludeSemantics(child: row),
        );
      },
    );
  }
}

/// Compact label + animated value pair, used in the averages row and the
/// diagnostics grid.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.format,
    this.unit,
    this.caption,
    this.valueColor,
    this.size = 20,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.secondary,
    this.semanticsLabel,
  });

  final String label;
  final double value;
  final String Function(double) format;
  final String? unit;
  final String? caption;
  final Color? valueColor;
  final double size;
  final CrossAxisAlignment crossAxisAlignment;

  /// The accessible name for this tile's readout (Requirement 11.8). Passed to
  /// the inner [AnimatedMetric] so the screen reader announces the named value
  /// (e.g. "Into manifold, 4.1 L/min"). Defaults to the visible [label] when
  /// omitted, so every tile is named without each call site restating it.
  final String? semanticsLabel;

  /// An optional annotation rendered directly beneath the value, before the
  /// caption. The `Bs_Equivalence` cost line ([CostLine]) is passed here so a
  /// single tile carries both its primary volume figure and the secondary
  /// monetary equivalent, keeping every volume call site on one mechanism
  /// (Requirement 6.5, design Property 7). `null` when there is nothing to add.
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: palette.textSecondary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: Tokens.s2),
        AnimatedMetric(
          value: value,
          format: format,
          unit: unit,
          size: size,
          color: valueColor,
          semanticsLabel: semanticsLabel ?? label,
        ),
        if (secondary != null) ...<Widget>[
          const SizedBox(height: Tokens.s1),
          secondary!,
        ],
        if (caption != null) ...<Widget>[
          const SizedBox(height: Tokens.s1),
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

/// The `Bs_Equivalence` shown beside a volume figure.
///
/// This is the single mechanism every volume call site uses to render the
/// monetary equivalent, so the carousel and the dashboard stay in agreement
/// (design Property 7, Requirement 6.5 "every volume figure").
///
/// The [formatter] is a [CostFormatter] carrying the active Tariff, locale and
/// enabled flag. [canonicalLitres] is the same canonical litre value fed to the
/// volume figure — never a display-unit number — so the amount is invariant
/// under a change of displayed volume unit (Requirement 6.7). When the formatter
/// is disabled, [CostFormatter.format] returns `null` and this widget renders
/// nothing (Requirement 5.8, Property 12).
///
/// The amount is routed through [AnimatedMetric] so it interpolates as the
/// volume changes while Reduce_Motion is off, and collapses to an instant
/// update when it is on (Requirement 6.9) — the same motion mechanism the
/// volume figure itself uses. It is rendered in the secondary text colour at
/// the body type size, beneath the primary value (Requirement 6.5). When the
/// Tariff is still the default placeholder rather than a user-committed value,
/// a subtle "default tariff" hint accompanies the amount (Requirement 6.8).
class CostLine extends StatelessWidget {
  const CostLine({
    super.key,
    required this.canonicalLitres,
    required this.formatter,
    this.semanticsLabel = defaultSemanticsLabel,
  });

  /// The canonical litre volume this cost line annotates. Fed straight to the
  /// [CostFormatter]; a display-unit value must never be passed here.
  final double canonicalLitres;

  /// The active cost formatter (Tariff, locale, enabled and default-tariff
  /// flag). When disabled, this widget renders nothing.
  final CostFormatter formatter;

  /// The default-tariff hint shown when the Tariff has not been configured by
  /// the user (Requirement 6.8). Kept as a named constant so the wording stays
  /// consistent with the Web_Client.
  static const String defaultTariffHint = 'default tariff';

  /// The default accessible name for the Bs_Equivalence readout
  /// (Requirement 11.8). A screen reader announces "<label>, Bs. 18.90".
  static const String defaultSemanticsLabel = 'cost';

  /// The accessible name for this Bs_Equivalence (Requirement 11.8). Threaded
  /// to the inner [AnimatedMetric] so the amount is announced with a name and
  /// its current formatted value.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    // Disabled display renders nothing at all (Req 5.8, Property 12).
    if (formatter.format(canonicalLitres) == null) {
      return const SizedBox.shrink();
    }

    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Route the amount through AnimatedMetric so it interpolates when
        // Reduce_Motion is off and snaps when it is on (Req 6.9). The formatter
        // only returns null when disabled, which is handled above, so the
        // fallback empty string is never rendered.
        Flexible(
          child: AnimatedMetric(
            value: canonicalLitres,
            format: (v) => formatter.format(v) ?? '',
            size: Tokens.bodySize,
            weight: FontWeight.w500,
            color: palette.textSecondary,
            semanticsLabel: semanticsLabel,
          ),
        ),
        if (formatter.isDefaultTariff) ...<Widget>[
          const SizedBox(width: Tokens.s2),
          Flexible(
            child: Text(
              defaultTariffHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textSecondary,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/units/measurement_units.dart';
import '../../../data/models/aggregates.dart';
import '../../../data/settings/settings_controller.dart';
import '../../common/animated_metric.dart';
import '../../common/motion_widgets.dart';
import '../../common/surface_card.dart';

/// The three rolling averages shown directly under the live reading:
/// per day, per 3 days, per week.
///
/// Each tile can be tapped to expand into the supporting numbers (total volume,
/// peak, how much of the window actually has data) rather than dumping six
/// figures on screen at once.
class AveragesRow extends StatefulWidget {
  const AveragesRow({
    super.key,
    required this.aggregates,
    required this.formatter,
    required this.accent,
  });

  final SensorAggregates aggregates;
  final UnitFormatter formatter;
  final Color accent;

  @override
  State<AveragesRow> createState() => _AveragesRowState();
}

class _AveragesRowState extends State<AveragesRow> {
  AverageWindow? _expanded;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CardLabel(
          'Average flow',
          trailing: Text(
            'rolling windows',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: Tokens.s2),
        Row(
          children: <Widget>[
            for (final stats in widget.aggregates.all) ...<Widget>[
              Expanded(
                child: _AverageTile(
                  stats: stats,
                  formatter: widget.formatter,
                  accent: widget.accent,
                  selected: _expanded == stats.window,
                  onTap: () => setState(() {
                    _expanded = _expanded == stats.window ? null : stats.window;
                  }),
                ),
              ),
              if (stats.window != AverageWindow.week)
                const SizedBox(width: Tokens.s2),
            ],
          ],
        ),
        AnimatedSize(
          duration: motionOf(context, Motion.base),
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: _expanded == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Tokens.s2),
                  child: _WindowDetail(
                    stats: widget.aggregates.forWindow(_expanded!),
                    formatter: widget.formatter,
                  ),
                ),
        ),
      ],
    );
  }
}

class _AverageTile extends StatelessWidget {
  const _AverageTile({
    required this.stats,
    required this.formatter,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final WindowStats stats;
  final UnitFormatter formatter;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    // Guarantee the tappable tile clears the 44x44 Compact touch-target floor
    // (Requirement 11.9). Width comes from the Expanded parent; the min height
    // is asserted here so the card is never shorter than a comfortable target.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: SurfaceCard(
        raised: true,
        accent: selected ? accent : null,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s2,
          vertical: Tokens.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    stats.window.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? accent : palette.textSecondary,
                      letterSpacing: 0.8,
                      fontSize: 10,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: selected ? 0.5 : 0,
                  duration: motionOf(context, Motion.fast),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 14,
                    color: selected ? accent : palette.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.s2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedMetric(
                value: stats.averageLpm,
                format: (v) => formatter.flowValue(v),
                size: 19,
                color: stats.hasData
                    ? palette.textPrimary
                    : palette.textSecondary,
                // Accessible name for the rolling-average readout
                // (Requirement 11.8): e.g. "Per day average, 3.4 L/min". The
                // unit lives in a separate Text below, so name it here explicitly.
                semanticsLabel:
                    '${stats.window.label} average, ${formatter.flowUnit.symbol}',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatter.flowUnit.symbol,
              style: AppText.mono(
                size: 10,
                weight: FontWeight.w500,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: Tokens.s1),
            _CoverageBar(coverage: stats.coverage, accent: accent),
          ],
        ),
      ),
    );
  }
}

/// Thin bar showing how much of the window has data. An average built from two
/// hours of a seven-day window is not a weekly average, and the UI should not
/// pretend otherwise.
class _CoverageBar extends StatelessWidget {
  const _CoverageBar({required this.coverage, required this.accent});

  final double coverage;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: '${(coverage * 100).toStringAsFixed(0)}% of the window has data',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: coverage.clamp(0.0, 1.0)),
          duration: motionOf(context, Motion.slow),
          curve: Motion.value,
          builder: (context, value, _) => LinearProgressIndicator(
            value: value,
            minHeight: 3,
            backgroundColor: palette.border,
            valueColor: AlwaysStoppedAnimation<Color>(
              value < 0.25 ? palette.textSecondary : accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowDetail extends StatelessWidget {
  const _WindowDetail({required this.stats, required this.formatter});

  final WindowStats stats;
  final UnitFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    // The Bs_Equivalence beside the window's total volume (Requirement 6.2,
    // 6.5). Built from the same settings source as the TotalsCard so both call
    // sites share one mechanism; fed canonical litres (Req 6.7).
    final settings = context.watch<SettingsController>().settings;
    final cost = settings.costFormatter(
      platformTag: WidgetsBinding.instance.platformDispatcher.locale
          .toLanguageTag(),
    );

    return SurfaceCard(
      raised: true,
      padding: const EdgeInsets.all(Tokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${stats.window.label} · last ${stats.window.shortLabel}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: Tokens.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: MetricTile(
                  label: 'Total used',
                  value: stats.totalLitres,
                  format: (v) => formatter.volumeValue(v),
                  unit: formatter.volumeUnit.symbol,
                  size: 17,
                  secondary: CostLine(
                    canonicalLitres: stats.totalLitres,
                    formatter: cost,
                    semanticsLabel: 'Total used cost',
                  ),
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Peak',
                  value: stats.peakLpm,
                  format: (v) => formatter.flowValue(v),
                  unit: formatter.flowUnit.symbol,
                  size: 17,
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'While running',
                  value: stats.averageWhileActiveLpm,
                  format: (v) => formatter.flowValue(v),
                  unit: formatter.flowUnit.symbol,
                  size: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          Row(
            children: <Widget>[
              Icon(
                stats.isReliable
                    ? Icons.check_circle_outline
                    : Icons.pending_outlined,
                size: 14,
                color: stats.isReliable ? palette.normal : palette.watch,
              ),
              const SizedBox(width: Tokens.s1),
              Expanded(
                child: Text(
                  stats.hasData
                      ? stats.isReliable
                            ? 'Built from ${stats.sampleCount} samples · '
                                  'flowing ${(stats.activeFraction * 100).toStringAsFixed(0)}% '
                                  'of the time'
                            : 'Only ${(stats.coverage * 100).toStringAsFixed(0)}% of this '
                                  'window has data — the figure is still settling'
                      : 'No data recorded in this window yet',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

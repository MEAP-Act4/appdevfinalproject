import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/protocol/leak_protocol.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../data/settings/settings_controller.dart';
import '../../../state/monitor_controller.dart';
import '../../common/animated_metric.dart';
import '../../common/charts.dart';
import '../../common/motion_widgets.dart';
import '../../common/surface_card.dart';

/// Inlet-only card: the actual leak verdict, shown as the envelope gauge.
///
/// Extracted verbatim from `sensor_page.dart` (task 7.2); this is a pure
/// refactor with no visual change. Mirrors the Web_Client `BalanceCard`
/// (task 7.3). Preserves the telemetry-null shimmer state.
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.telemetry});

  final Telemetry? telemetry;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final formatter = settings.formatter;
    final t = telemetry;

    if (t == null) {
      return const SurfaceCard(
        child: SizedBox(
          height: 120,
          child: Center(child: ShimmerBox(height: 60)),
        ),
      );
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CardLabel('Inlet vs outlets'),
          const SizedBox(height: Tokens.s3),
          Row(
            children: <Widget>[
              Expanded(
                child: MetricTile(
                  label: 'Into manifold',
                  value: t.inlet,
                  format: (v) => formatter.flowValue(v),
                  unit: formatter.flowUnit.symbol,
                  size: 18,
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Out of branches',
                  value: t.totalOut,
                  format: (v) => formatter.flowValue(v),
                  unit: formatter.flowUnit.symbol,
                  size: 18,
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Unaccounted',
                  value: t.balanceLpm,
                  format: (v) => formatter.flowValue(v),
                  unit: formatter.flowUnit.symbol,
                  size: 18,
                  valueColor: t.balanceLpm.abs() > t.thresholdLpm
                      ? palette.alert
                      : palette.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          EnvelopeGauge(
            label: 'Tolerance envelope',
            balanceLpm: t.balanceLpm,
            thresholdLpm: t.thresholdLpm,
            expectedLpm: t.expectedLpm,
          ),
          const SizedBox(height: Tokens.s3),
          Text(
            t.status == LeakStatus.idle
                ? 'Nothing flowing, so no balance check is running.'
                : 'Alarm threshold at this flow rate is '
                      '${formatter.flow(t.thresholdLpm)}. '
                      'Currently using ${(t.envelopeUsage * 100).toStringAsFixed(0)}% '
                      'of that allowance.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlet card: how much of the inlet this branch is taking.
///
/// Extracted verbatim from `sensor_page.dart` (task 7.2); this is a pure
/// refactor with no visual change. Mirrors the Web_Client `BranchShareCard`
/// (task 7.3). Preserves the telemetry-null shimmer state and the
/// `motionOf(context, Motion.base)` reduce-motion routing on the share bar.
class BranchShareCard extends StatelessWidget {
  const BranchShareCard({
    super.key,
    required this.sensorIndex,
    required this.telemetry,
  });

  final int sensorIndex;
  final Telemetry? telemetry;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final formatter = settings.formatter;
    final t = telemetry;

    if (t == null) {
      return const SurfaceCard(
        child: SizedBox(
          height: 110,
          child: Center(child: ShimmerBox(height: 48)),
        ),
      );
    }

    final branch = t.flowLpm[sensorIndex];
    final share = t.inlet > 0 ? (branch / t.inlet).clamp(0.0, 1.0) : 0.0;
    final other = sensorIndex == 1 ? t.outletB : t.outletA;
    final otherName = settings.sensorNames[sensorIndex == 1 ? 2 : 1];

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CardLabel('Share of supply'),
          const SizedBox(height: Tokens.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              AnimatedMetric(
                value: share * 100,
                format: (v) => v.toStringAsFixed(0),
                unit: '%',
                size: 30,
                color: palette.gradientGreen,
                // Accessible name for the share readout (Requirement 11.8).
                semanticsLabel: 'Share of supply',
              ),
              const Spacer(),
              Text(
                t.inlet > 0
                    ? 'of ${formatter.flow(t.inlet)} supplied'
                    : 'supply idle',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          ClipRRect(
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: share),
              duration: motionOf(context, Motion.base),
              curve: Motion.value,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: palette.surfaceRaised,
                valueColor: AlwaysStoppedAnimation<Color>(
                  palette.gradientGreen,
                ),
              ),
            ),
          ),
          const SizedBox(height: Tokens.s3),
          Text(
            '$otherName is drawing ${formatter.flow(other)}. A branch reading '
            'zero on its own is normal — a closed tap is not a fault.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cumulative volume for this channel, with the device-side reset.
///
/// Extracted verbatim from `sensor_page.dart` (task 7.2); this is a pure
/// refactor with no visual change. Mirrors the Web_Client `TotalsCard`
/// (task 7.3). Preserves the device-side reset button behaviour.
class TotalsCard extends StatelessWidget {
  const TotalsCard({super.key, required this.sensorIndex});

  final int sensorIndex;

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final formatter = settings.formatter;
    // One Bs_Equivalence formatter for every volume figure on this card
    // (Requirement 6.1, 6.5). Fed canonical litres, never the display-unit
    // value, so it is invariant under a change of volume unit (Req 6.7).
    final cost = settings.costFormatter(
      platformTag: WidgetsBinding.instance.platformDispatcher.locale
          .toLanguageTag(),
    );

    final aggregates = monitor.aggregates.forSensor(sensorIndex);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CardLabel(
            'Volume',
            trailing: TextButton.icon(
              onPressed: monitor.isConnected
                  ? () async {
                      final ok = await monitor.zeroTotals();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Device totals reset to zero'
                                : 'Could not reach the device',
                          ),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('Reset'),
              style: TextButton.styleFrom(
                // Keep the visible chrome tight but reserve a 44x44 hit area so
                // the control clears the Compact touch-target floor
                // (Requirement 11.9). `padded` reserves the minimum touch size
                // without enlarging the painted button.
                tapTargetSize: MaterialTapTargetSize.padded,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s2),
              ),
            ),
          ),
          const SizedBox(height: Tokens.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: MetricTile(
                  label: 'Since reset',
                  value: monitor.volumeFor(sensorIndex),
                  format: (v) => formatter.volumeValue(v),
                  unit: formatter.volumeUnit.symbol,
                  size: 20,
                  secondary: CostLine(
                    canonicalLitres: monitor.volumeFor(sensorIndex),
                    formatter: cost,
                    semanticsLabel: 'Since reset cost',
                  ),
                  caption: 'counted on the board',
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Last 24 h',
                  value: aggregates.day.totalLitres,
                  format: (v) => formatter.volumeValue(v),
                  unit: formatter.volumeUnit.symbol,
                  size: 20,
                  secondary: CostLine(
                    canonicalLitres: aggregates.day.totalLitres,
                    formatter: cost,
                    semanticsLabel: 'Last 24 hours cost',
                  ),
                  caption: 'from stored history',
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Last 7 d',
                  value: aggregates.week.totalLitres,
                  format: (v) => formatter.volumeValue(v),
                  unit: formatter.volumeUnit.symbol,
                  size: 20,
                  secondary: CostLine(
                    canonicalLitres: aggregates.week.totalLitres,
                    formatter: cost,
                    semanticsLabel: 'Last 7 days cost',
                  ),
                  caption: 'from stored history',
                ),
              ),
            ],
          ),
          if (aggregates.trendRatio.abs() > 0.15 &&
              aggregates.week.isReliable) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            Row(
              children: <Widget>[
                Icon(
                  aggregates.trendRatio > 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 16,
                  color: aggregates.trendRatio > 0
                      ? palette.watch
                      : palette.normal,
                ),
                const SizedBox(width: Tokens.s1),
                Expanded(
                  child: Text(
                    'Today is '
                    '${(aggregates.trendRatio.abs() * 100).toStringAsFixed(0)}% '
                    '${aggregates.trendRatio > 0 ? 'above' : 'below'} the weekly '
                    'average for this channel.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Explains the calibrated envelope in plain language, so the numbers on the
/// gauge are not a black box.
///
/// Extracted verbatim from `sensor_page.dart` (task 7.2); this is a pure
/// refactor with no visual change. Mirrors the Web_Client `EnvelopeExplainer`
/// (task 7.3). Preserves the conditional confirmation-time row.
class EnvelopeExplainerCard extends StatelessWidget {
  const EnvelopeExplainerCard({super.key, required this.telemetry});

  final Telemetry telemetry;

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final formatter = settings.formatter;
    final config = monitor.deviceConfig;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CardLabel('Why this is not an alarm'),
          const SizedBox(height: Tokens.s2),
          _ExplainRow(
            label: 'Expected imbalance',
            value: formatter.flow(telemetry.expectedLpm),
            hint: 'from the calibration dataset at this flow rate',
          ),
          _ExplainRow(
            label: 'Margin of error',
            value: formatter.flow(
              telemetry.thresholdLpm - telemetry.expectedLpm,
            ),
            hint: 'sensor quantisation plus linearity spec',
          ),
          _ExplainRow(
            label: 'Alarm threshold',
            value: formatter.flow(telemetry.thresholdLpm),
            hint: 'breach must persist before the alarm latches',
          ),
          if (config != null)
            _ExplainRow(
              label: 'Confirmation time',
              value: '${config.leakConfirmSamples} s',
              hint: 'consecutive breaching samples required',
            ),
          const SizedBox(height: Tokens.s2),
          Text(
            'Readings below the ${config == null ? '' : formatter.flow(config.noiseFloorLpm)} '
            'noise floor are reported as exactly zero, which is why a quiet '
            'system never raises a leak.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single labelled row inside [EnvelopeExplainerCard]. Kept private to this
/// file: its only caller is [EnvelopeExplainerCard]. If the Dashboard_View
/// (task 9.8) ever needs the same row treatment, promote it to public then.
class _ExplainRow extends StatelessWidget {
  const _ExplainRow({
    required this.label,
    required this.value,
    required this.hint,
  });

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.s2),
          Text(
            value,
            style: AppText.mono(
              size: 14,
              weight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

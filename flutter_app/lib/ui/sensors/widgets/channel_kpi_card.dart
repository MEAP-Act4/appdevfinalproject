import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/protocol/leak_protocol.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../data/settings/settings_controller.dart';
import '../../../state/monitor_controller.dart';
import '../../common/alert_banner.dart';
import '../../common/animated_metric.dart';
import '../../common/charts.dart';
import '../../common/motion_widgets.dart';
import '../../common/surface_card.dart';

/// The KPI card for a single channel: the live animated reading, the device
/// Status, the flowing/still affordance and the live 3-minute trace.
///
/// This is the same widget in the carousel hero slot and in the dashboard
/// KPI_Row cell (Requirement 4.6). The only difference between the two uses is
/// the [dense] flag, which controls the KPI numeral size — DESIGN.md §4 fixes
/// the dashboard cell at [Tokens.kpiSize] (32), while the carousel hero has
/// room for the larger [kHeroKpiSize].
///
/// Extracted verbatim from `sensor_page.dart` (task 7.1); this is a pure
/// refactor with no visual change at the carousel call site, which uses the
/// default [dense] `= false` and therefore keeps the historical hero size.
class ChannelKpiCard extends StatelessWidget {
  const ChannelKpiCard({
    super.key,
    required this.sensorIndex,
    required this.accent,
    required this.liveLpm,
    required this.flowing,
    required this.series,
    this.dense = false,
  });

  final int sensorIndex;
  final Color accent;
  final double liveLpm;
  final bool flowing;
  final List<double> series;

  /// Controls the KPI numeral size. `false` (the default) is the carousel hero
  /// size [kHeroKpiSize]; `true` is the WattVision §4 dashboard-cell size
  /// [Tokens.kpiSize] (32). The carousel call site relies on the default so its
  /// rendering is unchanged by this extraction.
  final bool dense;

  /// The larger KPI numeral size used in the carousel hero slot. Historical
  /// value from `_LiveReadingCard`, preserved so the carousel does not change.
  static const double kHeroKpiSize = 44;

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final formatter = settings.formatter;

    final role = SensorRole.byIndex(sensorIndex);
    final name = settings.sensorNames[sensorIndex];
    final status = monitor.status;
    final stale = monitor.isStale;

    final kpiSize = dense ? Tokens.kpiSize : kHeroKpiSize;

    return SurfaceCard(
      accent: flowing ? accent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${role.label} · ${role.description}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(status: status, live: !stale && monitor.isConnected),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: AnimatedMetric(
                  value: liveLpm,
                  format: (v) => formatter.flowValue(v),
                  unit: formatter.flowUnit.symbol,
                  size: kpiSize,
                  color: flowing ? palette.textPrimary : palette.textSecondary,
                  // Accessible name for the live KPI readout (Requirement 11.8):
                  // "<channel> flow" so the reader announces e.g.
                  // "Main Inlet flow, 5.2 L/min".
                  semanticsLabel: '$name flow',
                ),
              ),
              _FlowingBadge(flowing: flowing, accent: accent),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          Text(
            flowing
                ? 'Live reading, updated every second'
                : 'No flow on this channel right now',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: Tokens.s4),
          FlowSparkline(values: series, color: accent, height: 104),
          const SizedBox(height: Tokens.s2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                series.length > 1 ? '−${series.length}s' : '',
                style: AppText.mono(
                  size: 10,
                  weight: FontWeight.w500,
                  color: palette.textSecondary,
                ),
              ),
              Text(
                'now',
                style: AppText.mono(
                  size: 10,
                  weight: FontWeight.w500,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowingBadge extends StatelessWidget {
  const _FlowingBadge({required this.flowing, required this.accent});

  final bool flowing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final colour = flowing ? accent : palette.idle;
    return SoftSwitcher(
      child: Container(
        key: ValueKey<bool>(flowing),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s2, vertical: 5),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Tokens.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              flowing ? Icons.waves_rounded : Icons.do_not_disturb_on_outlined,
              size: 13,
              color: colour,
            ),
            const SizedBox(width: Tokens.s1),
            Text(
              flowing ? 'FLOWING' : 'STILL',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colour,
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

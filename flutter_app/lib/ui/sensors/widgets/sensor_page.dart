import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/protocol/leak_protocol.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../data/settings/settings_controller.dart';
import '../../../state/monitor_controller.dart';
import '../../common/motion_widgets.dart';
import '../../common/surface_card.dart';
import 'averages_row.dart';
import 'channel_cards.dart';
import 'channel_kpi_card.dart';

/// One sensor's full detail page inside the carousel.
///
/// A thin composition of the extracted channel widgets: the [ChannelKpiCard]
/// hero, the [AveragesRow] inside its own [SurfaceCard], the balance-or-share
/// card, the [TotalsCard], and the optional [EnvelopeExplainerCard]. The card
/// definitions themselves live in `channel_kpi_card.dart` and `channel_cards.dart`
/// (tasks 7.1 and 7.2); this file only arranges them.
class SensorPage extends StatelessWidget {
  const SensorPage({super.key, required this.sensorIndex});

  final int sensorIndex;

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;
    final palette = AppPalette.of(context);
    final formatter = settings.formatter;

    final role = SensorRole.byIndex(sensorIndex);
    final telemetry = monitor.latest;
    final live = monitor.flowFor(sensorIndex);
    final series = monitor.liveSeries(sensorIndex);
    final aggregates = monitor.aggregates.forSensor(sensorIndex);

    final isInlet = role == SensorRole.inlet;
    final accent = isInlet ? palette.accent : palette.gradientGreen;
    final flowing = live > 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Tokens.s3,
        Tokens.s2,
        Tokens.s3,
        Tokens.s6,
      ),
      children: <Widget>[
        FadeSlideIn(
          index: 0,
          child: ChannelKpiCard(
            sensorIndex: sensorIndex,
            accent: accent,
            liveLpm: live,
            flowing: flowing,
            series: series,
          ),
        ),
        const SizedBox(height: Tokens.s3),
        FadeSlideIn(
          index: 1,
          child: SurfaceCard(
            child: AveragesRow(
              aggregates: aggregates,
              formatter: formatter,
              accent: accent,
            ),
          ),
        ),
        const SizedBox(height: Tokens.s3),
        FadeSlideIn(
          index: 2,
          child: isInlet
              ? BalanceCard(telemetry: telemetry)
              : BranchShareCard(sensorIndex: sensorIndex, telemetry: telemetry),
        ),
        const SizedBox(height: Tokens.s3),
        FadeSlideIn(
          index: 3,
          child: TotalsCard(sensorIndex: sensorIndex),
        ),
        if (settings.showEnvelopeDetails && telemetry != null) ...<Widget>[
          const SizedBox(height: Tokens.s3),
          FadeSlideIn(index: 4, child: EnvelopeExplainerCard(telemetry: telemetry)),
        ],
      ],
    );
  }
}

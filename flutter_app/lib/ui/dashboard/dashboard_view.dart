/// Dashboard_View — the Medium and Expanded presentation of the Sensors tab
/// (Requirements 3.1–3.6, 3.9, 3.10).
///
/// The dashboard is a second presentation of the *same* per-channel data the
/// Compact carousel shows, composed on [Grid12] rather than stacked in a
/// carousel. Its defining discipline is that the composition is **data, not
/// branching layout code**: [dashboardComposition] turns the current
/// [LayoutMode] into a single ordered `List<`[DashboardCellSpec]`>` — a role
/// plus a column span per cell — and [DashboardView] maps that list to
/// [Grid12Cell]s. There is no `if (expanded) … else …` around the widget tree;
/// the only place the mode is consulted is the pure span table below.
///
/// That matters because the composition is a cross-client contract. The
/// canonical ordered cells and their spans live once, at the repo root, in
/// `test_fixtures/layout/compositions.json`, and *both* clients derive their
/// composition as data and assert it equals that fixture (Property 29). Keeping
/// the Flutter side a pure function of the mode — [dashboardComposition] —
/// rather than an implicit consequence of how widgets happen to be nested is
/// what makes that assertion possible without pumping a widget tree.
///
/// **The composition (Requirements 3.1–3.4).**
///
///  * KPI_Row: three cells, `span: 4` each, in the fixed order Main Inlet,
///    Outlet A, Outlet B (Requirement 3.2). `4 + 4 + 4 = 12`, so they occupy
///    one run.
///  * Main_Chart + Alerts_Panel: in Expanded the chart is `span: 8` and the
///    alerts panel `span: 4` (`8 + 4 = 12`, one shared run beginning on the
///    same grid row, Requirement 3.3); in Medium each is `span: 12`, so the
///    chart sits above the alerts panel in its own run (Requirement 3.4).
///
/// Compact has no Grid_12 composition — it renders the Sensor_Carousel instead
/// (`compositions.json` records this as `grid:false`). [dashboardComposition]
/// returns an empty list for Compact so a caller that wrongly built a grid there
/// would produce nothing, and this view is simply not mounted in Compact by the
/// shell (task 9.10 owns that wiring).
///
/// **Reuse, not duplication.** The KPI cells are the extracted
/// [ChannelKpiCard] with its `dense` flag set — the very same widget the
/// carousel hero uses (Requirement 4.6), only at the WattVision §4 dashboard
/// numeral size. The three rolling averages sit behind an in-place disclosure
/// on each KPI cell (Requirement 3.6) built from the extracted [AveragesRow],
/// so no averaging or formatting is re-derived here. The Main_Chart is the
/// multi-series [FlowSparkline.multi] (task 9.6). Channel selection for the
/// chart is a row of [FilterChip]s that is a *separate* multi-select state,
/// independent of the shared `selectedChannel`, because Requirement 3.9 wants
/// all three plottable at once while the carousel's focus stays singular.
///
/// _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.9, 3.10_
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/layout/layout_mode.dart';
import '../../core/layout/layout_scope.dart';
import '../../core/protocol/leak_protocol.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/settings/settings_controller.dart';
import '../../state/monitor_controller.dart';
import '../common/charts.dart';
import '../common/icon_language.dart';
import '../common/motion_widgets.dart';
import '../common/surface_card.dart';
import '../diagnostics/diagnostics_sheet.dart';
import '../layout/grid12.dart';
import '../sensors/widgets/averages_row.dart';
import '../sensors/widgets/channel_kpi_card.dart';
import 'alerts_panel.dart';

/// A stable identifier for one cell of the Dashboard_View composition.
///
/// These are *roles*, not display text, and they match the `role` values in
/// `test_fixtures/layout/compositions.json` one-for-one so Property 29 can
/// compare the derived composition against the shared fixture directly. The
/// three KPI roles carry the fixed KPI_Row order (Requirement 3.2).
enum DashboardCellRole {
  kpiMainInlet('kpi-main-inlet'),
  kpiOutletA('kpi-outlet-a'),
  kpiOutletB('kpi-outlet-b'),
  mainChart('main-chart'),
  alertsPanel('alerts-panel');

  const DashboardCellRole(this.id);

  /// The stable identifier shared with the fixture and the Web_Client.
  final String id;

  /// The sensor channel this KPI role plots, or `null` for the non-KPI roles.
  int? get sensorIndex {
    switch (this) {
      case DashboardCellRole.kpiMainInlet:
        return SensorRole.inlet.index;
      case DashboardCellRole.kpiOutletA:
        return SensorRole.outletA.index;
      case DashboardCellRole.kpiOutletB:
        return SensorRole.outletB.index;
      case DashboardCellRole.mainChart:
      case DashboardCellRole.alertsPanel:
        return null;
    }
  }
}

/// One entry in the Dashboard_View composition: a [role] and the Grid_12
/// column [span] it occupies. This is the pure data unit Property 29 asserts
/// against; it carries no widget.
@immutable
class DashboardCellSpec {
  const DashboardCellSpec(this.role, this.span)
    : assert(
        span >= 1 && span <= 12,
        'DashboardCellSpec.span must be an integer in 1..12, got $span.',
      );

  /// Which cell this is.
  final DashboardCellRole role;

  /// The Grid_12 column span, in `1..12`.
  final int span;

  @override
  bool operator ==(Object other) =>
      other is DashboardCellSpec && other.role == role && other.span == span;

  @override
  int get hashCode => Object.hash(role, span);

  @override
  String toString() => 'DashboardCellSpec(${role.id}, span: $span)';
}

/// The Dashboard_View composition for [mode], as a single ordered list — the
/// one place the layout depends on the mode (Requirements 3.1–3.4).
///
/// The KPI_Row is always three `span: 4` cells in the fixed order Main Inlet,
/// Outlet A, Outlet B. The Main_Chart and Alerts_Panel spans differ by mode:
///
///  * Expanded: chart `span: 8`, alerts `span: 4` — one shared run.
///  * Medium:   chart `span: 12`, alerts `span: 12` — stacked runs.
///
/// Compact returns an empty list: it has no grid composition (it renders the
/// Sensor_Carousel), matching `compositions.json`'s `grid:false`.
List<DashboardCellSpec> dashboardComposition(LayoutMode mode) {
  switch (mode) {
    case LayoutMode.compact:
      return const <DashboardCellSpec>[];
    case LayoutMode.medium:
      return const <DashboardCellSpec>[
        DashboardCellSpec(DashboardCellRole.kpiMainInlet, 4),
        DashboardCellSpec(DashboardCellRole.kpiOutletA, 4),
        DashboardCellSpec(DashboardCellRole.kpiOutletB, 4),
        DashboardCellSpec(DashboardCellRole.mainChart, 12),
        DashboardCellSpec(DashboardCellRole.alertsPanel, 12),
      ];
    case LayoutMode.expanded:
      return const <DashboardCellSpec>[
        DashboardCellSpec(DashboardCellRole.kpiMainInlet, 4),
        DashboardCellSpec(DashboardCellRole.kpiOutletA, 4),
        DashboardCellSpec(DashboardCellRole.kpiOutletB, 4),
        DashboardCellSpec(DashboardCellRole.mainChart, 8),
        DashboardCellSpec(DashboardCellRole.alertsPanel, 4),
      ];
  }
}

/// The Medium/Expanded dashboard.
///
/// Reads the [LayoutMode] from [LayoutScope], derives its composition with
/// [dashboardComposition], and lays the resulting cells out on a
/// [Grid12Scaffold] + [Grid12]. The chart channel selection is local
/// multi-select state ([_selectedForChart]) that starts with all three channels
/// on (Requirement 3.9) and is independent of the shared `selectedChannel`.
class DashboardView extends StatefulWidget {
  const DashboardView({super.key, this.alertsPanel});

  /// The Alerts_Panel widget to place in the alerts cell. Defaults to the real
  /// [AlertsPanel] (task 13.7), which reads its rows from the [AlertsController]
  /// in the provider tree and degrades to an empty state when none is present.
  /// A caller may override it — the composition tests pass a lightweight stand-
  /// in — but production leaves it null and gets the real panel.
  final Widget? alertsPanel;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  /// Which channels the Main_Chart plots. Multi-select, independent of the
  /// shared selection, and seeded with every channel on (Requirement 3.9).
  final Set<int> _selectedForChart = <int>{
    for (var i = 0; i < kSensorCount; i++) i,
  };

  void _toggleChartChannel(int index) {
    setState(() {
      // Keep at least one channel plotted so the chart never goes blank from a
      // stray tap; a chart of nothing is not a state the user asked for.
      if (_selectedForChart.contains(index)) {
        if (_selectedForChart.length > 1) _selectedForChart.remove(index);
      } else {
        _selectedForChart.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final mode = LayoutScope.of(context);
    final composition = dashboardComposition(mode);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        titleSpacing: Tokens.s3,
        title: const Text('Dashboard'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Diagnostics',
            onPressed: () => DiagnosticsSheet.show(context),
            icon: AppIcon(AppGlyph.gauge, color: palette.accentText),
          ),
          const SizedBox(width: Tokens.s1),
        ],
      ),
      body: SingleChildScrollView(
        child: Grid12Scaffold(
          child: Grid12(
            children: <Grid12Cell>[
              for (final spec in composition)
                Grid12Cell(span: spec.span, child: _cellFor(spec.role)),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the widget for one composition [role]. This is a lookup keyed by
  /// role, not layout branching — the span and order come from the data.
  Widget _cellFor(DashboardCellRole role) {
    switch (role) {
      case DashboardCellRole.kpiMainInlet:
      case DashboardCellRole.kpiOutletA:
      case DashboardCellRole.kpiOutletB:
        return _DashboardKpiCell(sensorIndex: role.sensorIndex!);
      case DashboardCellRole.mainChart:
        return _MainChart(
          selectedChannels: _selectedForChart,
          onToggleChannel: _toggleChartChannel,
        );
      case DashboardCellRole.alertsPanel:
        return widget.alertsPanel ?? const AlertsPanel();
    }
  }
}

/// A KPI_Row cell: the shared [ChannelKpiCard] at the dense dashboard size, with
/// the three rolling averages tucked behind an in-place disclosure on the same
/// card (Requirements 3.5, 3.6).
///
/// The disclosure keeps the averages *within that channel's KPI card* — the
/// card expands in place to reveal the extracted [AveragesRow] rather than
/// pushing the user to another surface, which is the "within that channel's KPI
/// card" arm of Requirement 3.6.
class _DashboardKpiCell extends StatefulWidget {
  const _DashboardKpiCell({required this.sensorIndex});

  final int sensorIndex;

  @override
  State<_DashboardKpiCell> createState() => _DashboardKpiCellState();
}

class _DashboardKpiCellState extends State<_DashboardKpiCell> {
  bool _showAverages = false;

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    final index = widget.sensorIndex;
    final role = SensorRole.byIndex(index);
    final isInlet = role == SensorRole.inlet;
    final accent = isInlet ? palette.accent : palette.gradientGreen;

    final live = monitor.flowFor(index);
    final series = monitor.liveSeries(index);
    final aggregates = monitor.aggregates.forSensor(index);
    final flowing = live > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The KPI card itself — the exact same widget as the carousel hero,
        // only dense. Requirement 4.6 holds structurally by reusing it.
        ChannelKpiCard(
          sensorIndex: index,
          accent: accent,
          liveLpm: live,
          flowing: flowing,
          series: series,
          dense: true,
        ),
        const SizedBox(height: Tokens.s2),
        // The in-place disclosure control.
        _AveragesDisclosureButton(
          expanded: _showAverages,
          accent: accent,
          onTap: () => setState(() => _showAverages = !_showAverages),
        ),
        // The averages reveal in place, animated (and collapsed instantly under
        // Reduce_Motion via motionOf).
        AnimatedSize(
          duration: motionOf(context, Motion.base),
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: !_showAverages
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Tokens.s2),
                  child: SurfaceCard(
                    child: AveragesRow(
                      aggregates: aggregates,
                      formatter: settings.formatter,
                      accent: accent,
                    ),
                  ),
                ),
        ),
        // A screen-reader announcement of the disclosure target, so the extra
        // averages are discoverable without sight of the chevron.
        if (!_showAverages)
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(top: Tokens.s1),
              child: Text(
                'Averages hidden',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The tap target that toggles the averages disclosure on a KPI cell.
class _AveragesDisclosureButton extends StatelessWidget {
  const _AveragesDisclosureButton({
    required this.expanded,
    required this.accent,
    required this.onTap,
  });

  final bool expanded;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final label = expanded ? 'Hide averages' : 'Show averages';

    return Semantics(
      button: true,
      expanded: expanded,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
          // Reserve a 44x44 minimum hit area so the disclosure clears the
          // Compact touch-target floor (Requirement 11.9). The row is short, so
          // without this the padded height can fall under 44.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.s2,
                vertical: Tokens.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  // Flexible so the label yields space to the trailing group at
                  // large text scales rather than overflowing the row
                  // (Requirement 11.10 at 200% scale).
                  Flexible(
                    child: Text(
                      'Rolling averages',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          expanded ? 'Hide' : 'Show',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: palette.accentText,
                          ),
                        ),
                      ),
                      const SizedBox(width: Tokens.s1),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: motionOf(context, Motion.fast),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: palette.accentText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Main_Chart cell: a row of [FilterChip]s for channel selection above the
/// multi-series [FlowSparkline.multi] (Requirements 3.7, 3.8, 3.9).
///
/// The chips are a multi-select — every chip can be pressed at once — and drive
/// [selectedChannels], which is state owned by [DashboardView] and independent
/// of the shared `selectedChannel`. The chart plots one series per selected
/// channel, coloured by the channel's accent so the legend chips and the
/// strokes agree.
class _MainChart extends StatelessWidget {
  const _MainChart({
    required this.selectedChannels,
    required this.onToggleChannel,
  });

  final Set<int> selectedChannels;
  final void Function(int) onToggleChannel;

  /// The stroke colour for a channel: the inlet takes the accent, the outlets
  /// the gradient-green partner — matching the carousel's per-channel accents.
  Color _accentFor(int index, AppPalette palette) =>
      SensorRole.byIndex(index) == SensorRole.inlet
      ? palette.accent
      : palette.gradientGreen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;

    // Plot the selected channels in canonical channel order so the draw order
    // is stable regardless of the order chips were toggled.
    final plotted = <int>[
      for (var i = 0; i < kSensorCount; i++)
        if (selectedChannels.contains(i)) i,
    ];
    final series = <List<double>>[
      for (final i in plotted) monitor.liveSeries(i),
    ];
    final colors = <Color>[for (final i in plotted) _accentFor(i, palette)];

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CardLabel('Flow history'),
          const SizedBox(height: Tokens.s2),
          Text(
            'Live flow across the selected channels.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: Tokens.s3),
          // Channel selection — a multi-select chip row, all three selectable
          // at once (Requirement 3.9).
          Wrap(
            spacing: Tokens.s2,
            runSpacing: Tokens.s2,
            children: <Widget>[
              for (var i = 0; i < kSensorCount; i++)
                _ChannelChip(
                  label: settings.sensorNames[i],
                  accent: _accentFor(i, palette),
                  selected: selectedChannels.contains(i),
                  onTap: () => onToggleChannel(i),
                ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          FlowSparkline.multi(series: series, colors: colors, height: 180),
        ],
      ),
    );
  }
}

/// A single multi-select channel chip for the Main_Chart selector. Wraps
/// [FilterChip] so the pressed state tints in the channel's accent and stays
/// legible against the card.
class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      // A small accent dot doubles as a non-colour affordance for the series it
      // controls, so the mapping is not conveyed by colour alone.
      avatar: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: selected ? accent : palette.textSecondary,
          shape: BoxShape.circle,
        ),
      ),
      backgroundColor: palette.surfaceRaised,
      selectedColor: accent.withValues(alpha: 0.16),
      side: BorderSide(
        color: selected ? accent.withValues(alpha: 0.45) : palette.border,
      ),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: selected ? palette.textPrimary : palette.textSecondary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
      ),
    );
  }
}

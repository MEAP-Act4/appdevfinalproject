import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/layout/layout_mode.dart';
import '../../core/layout/layout_scope.dart';
import '../../core/protocol/leak_protocol.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/units/measurement_units.dart';
import '../../data/ble/leak_transport.dart';
import '../../data/models/stored_reading.dart';
import '../../data/settings/settings_controller.dart';
import '../../state/monitor_controller.dart';
import '../common/alert_banner.dart';
import '../common/data_table_row.dart';
import '../common/icon_language.dart';
import '../common/motion_widgets.dart';
import '../common/surface_card.dart';

/// Bottom sheet with the link health, the firmware configuration, the event log
/// and the raw protocol traffic. This is the screen you open when something looks
/// wrong, so it shows evidence rather than summaries.
class DiagnosticsSheet extends StatelessWidget {
  const DiagnosticsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const DiagnosticsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return DefaultTabController(
      length: 3,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
              child: Row(
                children: <Widget>[
                  AppIcon(AppGlyph.gauge, color: palette.accentText),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: Text(
                      'Diagnostics',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const _DisconnectButton(),
                ],
              ),
            ),
            const SizedBox(height: Tokens.s2),
            TabBar(
              // Tab labels are text; the indicator under them is a graphic.
              labelColor: palette.accentText,
              unselectedLabelColor: palette.textSecondary,
              indicatorColor: palette.accent,
              dividerColor: palette.border,
              tabs: const <Widget>[
                Tab(text: 'Link'),
                Tab(text: 'Events'),
                Tab(text: 'Raw'),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: <Widget>[
                  _LinkTab(),
                  _EventsTab(),
                  _RawTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisconnectButton extends StatelessWidget {
  const _DisconnectButton();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final palette = AppPalette.of(context);
    if (monitor.linkState.grantsAccess == false && !monitor.usingSimulator) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      onPressed: () async {
        await monitor.disconnect();
        if (context.mounted) Navigator.of(context).pop();
      },
      icon: const Icon(Icons.link_off_rounded, size: 18),
      label: const Text('Disconnect'),
      style: TextButton.styleFrom(foregroundColor: palette.alert),
    );
  }
}

class _LinkTab extends StatelessWidget {
  const _LinkTab();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final config = monitor.deviceConfig;
    final telemetry = monitor.latest;
    final formatter = settings.formatter;

    return ListView(
      padding: const EdgeInsets.all(Tokens.s3),
      children: <Widget>[
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CardLabel(
                'Link',
                trailing: StatusPill(
                  status: monitor.status,
                  live: monitor.isConnected,
                  compact: true,
                ),
              ),
              const SizedBox(height: Tokens.s3),
              _KeyValue('Transport', monitor.transportKind),
              _KeyValue('State', monitor.linkState.name),
              _KeyValue(
                'Device',
                monitor.connectedDevice?.displayName ?? 'not connected',
              ),
              _KeyValue('Address', monitor.connectedDevice?.id ?? '—'),
              _KeyValue(
                'Last sample',
                monitor.secondsSinceLastSample == null
                    ? '—'
                    : '${monitor.secondsSinceLastSample}s ago',
              ),
              if (telemetry != null)
                _KeyValue('Sequence', '#${telemetry.seq}'),
              if (telemetry != null)
                _KeyValue(
                  'Board uptime',
                  UnitFormatter.duration(
                    Duration(milliseconds: telemetry.uptimeMs),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s3),
        if (config != null)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const CardLabel('Firmware configuration'),
                const SizedBox(height: Tokens.s3),
                _KeyValue('Version', config.firmwareVersion),
                _KeyValue(
                  'Protocol',
                  'v${config.protocolVersion}'
                      '${config.isCompatible ? '' : ' (mismatch)'}',
                  valueColor: config.isCompatible ? null : palette.alert,
                ),
                _KeyValue('Sample interval', '${config.sampleIntervalMs} ms'),
                _KeyValue(
                  'Pulses per litre',
                  config.pulsesPerLitre
                      .map((v) => v.toStringAsFixed(0))
                      .join(' · '),
                ),
                _KeyValue(
                  'Noise floor',
                  formatter.flow(config.noiseFloorLpm),
                ),
                _KeyValue(
                  'Tolerance floor',
                  '${formatter.flow(config.toleranceAbsLpm)} · '
                      '${(config.tolerancePct * 100).toStringAsFixed(0)}%',
                ),
                _KeyValue(
                  'Fault gate',
                  formatter.flow(config.faultMinFlowLpm),
                ),
                _KeyValue(
                  'Debounce',
                  'leak ${config.leakConfirmSamples}s · '
                      'clear ${config.leakClearSamples}s · '
                      'fault ${config.faultConfirmSamples}s',
                ),
                _KeyValue(
                  'Learned bias',
                  config.isCalibrated
                      ? formatter.flow(config.learnedBiasLpm)
                      : 'not calibrated',
                  valueColor: config.isCalibrated ? palette.normal : palette.watch,
                ),
              ],
            ),
          )
        else
          SurfaceCard(
            child: Text(
              'No handshake received yet. The board sends its configuration on '
              'connect and on request.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
          ),
        const SizedBox(height: Tokens.s3),
        if (monitor.baseline.isNotEmpty) CalibrationTable(rows: monitor.baseline),
        if (monitor.usingSimulator) ...<Widget>[
          const SizedBox(height: Tokens.s3),
          const _SimulatorControls(),
        ],
        const SizedBox(height: Tokens.s3),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await monitor.pingDevice();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'Ping sent' : 'Could not send ping'),
                    ),
                  );
                },
                icon: const Icon(Icons.network_ping, size: 18),
                label: const Text('Ping'),
              ),
            ),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => monitor.send(LeakCommand.requestBaseline),
                icon: const Icon(Icons.dataset_outlined, size: 18),
                label: const Text('Reload dataset'),
              ),
            ),
          ],
        ),
        // Demo-leak injection: only meaningful on a real live link (the
        // simulator and replay already drive leaks on their own).
        if (!monitor.usingSimulator && !monitor.usingReplay) ...<Widget>[
          const SizedBox(height: Tokens.s3),
          const _DemoLeakControl(),
        ],
      ],
    );
  }
}

/// Arms/disarms the demo-leak injection for a live presentation. Clearly a
/// test control: the switch copy and the app-wide SIMULATED banner make plain
/// that an armed injection is not a real hardware detection.
class _DemoLeakControl extends StatelessWidget {
  const _DemoLeakControl();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final armed = monitor.leakInjected;

    return SurfaceCard(
      accent: armed ? palette.alert : null,
      leadingAccentBar: armed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: CardLabel(
                  'Demo leak injection',
                  trailing: armed
                      ? Text(
                          'SIMULATED',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: palette.alert,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ),
              Switch(
                value: armed,
                onChanged: monitor.setLeakInjection,
              ),
            ],
          ),
          const SizedBox(height: Tokens.s1),
          Text(
            'Forces the live feed to read as a leak for a controlled demo. While '
            'armed the app shows a SIMULATED marker — this is a presentation aid, '
            'not a real detection. Turn it off to show the genuine reading, then '
            'physically open the joint to detect a real leak.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The firmware's calibration dataset, rendered as the table it is
/// (Requirement 8: Table Row Styling).
///
/// **Why a plain [Table] and not a [DataTable].** [DataTable] imposes its own
/// row heights and Material theming that fight the WattVision tokens; the plain
/// [Table] takes explicit [columnWidths] and leaves every pixel of styling to
/// us (design.md, Requirements 8.5, 8.6).
///
/// **Reconciling [Table] with [DataTableRow].** The framework's [Table] only
/// accepts [TableRow] children, so a [DataTableRow] — which carries the shared
/// hover / focus / `#2C2C2E` bottom-border treatment (Requirement 8.1–8.3) —
/// cannot be a direct child of a [Table]. The structure that satisfies *both*
/// the "plain [Table] with [columnWidths]" and the "[DataTableRow] per row"
/// halves of the task is:
///
///   * one shared [columnWidths] map defines the four numeric columns once;
///   * the header is a [Table] carrying that map in a single [TableRow];
///   * each data row is a [DataTableRow] whose child is a *second* [Table]
///     sharing the identical [columnWidths] map, so the header and every data
///     row line up on the same column boundaries while each row still gets the
///     per-row hover, focus and border treatment [Table]'s own rows cannot
///     provide.
///
/// **Compact horizontal scroll (Requirement 8.7).** In [LayoutMode.compact] the
/// whole table is wrapped in a horizontal [SingleChildScrollView] over a
/// fixed-min-width table, so a narrow pane scrolls the table region rather than
/// shrinking the numerals below the label type size. In wider bands the table
/// fills the available width.
///
/// **Values presented unmodified (Requirements 8.6, 13.10).** Each column keeps
/// the exact display precision the firmware-facing figures use — inlet at two
/// decimals, the three balance figures at three — with no rounding beyond that
/// declared precision. Property 24 (task 15.15) asserts the round-trip.
class CalibrationTable extends StatelessWidget {
  const CalibrationTable({super.key, required this.rows});

  /// The calibration dataset exactly as reported by the firmware over the
  /// protocol. Rendered in order, unmodified.
  final List<BaselineRow> rows;

  /// The four columns, all numeric, sharing one width map across the header
  /// [Table] and every data-row [Table] so the columns align. Fixed intrinsic
  /// widths let the numerals sit against their trailing edge and give the
  /// Compact scroll something to overflow.
  static const Map<int, TableColumnWidth> _columnWidths =
      <int, TableColumnWidth>{
    0: FlexColumnWidth(),
    1: FlexColumnWidth(),
    2: FlexColumnWidth(),
    3: FlexColumnWidth(),
  };

  /// The minimum table width honoured while scrolling horizontally in Compact,
  /// so the four mono columns keep their room rather than collapsing.
  static const double _compactMinWidth = 360;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final compact = LayoutScope.maybeOf(context) == LayoutMode.compact;

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Header laid out with the shared column widths so it lines up with the
        // data rows below.
        Table(
          columnWidths: _columnWidths,
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: const <TableRow>[
            TableRow(
              children: <Widget>[
                _TableHead('Inlet'),
                _TableHead('Expected'),
                _TableHead('Margin'),
                _TableHead('Alarm at'),
              ],
            ),
          ],
        ),
        const SizedBox(height: Tokens.s1),
        // Each data row is a DataTableRow (hover / focus / bottom border) whose
        // child shares the header's column widths so the columns stay aligned.
        for (final row in rows)
          DataTableRow(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Table(
              columnWidths: _columnWidths,
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: <TableRow>[
                TableRow(
                  children: <Widget>[
                    _NumericCell(row.inletLpm, 2),
                    _NumericCell(row.expectedBalanceLpm, 3),
                    _NumericCell(row.marginLpm, 3),
                    _NumericCell(
                      row.thresholdLpm,
                      3,
                      color: palette.accentText,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CardLabel('Calibration dataset'),
          const SizedBox(height: Tokens.s1),
          Text(
            'Standardized flow rates and the margin of error allowed at each one. '
            'The alarm threshold is interpolated between these rows.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: Tokens.s3),
          if (compact)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minWidth: _compactMinWidth),
                child: table,
              ),
            )
          else
            table,
          const SizedBox(height: Tokens.s2),
          Text(
            'All values in L/min, as stored on the board.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHead extends StatelessWidget {
  const _TableHead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      // A numeric column header aligns on its trailing edge with the mono
      // numerals below it (Requirement 8.5).
      textAlign: TextAlign.right,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.of(context).textSecondary,
            fontSize: 10,
            letterSpacing: 0.8,
          ),
    );
  }
}

/// A single numeric table cell: monospaced (Requirement 8.5) and aligned on its
/// trailing edge, presenting [value] at its declared [decimals] of precision
/// with no further rounding (Requirements 8.6, 13.10).
class _NumericCell extends StatelessWidget {
  const _NumericCell(this.value, this.decimals, {this.color});

  final double value;
  final int decimals;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      value.toStringAsFixed(decimals),
      textAlign: TextAlign.right,
      style: AppText.mono(
        size: 12,
        weight: FontWeight.w600,
        color: color ?? AppPalette.of(context).textPrimary,
      ),
    );
  }
}

class _SimulatorControls extends StatelessWidget {
  const _SimulatorControls();

  @override
  Widget build(BuildContext context) {
    final monitor = context.read<MonitorController>();
    final palette = AppPalette.of(context);
    // The avatar is a Widget rather than an IconData so the "Sensor fault"
    // scenario can carry the domain pipe glyph (Requirement 10.1/10.2) while
    // the other structural scenarios stay on Material icons. The chip's own
    // text label supplies the accessible name (Requirement 10.4).
    final scenarios = <(String, String, Widget)>[
      ('idle', 'Idle', const Icon(Icons.pause_rounded, size: 15)),
      ('normal', 'Normal draw', const Icon(Icons.check_rounded, size: 15)),
      ('heavy', 'Heavy draw', const Icon(Icons.bolt_rounded, size: 15)),
      (
        'branch',
        'One branch only',
        const Icon(Icons.call_split_rounded, size: 15)
      ),
      (
        'leak',
        'Slow leak',
        const Icon(Icons.water_damage_outlined, size: 15)
      ),
      (
        'fault',
        'Sensor fault',
        AppIcon(AppGlyph.pipe, size: 15, color: palette.textSecondary)
      ),
    ];

    return SurfaceCard(
      accent: AppPalette.of(context).accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CardLabel('Simulator scenarios'),
          const SizedBox(height: Tokens.s2),
          Wrap(
            spacing: Tokens.s2,
            runSpacing: Tokens.s2,
            children: <Widget>[
              for (final (key, label, avatar) in scenarios)
                ActionChip(
                  avatar: avatar,
                  label: Text(label),
                  onPressed: () => monitor.forceSimulatorScenario(key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Loaded once when the tab opens rather than on every rebuild: the parent
/// rebuilds at 1 Hz with the telemetry feed, and re-running the query that often
/// would hammer the database for no benefit. Pull to refresh instead.
class _EventsTab extends StatefulWidget {
  const _EventsTab();

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  late Future<List<LeakEvent>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<MonitorController>().recentEvents();
  }

  void _reload() {
    setState(() {
      _future = context.read<MonitorController>().recentEvents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final format = DateFormat('d MMM · HH:mm:ss');

    return FutureBuilder<List<LeakEvent>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = snapshot.data!;
        if (events.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(Tokens.s5),
              child: Text(
                'No events recorded yet. Connections, leaks, faults and '
                'calibration runs all land here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          color: palette.accent,
          backgroundColor: palette.surface,
          child: ListView.separated(
            padding: const EdgeInsets.all(Tokens.s3),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(height: Tokens.s2),
            itemBuilder: (context, index) {
              final event = events[index];
              // Only ever used as the kind label's text colour.
              final colour = event.kind.isAlarm
                  ? palette.alert
                  : event.kind == EventKind.calibration
                      ? palette.accentText
                      : palette.textSecondary;

              return FadeSlideIn(
                index: index.clamp(0, 8),
                offset: 8,
                child: SurfaceCard(
                  padding: const EdgeInsets.all(Tokens.s3),
                  accent: event.kind.isAlarm ? palette.alert : null,
                  leadingAccentBar: event.kind.isAlarm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              event.kind.wire.replaceAll('_', ' '),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: colour, letterSpacing: 1),
                            ),
                          ),
                          Text(
                            format.format(event.timestamp),
                            style: AppText.mono(
                              size: 11,
                              weight: FontWeight.w500,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Tokens.s1),
                      Text(event.message, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RawTab extends StatelessWidget {
  const _RawTab();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final palette = AppPalette.of(context);
    final lines = monitor.rawLog.reversed.toList(growable: false);

    if (lines.isEmpty) {
      return Center(
        child: Text(
          'No traffic yet.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(Tokens.s3),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        // The colour of a monospaced log line — text, start to finish.
        final colour = line.startsWith('>')
            ? palette.accentText
            : line.startsWith('!')
                ? palette.alert
                : line.startsWith('·')
                    ? palette.watch
                    : palette.textSecondary;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            line,
            style: AppText.mono(
              size: 11,
              weight: FontWeight.w400,
              color: colour,
              letterSpacing: 0,
            ),
          ),
        );
      },
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value, {this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppText.mono(
                size: 12,
                weight: FontWeight.w600,
                color: valueColor ?? palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/leak_protocol.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../state/monitor_controller.dart';
import '../common/charts.dart';
import '../common/motion_widgets.dart';

/// Walks the installer through an on-site baseline calibration.
///
/// Why this exists: every rig has a small, real imbalance. Three sensors with
/// slightly different K factors plus the tees will never sum to exactly zero. The
/// firmware ships with a conservative default table, but measuring the actual
/// residual on this plumbing and storing it as `learnedBias` is what lets the
/// tolerance be tightened without generating false alarms.
class CalibrationDialog extends StatefulWidget {
  const CalibrationDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CalibrationDialog(),
    );
  }

  @override
  State<CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<CalibrationDialog> {
  int _durationSeconds = 30;
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final update = monitor.calibration;

    final running = _started &&
        (update == null || update.phase == CalibrationPhase.running);
    final finished = update != null && update.phase != CalibrationPhase.running;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.auto_graph_rounded, color: palette.accentText, size: 22),
          const SizedBox(width: Tokens.s2),
          const Expanded(child: Text('Baseline calibration')),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SoftSwitcher(
          child: finished
              ? _ResultView(update: update)
              : running
                  ? _RunningView(update: update, total: _durationSeconds)
                  : _SetupView(
                      durationSeconds: _durationSeconds,
                      onDurationChanged: (v) =>
                          setState(() => _durationSeconds = v),
                    ),
        ),
      ),
      actions: <Widget>[
        if (finished)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          )
        else if (running)
          TextButton(
            onPressed: () async {
              await monitor.cancelCalibration();
              if (context.mounted) Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: palette.alert),
            child: const Text('Cancel run'),
          )
        else ...<Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () async {
              setState(() => _started = true);
              await monitor.startCalibration(seconds: _durationSeconds);
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text('Start ${_durationSeconds}s run'),
          ),
        ],
      ],
      actionsPadding: const EdgeInsets.fromLTRB(
        Tokens.s3,
        0,
        Tokens.s3,
        Tokens.s3,
      ),
      contentTextStyle: theme.textTheme.bodyMedium,
    );
  }
}

class _SetupView extends StatelessWidget {
  const _SetupView({
    required this.durationSeconds,
    required this.onDurationChanged,
  });

  final int durationSeconds;
  final ValueChanged<int> onDurationChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Before you start',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: Tokens.s2),
        const _Step(
          number: 1,
          text: 'Confirm there is no actual leak on the run being measured.',
        ),
        const _Step(
          number: 2,
          text: 'Open both outlet branches so all three meters are turning.',
        ),
        const _Step(
          number: 3,
          text: 'Hold a steady flow above 0.5 L/min for the whole run — no '
              'opening or closing taps partway through.',
        ),
        const SizedBox(height: Tokens.s3),
        Text(
          'Run length',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: palette.textSecondary, letterSpacing: 1),
        ),
        const SizedBox(height: Tokens.s2),
        Wrap(
          spacing: Tokens.s2,
          children: <Widget>[
            for (final seconds in <int>[15, 30, 60, 120])
              ChoiceChip(
                label: Text('${seconds}s'),
                selected: durationSeconds == seconds,
                onSelected: (_) => onDurationChanged(seconds),
              ),
          ],
        ),
        const SizedBox(height: Tokens.s2),
        Text(
          'Longer runs average out more sensor noise. 30 seconds is enough for '
          'most installs.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: AppText.mono(
                size: 11,
                weight: FontWeight.w700,
                // The digit is text; the circle behind it keeps the graphical
                // accent at 14% above.
                color: palette.accentText,
              ),
            ),
          ),
          const SizedBox(width: Tokens.s2),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.update, required this.total});

  final CalibrationUpdate? update;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final monitor = context.watch<MonitorController>();

    final remaining = update?.secondsRemaining ?? total;
    final elapsed = (total - remaining).clamp(0, total);
    final progress = total == 0 ? 0.0 : elapsed / total;
    final inlet = monitor.flowFor(0);
    final enoughFlow = inlet >= 0.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RingProgress(
          progress: progress,
          size: 110,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$remaining',
                style: AppText.mono(size: 28, color: palette.textPrimary),
              ),
              Text(
                'seconds',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary, fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s4),
        Text(
          'Measuring the natural imbalance',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: Tokens.s2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              enoughFlow ? Icons.check_circle : Icons.warning_amber_rounded,
              size: 16,
              color: enoughFlow ? palette.normal : palette.watch,
            ),
            const SizedBox(width: Tokens.s1),
            Text(
              enoughFlow
                  ? 'Flow is sufficient (${inlet.toStringAsFixed(2)} L/min)'
                  : 'Open the taps wider — need 0.5 L/min or more',
              style: theme.textTheme.bodySmall?.copyWith(
                color: enoughFlow ? palette.normal : palette.watch,
              ),
            ),
          ],
        ),
        if (update != null) ...<Widget>[
          const SizedBox(height: Tokens.s3),
          Text(
            '${update!.sampleCount} usable samples · running mean '
            '${update!.meanBalanceLpm.toStringAsFixed(4)} L/min',
            style: AppText.mono(
              size: 11,
              weight: FontWeight.w500,
              color: palette.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.update});

  final CalibrationUpdate update;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final ok = update.phase == CalibrationPhase.done;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              ok ? Icons.check_circle : Icons.error_outline,
              color: ok ? palette.normal : palette.alert,
              size: 28,
            ),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: Text(
                ok ? 'Calibration stored' : 'Calibration failed',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s3),
        if (ok) ...<Widget>[
          _ResultRow(
            label: 'Learned bias',
            value: '${update.meanBalanceLpm.toStringAsFixed(4)} L/min',
          ),
          _ResultRow(
            label: 'Measured at',
            value: '${update.meanInletLpm.toStringAsFixed(2)} L/min inlet',
          ),
          _ResultRow(label: 'Samples used', value: '${update.sampleCount}'),
          const SizedBox(height: Tokens.s3),
          Text(
            'This offset is now saved in the board\'s EEPROM and shifts the whole '
            'tolerance envelope, so the balance check is judged against how this '
            'plumbing actually behaves.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
        ] else
          Text(
            update.reason.isEmpty
                ? 'The run did not collect enough samples above the minimum flow.'
                : update.reason,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
          ),
          Text(
            value,
            style: AppText.mono(
              size: 12,
              weight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

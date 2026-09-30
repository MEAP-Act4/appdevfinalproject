import 'package:flutter/material.dart';

import '../../core/protocol/leak_protocol.dart';
import '../../core/theme/app_theme.dart';

/// Single mapping from a firmware verdict to everything the UI needs to show it.
/// Keeping this in one place is what stops "LEAK" being red in one widget and
/// amber in another.
class StatusVisuals {
  const StatusVisuals({
    required this.color,
    required this.fill,
    required this.label,
    required this.headline,
    required this.detail,
    required this.icon,
    required this.isAlarm,
  });

  final Color color;
  final Color fill;

  /// Short token for pills, e.g. "LEAK".
  final String label;

  /// Sentence for banners, e.g. "Leak detected".
  final String headline;

  /// Explanation shown under the headline.
  final String detail;

  final IconData icon;
  final bool isAlarm;

  static StatusVisuals of(BuildContext context, LeakStatus status) {
    final palette = AppPalette.of(context);
    switch (status) {
      case LeakStatus.idle:
        return StatusVisuals(
          color: palette.idle,
          fill: palette.surfaceRaised,
          label: 'IDLE',
          headline: 'No flow detected',
          detail:
              'Every channel reads zero. Nothing is being measured, so no leak '
              'check runs — this is a healthy standby state, not an error.',
          icon: Icons.pause_circle_outline,
          isAlarm: false,
        );
      case LeakStatus.ok:
        return StatusVisuals(
          color: palette.normal,
          fill: palette.normalBoxFill,
          label: 'NORMAL',
          headline: 'Balance within tolerance',
          detail:
              'Inlet and outlet totals agree inside the calibrated margin of '
              'error for this flow rate.',
          icon: Icons.verified_outlined,
          isAlarm: false,
        );
      case LeakStatus.watch:
        return StatusVisuals(
          color: palette.watch,
          fill: palette.watchBoxFill,
          label: 'WATCH',
          headline: 'Imbalance under observation',
          detail:
              'The balance stepped outside the envelope. The alarm only latches '
              'if it stays there, so transients like a valve slamming shut do '
              'not raise a false leak.',
          icon: Icons.visibility_outlined,
          isAlarm: false,
        );
      case LeakStatus.leak:
        return StatusVisuals(
          color: palette.alert,
          fill: palette.alertBoxFill,
          label: 'LEAK',
          headline: 'Leak detected',
          detail:
              'The inlet has been delivering more than both outlets report for '
              'long enough to rule out sensor noise. Check the run between the '
              'inlet meter and the branch meters.',
          icon: Icons.water_damage_outlined,
          isAlarm: true,
        );
      case LeakStatus.fault:
        return StatusVisuals(
          color: palette.alert,
          fill: palette.alertBoxFill,
          label: 'FAULT',
          headline: 'Sensor fault',
          detail:
              'The readings are physically impossible — water on one side and '
              'nothing on the other. Check the signal wiring and the 5 V feed '
              'to each sensor.',
          icon: Icons.cable_outlined,
          isAlarm: true,
        );
      case LeakStatus.calibrating:
        return StatusVisuals(
          color: palette.accent,
          fill: palette.surfaceRaised,
          label: 'CALIBRATING',
          headline: 'Learning the baseline',
          detail:
              'Hold a steady flow with every outlet open. The board is measuring '
              'this rig\'s natural imbalance.',
          icon: Icons.tune,
          isAlarm: false,
        );
      case LeakStatus.unknown:
        return StatusVisuals(
          color: palette.idle,
          fill: palette.surfaceRaised,
          label: 'NO DATA',
          headline: 'Waiting for the board',
          detail: 'No telemetry decoded yet.',
          icon: Icons.help_outline,
          isAlarm: false,
        );
    }
  }
}

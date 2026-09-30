/// Alerts_Panel — the newest-first list of Alert_Entry rows shown in the
/// Dashboard_View's alerts cell (Requirements 7.1, 7.2, 7.4, 7.5, 7.6, 7.8,
/// 12.7).
///
/// The panel is a *pure read surface* over [AlertsController]. It never queries
/// the store, never mutates alarm logic, and never re-derives a Status — the
/// controller (task 13.5) hands it an already-projected, already-bounded,
/// already-newest-first list. The panel's whole job is to render that list and
/// its two non-list states:
///
///   * an **empty state** ("no alerts yet") when the controller loaded fine but
///     has nothing (Requirement 7.4), and
///   * a **failed state** ("couldn't load") when the one initial query threw
///     ([AlertsController.initialLoadFailed]).
///
/// Both carry a RETRY control wired to [AlertsController.refresh], which is the
/// controller's second and only other database read.
///
/// **Severity treatment (Requirement 7.5).** One row widget, [_AlertRow], keys
/// its appearance off [AlertEntry.severity]:
///
///   * `alarm` (LEAK / FAULT) → the §3 alert treatment: the `alertBoxFill`
///     card fill, the `alert` accent as a 4-wide `leadingAccentBar`, and the
///     summary text in the `alert` colour. This is `#3A1C1C` fill / `#FF453A`
///     text / `#FF453A` border expressed *entirely* through `AppPalette`
///     tokens — this file holds no colour literals (Requirement 1.2).
///   * `warning` (WATCH) → a lighter treatment: the `watch` amber accent bar,
///     no full-bleed fill.
///   * `info` (clears, calibration, config, notes) → a plain row.
///
/// **Shared row treatment (Requirement 8.4).** Every row is a [DataTableRow] —
/// the one primitive shared with the Calibration_Table (task 15.3) — so an
/// Alert_Entry row carries the same `#2C2C2E` bottom-border separator and the
/// same `#252525` hover/focus background as a calibration row. The `alarm`
/// treatment layers *on top of* that shared row: the `alertBoxFill` tint, the
/// 4-wide `alert` leading bar and the `alert`-coloured summary are painted
/// inside the [DataTableRow]'s content, so the shared hover/focus/border and
/// the §3 alarm look coexist. The [DataTableRow] border replaces the old
/// per-row spacer, so rows are separated by one hairline rather than a gap.
///
/// **Status_Affordance (Requirement 7.6).** Every row renders a non-colour
/// marker for its Status — an icon plus the short affordance label from
/// [AlertEntry.affordance] — so Status is never conveyed by colour alone.
///
/// **Locale timestamps (Requirement 12.7).** Each row formats
/// [AlertEntry.timestamp] with an `intl` [DateFormat] built for the active
/// locale, resolved exactly as the Cost_Formatter resolves it: the settings
/// `localeOverride` first, then the platform locale, then English.
///
/// **Independent scroll (Requirement 7.8).** In Expanded the panel is a
/// bounded-height card — a [ConstrainedBox] with a `maxHeight` wrapping an inner
/// [ListView] — so the list scrolls on its own without dragging the Main_Chart
/// with it.
///
/// _Requirements: 7.1, 7.2, 7.4, 7.5, 7.6, 7.8, 8.4, 12.7_
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/locale/app_locale.dart';
import '../../core/protocol/leak_protocol.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/settings/settings_controller.dart';
import '../../state/alerts_controller.dart';
import '../common/data_table_row.dart';
import '../common/surface_card.dart';

/// The Alerts_Panel widget.
///
/// Reads [AlertsController] with [context.watch] so it rebuilds only when the
/// controller notifies — on append or reload, never on the 1 Hz telemetry tick
/// (task 13.5 owns that discipline). When no controller is provided — as in the
/// composition-only Dashboard_View tests, which never stand one up — the panel
/// degrades to its empty state rather than throwing, so the alerts cell always
/// renders something.
class AlertsPanel extends StatelessWidget {
  const AlertsPanel({super.key, this.maxHeight = 420});

  /// The bound applied to the inner scroll view in the card body, so the list
  /// scrolls independently of the Main_Chart (Requirement 7.8).
  final double maxHeight;

  /// The controller from the provider tree, or `null` when none is available.
  ///
  /// [context.watch] throws a `ProviderNotFoundException` when the type is
  /// absent. The Dashboard_View composition tests mount the view without an
  /// [AlertsController], and the alerts cell must still render, so a missing
  /// provider is treated as "not loaded yet" rather than an error.
  static AlertsController? _controllerOf(BuildContext context) {
    try {
      return context.watch<AlertsController>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final controller = _controllerOf(context);

    final entries = controller?.entries ?? const <AlertEntry>[];
    final failed = controller?.initialLoadFailed ?? false;

    final Widget body;
    if (failed) {
      body = _EmptyState(
        icon: Icons.cloud_off_rounded,
        message: "Couldn't load alerts. Check the connection and try again.",
        onRetry: controller?.refresh,
      );
    } else if (entries.isEmpty) {
      body = _EmptyState(
        icon: Icons.notifications_none_rounded,
        message: 'No alerts have been recorded yet.',
        onRetry: controller?.refresh,
      );
    } else {
      body = _AlertList(entries: entries, maxHeight: maxHeight);
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CardLabel(
            'Alerts',
            trailing: Text(
              entries.isEmpty ? '' : '${entries.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: Tokens.s3),
          body,
        ],
      ),
    );
  }
}

/// The bounded, independently-scrolling list of rows (Requirement 7.8).
///
/// The [ConstrainedBox] caps the height so, in the Expanded shared run beside
/// the `span: 8` Main_Chart, the inner [ListView] scrolls on its own instead of
/// growing the whole grid cell. `shrinkWrap` keeps the card only as tall as its
/// content when there are just a few rows, up to the cap.
class _AlertList extends StatelessWidget {
  const _AlertList({required this.entries, required this.maxHeight});

  final List<AlertEntry> entries;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    // The active locale, resolved exactly as the Cost_Formatter does: the
    // settings override wins, then the platform locale, then English. Built
    // once for the whole list rather than per row.
    final settings = context.watch<SettingsController>().settings;
    final locale = resolveLocale(
      override: settings.localeOverride.isEmpty
          ? null
          : settings.localeOverride,
      platformTag: WidgetsBinding.instance.platformDispatcher.locale
          .toLanguageTag(),
    );
    // A date + time pattern that honours the locale's own conventions for both
    // (Requirement 12.7). `yMMMd` and `jm` are locale-shaped skeletons, not a
    // fixed order.
    final format = DateFormat.yMMMd(locale.code).add_jm();

    // The bound is applied with a ConstrainedBox; the inner ListView fills it
    // and scrolls on its own (Requirement 7.8). The list is deliberately *not*
    // `shrinkWrap`ped: a shrink-wrapping list measures each row against an
    // unbounded height, which the alarm rows' stretched leading accent bar
    // cannot lay out. A bounded viewport gives every row a finite height, so
    // the §3 bar stretches cleanly.
    //
    // Rows carry no [ListView.separated] spacer: each row is a [DataTableRow]
    // whose `#2C2C2E` bottom hairline is the separator (Requirement 8.4), so a
    // plain builder keeps the borders from doubling up with a gap.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.builder(
        primary: false,
        itemCount: entries.length,
        itemBuilder: (context, index) => _AlertRow(
          entry: entries[index],
          timestampLabel: format.format(entries[index].timestamp),
        ),
      ),
    );
  }
}

/// One Alert_Entry row. A single widget keyed off [AlertEntry.severity]; the
/// severity decides the card treatment (Requirement 7.5), everything else is
/// the same layout.
class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.entry, required this.timestampLabel});

  final AlertEntry entry;

  /// The locale-formatted timestamp, computed once by the list.
  final String timestampLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    final isAlarm = entry.severity == AlertSeverity.alarm;
    final isWarning = entry.severity == AlertSeverity.warning;

    // The §3 alert treatment for an alarm: alert accent bar + alert-tinted
    // fill + alert-coloured summary. A warning takes the amber watch accent bar
    // only; info is a plain row. Every colour is a palette token.
    final Color? accent = isAlarm
        ? palette.alert
        : isWarning
        ? palette.watch
        : null;
    final Color? fill = isAlarm ? palette.alertBoxFill : null;
    final Color summaryColour = isAlarm ? palette.alert : palette.textPrimary;

    // The row body (channel + timestamp, Status_Affordance, summary), identical
    // for every severity.
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Top line: channel name + timestamp.
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                entry.channelName,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: palette.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Tokens.s2),
            Text(
              timestampLabel,
              style: AppText.mono(
                size: 11,
                weight: FontWeight.w500,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s1),
        // Status + Status_Affordance (Requirement 7.6): a non-colour marker
        // — an icon and the short affordance label — sits beside the Status
        // token so Status is never colour-only.
        _StatusAffordance(entry: entry),
        const SizedBox(height: Tokens.s2),
        // The human-readable summary (Requirement 7.2).
        Text(
          entry.summary,
          style: theme.textTheme.bodySmall?.copyWith(
            color: summaryColour,
          ),
        ),
      ],
    );

    // Option (b): the shared [DataTableRow] is the sole container for *every*
    // row, so all rows carry the same hover/focus `#252525` background and the
    // same `#2C2C2E` bottom hairline (Requirement 8.4). No per-row [SurfaceCard]
    // is used, so nothing double-draws a full card border against the shared
    // hairline separator.
    //
    // The §3 alarm/warning look (Requirement 7.5) is layered *inside* the row's
    // content: the 4-wide `accent` leading bar and the `alertBoxFill` tint are
    // painted by [_AlertSeverityOverlay] within the [DataTableRow] child rather
    // than by a SurfaceCard, and the summary already takes the `alert` colour
    // above. So the shared row treatment and the §3 alarm treatment coexist
    // cleanly with one border per row.
    return DataTableRow(
      // The primitive's default 16/8 inset is replaced by the row's own inset,
      // applied inside the severity overlay so the alert fill spans the full
      // row width behind the padded content.
      padding: EdgeInsets.zero,
      child: _AlertSeverityOverlay(accent: accent, fill: fill, child: body),
    );
  }
}

/// Paints the §3 alert treatment — the 4-wide leading accent bar and the
/// `alertBoxFill` tint — inside a [DataTableRow] (Requirements 7.5, 8.4).
///
/// This replaces the old per-row [SurfaceCard]: the shared [DataTableRow] owns
/// the border and the hover/focus background, so the severity treatment is now
/// just a fill plus a leading bar drawn within the row content. That keeps the
/// row to a single border (the shared hairline) with no card border to
/// double-draw against it.
///
///   * `accent != null` (alarm / warning) → an [IntrinsicHeight] row with a
///     4px `accent` bar stretched down the left edge, beside the padded body;
///   * `fill != null` (alarm only) → the `alertBoxFill` (`#3A1C1C`) tint fills
///     the area behind the padded body;
///   * both `null` (info) → a plain padded body.
///
/// Every colour is an [AppPalette] token; this file holds no colour literals
/// (Requirement 1.2).
class _AlertSeverityOverlay extends StatelessWidget {
  const _AlertSeverityOverlay({
    required this.accent,
    required this.fill,
    required this.child,
  });

  final Color? accent;
  final Color? fill;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The padded body, tinted with the §3 fill for an alarm. The Container also
    // stretches to the row height so the fill spans behind the whole body.
    final Widget padded = Container(
      color: fill,
      padding: const EdgeInsets.all(Tokens.s3),
      child: child,
    );

    if (accent == null) return padded;

    // IntrinsicHeight gives the row a concrete height so the leading accent bar
    // — a `CrossAxisAlignment.stretch` child — can stretch down the full row.
    // Inside a ListView each item is offered an unbounded height, so without
    // this the stretched bar would have no height to stretch to.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(width: 4, color: accent),
          Expanded(child: padded),
        ],
      ),
    );
  }
}

/// The Status token plus its non-colour Status_Affordance (Requirement 7.6).
///
/// Renders a Status-specific icon and the short affordance label from
/// [AlertEntry.affordance] alongside the device Status token, so the state is
/// legible without relying on colour.
class _StatusAffordance extends StatelessWidget {
  const _StatusAffordance({required this.entry});

  final AlertEntry entry;

  /// A Status-specific glyph. Distinct per status so the icon alone carries the
  /// state, satisfying the "not colour-only" rule.
  IconData get _icon {
    switch (entry.status) {
      case LeakStatus.leak:
        return Icons.water_damage_outlined;
      case LeakStatus.fault:
        return Icons.report_gmailerrorred_outlined;
      case LeakStatus.watch:
        return Icons.visibility_outlined;
      case LeakStatus.calibrating:
        return Icons.tune_rounded;
      case LeakStatus.ok:
        return Icons.check_circle_outline_rounded;
      case LeakStatus.idle:
        return Icons.note_outlined;
      case LeakStatus.unknown:
        return Icons.help_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final isAlarm = entry.severity == AlertSeverity.alarm;
    final colour = isAlarm ? palette.alert : palette.textSecondary;

    return Semantics(
      label: 'Status ${entry.status.wire}, ${entry.affordance}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon, size: 14, color: colour),
          const SizedBox(width: Tokens.s1),
          Text(
            entry.status.wire,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colour,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: Tokens.s2),
          // The affordance key as a short label, so the marker is text as well
          // as an icon.
          Text(
            entry.affordance,
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The empty and failed states, both a message plus a RETRY control
/// (Requirements 7.4). The message distinguishes "no alerts yet" from
/// "couldn't load"; the caller supplies the [icon] and [message].
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String message;

  /// [AlertsController.refresh], or `null` when no controller is available (in
  /// which case there is nothing to retry and the button is hidden).
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 18, color: palette.textSecondary),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (onRetry != null) ...<Widget>[
          const SizedBox(height: Tokens.s3),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => onRetry!(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('RETRY'),
            ),
          ),
        ],
      ],
    );
  }
}

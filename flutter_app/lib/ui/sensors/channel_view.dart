/// The shared per-channel projection (task 7.5).
///
/// Requirement 4.6 says the Sensor_Carousel and the Dashboard_View must present
/// the same live reading, the same Status, and the same per-day / per-3-day /
/// per-week averages for a given channel and instant. Requirement 13.2 raises
/// that to a cross-client contract: the same telemetry sequence applied to both
/// the Mobile_Client and the Web_Client must yield the same Status, live
/// readings, averages and Bs_Equivalence per channel.
///
/// `ChannelView.of(monitor, settings, index)` is the single place either
/// requirement is satisfied. It takes the monitor, the settings, and a channel
/// index, and returns a plain data object holding every value a channel
/// presentation needs — the live flow, the live series, the three window stats,
/// the device Status, and the formatted display strings. Both the carousel's
/// `SensorPage` and the future `DashboardView` read through it, so neither
/// re-derives anything locally and the two cannot drift.
///
/// This is the twin of the Web_Client `ChannelView.of` in
/// `react_app/src/core/channelView.ts` (task 7.6). The two clients carry the
/// SAME fields in the SAME derivation ORDER — fixed by design.md's ChannelView
/// description: name, live flow, the live series, the three window stats, the
/// device status, then the formatted strings. Property 7 (task 7.7) and the
/// parity fixtures (Property 30) exercise this function directly, which is only
/// possible because it has no widget, no `BuildContext`, and no platform
/// dependency.
///
/// It derives exactly the values the extracted widgets already compute inline,
/// so wiring a widget through it (Phase 5) is a no-visual-change refactor:
///   live    = monitor.flowFor(index)
///   series  = monitor.liveSeries(index)
///   windows = monitor.aggregates.forSensor(index) — day, 3-day, week
///   status  = monitor.status
///   formatting via settings.formatter.
///
/// **Staying Flutter-free.** This file imports no `package:flutter/material.dart`
/// and needs no `BuildContext`. It reads a [MonitorSource] and the plain
/// [AppSettings] value object. `MonitorController` satisfies [MonitorSource]
/// through its ordinary data getters (`flowFor`, `liveSeries`, `aggregates`,
/// `status`), all callable without a widget, so the carousel and dashboard pass
/// the live controller directly; a parity fixture can pass any object that
/// exposes the same four members. `LeakStatus`, `WindowStats` and the
/// `UnitFormatter` are pure Dart already.
///
/// Nothing here touches the wire protocol, calibration, or alarm logic
/// (Requirement 13.9): it is a presentation-only projection over an already
/// decoded snapshot.
///
/// _Requirements: 4.6, 13.2_
library;

import '../../core/protocol/leak_protocol.dart';
import '../../data/models/aggregates.dart';
import '../../data/settings/app_settings.dart';

/// The narrow, widget-free view of the monitor this projection reads.
///
/// `MonitorController` implements every member here through its plain data
/// getters, so the live controller is passed straight in. Declaring the shape
/// as an interface keeps `channel_view.dart` from importing the controller (and
/// with it Flutter), and lets a parity fixture supply a minimal stand-in.
abstract interface class MonitorSource {
  /// Live flow for one sensor in canonical L/min, or 0 before the first sample.
  double flowFor(int sensorIndex);

  /// Recent live values for one sensor, oldest first.
  List<double> liveSeries(int sensorIndex);

  /// Rolled-up window statistics for every sensor.
  AggregateSnapshot get aggregates;

  /// The device Status for this instant.
  LeakStatus get status;
}

/// The formatted display strings for a channel, one per figure a presentation
/// renders. Every string is produced through the single [UnitFormatter], so a
/// carousel cell and a dashboard cell that both read these agree (Requirement
/// 4.6), and the Web_Client's equivalent strings match (Requirement 13.2).
class ChannelViewText {
  const ChannelViewText({
    required this.liveReading,
    required this.status,
    required this.averages,
    required this.bsEquivalence,
  });

  /// The live flow reading with its unit symbol, e.g. `"12.34 L/min"`.
  final String liveReading;

  /// The device Status token, e.g. `"WATCH"`.
  final String status;

  /// Per-day / per-3-day / per-week average flow, each with its unit symbol,
  /// in that order.
  final List<String> averages;

  /// The Bs_Equivalence for this channel's volume, formatted by the
  /// Cost_Formatter. Task 11.11 adds the cost formatter; until it exists there
  /// is nothing to derive, so this slot is `null`. Property 7 already lists
  /// Bs_Equivalence among the compared figures, so the field is present now to
  /// keep the shape stable for both clients — mirroring the Web `bsEquivalence`.
  final String? bsEquivalence;
}

/// The pure projection of one channel at one instant. Field order is the
/// derivation order shared with the Web side and must not be reordered.
class ChannelView {
  const ChannelView({
    required this.sensorIndex,
    required this.name,
    required this.live,
    required this.series,
    required this.windows,
    required this.status,
    required this.text,
  });

  /// The channel index, 0..2 (Main Inlet, Outlet A, Outlet B).
  final int sensorIndex;

  /// The user-facing channel name from settings.
  final String name;

  /// The live flow in canonical L/min — `flowFor(index)`, or 0 when idle.
  final double live;

  /// The rolling live series for this channel, oldest first.
  final List<double> series;

  /// The three rolling window stats: day, 3-day, week — in that order.
  final List<WindowStats> windows;

  /// The device Status for this instant.
  final LeakStatus status;

  /// The formatted display strings.
  final ChannelViewText text;

  /// Derives the [ChannelView] for [index] from a monitor and settings. Pure:
  /// the same inputs always give the same output, and it mutates nothing it is
  /// handed.
  ///
  /// The derivation runs in the fixed shared order — name, live, series,
  /// windows, status, then formatting — so both clients and both presentations
  /// resolve every figure the same way.
  static ChannelView of(
    MonitorSource monitor,
    AppSettings settings,
    int index,
  ) =>
      channelViewOf(monitor, settings, index);
}

/// Top-level entry point behind [ChannelView.of]. Kept as a free function so a
/// parity fixture can call it directly without the class qualifier, matching
/// the Web `channelViewOf`.
ChannelView channelViewOf(
  MonitorSource monitor,
  AppSettings settings,
  int index,
) {
  final formatter = settings.formatter;

  // 1. Name — the settings label, falling back to the fixed role label.
  final names = settings.sensorNames;
  final name = (index >= 0 && index < names.length)
      ? names[index]
      : SensorRole.byIndex(index).label;

  // 2. Live flow — exactly what SensorPage derives inline.
  final live = monitor.flowFor(index);

  // 3. Live series — the rolling window for this channel, oldest first.
  final series = monitor.liveSeries(index);

  // 4. Window stats — day, 3-day, week, in that order.
  final aggregates = monitor.aggregates.forSensor(index);
  final windows = <WindowStats>[
    aggregates.day,
    aggregates.threeDay,
    aggregates.week,
  ];

  // 5. Status — the device Status for this instant.
  final status = monitor.status;

  // 6. Formatted strings — every figure through the one formatter.
  final text = ChannelViewText(
    liveReading: formatter.flow(live),
    status: status.wire,
    averages: <String>[
      formatter.flow(windows[0].averageLpm),
      formatter.flow(windows[1].averageLpm),
      formatter.flow(windows[2].averageLpm),
    ],
    // Cost_Formatter does not exist yet; task 11.11 fills this. Null until then
    // keeps the shape stable for Property 7.
    bsEquivalence: null,
  );

  return ChannelView(
    sensorIndex: index,
    name: name,
    live: live,
    series: series,
    windows: windows,
    status: status,
    text: text,
  );
}

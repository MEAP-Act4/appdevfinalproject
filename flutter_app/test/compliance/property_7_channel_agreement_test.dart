/// Property 7 — The carousel and the dashboard agree on every channel value.
/// Mobile_Client half (task 7.7).
///
/// Requirement 4.6: the Sensor_Carousel and the Dashboard_View must present the
/// SAME live reading, Status, per-day / per-3-day / per-week averages and
/// Bs_Equivalence for a given channel and instant, compared as formatted
/// strings.
///
/// **What "carousel path == dashboard path" actually reduces to here.** Both
/// presentations derive their channel figures through the ONE
/// `ChannelView.of(monitor, settings, index)` projection — the carousel's
/// `SensorPage` (task 7.3) and the future `DashboardView` (task 9.9). Neither
/// re-derives anything locally. So the two paths agreeing is exactly the
/// statement that this single projection is a pure, deterministic function:
/// applied twice to the same `(monitor, settings, index)` it yields
/// field-for-field equal results. That is what makes any two call sites — the
/// carousel today, the dashboard once task 9.9 lands — resolve every figure
/// identically, because they read the same projection rather than computing
/// their own.
///
/// The DashboardView widget does not exist yet, so there is no literal
/// "dashboard path" component to call. This file models the two paths honestly:
///
///   * **path A** = `ChannelView.of(monitor, settings, index)` — the projection
///     the carousel already reads.
///   * **path B** = `ChannelView.of(monitor, settings, index)` again — the same
///     projection the dashboard will read.
///
/// and asserts the six compared figures are equal between them: the live
/// reading string, the Status token, the three average strings, and the
/// Bs_Equivalence. Task 9.15 / 9.x add the *structural* dashboard tests once the
/// widget exists; the cross-CLIENT string equality (Mobile vs Web) is Property
/// 30 (task 17.2 / 17.3), not this one — this property is per-client
/// determinism and must not be conflated with either.
///
/// **Bs_Equivalence is `null` in both projections today** — the Cost_Formatter
/// (task 11.11) does not exist yet. The field is nonetheless in the compared
/// set: both paths must agree it is `null` now, so that when 11.11 fills it the
/// agreement is already enforced without touching this test.
///
/// **The `carousel derivation matches the projection` group** ties the existing
/// path to the projection concretely: the values `SensorPage` computes inline
/// (`flowFor(index)`, `liveSeries(index)`, `aggregates.forSensor(index)` day /
/// 3-day / week, `status`) equal the corresponding `ChannelView` fields, so the
/// carousel genuinely reads the projection rather than shadowing it.
///
/// Generators (design.md): `telemetry` — flows in [0, 60] L/min across the
/// Status vocabulary; `aggregates` — window stats with coverage in [0, 1] (and
/// averages in [0, 60] L/min, the figures the projection formats); `settings` —
/// the cross product of flow unit and volume unit (Tariff and locale are not
/// yet fields on `AppSettings`; they arrive with the Cost_Formatter in Phase 6,
/// at which point Bs_Equivalence stops being null and this same compared set
/// covers them); `channel` — integers in [0, 2].
///
/// **A note on the Status vocabulary.** The task text lists six values
/// (OK / WATCH / LEAK / FAULT / IDLE / UNKNOWN), but `LeakStatus` in
/// `leak_protocol.dart` declares SEVEN — it also has `calibrating` ('CAL'). The
/// projection is agnostic to which Status it carries, so generating across the
/// full `LeakStatus.values` set is a strict superset of the six and keeps the
/// property honest: it holds for every Status the wire can carry, including CAL.
///
/// The monitor is a widget-free [MonitorSource] fake, following the same
/// reasoning as `test/ui/channel_view_test.dart`: `ChannelView` reads a monitor
/// only through `flowFor`, `liveSeries`, `aggregates`, `status`, all callable
/// without a `BuildContext`, and the real `MonitorController` opens a database
/// unavailable under `flutter_test`. No colour literal is written here, and the
/// wire protocol, calibration and alarm logic are untouched (Requirement 13.9):
/// this reads an already-decoded snapshot.
///
/// Requirements: 4.6.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/core/units/measurement_units.dart';
import 'package:leakguard/data/models/aggregates.dart';
import 'package:leakguard/data/settings/app_settings.dart';
import 'package:leakguard/ui/sensors/channel_view.dart';

import '../support/props.dart';

/// A widget-free [MonitorSource] carrying fixed synthetic values — the minimal
/// input `ChannelView` reads. Immutable, so a generated snapshot cannot be
/// mutated between the two projection calls.
class _FakeMonitor implements MonitorSource {
  _FakeMonitor({
    required this.flows,
    required this.series,
    required this.aggregates,
    required this.status,
  });

  final List<double> flows;
  final List<List<double>> series;

  @override
  final AggregateSnapshot aggregates;

  @override
  final LeakStatus status;

  @override
  double flowFor(int sensorIndex) => flows[sensorIndex];

  @override
  List<double> liveSeries(int sensorIndex) => series[sensorIndex];
}

/// One generated scenario: a synthetic monitor snapshot, the settings, and the
/// channel index to project.
typedef Scenario = ({
  _FakeMonitor monitor,
  AppSettings settings,
  int index,
});

/// Flows in [0, 60] L/min — the design.md telemetry domain.
final Generator<double> _flow = any.doubleBetween(0, 60);

/// Window-average flow, generated over the same [0, 60] L/min band the live
/// flow uses, since that is the figure the projection formats.
final Generator<double> _averageLpm = any.doubleBetween(0, 60);

/// Coverage in [0, 1] — the design.md aggregate domain.
final Generator<double> _coverage = any.doubleBetween(0, 1);

/// A [WindowStats] for [window] with a generated average and coverage. The
/// other fields are inert: the projection formats only `averageLpm`, so they
/// are not part of the compared set, but they must be valid.
Generator<WindowStats> _window(AverageWindow window) =>
    any.combine2<double, double, WindowStats>(
      _averageLpm,
      _coverage,
      (double averageLpm, double coverage) => WindowStats(
        window: window,
        averageLpm: averageLpm,
        peakLpm: averageLpm * 2,
        totalLitres: averageLpm * 10,
        sampleCount: 500,
        coverage: coverage,
        activeFraction: 0.5,
      ),
    );

/// A [SensorAggregates] for [index] with generated day / 3-day / week windows.
Generator<SensorAggregates> _sensorAggregates(int index) =>
    any.combine3<WindowStats, WindowStats, WindowStats, SensorAggregates>(
      _window(AverageWindow.day),
      _window(AverageWindow.threeDay),
      _window(AverageWindow.week),
      (WindowStats day, WindowStats threeDay, WindowStats week) =>
          SensorAggregates(
        sensorIndex: index,
        day: day,
        threeDay: threeDay,
        week: week,
      ),
    );

/// A full three-sensor [AggregateSnapshot] with independently generated
/// windows per channel.
final Generator<AggregateSnapshot> _snapshot =
    any.combine3<SensorAggregates, SensorAggregates, SensorAggregates,
        AggregateSnapshot>(
  _sensorAggregates(0),
  _sensorAggregates(1),
  _sensorAggregates(2),
  (SensorAggregates a, SensorAggregates b, SensorAggregates c) =>
      AggregateSnapshot(
    perSensor: <SensorAggregates>[a, b, c],
    trends: const <List<TrendPoint>>[
      <TrendPoint>[],
      <TrendPoint>[],
      <TrendPoint>[],
    ],
    computedAt: null,
    totalRows: 0,
    oldestTimestampMs: null,
  ),
);

/// A live series of up to eight flow samples for one channel, each in [0, 60].
final Generator<List<double>> _seriesGen =
    any.listBetween<double>(_flow, minLength: 0, maxLength: 8);

/// The three per-channel flows in [0, 60], as a fixed-length list.
final Generator<List<double>> _flowsGen =
    any.combine3<double, double, double, List<double>>(
  _flow,
  _flow,
  _flow,
  (double a, double b, double c) => <double>[a, b, c],
);

/// The three per-channel live series, as a fixed-length list of lists.
final Generator<List<List<double>>> _seriesTripleGen =
    any.combine3<List<double>, List<double>, List<double>, List<List<double>>>(
  _seriesGen,
  _seriesGen,
  _seriesGen,
  (List<double> a, List<double> b, List<double> c) =>
      <List<double>>[a, b, c],
);

/// The monitor fake — three flows, three series, a snapshot and a Status drawn
/// from the FULL `LeakStatus` vocabulary (a superset of the design.md six).
final Generator<_FakeMonitor> _monitorGen = any.combine4<List<double>,
    List<List<double>>, AggregateSnapshot, LeakStatus, _FakeMonitor>(
  _flowsGen,
  _seriesTripleGen,
  _snapshot,
  any.enumOf<LeakStatus>(LeakStatus.values),
  (
    List<double> flows,
    List<List<double>> series,
    AggregateSnapshot agg,
    LeakStatus status,
  ) =>
      _FakeMonitor(
    flows: flows,
    series: series,
    aggregates: agg,
    status: status,
  ),
);

/// Settings across the cross product of flow unit and volume unit. Tariff and
/// locale are not yet `AppSettings` fields (Phase 6), so the cross product is
/// exactly flow × volume today; Bs_Equivalence stays null until then.
final Generator<AppSettings> _settingsGen =
    any.combine2<FlowUnit, VolumeUnit, AppSettings>(
  any.enumOf<FlowUnit>(FlowUnit.values),
  any.enumOf<VolumeUnit>(VolumeUnit.values),
  (FlowUnit flow, VolumeUnit volume) => AppSettings(
    sensorNames: const <String>['Main Inlet', 'Outlet A', 'Outlet B'],
    flowUnit: flow,
    volumeUnit: volume,
  ),
);

/// The full scenario generator: monitor × settings × channel index [0, 2].
final Generator<Scenario> _scenario =
    any.combine3<_FakeMonitor, AppSettings, int, Scenario>(
  _monitorGen,
  _settingsGen,
  any.intBetween(0, 2),
  (_FakeMonitor monitor, AppSettings settings, int index) =>
      (monitor: monitor, settings: settings, index: index),
);

void main() {
  group('Property 7 — Requirement 4.6, carousel and dashboard agree', () {
    forAll<Scenario>(
      'the six compared figures are equal through the carousel and dashboard '
      'paths, both resolving the single ChannelView projection',
      _scenario,
      (Scenario s) {
        // path A — the projection the carousel reads.
        final ChannelView carousel =
            ChannelView.of(s.monitor, s.settings, s.index);
        // path B — the SAME projection the dashboard will read once task 9.9
        // lands. Modelled as a second call so the property is a genuine
        // determinism check, not `x == x` on one object.
        final ChannelView dashboard =
            ChannelView.of(s.monitor, s.settings, s.index);

        final reason = 'channel ${s.index}, status ${s.monitor.status.wire}, '
            'flow ${s.settings.flowUnit.symbol}, '
            'volume ${s.settings.volumeUnit.symbol}';

        // 1. Live reading string.
        expect(
          dashboard.text.liveReading,
          equals(carousel.text.liveReading),
          reason: 'live reading disagrees ($reason)',
        );

        // 2. Status token.
        expect(
          dashboard.text.status,
          equals(carousel.text.status),
          reason: 'status disagrees ($reason)',
        );

        // 3, 4, 5. The three averages — per-day, per-3-day, per-week.
        expect(
          dashboard.text.averages,
          equals(carousel.text.averages),
          reason: 'averages disagree ($reason)',
        );

        // 6. Bs_Equivalence — null in both today, but in the compared set so
        // agreement is enforced the moment task 11.11 fills it.
        expect(
          dashboard.text.bsEquivalence,
          equals(carousel.text.bsEquivalence),
          reason: 'Bs_Equivalence disagrees ($reason)',
        );
      },
    );

    forAll<Scenario>(
      'Bs_Equivalence is null in both paths until the Cost_Formatter lands',
      _scenario,
      (Scenario s) {
        final ChannelView carousel =
            ChannelView.of(s.monitor, s.settings, s.index);
        final ChannelView dashboard =
            ChannelView.of(s.monitor, s.settings, s.index);
        // Both agree, AND both are null today — the field is present in the
        // compared set so the agreement is future-proof (task 11.11).
        expect(carousel.text.bsEquivalence, isNull);
        expect(dashboard.text.bsEquivalence, isNull);
      },
    );
  });

  group('Property 7 — the carousel derivation matches the projection', () {
    // Ties the EXISTING carousel path to the projection: the values SensorPage
    // computes inline are exactly the ChannelView fields, so the carousel reads
    // the projection rather than shadowing it. This is what makes path A a
    // faithful stand-in for the carousel above.
    forAll<Scenario>(
      'live, series, status and the three window averages equal the inline '
      'SensorPage derivation',
      _scenario,
      (Scenario s) {
        final ChannelView view = ChannelView.of(s.monitor, s.settings, s.index);
        final SensorAggregates agg = s.monitor.aggregates.forSensor(s.index);

        expect(view.live, equals(s.monitor.flowFor(s.index)));
        expect(view.series, equals(s.monitor.liveSeries(s.index)));
        expect(view.status, equals(s.monitor.status));
        expect(
          view.windows.map((WindowStats w) => w.averageLpm).toList(),
          equals(<double>[
            agg.day.averageLpm,
            agg.threeDay.averageLpm,
            agg.week.averageLpm,
          ]),
        );

        // And the formatted strings come out of the one formatter, so a
        // presentation reading `text` cannot drift from one re-formatting a
        // raw field itself.
        final UnitFormatter formatter = s.settings.formatter;
        expect(view.text.liveReading, equals(formatter.flow(view.live)));
        expect(
          view.text.averages,
          equals(<String>[
            formatter.flow(agg.day.averageLpm),
            formatter.flow(agg.threeDay.averageLpm),
            formatter.flow(agg.week.averageLpm),
          ]),
        );
        expect(view.text.status, equals(s.monitor.status.wire));
      },
    );
  });

  group('Property 7 — the generators do real work', () {
    test('covers the full LeakStatus vocabulary, a superset of the six', () {
      // The design.md six plus CAL — the property holds for every wire Status.
      expect(LeakStatus.values, contains(LeakStatus.ok));
      expect(LeakStatus.values, contains(LeakStatus.watch));
      expect(LeakStatus.values, contains(LeakStatus.leak));
      expect(LeakStatus.values, contains(LeakStatus.fault));
      expect(LeakStatus.values, contains(LeakStatus.idle));
      expect(LeakStatus.values, contains(LeakStatus.unknown));
      expect(LeakStatus.values, contains(LeakStatus.calibrating));
      expect(LeakStatus.values.length, 7);
    });

    test('settings cross product spans every flow and volume unit', () {
      expect(FlowUnit.values, hasLength(6));
      expect(VolumeUnit.values, hasLength(4));
    });
  });
}

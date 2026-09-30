import 'package:flutter/foundation.dart';

import '../core/protocol/leak_protocol.dart';
import '../data/db/app_database.dart';
import '../data/models/stored_reading.dart';
import '../data/settings/settings_controller.dart';
import 'monitor_controller.dart';

/// How loud an [AlertEntry] is. The controller carries severity as *data*; the
/// mapping of a severity to a colour or a §3 alert treatment belongs to the
/// panel and the token layer (task 13.7), never here.
enum AlertSeverity {
  /// A confirmed LEAK or FAULT — the §3 alert-box treatment.
  alarm,

  /// A WATCH — an advisory that has not latched into an alarm.
  warning,

  /// Everything else worth remembering: clears, calibration, config, notes.
  info,
}

/// One projected row for the Alerts_Panel — a pure, immutable read model over a
/// single [LeakEvent]. Carries only presentation-neutral data: the panel turns
/// [severity] and [affordance] into colours and glyphs, this class never does.
///
/// Requirements 7.1, 7.2, 7.4, 7.9.
@immutable
class AlertEntry {
  const AlertEntry({
    required this.timestampMs,
    required this.kind,
    required this.status,
    required this.channelName,
    required this.summary,
    required this.severity,
    required this.affordance,
  });

  /// UTC-epoch milliseconds, matching the stored event. The panel formats it
  /// per the active locale (Requirement 12.7).
  final int timestampMs;

  final EventKind kind;

  /// The device-vocabulary Status this entry represents. Derived from [kind];
  /// the alarm logic and the device-reported Status are never altered
  /// (Requirement 7.9).
  final LeakStatus status;

  /// The affected channel name, resolved from settings.
  final String channelName;

  /// Human-readable summary — the event's own message (Requirement 7.2).
  final String summary;

  final AlertSeverity severity;

  /// A non-colour marker distinct per [status], so Status is never conveyed by
  /// colour alone (Status_Affordance, Requirement 7.6 / 11.5). It is a short
  /// stable key — the panel maps it to a glyph or label.
  final String affordance;

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true).toLocal();

  /// The event kinds worth surfacing in the Alerts_Panel. Connection noise
  /// (`CONNECTED` / `DISCONNECTED`) and the generic `WATCH` marker are excluded
  /// — they stay in the Diagnostics_Sheet event log (Requirement 13.10).
  static const Set<EventKind> alertWorthyKinds = <EventKind>{
    EventKind.leakRaised,
    EventKind.leakCleared,
    EventKind.faultRaised,
    EventKind.faultCleared,
    EventKind.watchRaised,
    EventKind.calibration,
    EventKind.configChanged,
    EventKind.note,
  };

  /// True when [kind] belongs in the panel. `note` is treated as the catch-all
  /// for any unrecognised wire kind, so it is always kept.
  static bool isAlertWorthy(EventKind kind) => alertWorthyKinds.contains(kind);

  /// Projects one stored event into an [AlertEntry], or `null` when the event
  /// is filtered out (connection noise or the bare `WATCH` marker).
  ///
  /// [sensorNames] is the three-channel label list from settings; index 0 is
  /// the inlet. Balance-derived entries (leak / fault / watch, which carry a
  /// balance and threshold) are named with the inlet channel; an event that
  /// carries a specific channel would use that channel's name.
  static AlertEntry? project(
    LeakEvent event, {
    required List<String> sensorNames,
  }) {
    if (!isAlertWorthy(event.kind)) return null;

    final status = _statusFor(event.kind);
    final severity = _severityFor(event.kind);
    final summary = _summaryFor(event);
    final channelName = _channelNameFor(event, sensorNames);

    return AlertEntry(
      timestampMs: event.timestampMs,
      kind: event.kind,
      status: status,
      channelName: channelName,
      summary: summary,
      severity: severity,
      affordance: _affordanceFor(status),
    );
  }

  static LeakStatus _statusFor(EventKind kind) {
    switch (kind) {
      case EventKind.leakRaised:
        return LeakStatus.leak;
      case EventKind.faultRaised:
        return LeakStatus.fault;
      case EventKind.watchRaised:
        return LeakStatus.watch;
      case EventKind.calibration:
        return LeakStatus.calibrating;
      case EventKind.leakCleared:
      case EventKind.faultCleared:
        return LeakStatus.ok;
      case EventKind.configChanged:
      case EventKind.note:
        return LeakStatus.idle;
      case EventKind.connected:
      case EventKind.disconnected:
      case EventKind.watch:
        // Filtered out before reaching here; be defensive rather than throw.
        return LeakStatus.idle;
    }
  }

  static AlertSeverity _severityFor(EventKind kind) {
    switch (kind) {
      case EventKind.leakRaised:
      case EventKind.faultRaised:
        return AlertSeverity.alarm;
      case EventKind.watchRaised:
        return AlertSeverity.warning;
      case EventKind.leakCleared:
      case EventKind.faultCleared:
      case EventKind.calibration:
      case EventKind.configChanged:
      case EventKind.note:
        return AlertSeverity.info;
      case EventKind.connected:
      case EventKind.disconnected:
      case EventKind.watch:
        return AlertSeverity.info;
    }
  }

  /// The summary is the event's own message. An unrecognised kind cannot arise
  /// through [EventKind.fromWire] (it folds anything unknown to `note`), but if
  /// a `note` ever reaches us with an empty message we surface the raw kind
  /// token rather than showing a blank row — nothing is dropped.
  static String _summaryFor(LeakEvent event) {
    final message = event.message.trim();
    if (message.isNotEmpty) return message;
    return event.kind.wire;
  }

  /// Balance-derived transitions (leak / fault / watch) are about the inlet
  /// balance, so they are named with the inlet channel. Everything else uses
  /// the inlet name too, since these events do not carry a specific channel.
  static String _channelNameFor(LeakEvent event, List<String> sensorNames) {
    const fallbackInlet = 'Main Inlet';
    if (sensorNames.isEmpty) return fallbackInlet;
    final name = sensorNames.first.trim();
    return name.isEmpty ? fallbackInlet : name;
  }

  /// A stable, distinct-per-status text key. Not a colour and not a glyph — the
  /// panel resolves it to an icon or label. Distinctness is what Property 18
  /// asserts.
  static String _affordanceFor(LeakStatus status) {
    switch (status) {
      case LeakStatus.leak:
        return 'leak';
      case LeakStatus.fault:
        return 'fault';
      case LeakStatus.watch:
        return 'watch';
      case LeakStatus.calibrating:
        return 'calibrating';
      case LeakStatus.ok:
        return 'cleared';
      case LeakStatus.idle:
        return 'note';
      case LeakStatus.unknown:
        return 'unknown';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AlertEntry &&
      other.timestampMs == timestampMs &&
      other.kind == kind &&
      other.status == status &&
      other.channelName == channelName &&
      other.summary == summary &&
      other.severity == severity &&
      other.affordance == affordance;

  @override
  int get hashCode => Object.hash(
        timestampMs,
        kind,
        status,
        channelName,
        summary,
        severity,
        affordance,
      );
}

/// The Alerts_Panel's data source — a projection over the existing event log
/// with its **own** notifier, deliberately separate from [MonitorController].
///
/// [MonitorController] fires at 1 Hz with every telemetry sample; if the alerts
/// list rode on that notifier the whole panel would re-render each second. This
/// controller instead:
///
///   * reads the database exactly twice per session — once on [initialise] and
///     once per [refresh] — never on telemetry; and
///   * receives each newly-logged event through an append hook wired to
///     [MonitorController.onEventLogged], prepending it in the same frame
///     without re-querying.
///
/// It therefore notifies ONLY on append or reload. Requirements 7.1–7.4, 7.9.
class AlertsController extends ChangeNotifier {
  AlertsController({
    required AppDatabase database,
    required SettingsController settings,
  }) : this.withLoader(
          loadEvents: () => database.events(limit: maxEntries),
          settings: settings,
        );

  /// Test seam: build a controller over an arbitrary event loader without a
  /// live [AppDatabase]. The projection and bounding are identical; only the
  /// source of the batch differs.
  @visibleForTesting
  AlertsController.withLoader({
    required this._loadEvents,
    required this._settings,
  });

  /// The single read against the store, capped at [maxEntries]. Invoked exactly
  /// once per [initialise] and once per [refresh] — the only two reads a
  /// session performs.
  final Future<List<LeakEvent>> Function() _loadEvents;
  final SettingsController _settings;

  /// Newest-first, bounded at [maxEntries]. Oldest evicted on overflow.
  static const int maxEntries = 200;

  final List<AlertEntry> _entries = <AlertEntry>[];
  List<AlertEntry>? _view;

  bool _initialLoadFailed = false;
  bool _loaded = false;

  MonitorController? _attachedMonitor;

  /// The projected rows, newest-first, as an unmodifiable view.
  List<AlertEntry> get entries =>
      _view ??= List<AlertEntry>.unmodifiable(_entries);

  /// True when the one-and-only initial query threw. The panel shows a retry
  /// state; [refresh] clears it on success.
  bool get initialLoadFailed => _initialLoadFailed;

  /// True once [initialise] (or a [refresh]) has completed, success or failure.
  bool get isLoaded => _loaded;

  bool get isEmpty => _entries.isEmpty;

  List<String> get _sensorNames => _settings.settings.sensorNames;

  /// Registers the append hook on [monitor] so every newly-logged event is
  /// prepended in the same frame as the transition, without a database read.
  /// [MonitorController] never imports this class — the wiring is one-way.
  void attachTo(MonitorController monitor) {
    _attachedMonitor = monitor;
    monitor.onEventLogged = _onEventLogged;
  }

  /// Removes the append hook if it is still ours.
  void detach() {
    final monitor = _attachedMonitor;
    if (monitor != null && identical(monitor.onEventLogged, _onEventLogged)) {
      monitor.onEventLogged = null;
    }
    _attachedMonitor = null;
  }

  /// The first of the two per-session database reads.
  Future<void> initialise() => _load();

  /// The second — a manual refresh. Idempotent to call more than once, but each
  /// call is one query.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    try {
      final events = await _loadEvents();
      _replaceFrom(events);
      _initialLoadFailed = false;
    } on Object {
      _initialLoadFailed = true;
    } finally {
      _loaded = true;
      _invalidateView();
      notifyListeners();
    }
  }

  /// Rebuilds the in-memory list from a freshly-queried batch. The database
  /// returns `ts DESC` (newest-first), but the panel's newest-first ordering is
  /// the controller's own contract (Property 13): it must hold for any input
  /// order, not only a pre-sorted query. So the projection filters, the entries
  /// are sorted newest-first by timestamp, and only then is the bound applied —
  /// keeping the [maxEntries] newest rows rather than the first [maxEntries]
  /// the batch happened to arrive in. The device-reported Status and the alarm
  /// interpretation are never touched (Requirement 7.9); this reorders rows
  /// only.
  void _replaceFrom(List<LeakEvent> events) {
    final names = _sensorNames;
    _entries.clear();
    for (final event in events) {
      final entry = AlertEntry.project(event, sensorNames: names);
      if (entry == null) continue;
      _entries.add(entry);
    }
    // Newest-first by timestamp. Rows with equal timestamps keep whatever
    // adjacent order the sort leaves them in — Property 13 only requires the
    // pair to be non-increasing, and equal timestamps satisfy `ts[i] >= ts[i+1]`
    // either way.
    _entries.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
  }

  /// Drives the append hook directly. Exposed so the append path can be tested
  /// without standing up a full [MonitorController].
  @visibleForTesting
  void debugAppend(LeakEvent event) => _onEventLogged(event);

  /// The append hook. Projects a single event; if it survives the alert-worthy
  /// filter, prepends it (newest-first), evicts the oldest past [maxEntries],
  /// and notifies. A filtered-out event does nothing — no notify.
  void _onEventLogged(LeakEvent event) {
    final entry = AlertEntry.project(event, sensorNames: _sensorNames);
    if (entry == null) return;
    _entries.insert(0, entry);
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    _invalidateView();
    notifyListeners();
  }

  void _invalidateView() => _view = null;

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}

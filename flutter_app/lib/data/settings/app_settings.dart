import 'package:flutter/foundation.dart';

import '../../core/locale/app_locale.dart';
import '../../core/money/cost_formatter.dart';
import '../../core/units/measurement_units.dart';

/// The appearance the user has chosen. Replaces the former `ThemeMode` field.
///
/// [dark] is the default because the dashboard is designed dark-first.
/// [highContrastDark] stays inside the WattVision §2 dark family and only
/// raises text and border contrast. [light] is supported but demoted: light
/// backgrounds sit outside the design guidance for prolonged data reading.
/// [system] follows the platform brightness.
///
/// Declaration order is the persisted order — the index is written to
/// SharedPreferences under the `appearance` key, so values must only ever be
/// appended. The legacy `themeMode` indices are deliberately different and are
/// translated once on load; see `SettingsController`.
enum Appearance {
  dark,
  highContrastDark,
  light,
  system,
}

/// How long readings are kept before the pruner removes them.
enum RetentionPolicy {
  week('7 days', Duration(days: 7)),
  month('30 days', Duration(days: 30)),
  quarter('90 days', Duration(days: 90)),
  year('1 year', Duration(days: 365)),
  forever('Keep everything', null);

  const RetentionPolicy(this.label, this.duration);
  final String label;
  final Duration? duration;
}

/// How often a sample is written to the database. The device always streams at
/// 1 Hz; this only controls persistence, and the written row records how many
/// samples it represents so averages stay correct at any setting.
enum LoggingInterval {
  everySecond('Every second', Duration(seconds: 1), '≈86k rows/day'),
  fiveSeconds('Every 5 seconds', Duration(seconds: 5), '≈17k rows/day'),
  tenSeconds('Every 10 seconds', Duration(seconds: 10), '≈8.6k rows/day'),
  thirtySeconds('Every 30 seconds', Duration(seconds: 30), '≈2.9k rows/day'),
  oneMinute('Every minute', Duration(minutes: 1), '≈1.4k rows/day');

  const LoggingInterval(this.label, this.duration, this.footprint);
  final String label;
  final Duration duration;
  final String footprint;
}

/// Everything the user can configure. Immutable; the controller swaps whole
/// instances so `notifyListeners` fires once per change.
@immutable
class AppSettings {
  const AppSettings({
    this.appearance = Appearance.dark,
    this.reduceMotion = false,
    this.flowUnit = FlowUnit.litresPerMinute,
    this.volumeUnit = VolumeUnit.litres,
    this.followFlowUnitForVolume = true,
    this.alertOnLeak = true,
    this.alertOnWatch = false,
    this.alertOnFault = true,
    this.hapticsEnabled = true,
    this.audibleAlarm = false,
    this.autoReconnect = true,
    this.rememberedDeviceId = '',
    this.rememberedDeviceName = '',
    this.sensorNames = const <String>['Main Inlet', 'Outlet A', 'Outlet B'],
    this.loggingInterval = LoggingInterval.tenSeconds,
    this.retention = RetentionPolicy.quarter,
    this.autoPrune = true,
    this.showEnvelopeDetails = true,
    this.requireConnectionToBrowse = true,
    this.onboardingSeen = false,
    this.tariffBsPerCubicMetre = 5.0,
    this.tariffConfiguredByUser = false,
    this.showCostEquivalence = true,
    this.localeOverride = '',
  });

  final Appearance appearance;

  /// Honours the OS "reduce motion" intent. When on, long transitions collapse to
  /// cross-fades and the ambient pulses stop.
  final bool reduceMotion;

  final FlowUnit flowUnit;
  final VolumeUnit volumeUnit;

  /// When true, picking a flow unit also picks the matching volume unit.
  final bool followFlowUnitForVolume;

  final bool alertOnLeak;
  final bool alertOnWatch;
  final bool alertOnFault;
  final bool hapticsEnabled;
  final bool audibleAlarm;

  final bool autoReconnect;
  final String rememberedDeviceId;
  final String rememberedDeviceName;

  /// User-editable labels for the three channels.
  final List<String> sensorNames;

  final LoggingInterval loggingInterval;
  final RetentionPolicy retention;
  final bool autoPrune;

  /// Shows the tolerance-envelope numbers on the sensor cards.
  final bool showEnvelopeDetails;

  /// The connection gate. Off puts the app in read-only history mode without a
  /// live link — useful on a second phone.
  final bool requireConnectionToBrowse;

  final bool onboardingSeen;

  /// The water price in Bolivianos per cubic metre, used only for display.
  /// Persisted at up to 4 decimal places; never written to the reading
  /// database. Defaults to [Tariff.defaultValue].
  final double tariffBsPerCubicMetre;

  /// Whether the user has committed a Tariff value. False means the default is
  /// still in use, which drives the "default tariff in use" hint on the
  /// Bs_Equivalence.
  final bool tariffConfiguredByUser;

  /// Master switch for the Bs_Equivalence display. When off, volume figures are
  /// shown without a monetary equivalent.
  final bool showCostEquivalence;

  /// An explicit locale override for number, currency and date formatting.
  /// Empty means "no override" — resolution falls back to the platform locale.
  final String localeOverride;

  UnitFormatter get formatter =>
      UnitFormatter(flowUnit: flowUnit, volumeUnit: volumeUnit);

  /// Builds the [CostFormatter] for the current Tariff, cost-display switch and
  /// resolved locale — the single source every `Bs_Equivalence` call site uses.
  ///
  /// [platformTag] is the platform locale as a BCP 47 tag (from
  /// `WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag()`),
  /// passed in rather than read here so the model stays platform-free and
  /// testable. Locale resolution follows the same override → platform → English
  /// chain the Settings tab uses (Requirement 12.6). [showCostEquivalence]
  /// drives `enabled` (Req 5.8) and `!tariffConfiguredByUser` drives the
  /// default-tariff indication (Req 6.8).
  CostFormatter costFormatter({String? platformTag}) {
    final locale = resolveLocale(
      override: localeOverride.isEmpty ? null : localeOverride,
      platformTag: platformTag,
    );
    return CostFormatter(
      tariffBsPerCubicMetre: tariffBsPerCubicMetre,
      locale: locale.code,
      enabled: showCostEquivalence,
      isDefaultTariff: !tariffConfiguredByUser,
    );
  }

  bool get hasRememberedDevice => rememberedDeviceId.isNotEmpty;

  AppSettings copyWith({
    Appearance? appearance,
    bool? reduceMotion,
    FlowUnit? flowUnit,
    VolumeUnit? volumeUnit,
    bool? followFlowUnitForVolume,
    bool? alertOnLeak,
    bool? alertOnWatch,
    bool? alertOnFault,
    bool? hapticsEnabled,
    bool? audibleAlarm,
    bool? autoReconnect,
    String? rememberedDeviceId,
    String? rememberedDeviceName,
    List<String>? sensorNames,
    LoggingInterval? loggingInterval,
    RetentionPolicy? retention,
    bool? autoPrune,
    bool? showEnvelopeDetails,
    bool? requireConnectionToBrowse,
    bool? onboardingSeen,
    double? tariffBsPerCubicMetre,
    bool? tariffConfiguredByUser,
    bool? showCostEquivalence,
    String? localeOverride,
  }) {
    return AppSettings(
      appearance: appearance ?? this.appearance,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      flowUnit: flowUnit ?? this.flowUnit,
      volumeUnit: volumeUnit ?? this.volumeUnit,
      followFlowUnitForVolume:
          followFlowUnitForVolume ?? this.followFlowUnitForVolume,
      alertOnLeak: alertOnLeak ?? this.alertOnLeak,
      alertOnWatch: alertOnWatch ?? this.alertOnWatch,
      alertOnFault: alertOnFault ?? this.alertOnFault,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      audibleAlarm: audibleAlarm ?? this.audibleAlarm,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      rememberedDeviceId: rememberedDeviceId ?? this.rememberedDeviceId,
      rememberedDeviceName: rememberedDeviceName ?? this.rememberedDeviceName,
      sensorNames: sensorNames ?? this.sensorNames,
      loggingInterval: loggingInterval ?? this.loggingInterval,
      retention: retention ?? this.retention,
      autoPrune: autoPrune ?? this.autoPrune,
      showEnvelopeDetails: showEnvelopeDetails ?? this.showEnvelopeDetails,
      requireConnectionToBrowse:
          requireConnectionToBrowse ?? this.requireConnectionToBrowse,
      onboardingSeen: onboardingSeen ?? this.onboardingSeen,
      tariffBsPerCubicMetre:
          tariffBsPerCubicMetre ?? this.tariffBsPerCubicMetre,
      tariffConfiguredByUser:
          tariffConfiguredByUser ?? this.tariffConfiguredByUser,
      showCostEquivalence: showCostEquivalence ?? this.showCostEquivalence,
      localeOverride: localeOverride ?? this.localeOverride,
    );
  }
}

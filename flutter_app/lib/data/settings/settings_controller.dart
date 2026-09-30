import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/money/tariff.dart';
import '../../core/units/measurement_units.dart';
import 'app_settings.dart';

/// Loads, exposes and persists [AppSettings].
///
/// Writes are fire-and-forget against SharedPreferences but the in-memory value
/// updates synchronously, so the UI never waits on disk.
class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs, this._settings);

  final SharedPreferences _prefs;
  AppSettings _settings;

  AppSettings get settings => _settings;

  static const String _kAppearance = 'appearance';

  /// The key earlier releases wrote a `ThemeMode.index` into. Read once on
  /// load, mapped onto [Appearance], then dropped. Never written again.
  @visibleForTesting
  static const String kLegacyThemeMode = 'themeMode';

  static const String _kReduceMotion = 'reduceMotion';
  static const String _kFlowUnit = 'flowUnit';
  static const String _kVolumeUnit = 'volumeUnit';
  static const String _kFollowFlowUnit = 'followFlowUnitForVolume';
  static const String _kAlertLeak = 'alertOnLeak';
  static const String _kAlertWatch = 'alertOnWatch';
  static const String _kAlertFault = 'alertOnFault';
  static const String _kHaptics = 'haptics';
  static const String _kAudible = 'audibleAlarm';
  static const String _kAutoReconnect = 'autoReconnect';
  static const String _kDeviceId = 'rememberedDeviceId';
  static const String _kDeviceName = 'rememberedDeviceName';
  static const String _kSensorNames = 'sensorNames';
  static const String _kLoggingInterval = 'loggingInterval';
  static const String _kRetention = 'retention';
  static const String _kAutoPrune = 'autoPrune';
  static const String _kEnvelopeDetails = 'showEnvelopeDetails';
  static const String _kRequireConnection = 'requireConnectionToBrowse';
  static const String _kOnboardingSeen = 'onboardingSeen';
  static const String _kTariff = 'tariffBsPerCubicMetre';
  static const String _kTariffConfigured = 'tariffConfiguredByUser';
  static const String _kShowCostEquivalence = 'showCostEquivalence';
  static const String _kLocaleOverride = 'localeOverride';

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = _read(prefs);
    await _retireLegacyThemeMode(prefs, settings.appearance);
    return SettingsController._(prefs, settings);
  }

  /// Reads the appearance, falling back to the legacy `themeMode` index when the
  /// new key has never been written.
  static Appearance _readAppearance(SharedPreferences prefs) {
    final index = prefs.getInt(_kAppearance);
    if (index != null && index >= 0 && index < Appearance.values.length) {
      return Appearance.values[index];
    }
    final legacy = prefs.getInt(kLegacyThemeMode);
    if (legacy == null) return Appearance.dark;
    return appearanceFromLegacyThemeMode(legacy);
  }

  /// Translates a persisted `ThemeMode.index` into an [Appearance].
  ///
  /// `ThemeMode` ordered its values system, light, dark, so 0 → system,
  /// 1 → light, 2 → dark. Anything outside that range is a value this app never
  /// wrote and lands on the default, Dark.
  @visibleForTesting
  static Appearance appearanceFromLegacyThemeMode(int index) => switch (index) {
        0 => Appearance.system,
        1 => Appearance.light,
        2 => Appearance.dark,
        _ => Appearance.dark,
      };

  /// Completes the one-time move from `themeMode` to `appearance`: the migrated
  /// value is written under the new key and the legacy key is removed, so the
  /// translation above runs at most once per install. Every other persisted key
  /// is left exactly as it was.
  static Future<void> _retireLegacyThemeMode(
    SharedPreferences prefs,
    Appearance appearance,
  ) async {
    if (!prefs.containsKey(kLegacyThemeMode)) return;
    if (!prefs.containsKey(_kAppearance)) {
      await prefs.setInt(_kAppearance, appearance.index);
    }
    await prefs.remove(kLegacyThemeMode);
  }

  static AppSettings _read(SharedPreferences prefs) {
    T pick<T>(List<T> values, String key, T fallback) {
      final index = prefs.getInt(key);
      if (index == null || index < 0 || index >= values.length) return fallback;
      return values[index];
    }

    final names = prefs.getStringList(_kSensorNames);

    return AppSettings(
      appearance: _readAppearance(prefs),
      reduceMotion: prefs.getBool(_kReduceMotion) ?? false,
      flowUnit: pick(FlowUnit.values, _kFlowUnit, FlowUnit.litresPerMinute),
      volumeUnit: pick(VolumeUnit.values, _kVolumeUnit, VolumeUnit.litres),
      followFlowUnitForVolume: prefs.getBool(_kFollowFlowUnit) ?? true,
      alertOnLeak: prefs.getBool(_kAlertLeak) ?? true,
      alertOnWatch: prefs.getBool(_kAlertWatch) ?? false,
      alertOnFault: prefs.getBool(_kAlertFault) ?? true,
      hapticsEnabled: prefs.getBool(_kHaptics) ?? true,
      audibleAlarm: prefs.getBool(_kAudible) ?? false,
      autoReconnect: prefs.getBool(_kAutoReconnect) ?? true,
      rememberedDeviceId: prefs.getString(_kDeviceId) ?? '',
      rememberedDeviceName: prefs.getString(_kDeviceName) ?? '',
      sensorNames: (names != null && names.length == 3)
          ? List<String>.unmodifiable(names)
          : const <String>['Main Inlet', 'Outlet A', 'Outlet B'],
      loggingInterval: pick(
        LoggingInterval.values,
        _kLoggingInterval,
        LoggingInterval.tenSeconds,
      ),
      retention: pick(
        RetentionPolicy.values,
        _kRetention,
        RetentionPolicy.quarter,
      ),
      autoPrune: prefs.getBool(_kAutoPrune) ?? true,
      showEnvelopeDetails: prefs.getBool(_kEnvelopeDetails) ?? true,
      requireConnectionToBrowse: prefs.getBool(_kRequireConnection) ?? true,
      onboardingSeen: prefs.getBool(_kOnboardingSeen) ?? false,
      tariffBsPerCubicMetre: _readTariff(prefs),
      tariffConfiguredByUser: _isStoredTariffValid(prefs) &&
          (prefs.getBool(_kTariffConfigured) ?? false),
      showCostEquivalence: prefs.getBool(_kShowCostEquivalence) ?? true,
      localeOverride: prefs.getString(_kLocaleOverride) ?? '',
    );
  }

  /// Whether SharedPreferences holds a Tariff that is present, finite and
  /// inside the accepted `(0, 1000]` range. A stored value that is missing,
  /// non-finite or out of range is treated as corrupt: the default substitutes
  /// and [tariffConfiguredByUser] is forced back to false.
  static bool _isStoredTariffValid(SharedPreferences prefs) {
    final stored = prefs.getDouble(_kTariff);
    if (stored == null || !stored.isFinite) return false;
    // Tariff.min is exclusive, Tariff.max is inclusive (Req 5.3, 5.4).
    return stored > Tariff.min && stored <= Tariff.max;
  }

  /// Reads the persisted Tariff, substituting [Tariff.defaultValue] whenever the
  /// stored value is missing, non-finite or out of range. The value is
  /// quantised to the persisted precision on the way out.
  static double _readTariff(SharedPreferences prefs) {
    if (!_isStoredTariffValid(prefs)) return Tariff.defaultValue;
    return Tariff.quantise(prefs.getDouble(_kTariff)!);
  }

  void _apply(AppSettings next, Future<void> Function() persist) {
    _settings = next;
    notifyListeners();
    // Deliberately not awaited: preference writes must never stall a tap.
    persist().catchError((Object _) {});
  }

  // --- Appearance -----------------------------------------------------------

  void setAppearance(Appearance appearance) => _apply(
        _settings.copyWith(appearance: appearance),
        () => _prefs.setInt(_kAppearance, appearance.index),
      );

  void setReduceMotion(bool value) => _apply(
        _settings.copyWith(reduceMotion: value),
        () => _prefs.setBool(_kReduceMotion, value),
      );

  void setLocaleOverride(String tag) => _apply(
        _settings.copyWith(localeOverride: tag),
        () => _prefs.setString(_kLocaleOverride, tag),
      );

  // --- Tariff & cost --------------------------------------------------------

  /// Commits a user-entered Tariff, quantised to the persisted precision, and
  /// marks it as configured by the user. Callers validate the value against the
  /// [Tariff] bounds before calling; out-of-range values are rejected upstream.
  void setTariff(double bsPerCubicMetre) {
    final value = Tariff.quantise(bsPerCubicMetre);
    _apply(
      _settings.copyWith(
        tariffBsPerCubicMetre: value,
        tariffConfiguredByUser: true,
      ),
      () async {
        await _prefs.setDouble(_kTariff, value);
        await _prefs.setBool(_kTariffConfigured, true);
      },
    );
  }

  void setShowCostEquivalence(bool v) => _apply(
        _settings.copyWith(showCostEquivalence: v),
        () => _prefs.setBool(_kShowCostEquivalence, v),
      );

  // --- Units ---------------------------------------------------------------

  void setFlowUnit(FlowUnit unit) {
    final volume = _settings.followFlowUnitForVolume
        ? VolumeUnit.companionOf(unit)
        : _settings.volumeUnit;
    _apply(
      _settings.copyWith(flowUnit: unit, volumeUnit: volume),
      () async {
        await _prefs.setInt(_kFlowUnit, unit.index);
        await _prefs.setInt(_kVolumeUnit, volume.index);
      },
    );
  }

  void setVolumeUnit(VolumeUnit unit) => _apply(
        _settings.copyWith(volumeUnit: unit, followFlowUnitForVolume: false),
        () async {
          await _prefs.setInt(_kVolumeUnit, unit.index);
          await _prefs.setBool(_kFollowFlowUnit, false);
        },
      );

  void setFollowFlowUnitForVolume(bool value) {
    final volume = value
        ? VolumeUnit.companionOf(_settings.flowUnit)
        : _settings.volumeUnit;
    _apply(
      _settings.copyWith(
        followFlowUnitForVolume: value,
        volumeUnit: volume,
      ),
      () async {
        await _prefs.setBool(_kFollowFlowUnit, value);
        await _prefs.setInt(_kVolumeUnit, volume.index);
      },
    );
  }

  // --- Alerts --------------------------------------------------------------

  void setAlertOnLeak(bool v) => _apply(
        _settings.copyWith(alertOnLeak: v),
        () => _prefs.setBool(_kAlertLeak, v),
      );

  void setAlertOnWatch(bool v) => _apply(
        _settings.copyWith(alertOnWatch: v),
        () => _prefs.setBool(_kAlertWatch, v),
      );

  void setAlertOnFault(bool v) => _apply(
        _settings.copyWith(alertOnFault: v),
        () => _prefs.setBool(_kAlertFault, v),
      );

  void setHaptics(bool v) => _apply(
        _settings.copyWith(hapticsEnabled: v),
        () => _prefs.setBool(_kHaptics, v),
      );

  void setAudibleAlarm(bool v) => _apply(
        _settings.copyWith(audibleAlarm: v),
        () => _prefs.setBool(_kAudible, v),
      );

  // --- Connection ----------------------------------------------------------

  void setAutoReconnect(bool v) => _apply(
        _settings.copyWith(autoReconnect: v),
        () => _prefs.setBool(_kAutoReconnect, v),
      );

  void rememberDevice(String id, String name) => _apply(
        _settings.copyWith(rememberedDeviceId: id, rememberedDeviceName: name),
        () async {
          await _prefs.setString(_kDeviceId, id);
          await _prefs.setString(_kDeviceName, name);
        },
      );

  void forgetDevice() => _apply(
        _settings.copyWith(rememberedDeviceId: '', rememberedDeviceName: ''),
        () async {
          await _prefs.remove(_kDeviceId);
          await _prefs.remove(_kDeviceName);
        },
      );

  void setRequireConnectionToBrowse(bool v) => _apply(
        _settings.copyWith(requireConnectionToBrowse: v),
        () => _prefs.setBool(_kRequireConnection, v),
      );

  // --- Sensors -------------------------------------------------------------

  void renameSensor(int index, String name) {
    final trimmed = name.trim();
    if (index < 0 || index > 2) return;
    final next = List<String>.of(_settings.sensorNames);
    next[index] = trimmed.isEmpty
        ? const <String>['Main Inlet', 'Outlet A', 'Outlet B'][index]
        : trimmed;
    _apply(
      _settings.copyWith(sensorNames: List<String>.unmodifiable(next)),
      () => _prefs.setStringList(_kSensorNames, next),
    );
  }

  // --- Data ----------------------------------------------------------------

  void setLoggingInterval(LoggingInterval interval) => _apply(
        _settings.copyWith(loggingInterval: interval),
        () => _prefs.setInt(_kLoggingInterval, interval.index),
      );

  void setRetention(RetentionPolicy policy) => _apply(
        _settings.copyWith(retention: policy),
        () => _prefs.setInt(_kRetention, policy.index),
      );

  void setAutoPrune(bool v) => _apply(
        _settings.copyWith(autoPrune: v),
        () => _prefs.setBool(_kAutoPrune, v),
      );

  void setShowEnvelopeDetails(bool v) => _apply(
        _settings.copyWith(showEnvelopeDetails: v),
        () => _prefs.setBool(_kEnvelopeDetails, v),
      );

  void markOnboardingSeen() => _apply(
        _settings.copyWith(onboardingSeen: true),
        () => _prefs.setBool(_kOnboardingSeen, true),
      );

  Future<void> resetAll() async {
    await _prefs.clear();
    _settings = const AppSettings();
    notifyListeners();
  }
}

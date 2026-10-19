import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/locale/app_locale.dart';
import '../../core/money/tariff.dart';
import '../../core/protocol/leak_protocol.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/units/measurement_units.dart';
import '../../data/settings/app_settings.dart';
import '../../data/settings/settings_controller.dart';
import '../../state/monitor_controller.dart';
import '../common/alert_banner.dart';
import '../common/icon_language.dart';
import '../common/motion_widgets.dart';
import '../common/surface_card.dart';
import '../diagnostics/diagnostics_sheet.dart';
import 'calibration_dialog.dart';
import 'widgets/setting_tiles.dart';

/// Tab 2 — settings.
///
/// Split into what the app controls (appearance, units, alerts, storage) and what
/// the *firmware* controls (noise floor, tolerance, debounce, K factors). Device
/// settings write straight through to the Arduino and persist in its EEPROM, so
/// they are disabled while offline and clearly marked.
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Settings'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Diagnostics',
            onPressed: () => DiagnosticsSheet.show(context),
            icon: AppIcon(AppGlyph.gauge, color: palette.accentText),
          ),
          const SizedBox(width: Tokens.s1),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s3,
          0,
          Tokens.s3,
          Tokens.s6,
        ),
        children: const <Widget>[
          AppearanceSection(),
          _UnitsSection(),
          TariffSection(),
          _SensorNamesSection(),
          _AlertsSection(),
          _DetectionSection(),
          _ConnectionSection(),
          _DataSection(),
          _AboutSection(),
        ],
      ),
    );
  }
}

// =============================================================================
// Appearance
// =============================================================================

/// The persistent Requirement 9.4 advisory, shown whenever the light appearance
/// is active.
///
/// Held as a single named constant — not an inline literal — so the wording test
/// asserts this constant and the widget renders this same constant, giving one
/// source of truth for the string. The Web_Client holds the byte-identical text
/// on its own side (task 3.8, exported as `LIGHT_APPEARANCE_ADVISORY`), which is
/// what lets task 17.2 / 17.3 compare the two clients for the parity Requirement
/// 9.6 demands.
///
/// Requirements 9.4, 9.6.
const String kLightAppearanceAdvisory =
    'Light backgrounds sit outside WattVision guidance for prolonged data '
    'reading.';

/// The primary Appearance choice (Dark, High contrast dark, Follow system) and
/// the Accessibility section that demotes the light appearance to a switch.
///
/// Stateful because the two controls are two views of one [Appearance] value:
/// turning the light switch off must restore the dark appearance selected
/// *before* light was turned on, not always snap to [Appearance.dark] — snapping
/// would silently discard a High_Contrast_Dark or Follow-system choice. That
/// "previous dark appearance" is session-scoped memory ([_lastDarkAppearance]);
/// the appearance itself is what persists across restarts (Requirement 9.7).
///
/// The section renders both the Appearance card and the Accessibility card so
/// the shared memory lives in one place. Requirements 9.1, 9.2, 9.3, 9.4, 9.6.
///
/// Public and named (rather than a `_private` widget) only so the appearance and
/// accessibility behaviour can be pumped in a widget test with just a
/// [SettingsController] in scope — it depends on nothing else, unlike the other
/// settings sections. It is not part of the tab's public surface otherwise.
@visibleForTesting
class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key});

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  /// The primary Appearance options, in order — every appearance except light.
  /// Light is demoted into the Accessibility section (Requirement 9.3); it is
  /// never selectable here. `highContrastDark` is reachable only through this
  /// control, never through the light switch.
  static const List<Appearance> _primaryOptions = <Appearance>[
    Appearance.dark,
    Appearance.highContrastDark,
    Appearance.system,
  ];

  /// The dark-family appearance to restore when the light switch is turned off.
  /// Seeded from the current appearance, or to [Appearance.dark] when light is
  /// already active on mount and there is therefore no prior dark choice.
  Appearance? _lastDarkAppearance;

  Appearance get _fallbackDark => _lastDarkAppearance ?? Appearance.dark;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final palette = AppPalette.of(context);

    final lightActive = settings.appearance == Appearance.light;
    // While light is active the primary control has no appearance of its own to
    // reflect, so it shows the dark choice the switch will restore. Otherwise it
    // shows — and is — the current appearance.
    final primaryAppearance =
        lightActive ? _fallbackDark : settings.appearance;

    void selectPrimary(Appearance appearance) {
      // Selecting a primary option turns light off by definition: it writes a
      // dark-family appearance and updates the memory to match.
      setState(() => _lastDarkAppearance = appearance);
      controller.setAppearance(appearance);
    }

    void toggleLight(bool on) {
      if (on) {
        // Remember where to come back to before leaving the dark family.
        if (!lightActive) {
          setState(() => _lastDarkAppearance = settings.appearance);
        }
        controller.setAppearance(Appearance.light);
      } else {
        controller.setAppearance(_fallbackDark);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FadeSlideIn(
          index: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionHeading(
                'Appearance',
                icon: Icons.palette_outlined,
                subtitle: 'The dashboard is designed dark-first for long '
                    'sessions of reading data. High contrast dark raises text '
                    'and border contrast without leaving the dark palette.',
              ),
              SettingGroup(
                children: <Widget>[
                  SettingChoice<Appearance>(
                    title: 'Theme',
                    icon: Icons.dark_mode_outlined,
                    value: primaryAppearance,
                    options: _primaryOptions,
                    labelOf: (mode) => switch (mode) {
                      Appearance.dark => 'Dark',
                      Appearance.highContrastDark => 'High contrast dark',
                      Appearance.system => 'Follow system',
                      Appearance.light => 'Light',
                    },
                    descriptionOf: (mode) => switch (mode) {
                      Appearance.dark =>
                        'Recommended — highest contrast for charts',
                      Appearance.highContrastDark =>
                        'Same dark surfaces, stronger text and borders',
                      Appearance.system => 'Match the device setting',
                      Appearance.light => 'Brighter surfaces, dimmed accents',
                    },
                    onChanged: selectPrimary,
                  ),
                  SettingSwitch(
                    title: 'Reduce motion',
                    subtitle: 'Removes the ambient pulses and page transitions. '
                        'Values still update, just without the sweep.',
                    icon: Icons.animation_outlined,
                    value: settings.reduceMotion,
                    onChanged: controller.setReduceMotion,
                  ),
                  SettingSwitch(
                    title: 'Show tolerance details',
                    subtitle: 'Adds the expected-imbalance and margin-of-error '
                        'breakdown to each sensor page.',
                    icon: Icons.rule_outlined,
                    value: settings.showEnvelopeDetails,
                    onChanged: controller.setShowEnvelopeDetails,
                  ),
                ],
              ),
            ],
          ),
        ),
        FadeSlideIn(
          index: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionHeading(
                'Accessibility',
                icon: Icons.accessibility_new_outlined,
                subtitle: 'Affordances for readability and comfort. The light '
                    'appearance lives here rather than in the primary theme '
                    'choice.',
              ),
              SettingGroup(
                children: <Widget>[
                  // Light is a switch, not a peer theme option (Requirement
                  // 9.3). On → Appearance.light; off → the dark appearance held
                  // before it was turned on. The primary control above and this
                  // switch are one Appearance value seen two ways.
                  SettingSwitch(
                    title: 'Light appearance',
                    subtitle: 'Use a light background instead of the dark '
                        'WattVision palette.',
                    icon: Icons.light_mode_outlined,
                    value: lightActive,
                    onChanged: toggleLight,
                  ),
                ],
              ),
              // Requirement 9.4: a *persistent* advisory, visible for as long as
              // the light appearance is selected. NoticeBanner has no dismiss
              // timer, so it stays put rather than behaving like a toast.
              if (lightActive) ...<Widget>[
                const SizedBox(height: Tokens.s2),
                NoticeBanner(
                  title: 'Outside design guidance',
                  message: kLightAppearanceAdvisory,
                  icon: Icons.warning_amber_rounded,
                  accent: palette.watch,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Units
// =============================================================================

class _UnitsSection extends StatelessWidget {
  const _UnitsSection();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final monitor = context.watch<MonitorController>();
    final formatter = settings.formatter;

    // Live preview so the effect of a unit change is immediately obvious.
    final sample = monitor.flowFor(0);

    return FadeSlideIn(
      index: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeading(
            'Units',
            icon: Icons.straighten_outlined,
            subtitle: 'The board always reports litres per minute. Readings are '
                'converted for display only, so changing units never rewrites '
                'stored history.',
          ),
          SettingGroup(
            children: <Widget>[
              SettingChoice<FlowUnit>(
                title: 'Flow rate',
                icon: Icons.speed_outlined,
                value: settings.flowUnit,
                options: FlowUnit.values,
                labelOf: (u) => u.symbol,
                descriptionOf: (u) => u.label,
                onChanged: controller.setFlowUnit,
              ),
              SettingSwitch(
                title: 'Match volume unit to flow unit',
                subtitle: 'Picking gal/min also switches totals to gallons.',
                icon: Icons.link_rounded,
                value: settings.followFlowUnitForVolume,
                onChanged: controller.setFollowFlowUnitForVolume,
              ),
              SettingChoice<VolumeUnit>(
                title: 'Volume',
                icon: Icons.water_outlined,
                value: settings.volumeUnit,
                options: VolumeUnit.values,
                labelOf: (u) => u.symbol,
                descriptionOf: (u) => u.label,
                enabled: !settings.followFlowUnitForVolume,
                onChanged: controller.setVolumeUnit,
              ),
              SettingInfo(
                title: 'Preview',
                subtitle: 'Current inlet reading in the selected units',
                icon: Icons.visibility_outlined,
                value: formatter.flow(sample),
                valueColor: AppPalette.of(context).accentText,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Tariff & cost
// =============================================================================

/// The Tariff row's title. Named so the wording parity test (task 11.9) and the
/// Web_Client's `TARIFF_CONTROL_TITLE` (task 11.10) assert one source of truth.
///
/// Requirements 5.1, 5.2.
const String kTariffControlTitle = 'Water tariff';

/// The Tariff field's supporting copy. Deliberately labels the value as an
/// *editable placeholder* — a starting point the user may overwrite — rather
/// than a billed figure, which is Requirement 5.2's demand. Byte-identical to
/// the Web_Client's `TARIFF_CONTROL_SUBTITLE` for the parity Requirement.
///
/// Requirements 5.2.
const String kTariffControlSubtitle =
    'A starting placeholder in Bs. per cubic metre, not a billed figure. '
    'Enter your own water price to overwrite it.';

/// The `localeOverride` sentinel for "no override" — resolution falls back to
/// the platform locale (Requirement 12.6). Choosing "Follow system" writes this
/// empty string, handing locale resolution back to the platform.
const String _kFollowSystemLocale = '';

/// The Settings section holding the Tariff, the Bs_Equivalence master switch and
/// the locale override. Requirements 5.1, 5.2, 5.3, 5.4, 5.8, 12.5, 12.6.
///
/// Public and named (rather than a `_private` widget) only so the tariff,
/// cost-switch and locale-override behaviour can be pumped in a widget test
/// with just a [SettingsController] in scope — it depends on nothing else,
/// unlike the other settings sections that read the [MonitorController]. It is
/// not part of the tab's public surface otherwise.
@visibleForTesting
class TariffSection extends StatelessWidget {
  const TariffSection({super.key});

  /// Human labels for each supported locale, plus the follow-system default.
  static String _localeLabel(String tag) => switch (tag) {
        _kFollowSystemLocale => 'Follow system',
        'es' => 'Español',
        'en' => 'English',
        _ => tag,
      };

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    // The locale that drives the *editing* representation of the persisted
    // Tariff — the ungrouped, trailing-zero-trimmed form Requirement 5.6's
    // round-trip is defined over. Resolution honours the user override first,
    // then the platform locale (Requirement 12.6). Parsing itself accepts
    // either decimal separator regardless of locale, so the field stays
    // forgiving even when the resolved locale and the keyboard disagree.
    final activeLocale = resolveLocale(
      override: settings.localeOverride.isEmpty ? null : settings.localeOverride,
      platformTag:
          WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
    );

    // Follow-system first, then one option per supported locale.
    final localeOptions = <String>[
      _kFollowSystemLocale,
      for (final locale in AppLocale.values) locale.code,
    ];

    return FadeSlideIn(
      index: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeading(
            'Tariff & cost',
            icon: Icons.payments_outlined,
            subtitle: 'Set your water price to see a Bolivianos figure '
                'alongside every volume. This is display only — no money is '
                'ever stored with your readings.',
          ),
          SettingGroup(
            children: <Widget>[
              // Requirements 5.1, 5.2, 5.3, 5.4, 12.5. The field opens on the
              // ungrouped editing form of the persisted value, commits an
              // accepted value straight through the controller (so every
              // Bs_Equivalence picks it up on the next frame — well inside the
              // 320ms budget of Requirement 5.3), and on a rejected entry
              // reverts the draft to the persisted value on blur and shows the
              // accepted-range message.
              _TariffTextField(
                title: kTariffControlTitle,
                subtitle: kTariffControlSubtitle,
                value: settings.tariffBsPerCubicMetre,
                localeCode: activeLocale.code,
                onCommit: controller.setTariff,
              ),
              // Requirement 5.8: the master switch for the Bs_Equivalence
              // display. Off → volume figures show without a cost.
              SettingSwitch(
                title: 'Show cost equivalence',
                subtitle: 'Adds a Bs. figure next to every volume. Turn off to '
                    'show litres only.',
                icon: Icons.attach_money_rounded,
                value: settings.showCostEquivalence,
                onChanged: controller.setShowCostEquivalence,
              ),
              // Requirement 12.6: the locale override, step 1 of the resolution
              // chain. "Follow system" is the empty-string sentinel that hands
              // resolution back to the platform.
              SettingChoice<String>(
                title: 'Number & currency format',
                subtitle: 'Chooses the decimal and grouping separators for '
                    'figures and the Bs. amount.',
                icon: Icons.translate_rounded,
                value: settings.localeOverride,
                options: localeOptions,
                labelOf: _localeLabel,
                onChanged: controller.setLocaleOverride,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Tariff text control: an editable field with the parse / validate /
/// revert behaviour the Tariff needs.
///
/// The draft is seeded from [Tariff.formatForEditing] of the persisted value,
/// so the field always opens on the ungrouped, trailing-zero-trimmed
/// representation Requirement 5.6's round-trip is defined over. On commit — a
/// blur (focus lost) or the keyboard's done action — the draft runs through
/// [Tariff.parse]:
///
///  * on [TariffOk] the accepted value is committed through [onCommit]
///    synchronously (no debounce), and the draft is normalised to the accepted
///    value's editing form;
///  * on [TariffInvalid] the persisted value is left untouched, the draft
///    reverts to the persisted value's editing form, and the returned message
///    (the accepted-range or ambiguity text) is shown beneath the field.
///
/// Requirements 5.1, 5.2, 5.3, 5.4, 12.5.
class _TariffTextField extends StatefulWidget {
  const _TariffTextField({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.localeCode,
    required this.onCommit,
  });

  final String title;
  final String subtitle;

  /// The persisted Tariff, in Bs. per cubic metre.
  final double value;

  /// The active locale code (`es` / `en`) whose decimal separator the editing
  /// form uses.
  final String localeCode;

  /// Invoked with an accepted, in-range Tariff value on commit.
  final ValueChanged<double> onCommit;

  @override
  State<_TariffTextField> createState() => _TariffTextFieldState();
}

class _TariffTextFieldState extends State<_TariffTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: Tariff.formatForEditing(widget.value, widget.localeCode),
  );
  final FocusNode _focus = FocusNode();

  /// The accepted-range or ambiguity message from the last rejected commit, or
  /// null when the last commit was accepted (or nothing has been committed).
  String? _message;

  @override
  void initState() {
    super.initState();
    // Commit on blur — leaving the field is a commit, exactly as the sensor
    // name field treats it.
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_TariffTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A value or locale change from outside (a reset, or a locale switch) while
    // the field is idle re-seeds the draft on the new editing form.
    final changed = oldWidget.value != widget.value ||
        oldWidget.localeCode != widget.localeCode;
    if (changed && !_focus.hasFocus) {
      _controller.text = Tariff.formatForEditing(widget.value, widget.localeCode);
      _message = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final persistedForm =
        Tariff.formatForEditing(widget.value, widget.localeCode);

    // A commit fires on every blur, and a rejected entry has just reverted the
    // draft to [persistedForm]. Re-committing that unchanged, already-valid
    // draft would silently clear the accepted-range message the user still
    // needs to read, so a no-op commit is skipped: nothing was edited.
    if (_controller.text == persistedForm) return;

    final result = Tariff.parse(_controller.text, widget.localeCode);
    switch (result) {
      case TariffOk(:final value):
        setState(() => _message = null);
        // Normalise the draft to the accepted value's canonical editing form.
        _controller.text = Tariff.formatForEditing(value, widget.localeCode);
        widget.onCommit(value);
      case TariffInvalid(:final message):
        // Requirement 5.4: retain the persisted value, revert the draft to it,
        // and surface the accepted-range message.
        setState(() => _message = message);
        _controller.text = persistedForm;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s3,
        vertical: Tokens.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: Tokens.s2),
          TextField(
            controller: _controller,
            focusNode: _focus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _commit(),
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              labelText: widget.title,
              prefixText: 'Bs. ',
              suffixText: '/ m³',
              errorText: _message,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Tokens.radiusControl),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Tokens.radiusControl),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Tokens.radiusControl),
                borderSide: BorderSide(color: palette.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Sensor names
// =============================================================================

class _SensorNamesSection extends StatelessWidget {
  const _SensorNamesSection();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return FadeSlideIn(
      index: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeading(
            'Sensor labels',
            icon: Icons.label_outline,
            subtitle: 'Name the channels after what they actually feed — '
                '"Kitchen", "Garden tap" — so an alert means something at a '
                'glance.',
          ),
          SettingGroup(
            children: <Widget>[
              for (var i = 0; i < kSensorCount; i++)
                SettingTextField(
                  title: SensorRole.byIndex(i).label,
                  value: settings.sensorNames[i],
                  hint: SensorRole.byIndex(i).description,
                  icon: i == 0 ? Icons.input_rounded : Icons.call_split_rounded,
                  onSubmitted: (name) => controller.renameSensor(i, name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Alerts
// =============================================================================

class _AlertsSection extends StatelessWidget {
  const _AlertsSection();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return FadeSlideIn(
      index: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeading(
            'Alerts',
            icon: Icons.notifications_active_outlined,
            subtitle: 'Which verdicts get your attention while the app is open.',
          ),
          SettingGroup(
            children: <Widget>[
              SettingSwitch(
                title: 'Confirmed leaks',
                subtitle: 'Fires once the imbalance has persisted long enough to '
                    'rule out sensor noise.',
                icon: Icons.water_damage_outlined,
                value: settings.alertOnLeak,
                onChanged: controller.setAlertOnLeak,
              ),
              SettingSwitch(
                title: 'Sensor faults',
                subtitle: 'Wiring problems and dead sensors.',
                icon: Icons.cable_outlined,
                value: settings.alertOnFault,
                onChanged: controller.setAlertOnFault,
              ),
              SettingSwitch(
                title: 'Early warnings',
                subtitle: 'Also alert on unconfirmed imbalance. Noisier, but '
                    'gives you a few seconds of head start.',
                icon: Icons.visibility_outlined,
                value: settings.alertOnWatch,
                onChanged: controller.setAlertOnWatch,
              ),
              SettingSwitch(
                title: 'Haptic feedback',
                icon: Icons.vibration_rounded,
                value: settings.hapticsEnabled,
                onChanged: controller.setHaptics,
              ),
              SettingSwitch(
                title: 'Alert sound',
                subtitle: 'Plays the system alert tone on a confirmed alarm.',
                icon: Icons.volume_up_outlined,
                value: settings.audibleAlarm,
                onChanged: controller.setAudibleAlarm,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Detection tuning — writes to the Arduino
// =============================================================================

class _DetectionSection extends StatelessWidget {
  const _DetectionSection();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final settings = context.watch<SettingsController>().settings;
    final palette = AppPalette.of(context);
    final config = monitor.deviceConfig;
    final formatter = settings.formatter;
    final online = monitor.isConnected && config != null;

    return FadeSlideIn(
      index: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeading(
            'Leak detection',
            icon: Icons.tune,
            subtitle: 'These live on the Arduino, not in the app. Changes are '
                'written to its EEPROM and survive a power cycle.',
          ),
          if (!online) ...<Widget>[
            NoticeBanner(
              title: 'Device offline',
              message: 'Connect the module to read or change its detection '
                  'settings.',
              icon: Icons.bluetooth_disabled,
              accent: palette.idle,
            ),
            const SizedBox(height: Tokens.s2),
          ],
          SettingGroup(
            accent: online ? null : palette.border,
            children: <Widget>[
              SettingAction(
                title: 'Run baseline calibration',
                subtitle: config?.isCalibrated ?? false
                    ? 'Last learned bias '
                        '${formatter.flow(config!.learnedBiasLpm)}'
                    : 'Not calibrated yet — strongly recommended after install',
                icon: Icons.auto_graph_rounded,
                enabled: online,
                onTap: () => CalibrationDialog.show(context),
                trailing: config?.isCalibrated ?? false
                    ? Icon(Icons.check_circle, color: palette.normal, size: 20)
                    : Icon(Icons.priority_high_rounded,
                        color: palette.watch, size: 20),
              ),
              SettingSlider(
                title: 'Noise floor',
                subtitle: 'Readings under this are reported as exactly zero. '
                    'This is what stops an idle system raising false leaks.',
                icon: Icons.blur_on_rounded,
                enabled: online,
                value: config?.noiseFloorLpm ?? 0.12,
                min: 0,
                max: 1.0,
                divisions: 40,
                format: (v) => formatter.flow(v),
                onCommitted: (v) => monitor.setNoiseFloor(v),
              ),
              SettingSlider(
                title: 'Minimum margin of error',
                subtitle: 'Absolute floor on the allowed imbalance, applied on '
                    'top of the calibration dataset.',
                icon: Icons.straighten_rounded,
                enabled: online,
                value: config?.toleranceAbsLpm ?? 0.2,
                min: 0.05,
                max: 2.0,
                divisions: 39,
                format: (v) => formatter.flow(v),
                onCommitted: (v) => monitor.setTolerance(
                  v,
                  config?.tolerancePct ?? 0.08,
                ),
              ),
              SettingSlider(
                title: 'Proportional margin',
                subtitle: 'Extra allowance as a percentage of inlet flow, for '
                    'high-flow events.',
                icon: Icons.percent_rounded,
                enabled: online,
                value: (config?.tolerancePct ?? 0.08) * 100,
                min: 0,
                max: 40,
                divisions: 40,
                format: (v) => '${v.toStringAsFixed(0)}%',
                onCommitted: (v) => monitor.setTolerance(
                  config?.toleranceAbsLpm ?? 0.2,
                  v / 100,
                ),
              ),
              SettingSlider(
                title: 'Confirmation time',
                subtitle: 'How long an imbalance must persist before the alarm '
                    'latches. Lower reacts faster but is more twitchy.',
                icon: Icons.timer_outlined,
                enabled: online,
                value: (config?.leakConfirmSamples ?? 8).toDouble(),
                min: 2,
                max: 60,
                divisions: 58,
                format: (v) => '${v.toStringAsFixed(0)} s',
                onCommitted: (v) => monitor.setDebounce(
                  v.round(),
                  config?.leakClearSamples ?? 5,
                  config?.faultConfirmSamples ?? 10,
                ),
              ),
              SettingSlider(
                title: 'Clear time',
                subtitle: 'Clean samples needed before a latched alarm is '
                    'retracted.',
                icon: Icons.timer_off_outlined,
                enabled: online,
                value: (config?.leakClearSamples ?? 5).toDouble(),
                min: 1,
                max: 60,
                divisions: 59,
                format: (v) => '${v.toStringAsFixed(0)} s',
                onCommitted: (v) => monitor.setDebounce(
                  config?.leakConfirmSamples ?? 8,
                  v.round(),
                  config?.faultConfirmSamples ?? 10,
                ),
              ),
              SettingAction(
                title: 'Sensor K factors',
                subtitle: 'Pulses per litre for each meter. YF-S201 is 450.',
                icon: Icons.settings_input_component_outlined,
                enabled: online,
                onTap: () => _KFactorSheet.show(context),
              ),
              SettingAction(
                title: 'Restore device defaults',
                subtitle: 'Resets the Arduino tuning, not the app settings.',
                icon: Icons.restore_rounded,
                enabled: online,
                destructive: true,
                onTap: () async {
                  final confirmed = await _confirm(
                    context,
                    title: 'Restore device defaults?',
                    message: 'The board will go back to its factory tolerance, '
                        'noise floor, debounce and K factors. Your learned '
                        'calibration bias is cleared too.',
                    confirmLabel: 'Restore',
                  );
                  if (confirmed && context.mounted) {
                    await monitor.restoreDeviceDefaults();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Per-sensor pulses-per-litre editor.
class _KFactorSheet extends StatelessWidget {
  const _KFactorSheet();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _KFactorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final palette = AppPalette.of(context);
    final settings = context.watch<SettingsController>().settings;
    final config = monitor.deviceConfig;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Tokens.s3,
        0,
        Tokens.s3,
        MediaQuery.viewInsetsOf(context).bottom + Tokens.s4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Sensor K factors',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Tokens.s1),
          Text(
            'Pulses per litre. If a channel reads consistently high or low '
            'against a measured jug, adjust its K factor rather than widening '
            'the tolerance.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: Tokens.s3),
          SettingGroup(
            children: <Widget>[
              for (var i = 0; i < kSensorCount; i++)
                SettingSlider(
                  title: settings.sensorNames[i],
                  subtitle: SensorRole.byIndex(i).label,
                  value: config?.pulsesPerLitre[i] ?? 450,
                  min: 200,
                  max: 900,
                  divisions: 140,
                  format: (v) => v.toStringAsFixed(0),
                  onCommitted: (v) => monitor.setPulsesPerLitre(i, v),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Connection
// =============================================================================

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final monitor = context.watch<MonitorController>();
    final palette = AppPalette.of(context);

    return FadeSlideIn(
      index: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeading(
            'Connection',
            icon: Icons.bluetooth_rounded,
          ),
          SettingGroup(
            children: <Widget>[
              SettingInfo(
                title: 'Status',
                subtitle: monitor.usingReplay
                    ? 'Replaying recorded data — no hardware attached'
                    : monitor.usingSimulator
                        ? 'Simulated feed — no hardware attached'
                        : monitor.connectedDevice?.displayName ??
                            'Not connected',
                icon: Icons.sensors,
                value: monitor.usingReplay
                    ? 'REPLAY'
                    : monitor.isConnected
                        ? 'LIVE'
                        : monitor.isStale
                            ? 'STALE'
                            : 'OFFLINE',
                valueColor: monitor.usingReplay
                    ? palette.accentText
                    : monitor.isConnected
                        ? palette.normal
                        : monitor.isStale
                            ? palette.watch
                            : palette.idle,
              ),
              SettingSwitch(
                title: 'Reconnect automatically',
                subtitle: 'Reattaches to the last module on launch and after a '
                    'dropout, with backoff.',
                icon: Icons.autorenew_rounded,
                value: settings.autoReconnect,
                onChanged: controller.setAutoReconnect,
              ),
              SettingSwitch(
                title: 'Require a live link',
                subtitle: 'On: the app stays locked until the module is '
                    'connected. Off: you can open stored history without it.',
                icon: Icons.lock_outline_rounded,
                value: settings.requireConnectionToBrowse,
                onChanged: controller.setRequireConnectionToBrowse,
              ),
              if (settings.hasRememberedDevice)
                SettingAction(
                  title: 'Forget ${settings.rememberedDeviceName}',
                  subtitle: settings.rememberedDeviceId,
                  icon: Icons.link_off_rounded,
                  destructive: true,
                  onTap: controller.forgetDevice,
                ),
              if (monitor.isConnected || monitor.usingSimulator)
                SettingAction(
                  title: 'Disconnect',
                  subtitle: 'Returns to the connection screen.',
                  icon: Icons.power_settings_new_rounded,
                  destructive: true,
                  onTap: monitor.disconnect,
                ),
              SettingAction(
                title: 'Reboot the board',
                subtitle: 'Watchdog reset. Readings resume within a second.',
                icon: Icons.restart_alt_rounded,
                enabled: monitor.isConnected && !monitor.usingSimulator,
                onTap: () async {
                  final confirmed = await _confirm(
                    context,
                    title: 'Reboot the Arduino?',
                    message: 'Cumulative volume counters restart from zero. '
                        'Stored history is untouched.',
                    confirmLabel: 'Reboot',
                  );
                  if (confirmed && context.mounted) {
                    await monitor.rebootDevice();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Data & storage
// =============================================================================

class _DataSection extends StatefulWidget {
  const _DataSection();

  @override
  State<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<_DataSection> {
  int? _rowCount;
  int? _sizeBytes;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStats());
  }

  Future<void> _loadStats() async {
    final monitor = context.read<MonitorController>();
    final rows = await monitor.readingCount();
    final size = await monitor.databaseSizeBytes();
    if (!mounted) return;
    setState(() {
      _rowCount = rows;
      _sizeBytes = size;
    });
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final monitor = context.read<MonitorController>();

    return FadeSlideIn(
      index: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeading(
            'Data & storage',
            icon: Icons.storage_outlined,
            subtitle: 'Readings are logged to an on-device SQLite database. '
                'Averages are computed from it, so history survives restarts and '
                'dropouts.',
          ),
          SettingGroup(
            children: <Widget>[
              SettingChoice<LoggingInterval>(
                title: 'Logging interval',
                subtitle: 'The board always streams at 1 Hz; this controls how '
                    'often a row is written. Rows record how many samples they '
                    'cover, so averages stay accurate either way.',
                icon: Icons.save_outlined,
                value: settings.loggingInterval,
                options: LoggingInterval.values,
                labelOf: (i) => i.label,
                descriptionOf: (i) => i.footprint,
                onChanged: controller.setLoggingInterval,
              ),
              SettingChoice<RetentionPolicy>(
                title: 'Keep history for',
                icon: Icons.history_rounded,
                value: settings.retention,
                options: RetentionPolicy.values,
                labelOf: (r) => r.label,
                onChanged: controller.setRetention,
              ),
              SettingSwitch(
                title: 'Prune automatically',
                subtitle: 'Removes rows past the retention window on launch.',
                icon: Icons.cleaning_services_outlined,
                value: settings.autoPrune,
                onChanged: controller.setAutoPrune,
              ),
              SettingInfo(
                title: 'Stored readings',
                icon: Icons.table_rows_outlined,
                value: _rowCount == null ? '…' : '$_rowCount',
                subtitle: _sizeBytes == null
                    ? null
                    : 'Database ${_formatBytes(_sizeBytes!)}',
              ),
              SettingAction(
                title: 'Export to CSV',
                subtitle: 'Writes canonical L/min values to the app documents '
                    'folder.',
                icon: Icons.file_download_outlined,
                onTap: () => _export(context),
              ),
              SettingAction(
                title: 'Prune now',
                subtitle: 'Apply the retention window immediately.',
                icon: Icons.content_cut_rounded,
                enabled: settings.retention.duration != null,
                onTap: () async {
                  final removed = await monitor.pruneNow();
                  await _loadStats();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Removed $removed readings')),
                  );
                },
              ),
              SettingAction(
                title: 'Clear all history',
                subtitle: 'Deletes every reading and event. Cannot be undone.',
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onTap: () async {
                  final confirmed = await _confirm(
                    context,
                    title: 'Delete all stored data?',
                    message: 'Every logged reading and every event in the log '
                        'will be removed. Daily, 3-day and weekly averages '
                        'restart from empty. This cannot be undone.',
                    confirmLabel: 'Delete everything',
                    destructive: true,
                  );
                  if (!confirmed) return;
                  await monitor.clearHistory();
                  await _loadStats();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('History cleared')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final monitor = context.read<MonitorController>();
    try {
      final csv = await monitor.exportCsv();
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(p.join(dir.path, 'leakguard-$stamp.csv'));
      await file.writeAsString(csv);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported to ${file.path}'),
          duration: const Duration(seconds: 6),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }
}

// =============================================================================
// About
// =============================================================================

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorController>();
    final controller = context.watch<SettingsController>();
    final config = monitor.deviceConfig;
    final palette = AppPalette.of(context);

    return FadeSlideIn(
      index: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeading('About', icon: Icons.info_outline),
          SettingGroup(
            children: <Widget>[
              const SettingInfo(
                title: 'App version',
                value: '1.0.0',
                icon: Icons.smartphone_outlined,
              ),
              SettingInfo(
                title: 'Firmware',
                value: config?.firmwareVersion ?? '—',
                icon: Icons.memory_rounded,
              ),
              SettingInfo(
                title: 'Link protocol',
                subtitle: 'App expects v$kProtocolVersion',
                value: config == null ? '—' : 'v${config.protocolVersion}',
                icon: Icons.swap_horiz_rounded,
                valueColor: config == null
                    ? null
                    : config.isCompatible
                        ? palette.normal
                        : palette.alert,
              ),
              SettingAction(
                title: 'Reset app settings',
                subtitle: 'Appearance, units, alerts and storage preferences. '
                    'Device tuning and stored readings are untouched.',
                icon: Icons.settings_backup_restore_rounded,
                destructive: true,
                onTap: () async {
                  final confirmed = await _confirm(
                    context,
                    title: 'Reset app settings?',
                    message: 'Everything returns to defaults, including the '
                        'remembered module.',
                    confirmLabel: 'Reset',
                  );
                  if (confirmed) await controller.resetAll();
                },
              ),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          Center(
            child: Text(
              'LeakGuard · Arduino Uno + HM-10 · 3-channel balance monitoring',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    fontSize: 11,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Shared confirm dialog
// =============================================================================

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final palette = AppPalette.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? palette.alert : palette.accent,
            foregroundColor:
                destructive ? Colors.white : Tokens.darkBackground,
            minimumSize: const Size(0, 44),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

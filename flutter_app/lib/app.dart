import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/settings/app_settings.dart';
import 'data/settings/settings_controller.dart';
import 'ui/root_view.dart';

/// Collapses [Appearance.system] onto the appearance the platform implies, and
/// returns the other three unchanged.
///
/// The platform exposes *brightness* and nothing else, so System resolves to
/// [Appearance.dark] or [Appearance.light] and **never** to
/// [Appearance.highContrastDark]. High contrast is an explicit request; there is
/// no OS signal that asks for it, and inferring it from dark mode would hand
/// every dark-mode user an appearance they did not choose.
Appearance resolveSystemAppearance(
  Appearance appearance,
  Brightness platformBrightness,
) {
  if (appearance != Appearance.system) return appearance;
  return platformBrightness == Brightness.dark
      ? Appearance.dark
      : Appearance.light;
}

/// The theme that renders [appearance] (Requirements 9.1, 9.2, 9.6).
///
/// There are three themes and `MaterialApp`'s `theme` / `darkTheme` pair can
/// only hold two, so the choice is made here rather than delegated to
/// `themeMode`. See [LeakGuardApp.build] for how the result is handed over.
ThemeData themeForAppearance(
  Appearance appearance,
  Brightness platformBrightness,
) {
  return switch (resolveSystemAppearance(appearance, platformBrightness)) {
    Appearance.highContrastDark => AppTheme.highContrastDark(),
    Appearance.light => AppTheme.light(),
    // Dark is the default, and System has already been collapsed onto Dark or
    // Light above, so it cannot reach this arm.
    Appearance.dark || Appearance.system => AppTheme.dark(),
  };
}

class LeakGuardApp extends StatelessWidget {
  const LeakGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;

    // Read unconditionally so this rebuilds when the OS flips brightness while
    // Follow system is selected. For the three explicit appearances the value is
    // ignored, at the cost of one wasted rebuild on an OS theme change.
    final theme = themeForAppearance(
      settings.appearance,
      MediaQuery.platformBrightnessOf(context),
    );

    // The system bars follow the *resolved* theme rather than the stored
    // setting, which is what keeps them right for all four values — including
    // High Contrast Dark, whose surface is Dark's surface unchanged.
    final palette = theme.extension<AppPalette>() ?? AppPalette.dark;
    final isDark = theme.brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: palette.surface,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'LeakGuard',
      debugShowCheckedModeBanner: false,
      // Both slots get the same resolved theme. MaterialApp picks between them
      // on `themeMode` and the platform brightness, neither of which can express
      // a third appearance, so the choice is made above and MaterialApp is left
      // with nothing to decide.
      theme: theme,
      darkTheme: theme,
      themeAnimationDuration: settings.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 380),
      themeAnimationCurve: Curves.easeOutCubic,
      home: const RootView(),
      builder: (context, child) {
        // Clamp text scaling: the monospaced KPI readouts are laid out to a fixed
        // grid and a 2x system font would break the dashboard.
        final scale = MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.35,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

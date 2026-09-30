import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design_tokens.dart';

/// Semantic colours that depend on brightness. Read them from a widget with
/// `AppPalette.of(context)` instead of branching on `Theme.of(context).brightness`
/// all over the UI.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentText,
    required this.alert,
    required this.normal,
    required this.watch,
    required this.idle,
    required this.gradientGreen,
    required this.alertBoxFill,
    required this.watchBoxFill,
    required this.normalBoxFill,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  /// The accent as a *graphical* colour: chart strokes, fills, indicators,
  /// gauges. Requirement 11.4 keeps this separate from [accentText], because
  /// passing as a graphic and passing as text are different thresholds.
  final Color accent;

  /// The accent as a *text and icon* colour.
  ///
  /// Aliases [accent] in both dark appearances, where cyan measures 10.84:1 on
  /// the card surface. The light appearance darkens it, because the light
  /// accent measures 3.74:1 and fails the 4.5:1 body-text threshold.
  final Color accentText;

  final Color alert;
  final Color normal;
  final Color watch;
  final Color idle;
  final Color gradientGreen;
  final Color alertBoxFill;
  final Color watchBoxFill;
  final Color normalBoxFill;

  static const AppPalette dark = AppPalette(
    background: Tokens.darkBackground,
    surface: Tokens.darkSurface,
    surfaceRaised: Tokens.darkSurfaceRaised,
    border: Tokens.darkBorder,
    textPrimary: Tokens.darkTextPrimary,
    textSecondary: Tokens.darkTextSecondary,
    accent: Tokens.accent,
    // 10.84:1 on #1E1E1E, so the graphical accent doubles as the text accent.
    accentText: Tokens.accent,
    alert: Tokens.alert,
    normal: Tokens.normal,
    watch: Tokens.watch,
    idle: Tokens.idle,
    gradientGreen: Tokens.gradientGreen,
    alertBoxFill: Tokens.alertBoxFill,
    watchBoxFill: Tokens.watchBoxFill,
    normalBoxFill: Tokens.normalBoxFill,
  );

  /// The High_Contrast_Dark appearance (Requirement 9.2).
  ///
  /// Built with [copyWith] off [dark] so no token is restated: `background`,
  /// `surface` and `surfaceRaised` are inherited *identically*, which is what
  /// keeps this appearance inside the WattVision §2 dark family. Only text and
  /// border contrast rise.
  static final AppPalette highContrastDark = dark.copyWith(
    textSecondary: Tokens.hcTextSecondary,
    border: Tokens.hcBorder,
    // Cyan already clears 4.5:1 on #1E1E1E; stated explicitly so the override
    // set reads as the complete answer to "what does high contrast change".
    accentText: Tokens.accent,
  );

  static const AppPalette light = AppPalette(
    background: Tokens.lightBackground,
    surface: Tokens.lightSurface,
    surfaceRaised: Tokens.lightSurfaceRaised,
    border: Tokens.lightBorder,
    textPrimary: Tokens.lightTextPrimary,
    textSecondary: Tokens.lightTextSecondary,
    accent: Tokens.lightAccent,
    // The darkened accent still measures only 3.74:1 on #FFFFFF, so text takes
    // a darker value again — Requirement 11.4.
    accentText: Tokens.lightAccentText,
    alert: Tokens.lightAlert,
    normal: Tokens.lightNormal,
    watch: Tokens.lightWatch,
    idle: Tokens.lightIdle,
    gradientGreen: Tokens.lightGradientGreen,
    alertBoxFill: Tokens.lightAlertBoxFill,
    watchBoxFill: Tokens.lightWatchBoxFill,
    normalBoxFill: Tokens.lightNormalBoxFill,
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? dark;

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? accentText,
    Color? alert,
    Color? normal,
    Color? watch,
    Color? idle,
    Color? gradientGreen,
    Color? alertBoxFill,
    Color? watchBoxFill,
    Color? normalBoxFill,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      accentText: accentText ?? this.accentText,
      alert: alert ?? this.alert,
      normal: normal ?? this.normal,
      watch: watch ?? this.watch,
      idle: idle ?? this.idle,
      gradientGreen: gradientGreen ?? this.gradientGreen,
      alertBoxFill: alertBoxFill ?? this.alertBoxFill,
      watchBoxFill: watchBoxFill ?? this.watchBoxFill,
      normalBoxFill: normalBoxFill ?? this.normalBoxFill,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      normal: Color.lerp(normal, other.normal, t)!,
      watch: Color.lerp(watch, other.watch, t)!,
      idle: Color.lerp(idle, other.idle, t)!,
      gradientGreen: Color.lerp(gradientGreen, other.gradientGreen, t)!,
      alertBoxFill: Color.lerp(alertBoxFill, other.alertBoxFill, t)!,
      watchBoxFill: Color.lerp(watchBoxFill, other.watchBoxFill, t)!,
      normalBoxFill: Color.lerp(normalBoxFill, other.normalBoxFill, t)!,
    );
  }
}

/// Monospaced numeric style helper — DESIGN.md §4 mandates a mono face for every
/// metric so digits do not jitter as values change.
class AppText {
  const AppText._();

  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing ?? -0.5,
      height: 1.1,
    );
  }

  static TextStyle kpi(BuildContext context, {Color? color}) => mono(
        size: Tokens.kpiSize,
        color: color ?? AppPalette.of(context).textPrimary,
      );
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);

  /// The High_Contrast_Dark appearance (Requirement 9.2).
  ///
  /// Built exactly as [dark] is, with [Brightness.dark], because it *is* a dark
  /// theme: [AppPalette.highContrastDark] inherits background, surface and
  /// surfaceRaised from [AppPalette.dark] untouched and only raises text and
  /// border contrast. Nothing in [_build] branches on anything but brightness
  /// and the palette, so this needs no special casing.
  static ThemeData highContrastDark() =>
      _build(Brightness.dark, AppPalette.highContrastDark);

  static ThemeData light() => _build(Brightness.light, AppPalette.light);

  /// Applies the Inter family to every slot of [source].
  ///
  /// `GoogleFonts.interTextTheme` would do this in one call, but google_fonts 9
  /// is built against the decoupled `material_ui` package, so its `TextTheme` is
  /// a different type from the framework's. `TextStyle` is still shared, so the
  /// styles are mapped one by one — same result, no cross-package type clash.
  static TextTheme _applyInter(TextTheme source) => TextTheme(
        displayLarge: GoogleFonts.inter(textStyle: source.displayLarge),
        displayMedium: GoogleFonts.inter(textStyle: source.displayMedium),
        displaySmall: GoogleFonts.inter(textStyle: source.displaySmall),
        headlineLarge: GoogleFonts.inter(textStyle: source.headlineLarge),
        headlineMedium: GoogleFonts.inter(textStyle: source.headlineMedium),
        headlineSmall: GoogleFonts.inter(textStyle: source.headlineSmall),
        titleLarge: GoogleFonts.inter(textStyle: source.titleLarge),
        titleMedium: GoogleFonts.inter(textStyle: source.titleMedium),
        titleSmall: GoogleFonts.inter(textStyle: source.titleSmall),
        bodyLarge: GoogleFonts.inter(textStyle: source.bodyLarge),
        bodyMedium: GoogleFonts.inter(textStyle: source.bodyMedium),
        bodySmall: GoogleFonts.inter(textStyle: source.bodySmall),
        labelLarge: GoogleFonts.inter(textStyle: source.labelLarge),
        labelMedium: GoogleFonts.inter(textStyle: source.labelMedium),
        labelSmall: GoogleFonts.inter(textStyle: source.labelSmall),
      );

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    final textTheme = _applyInter(base.textTheme).copyWith(
      // Titles: Inter Semi Bold 24 (DESIGN.md §4).
      titleLarge: GoogleFonts.inter(
        fontSize: Tokens.titleSize,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
        height: 1.2,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      // Body: Inter Regular 14.
      bodyMedium: GoogleFonts.inter(
        fontSize: Tokens.bodySize,
        fontWeight: FontWeight.w400,
        color: palette.textPrimary,
        height: 1.45,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: Tokens.labelSize,
        fontWeight: FontWeight.w400,
        color: palette.textSecondary,
        height: 1.4,
      ),
      // Labels are the grey metadata captions.
      labelLarge: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
        letterSpacing: 0.2,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: Tokens.labelSize,
        fontWeight: FontWeight.w500,
        color: palette.textSecondary,
        letterSpacing: 0.4,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: palette.textSecondary,
        letterSpacing: 0.8,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: brightness,
      ).copyWith(
        primary: palette.accent,
        onPrimary: brightness == Brightness.dark
            ? Tokens.onAccent
            : Tokens.lightOnAccent,
        surface: palette.surface,
        onSurface: palette.textPrimary,
        error: palette.alert,
      ),
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[palette],
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: Tokens.hairline,
        space: Tokens.hairline,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: BorderSide(color: palette.border, width: Tokens.hairline),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.accent.withValues(alpha: 0.16),
        height: 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            // Text, so the text accent — Requirement 11.4. The indicator behind
            // it stays on the graphical accent above.
            color: selected ? palette.accentText : palette.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? palette.accentText : palette.textSecondary,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: brightness == Brightness.dark
              ? Tokens.onAccent
              : Tokens.lightOnAccent,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusControl),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.border),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusControl),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        // A TextButton is a label on the surface behind it, with no fill of its
        // own, so its foreground is text — Requirement 11.4.
        style: TextButton.styleFrom(foregroundColor: palette.accentText),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.accent;
          return palette.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.accent.withValues(alpha: 0.28);
          }
          return palette.surfaceRaised;
        }),
        trackOutlineColor: WidgetStateProperty.all(palette.border),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.surfaceRaised,
        thumbColor: palette.accent,
        overlayColor: palette.accent.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceRaised,
        contentTextStyle: textTheme.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: BorderSide(color: palette.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Tokens.radiusCard),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Design tokens transcribed from `DESIGN.md` (WattVision system).
///
/// Everything visual in the app pulls from here — no ad-hoc hex codes in
/// widgets, and none in `app_theme.dart` either. The dark palette is the
/// canonical one. High_Contrast_Dark overrides two of its values and inherits
/// the rest. The light palette is a derived variant for the "Appearance"
/// setting, holding the same hues at darkened lightnesses so the product still
/// reads as the same system while staying legible on a light surface.
///
/// Every value here is recorded in `token_registry.dart`, which carries the
/// WattVision section it comes from, or — for the values WattVision does not
/// supply — the Requirement 1.9 rationale and consumer.
class Tokens {
  const Tokens._();

  // --- Dark palette (canonical, DESIGN.md §2) -------------------------------
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceRaised = Color(0xFF252525);
  static const Color darkBorder = Color(0xFF2C2C2E);

  // --- High_Contrast_Dark overrides (Requirement 9.2) -----------------------
  //
  // The high-contrast appearance stays inside the §2 dark family: background,
  // surface and surfaceRaised are inherited from Dark unchanged, and only text
  // and border contrast rise. Both values are declared Token_Extensions.

  /// Secondary text in High_Contrast_Dark. #98989D gives 5.81:1 on #1E1E1E;
  /// this lifts the same neutral to 9.90:1.
  static const Color hcTextSecondary = Color(0xFFC7C7CC);

  /// Hairline and chart-grid colour in High_Contrast_Dark. The §3 border
  /// #2C2C2E is deliberately subtle at 1.20:1 on #1E1E1E; this is the same
  /// hairline made visible at 1.83:1, without thickening it.
  static const Color hcBorder = Color(0xFF48484A);

  // --- Light palette (derived) ---------------------------------------------
  static const Color lightBackground = Color(0xFFF4F5F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceRaised = Color(0xFFECEEF1);
  static const Color lightBorder = Color(0xFFD9DDE3);

  // Light-appearance accents. The §2 accents are near-white in luminance, so
  // each is darkened for legibility on a light surface while holding its hue.
  static const Color lightAccent = Color(0xFF0091A7);
  static const Color lightAlert = Color(0xFFD3261C);
  static const Color lightNormal = Color(0xFF1E8E33);
  static const Color lightWatch = Color(0xFF9A7B00);
  static const Color lightIdle = Color(0xFF8E9299);

  /// Equal to [lightNormal] by construction: at the darkened lightness the
  /// light appearance needs, #32D74B and #30D158 converge on one value. The
  /// normal / gradientGreen distinction holds in the dark appearances only.
  static const Color lightGradientGreen = Color(0xFF1E8E33);

  // --- Accents (shared across both modes) ----------------------------------
  /// Primary data accent — charts, KPIs, primary actions.
  static const Color accent = Color(0xFF00E5FF);

  /// Alert accent — leaks, consumption spikes.
  static const Color alert = Color(0xFFFF453A);

  /// Secondary accent — "live" state and normal values.
  static const Color normal = Color(0xFF32D74B);

  /// Chart area-gradient partner for [accent].
  static const Color gradientGreen = Color(0xFF30D158);

  /// Advisory / not-yet-confirmed state. Amber sits between normal and alert.
  static const Color watch = Color(0xFFFFD60A);

  /// Offline / unknown.
  static const Color idle = Color(0xFF636366);

  // --- Accent as text (Requirement 11.4) -----------------------------------
  //
  // [accent] is a graphical colour first. On #1E1E1E it measures 10.84:1 and
  // is legible as text, so the dark appearances alias it; on a light surface
  // [lightAccent] measures 3.74:1 and fails the 4.5:1 body-text threshold, so
  // the light appearance needs a separate, darker text value.

  /// Accent-as-text for the light appearance: 5.79:1 on #FFFFFF.
  static const Color lightAccentText = Color(0xFF00707F);

  // --- Foreground on an accent fill ----------------------------------------

  /// Label and icon colour inside a filled accent button in the dark
  /// appearances. Equal to [darkBackground] by construction — white on
  /// #00E5FF fails contrast, so the background colour is reused.
  static const Color onAccent = Color(0xFF121212);

  /// The same foreground for the light appearance, where the accent is dark
  /// enough that white is the legible choice.
  static const Color lightOnAccent = Color(0xFFFFFFFF);

  // --- Text ----------------------------------------------------------------
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF98989D);
  static const Color lightTextPrimary = Color(0xFF121212);
  static const Color lightTextSecondary = Color(0xFF5B5F66);

  // --- Alert box (DESIGN.md §3) --------------------------------------------
  static const Color alertBoxFill = Color(0xFF3A1C1C);
  static const Color watchBoxFill = Color(0xFF3A331C);
  static const Color normalBoxFill = Color(0xFF17301C);

  // Light-appearance box fills: the §3 recipe inverted into lightened tints.
  static const Color lightAlertBoxFill = Color(0xFFFCE8E6);
  static const Color lightWatchBoxFill = Color(0xFFFBF3D9);

  /// The OK box fill for the light appearance.
  ///
  /// #E6F5E9 was the shipped value and sat at HSL saturation 0.429, inside the
  /// §6 pastel band and visibly washed out beside its two siblings (#FCE8E6 at
  /// 0.786 and #FBF3D9 at 0.810). This value carries the same green at
  /// saturation 0.592, which clears the pastel rule and matches the family.
  static const Color lightNormalBoxFill = Color(0xFFD8F5DF);

  // --- Geometry ------------------------------------------------------------
  /// Card radius from DESIGN.md §3.
  static const double radiusCard = 16;
  static const double radiusControl = 12;
  static const double radiusPill = 999;

  /// Card padding from DESIGN.md §3.
  static const double cardPadding = 20;
  static const double hairline = 1;

  // --- Spacing scale: multiples of 8 (DESIGN.md §5) ------------------------
  static const double s1 = 4; // half step, for tight icon gaps only
  static const double s2 = 8;
  static const double s3 = 16;
  static const double s4 = 24;
  static const double s5 = 32;
  static const double s6 = 40;
  static const double s7 = 48;

  // --- Type scale (DESIGN.md §4) -------------------------------------------
  static const double titleSize = 24;
  static const double kpiSize = 32;
  static const double bodySize = 14;
  static const double labelSize = 12;
}

/// Motion tokens. One place to tune the feel of the whole app.
class Motion {
  const Motion._();

  static const Duration instant = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration base = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 520);
  static const Duration ambient = Duration(milliseconds: 2200);

  /// Standard easing for entrances and layout changes.
  static const Curve enter = Curves.easeOutCubic;

  /// Exits move a little faster than entrances.
  static const Curve exit = Curves.easeInCubic;

  /// For value interpolation — never overshoots a numeric readout.
  static const Curve value = Curves.easeOutQuart;

  /// Playful but restrained; used for the connect success beat.
  static const Curve emphasized = Curves.easeOutBack;
}

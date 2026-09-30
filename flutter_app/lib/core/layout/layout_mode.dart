/// Layout_Engine — the authoritative width bands and per-mode grid metrics for
/// the Mobile_Client.
///
/// This module is the single source of truth on the Flutter side for the three
/// responsive bands (Requirement 2.1) and the per-mode gutter, outer padding
/// and content cap (Requirements 2.3–2.6). Its React counterpart,
/// `react_app/src/core/layout.ts`, holds the same numbers as the single
/// authority on that side, and Requirement 13.1 requires the two to agree.
///
/// It is intentionally dependency-light: pure Dart plus the token scale, no
/// Flutter widget imports. That lets the compliance suite and the parity
/// fixtures import it directly. The `InheritedWidget` that publishes the
/// resolved mode is a separate module (`layout_scope.dart`, task 5.3) and the
/// grid widgets are `lib/ui/layout/grid12.dart` (task 5.5).
library;

import '../theme/design_tokens.dart';
import '../theme/token_registry.dart';

/// The three responsive width bands (Requirement 2.1).
///
/// * [compact]  — viewport logical width below [Breakpoints.medium].
/// * [medium]   — from [Breakpoints.medium] up to (but not including)
///                [Breakpoints.expanded].
/// * [expanded] — [Breakpoints.expanded] and above.
enum LayoutMode { compact, medium, expanded }

/// The one authoritative threshold table (Requirement 2.1) and the Expanded
/// content cap (Requirement 2.6).
///
/// Boundary semantics are half-open and lower-inclusive, so a width belongs to
/// exactly one band with no gap and no overlap:
///
/// * width `< 600`                    → [LayoutMode.compact]
/// * `600 <= width < 1024`            → [LayoutMode.medium]
/// * `width >= 1024`                  → [LayoutMode.expanded]
///
/// Concretely: 599 → compact, **600 → medium**, 1023 → medium,
/// **1024 → expanded**, 1025 → expanded. This matches Requirement 2.1's
/// "Medium from 600 to 1023 inclusive, Expanded at 1024 and above".
class Breakpoints {
  const Breakpoints._();

  /// Lower bound of the Medium band. `>= 600` is Medium.
  static const double medium = 600; // Req 2.1

  /// Lower bound of the Expanded band. `>= 1024` is Expanded.
  static const double expanded = 1024; // Req 2.1

  /// Expanded content cap; the grid is centred within the viewport once wider.
  static const double contentMax = 1440; // Req 2.6

  /// Resolves a viewport logical [width] to exactly one [LayoutMode].
  ///
  /// This function is **total** — every finite `width`, including values below
  /// 320 and above 2560, resolves to a mode — and **exclusive** — exactly one
  /// band predicate holds (Property 1, proven by task 5.9). A sub-320 width
  /// still resolves to [LayoutMode.compact]; there is no floor below which the
  /// function is undefined.
  static LayoutMode resolve(double width) {
    if (width >= expanded) return LayoutMode.expanded;
    if (width >= medium) return LayoutMode.medium;
    return LayoutMode.compact;
  }
}

/// Per-[LayoutMode] grid metrics: the gutter between columns, the outer padding
/// around the grid, and the content-width cap (Requirements 2.3–2.6).
///
/// The triples are, in `gutter / outerPadding / contentMax` form:
///
/// | Mode     | gutter | outerPadding | contentMax |
/// |----------|--------|--------------|------------|
/// | compact  | 16     | 16           | 560        |
/// | medium   | 16     | 24           | none        |
/// | expanded | 24     | 32           | 1440       |
///
/// The gutter and padding values are all multiples of eight (Requirement 1.8)
/// and are taken from the WattVision §5 spacing scale ([Tokens.s3] = 16,
/// [Tokens.s4] = 24, [Tokens.s5] = 32) rather than repeated as bare literals.
/// This layout module is the authority for how those steps combine into the
/// per-mode triples; `design_tokens.dart` only owns the steps themselves.
///
/// The column count is not restated here — it is [kLayoutScale.columns] (12),
/// the registry's single record of the Grid_12 width.
///
/// `contentMax` is modelled as a nullable [double]: Medium has **no cap**,
/// represented as `null` rather than a `double.infinity` sentinel. That keeps
/// the Medium "no cap" case and the Expanded cap case (Property 3) each clean —
/// a `null` is unambiguously "do not clamp", and a non-null value is always a
/// real width to clamp to.
class GridMetrics {
  const GridMetrics._();

  /// Grid_12 always has this many columns (Requirement 2.7). Read from the
  /// registry so there is one place the column count lives.
  static int get columns => kLayoutScale.columns;

  /// Gutter between columns for [mode] (Requirements 2.3, 2.4).
  static double gutterFor(LayoutMode mode) {
    switch (mode) {
      case LayoutMode.compact:
        return Tokens.s3; // 16
      case LayoutMode.medium:
        return Tokens.s3; // 16
      case LayoutMode.expanded:
        return Tokens.s4; // 24
    }
  }

  /// Outer padding around the grid for [mode] (Requirements 2.3, 2.4, 2.5).
  static double outerPaddingFor(LayoutMode mode) {
    switch (mode) {
      case LayoutMode.compact:
        return Tokens.s3; // 16
      case LayoutMode.medium:
        return Tokens.s4; // 24
      case LayoutMode.expanded:
        return Tokens.s5; // 32
    }
  }

  /// Content-width cap for [mode], or `null` when the mode imposes no cap.
  ///
  /// Compact caps at 560 — the relocated legacy `.app` width (Requirement 2.10
  /// mitigation). Medium is uncapped (`null`). Expanded caps at
  /// [Breakpoints.contentMax] (Requirement 2.6).
  static double? contentMaxFor(LayoutMode mode) {
    switch (mode) {
      case LayoutMode.compact:
        return 560;
      case LayoutMode.medium:
        return null;
      case LayoutMode.expanded:
        return Breakpoints.contentMax; // 1440
    }
  }
}

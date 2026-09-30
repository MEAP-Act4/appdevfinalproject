/// Grid_12 — the Mobile_Client's twelve-column composition primitive
/// (Requirements 2.2–2.8, 11.10).
///
/// This module exposes three widgets:
///
///  * [Grid12Cell] — a value describing one cell: a `span` of 1..12 columns and
///    the `child` that fills it. The span is asserted to be an integer in
///    1..12 at construction, so Requirement 2.7 ("spans are integers 1..12") is
///    enforced at the type boundary rather than checked at layout time.
///  * [Grid12] — lays a `List<Grid12Cell>` out on twelve equal columns using
///    `LayoutBuilder` + `Wrap` + `SizedBox`. It owns the column arithmetic
///    (Requirements 2.2–2.5) and the row wrapping (Requirement 2.8).
///  * [Grid12Scaffold] — wraps a grid in the mode's outer padding and, for
///    Expanded, the 1440 content cap centred in the viewport (Requirement 2.6).
///
/// **Why `LayoutBuilder` + `Wrap` + `SizedBox`, not `GridView`.** `GridView` is
/// a scrollable that imposes a *uniform tile extent* on every child. The
/// dashboard needs the opposite: cells of wildly different intrinsic heights (a
/// compact KPI card, a tall chart, a scrolling alerts list) laid out inside one
/// outer scroll view. `GridView` would force either a fixed `childAspectRatio`
/// that clips content at 200% text scale — breaking Requirement 11.10 — or
/// nested scrollables. `Wrap` sizes each run to its tallest child, honours
/// intrinsic heights, and wraps overflow onto the next run, which is
/// Requirement 2.8 for free, the same way CSS Grid gives it to the Web_Client.
///
/// **The column arithmetic (Requirements 2.2–2.5).** Given the available
/// content width `maxWidth` and the mode's `gutter`, the width of a single
/// column is
///
/// ```
/// columnWidth = (maxWidth - gutter * 11) / 12
/// ```
///
/// because twelve columns are separated by eleven gutters. A cell spanning
/// `span` columns then covers those `span` columns *and* the `span - 1` gutters
/// between them, so
///
/// ```
/// cellWidth = columnWidth * span + gutter * (span - 1)
/// ```
///
/// This makes a run whose spans sum to exactly 12 fill `maxWidth` exactly:
/// `Σ(columnWidth·spanᵢ) + Σ(gutter·(spanᵢ-1))` over cells summing to 12
/// columns equals `12·columnWidth + gutter·(12 - n) `, and `Wrap` adds the `n-1`
/// inter-cell gutters back, recovering `12·columnWidth + 11·gutter = maxWidth`.
/// Property 2 (task 5.10) asserts that conservation; this file must get the
/// arithmetic exactly right for it to hold.
///
/// **Degenerate width (edge case, Requirement 2.2).** During a transient layout
/// pass the available width can be zero or negative. Rather than compute a
/// negative `columnWidth` and hand `SizedBox` a negative width, [Grid12] falls
/// back to a single full-width column: every cell is laid out at the available
/// width (clamped to be non-negative) and the grid degrades to a plain vertical
/// stack. This keeps layout total without ever producing a negative extent.
library;

import 'package:flutter/widgets.dart';

import '../../core/layout/layout_mode.dart';
import '../../core/layout/layout_scope.dart';

/// One cell in a [Grid12]: a [child] occupying [span] of the twelve columns.
///
/// [span] is asserted to be an integer in `1..12` at construction. That is
/// Requirement 2.7 enforced at the type boundary: an out-of-range span is a
/// programming error caught the moment the cell is built, not a layout that
/// silently misbehaves. The type is already `int`, so "is an integer" is the
/// static guarantee and the assert covers only the range.
@immutable
class Grid12Cell {
  /// Creates a cell spanning [span] columns (1..12) holding [child].
  const Grid12Cell({
    required this.span,
    required this.child,
  }) : assert(
          span >= 1 && span <= 12,
          'Grid12Cell.span must be an integer in 1..12, got $span.',
        );

  /// The number of columns this cell occupies, in `1..12`.
  final int span;

  /// The widget that fills the cell.
  final Widget child;
}

/// Lays a list of [Grid12Cell]s out on twelve equal columns.
///
/// Reads the current [LayoutMode] from [LayoutScope] to pick the gutter
/// ([GridMetrics.gutterFor]); measures the available width with a
/// [LayoutBuilder]; and places each cell in a [SizedBox] of the computed cell
/// width inside a [Wrap] that spaces cells and runs by the gutter. See the
/// library doc comment for the arithmetic and the degenerate-width fallback.
///
/// This widget does **not** apply the outer padding or the Expanded content
/// cap — that is [Grid12Scaffold]'s job, one level up. A bare [Grid12] fills
/// whatever width its parent gives it.
class Grid12 extends StatelessWidget {
  /// Creates a grid laying [children] out on twelve columns.
  const Grid12({super.key, required this.children});

  /// The cells to lay out, in order. `Wrap` packs them left-to-right, top-to-
  /// bottom, starting a new run whenever the next cell would overflow the
  /// available width (Requirement 2.8).
  final List<Grid12Cell> children;

  /// The fixed column count of Grid_12 (Requirement 2.7): twelve columns
  /// separated by eleven gutters.
  static const int columnCount = 12;

  @override
  Widget build(BuildContext context) {
    final mode = LayoutScope.of(context);
    final gutter = GridMetrics.gutterFor(mode);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // Degenerate width: fall back to a single full-width column rather than
        // computing a negative columnWidth (Requirement 2.2 edge case). A
        // non-finite maxWidth (unbounded parent) is treated the same way.
        if (!maxWidth.isFinite || maxWidth <= 0) {
          final fallbackWidth = maxWidth.isFinite && maxWidth > 0
              ? maxWidth
              : 0.0;
          return Wrap(
            spacing: gutter,
            runSpacing: gutter,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: <Widget>[
              for (final cell in children)
                SizedBox(width: fallbackWidth, child: cell.child),
            ],
          );
        }

        final columnWidth = (maxWidth - gutter * (columnCount - 1)) / columnCount;
        return Wrap(
          spacing: gutter,
          runSpacing: gutter,
          // Cells in a run share a top edge (Requirement 3.3).
          crossAxisAlignment: WrapCrossAlignment.start,
          children: <Widget>[
            for (final cell in children)
              SizedBox(
                width: cellWidthFor(
                  columnWidth: columnWidth,
                  gutter: gutter,
                  span: cell.span,
                ),
                child: cell.child,
              ),
          ],
        );
      },
    );
  }

  /// The width of a cell spanning [span] columns, given the [columnWidth] and
  /// the [gutter] between columns.
  ///
  /// A `span`-column cell covers `span` columns and the `span - 1` internal
  /// gutters between them: `columnWidth * span + gutter * (span - 1)`. Exposed
  /// (and static) so the example tests can pin the arithmetic on fixed inputs
  /// without pumping a widget, and so callers computing their own layout share
  /// the one definition.
  static double cellWidthFor({
    required double columnWidth,
    required double gutter,
    required int span,
  }) =>
      columnWidth * span + gutter * (span - 1);

  /// The width of a single column for a given available [maxWidth] and [gutter]:
  /// `(maxWidth - gutter * 11) / 12`. Exposed for the same reason as
  /// [cellWidthFor].
  static double columnWidthFor({
    required double maxWidth,
    required double gutter,
  }) =>
      (maxWidth - gutter * (columnCount - 1)) / columnCount;
}

/// Wraps a [Grid12] (or any grid content) in the current mode's outer padding
/// and, for Expanded, the 1440 content cap centred in the viewport
/// (Requirement 2.6).
///
/// Reads the [LayoutMode] from [LayoutScope]. The cap comes from
/// [GridMetrics.contentMaxFor]: a non-null value is a real width the content is
/// clamped to and centred within via `Center` + `ConstrainedBox`; a `null` cap
/// (Medium) means no clamp, so the [ConstrainedBox]/`Center` pair is skipped and
/// the content fills the padded width. The outer padding is always
/// [GridMetrics.outerPaddingFor], applied on all four sides.
///
/// Order matters: the cap is applied *inside* the padding, so the padding is
/// measured against the viewport edge and the capped content is centred in the
/// space the padding leaves. That matches the Web_Client's `margin-inline: auto`
/// + `padding-inline` on `.grid12`.
class Grid12Scaffold extends StatelessWidget {
  /// Creates a scaffold applying the mode's padding and cap around [child].
  const Grid12Scaffold({super.key, required this.child});

  /// The grid content to centre and pad — typically a [Grid12].
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mode = LayoutScope.of(context);
    final padding = GridMetrics.outerPaddingFor(mode);
    final cap = GridMetrics.contentMaxFor(mode);

    // A null cap (Medium) means "do not clamp": fill the padded width.
    Widget content = child;
    if (cap != null) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cap),
          child: child,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(padding),
      child: content,
    );
  }
}

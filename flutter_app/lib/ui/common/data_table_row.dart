import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';

/// The table-row styling primitive from DESIGN.md's "Table row styling" section
/// (Requirements 8.1, 8.2, 8.3).
///
/// One reusable row, two call sites: the Calibration_Table (task 15.3) and the
/// Alert_Entry rows (task 15.5) both wrap their content in a [DataTableRow], so
/// the hover, focus and border treatment lives in exactly one place —
/// Requirement 8.4's "same bottom border and the same `#252525` hover and focus
/// background".
///
/// Built on [FocusableActionDetector] rather than a hand-rolled
/// [MouseRegion] + [Focus] pair. That widget surfaces both
/// `onShowHoverHighlight` and `onShowFocusHighlight` through a single node and
/// already threads focus into the traversal order, which is what makes a row
/// keyboard-reachable without extra wiring. Its two callbacks feed local state:
///
///   * hovered OR focused paints the row background in [AppPalette.surfaceRaised]
///     — the `#252525` row-hover token of DESIGN.md §2. The hover background of
///     Requirement 8.2 and the focus background of Requirement 8.3 are the same
///     colour, so one flag drives both (Requirement 8.4 uses it again for the
///     Alert_Entry rows);
///   * focus additionally draws a visible focus indicator (Requirement 8.3): a
///     ring in [AppPalette.accent] inset just inside the row. Task 11.7 will
///     hold this to a measured 3:1 contrast; here it is a clearly visible
///     outline, kept a graphical (non-text) use of the accent per
///     Requirement 11.4.
///
/// A 1-wide bottom border in [AppPalette.border] (`#2C2C2E`) is always present
/// (Requirement 8.1), independent of hover and focus.
///
/// The row takes generic [child] content and an optional [onTap]. When [onTap]
/// is set the row activates on pointer tap and on Enter or Space from the
/// keyboard, so a focusable row is also operable without a mouse.
class DataTableRow extends StatefulWidget {
  const DataTableRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Tokens.s3,
      vertical: Tokens.s2,
    ),
    this.focusNode,
    this.autofocus = false,
  });

  /// The row content — a [Row] of cells at the Calibration_Table call site, an
  /// Alert_Entry summary at the alerts call site. Kept opaque so the primitive
  /// stays generic.
  final Widget child;

  /// Invoked on pointer tap and on Enter/Space while focused. When null the row
  /// is still hover- and focus-highlighted but carries no activation.
  final VoidCallback? onTap;

  /// Inner padding around [child]. Defaults to the 16/8 spacing-scale inset.
  final EdgeInsetsGeometry padding;

  /// An externally owned focus node, if the caller wants to drive focus. When
  /// null [FocusableActionDetector] manages its own.
  final FocusNode? focusNode;

  final bool autofocus;

  @override
  State<DataTableRow> createState() => _DataTableRowState();
}

class _DataTableRowState extends State<DataTableRow> {
  bool _hovered = false;
  bool _focused = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final onTap = widget.onTap;

    // Hover and focus share the one raised background (Requirements 8.2, 8.3).
    final highlighted = _hovered || _focused;

    // The activation intent -> callback wiring. Only present when there is an
    // onTap to invoke, so a read-only row adds nothing to the shortcut map.
    final Map<Type, Action<Intent>> actions = onTap == null
        ? const <Type, Action<Intent>>{}
        : <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onTap();
                return null;
              },
            ),
          };

    const shortcuts = <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    };

    Widget row = FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      // A row with no activation is still focusable so it can be tracked across
      // with the keyboard, but it is skipped by traversal when there is nothing
      // to do — mouse hover still highlights it either way.
      enabled: true,
      mouseCursor:
          onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      shortcuts: onTap == null ? const <ShortcutActivator, Intent>{} : shortcuts,
      actions: actions,
      onShowHoverHighlight: _setHovered,
      onShowFocusHighlight: _setFocused,
      child: Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          // Hover OR focus -> surfaceRaised (#252525); otherwise transparent so
          // the surface behind the table shows through.
          color: highlighted ? palette.surfaceRaised : Colors.transparent,
          // Always a 1px bottom hairline in the border token (Requirement 8.1).
          border: Border(
            bottom: BorderSide(color: palette.border, width: Tokens.hairline),
          ),
        ),
        child: widget.child,
      ),
    );

    // The visible focus indicator (Requirement 8.3): an accent ring drawn over
    // the row only while focused. Layered above so it never shifts the row's
    // size — the border below stays put whether focused or not.
    if (_focused) {
      row = Stack(
        children: <Widget>[
          row,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: palette.accent, width: 2),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (onTap == null) return row;

    // A transparent Material lets the row take taps without painting a second
    // opaque layer over the surfaceRaised highlight. The InkWell is kept off
    // the focus and hover paths (`canRequestFocus: false`, `excludeFromSemantics`
    // left default) so the [FocusableActionDetector] above stays the single
    // focus stop and the single hover source per row; the InkWell only supplies
    // the pointer splash. Keyboard activation is handled by the
    // shortcuts/actions above.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        splashColor: palette.accent.withValues(alpha: 0.08),
        highlightColor: palette.accent.withValues(alpha: 0.05),
        child: row,
      ),
    );
  }
}

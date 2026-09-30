/// Layout_Engine — the `InheritedWidget` that publishes the already-resolved
/// [LayoutMode] down the Mobile_Client widget tree.
///
/// This module owns *distribution* only, not resolution. The width bands and
/// per-mode grid metrics live in `layout_mode.dart`; the site that turns a
/// `LayoutBuilder`'s constraints into a [LayoutMode] and wraps the app in a
/// [LayoutScope] is `lib/ui/root_view.dart` (task 5.8). By the time a mode
/// reaches this widget it has already been resolved, so [LayoutScope] takes a
/// [LayoutMode] and a `child` and does nothing but carry the mode.
///
/// **Why an `InheritedWidget` (Requirement 2.1).** The mode is derived from
/// build-time constraints, not from mutable application state, so a
/// `ChangeNotifier` would model it wrongly. `InheritedWidget` is also already
/// the mechanism carrying `AppPalette` down the tree via `ThemeExtension`, so
/// this is the established pattern in this codebase rather than a new one.
///
/// **The rebuild economy (Requirement 2.9).** [updateShouldNotify] compares
/// only the [LayoutMode] enum. A `LayoutBuilder` rebuilds its builder callback
/// on every pixel of a drag-resize, so the builder above reconstructs a
/// [LayoutScope] on every frame — but a new [LayoutScope] whose `mode` equals
/// the old one returns `false` here, so dependents are *not* notified. Only a
/// genuine band change (Compact→Medium→Expanded) notifies. Dependents therefore
/// rebuild on a band change and never on a sub-band pixel resize.
library;

import 'package:flutter/widgets.dart';

import 'layout_mode.dart';

/// Carries the resolved [LayoutMode] to descendants.
///
/// Construct it around a `const` child inside the single `LayoutBuilder` that
/// resolves the mode (task 5.8); everything below can then read the current
/// band with [of] without re-resolving width itself.
class LayoutScope extends InheritedWidget {
  /// Creates a scope publishing [mode] to [child]'s subtree.
  const LayoutScope({
    super.key,
    required this.mode,
    required super.child,
  });

  /// The resolved responsive band for this subtree.
  final LayoutMode mode;

  /// The current [LayoutMode], establishing a dependency so the caller rebuilds
  /// when the band changes.
  ///
  /// Asserts that a [LayoutScope] is present above [context]. This is the
  /// deliberate choice for the common case: every widget that reads the layout
  /// band is mounted under the `RootView` scope, so a missing scope is a
  /// programming error worth failing loudly (with a message that names the fix)
  /// rather than papering over with a silent default that would render the
  /// wrong layout. Callers that legitimately may run outside a scope — e.g. a
  /// widget reused in isolation in a test or a preview — should use [maybeOf]
  /// and supply their own fallback.
  static LayoutMode of(BuildContext context) {
    final scope = maybeOf(context);
    assert(
      scope != null,
      'LayoutScope.of() called with a context that has no LayoutScope '
      'ancestor.\n'
      'A LayoutScope is installed by RootView around the app. Ensure the '
      'widget calling LayoutScope.of() is a descendant of that scope, or use '
      'LayoutScope.maybeOf() and provide a fallback if the widget may be built '
      'outside it.',
    );
    return scope ?? LayoutMode.compact;
  }

  /// The current [LayoutMode], or `null` when there is no [LayoutScope] above
  /// [context].
  ///
  /// Like [of], this establishes a dependency, so the caller rebuilds on a band
  /// change. Use this when the absence of a scope is a valid state the caller
  /// can handle itself.
  static LayoutMode? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayoutScope>()?.mode;

  /// Dependents rebuild only when the [LayoutMode] band changes — never on a
  /// pixel-by-pixel resize within the same band (Requirement 2.9).
  @override
  bool updateShouldNotify(LayoutScope oldWidget) => oldWidget.mode != mode;
}

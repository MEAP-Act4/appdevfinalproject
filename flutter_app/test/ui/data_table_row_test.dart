/// Widget tests for the [DataTableRow] primitive (task 15.1).
///
/// Requirements 8.1, 8.2, 8.3.
///
/// What is asserted:
///
///   * a resting row draws no highlight fill and a 1-wide bottom border in the
///     border token `#2C2C2E` (Requirement 8.1);
///   * pointer hover paints the row background in the surfaceRaised token
///     `#252525` (Requirement 8.2);
///   * keyboard focus paints the same surfaceRaised background AND adds a
///     visible focus indicator ring in the accent token (Requirement 8.3);
///   * Enter activates the row's onTap while it holds keyboard focus.
///
/// The decoration is read straight off the [Container] the primitive builds, so
/// the assertions check the painted colours rather than a proxy.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/core/theme/design_tokens.dart';
import 'package:leakguard/ui/common/data_table_row.dart';

/// The [DataTableRow]'s own decorated [Container]: the one whose decoration
/// carries a bottom [Border] and (when highlighted) the fill colour. Excludes
/// any Material/InkWell ancestors, which have no such border.
BoxDecoration _rowDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(DataTableRow),
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border is Border &&
            ((w.decoration as BoxDecoration).border as Border).bottom.width ==
                Tokens.hairline,
      ),
    ),
  );
  return container.decoration! as BoxDecoration;
}

/// True when a focus-indicator ring in the accent colour is painted. The ring
/// is the [DecoratedBox] the primitive layers in only while focused, bordered
/// on all four sides in the accent.
bool _hasAccentFocusRing(WidgetTester tester, Color accent) {
  final rings = find.descendant(
    of: find.byType(DataTableRow),
    matching: find.byWidgetPredicate((Widget w) {
      if (w is! DecoratedBox) return false;
      final decoration = w.decoration;
      if (decoration is! BoxDecoration) return false;
      final border = decoration.border;
      return border is Border && border.top.color == accent;
    }),
  );
  return rings.evaluate().isNotEmpty;
}

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onTap,
  FocusNode? focusNode,
}) async {
  // FocusableActionDetector only surfaces its hover and focus highlights while
  // the focus highlight mode is "traditional" (pointer/keyboard navigation), so
  // that touch taps do not paint focus rings. A programmatic requestFocus in a
  // test leaves the mode at its touch default, which would suppress the very
  // highlights under test. Pinning the strategy to alwaysTraditional models the
  // desktop/keyboard case these criteria describe.
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic;
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: DataTableRow(
              onTap: onTap,
              focusNode: focusNode,
              child: const Text('cell'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a resting row has no highlight fill and a 1px bottom border in the '
    'border token #2C2C2E (Requirement 8.1)',
    (tester) async {
      await _pump(tester);

      final decoration = _rowDecoration(tester);
      final border = decoration.border! as Border;

      expect(border.bottom.width, Tokens.hairline);
      expect(border.bottom.color, AppPalette.dark.border);
      expect(AppPalette.dark.border, Tokens.darkBorder); // == #2C2C2E
      // Resting: transparent fill (no hover, no focus).
      expect(decoration.color, Colors.transparent);
    },
  );

  testWidgets(
    'pointer hover paints the surfaceRaised background #252525 '
    '(Requirement 8.2)',
    (tester) async {
      await _pump(tester);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(tester.getCenter(find.byType(DataTableRow)));
      await tester.pumpAndSettle();

      final decoration = _rowDecoration(tester);
      expect(decoration.color, AppPalette.dark.surfaceRaised);
      expect(AppPalette.dark.surfaceRaised, Tokens.darkSurfaceRaised); // #252525
    },
  );

  testWidgets(
    'keyboard focus paints the surfaceRaised background AND a visible accent '
    'focus indicator (Requirement 8.3)',
    (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await _pump(tester, onTap: () {}, focusNode: focusNode);

      focusNode.requestFocus();
      await tester.pumpAndSettle();

      final decoration = _rowDecoration(tester);
      // Same #252525 background as hover.
      expect(decoration.color, AppPalette.dark.surfaceRaised);
      // Plus a visible focus indicator ring in the accent.
      expect(_hasAccentFocusRing(tester, AppPalette.dark.accent), isTrue);
    },
  );

  testWidgets(
    'Enter activates onTap while the row holds keyboard focus',
    (tester) async {
      var taps = 0;
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await _pump(tester, onTap: () => taps++, focusNode: focusNode);

      focusNode.requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(taps, 1);
    },
  );
}

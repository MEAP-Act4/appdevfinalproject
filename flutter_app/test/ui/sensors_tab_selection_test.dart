/// Widget examples for the carousel page-index wiring (task 9.4).
///
/// Requirements 4.1, 4.3, 4.4.
///
/// **What is under test.** Task 9.4 removed `_SensorsTabState._page` and made
/// the shared [SelectionController] the single owner of "which sensor is on
/// screen". The contract has two halves:
///
///   1. the `PageController` is seeded from the controller **once, at mount**,
///      so a carousel that mounts after the Dashboard_View left channel 2
///      selected opens on page 2 (Requirement 4.4); and
///   2. `onPageChanged` is the **sole writer** back to the controller — no
///      listener drives the page — so a settled page change records the new
///      selection exactly once and never re-enters through a
///      notify -> animate -> write-back loop (Requirement 4.3).
///
/// **Why the harness, not `SensorsTab` directly.** `SensorsTab` reads a
/// [MonitorController], whose constructor opens an `AppDatabase` (sqflite) that
/// is unavailable under `flutter_test` — the same reason `channel_view_test.dart`
/// and `channel_kpi_card_test.dart` build stand-ins rather than the real
/// controller. This harness reproduces the exact `_SensorsTabState` wiring
/// verbatim (seed `PageController(initialPage:)` from `context.read` in
/// `initState`; `onPageChanged` calls `selectChannel`; the page index is read
/// back through `context.select`) around a real `SelectionController` and a
/// real `PageView`, so the seed-once and single-writer behaviour is exercised
/// against the genuine controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/protocol/leak_protocol.dart';
import 'package:leakguard/state/selection_controller.dart';
import 'package:provider/provider.dart';

/// A minimal mirror of `_SensorsTabState`'s carousel wiring, carrying no
/// dependency on `MonitorController`/`SettingsController`.
class _CarouselHarness extends StatefulWidget {
  const _CarouselHarness();

  @override
  State<_CarouselHarness> createState() => _CarouselHarnessState();
}

class _CarouselHarnessState extends State<_CarouselHarness> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    // Seed once, at mount, from the shared selection.
    final selected = context.read<SelectionController>().selectedChannel;
    _pageController = PageController(initialPage: selected);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Read the selection through select() so a rebuild happens on a channel
    // change only, matching the tab. No listener animates the page here — the
    // page is driven by the user and by the seed, never fed back.
    final page = context.select<SelectionController, int>(
      (controller) => controller.selectedChannel,
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: <Widget>[
          Text('page:$page', textDirection: TextDirection.ltr),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: kSensorCount,
              onPageChanged: (index) =>
                  context.read<SelectionController>().selectChannel(index),
              itemBuilder: (context, index) => Center(
                child: Text('sensor:$index', textDirection: TextDirection.ltr),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, SelectionController controller) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SelectionController>.value(
      value: controller,
      child: const MediaQuery(
        data: MediaQueryData(size: Size(400, 800)),
        child: _CarouselHarness(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The page the [PageView] is actually showing, read from its controller.
int _visiblePage(WidgetTester tester) {
  final view = tester.widget<PageView>(find.byType(PageView));
  return view.controller!.page!.round();
}

void main() {
  group('carousel page index (task 9.4)', () {
    testWidgets('seeds the page from the controller once at mount', (
      tester,
    ) async {
      // The Dashboard_View left channel 2 selected before this carousel mounts.
      final controller = SelectionController(selectedChannel: 2);
      await _pump(tester, controller);

      // The carousel opens on page 2 — Requirement 4.4.
      expect(_visiblePage(tester), 2);
      expect(find.text('page:2'), findsOneWidget);
      expect(controller.selectedChannel, 2);
    });

    testWidgets('a settled page change writes the selection exactly once', (
      tester,
    ) async {
      final controller = SelectionController();
      var notifications = 0;
      controller.addListener(() => notifications++);
      await _pump(tester, controller);

      // Fling to the next page and let the settle complete: onPageChanged is
      // the only path that touches the controller.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      expect(controller.selectedChannel, 1);
      expect(find.text('page:1'), findsOneWidget);
      // Exactly one notification — the single write from onPageChanged. A
      // feedback loop would have produced more than one.
      expect(notifications, 1);
    });

    testWidgets('no write-back loop: the page rests after one change', (
      tester,
    ) async {
      final controller = SelectionController();
      await _pump(tester, controller);

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // Pumping further frames must not move the page again — proof the
      // controller notify does not re-drive the PageController.
      final settled = _visiblePage(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(_visiblePage(tester), settled);
      expect(_visiblePage(tester), 1);
      expect(controller.selectedChannel, 1);
    });
  });
}

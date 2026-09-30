/// Sanity example tests for the Layout_Engine bands and per-mode grid metrics
/// (task 5.1).
///
/// This is deliberately the small, example-shaped companion to the property
/// tests that arrive later: Property 1 (totality/exclusivity of `resolve`,
/// task 5.9), Property 2 (grid arithmetic, task 5.10) and Property 3 (the
/// Expanded cap). Those state the invariants over generated inputs; this file
/// pins the exact boundary values the design fixes so a regression on
/// 599/600/1023/1024/1025 fails here immediately and unambiguously, and it
/// pins the per-mode gutter/padding/contentMax triples that
/// `react_app/src/core/layout.ts` must agree with (Requirement 13.1).
///
/// Requirements 2.1, 2.3, 2.4, 2.5, 2.6.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';
import 'package:leakguard/core/theme/token_registry.dart';

void main() {
  group('Breakpoints.resolve — band boundaries (Req 2.1)', () {
    test('the documented boundary values resolve as stated', () {
      // Below 600 → compact.
      expect(Breakpoints.resolve(599), LayoutMode.compact);
      // 600 inclusive → medium.
      expect(Breakpoints.resolve(600), LayoutMode.medium);
      // 1023 inclusive → medium.
      expect(Breakpoints.resolve(601), LayoutMode.medium);
      expect(Breakpoints.resolve(1023), LayoutMode.medium);
      // 1024 and above → expanded.
      expect(Breakpoints.resolve(1024), LayoutMode.expanded);
      expect(Breakpoints.resolve(1025), LayoutMode.expanded);
    });

    test('resolve is total across [320, 2560] and beyond', () {
      // Every integer width in the responsive range resolves to some mode, and
      // it agrees with exactly one band predicate.
      for (var w = 320; w <= 2560; w++) {
        final mode = Breakpoints.resolve(w.toDouble());
        final isCompact = w < Breakpoints.medium;
        final isMedium = w >= Breakpoints.medium && w < Breakpoints.expanded;
        final isExpanded = w >= Breakpoints.expanded;

        // Exactly one band predicate holds (exclusivity).
        final holding = <bool>[isCompact, isMedium, isExpanded]
            .where((held) => held)
            .length;
        expect(holding, 1, reason: 'width $w matched $holding bands');

        // The returned mode is the one whose predicate holds.
        final expected = isCompact
            ? LayoutMode.compact
            : isMedium
                ? LayoutMode.medium
                : LayoutMode.expanded;
        expect(mode, expected, reason: 'width $w');
      }
    });

    test('sub-320 and very wide widths still resolve (totality)', () {
      expect(Breakpoints.resolve(0), LayoutMode.compact);
      expect(Breakpoints.resolve(1), LayoutMode.compact);
      expect(Breakpoints.resolve(319), LayoutMode.compact);
      expect(Breakpoints.resolve(5000), LayoutMode.expanded);
    });

    test('the threshold constants themselves are fixed (Req 2.1, 2.6)', () {
      expect(Breakpoints.medium, 600);
      expect(Breakpoints.expanded, 1024);
      expect(Breakpoints.contentMax, 1440);
    });
  });

  group('GridMetrics — per-mode triples (Req 2.3–2.6)', () {
    test('compact is 16 / 16 / 560', () {
      expect(GridMetrics.gutterFor(LayoutMode.compact), 16);
      expect(GridMetrics.outerPaddingFor(LayoutMode.compact), 16);
      expect(GridMetrics.contentMaxFor(LayoutMode.compact), 560);
    });

    test('medium is 16 / 24 / none', () {
      expect(GridMetrics.gutterFor(LayoutMode.medium), 16);
      expect(GridMetrics.outerPaddingFor(LayoutMode.medium), 24);
      expect(GridMetrics.contentMaxFor(LayoutMode.medium), isNull);
    });

    test('expanded is 24 / 32 / 1440', () {
      expect(GridMetrics.gutterFor(LayoutMode.expanded), 24);
      expect(GridMetrics.outerPaddingFor(LayoutMode.expanded), 32);
      expect(GridMetrics.contentMaxFor(LayoutMode.expanded), 1440);
    });

    test('every gutter and padding is a multiple of eight (Req 1.8)', () {
      for (final mode in LayoutMode.values) {
        expect(GridMetrics.gutterFor(mode) % 8, 0, reason: '$mode gutter');
        expect(GridMetrics.outerPaddingFor(mode) % 8, 0,
            reason: '$mode padding');
      }
    });

    test('column count is the registry authority, not a literal', () {
      expect(GridMetrics.columns, kLayoutScale.columns);
      expect(GridMetrics.columns, 12);
    });
  });
}

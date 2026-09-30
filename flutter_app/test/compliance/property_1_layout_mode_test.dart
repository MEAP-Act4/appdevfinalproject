/// Property 1 — Layout_Mode resolution is total and exclusive.
/// Mobile_Client half.
///
/// *For any* viewport width in the responsive range, [Breakpoints.resolve]
/// returns a non-null [LayoutMode], exactly one of the three band predicates
/// holds, and the returned mode is the one whose predicate holds. The bands
/// are half-open and lower-inclusive:
///
/// * `w < 600`            → [LayoutMode.compact]
/// * `600 <= w < 1024`    → [LayoutMode.medium]
/// * `w >= 1024`          → [LayoutMode.expanded]
///
/// **Validates: Requirements 2.1, 2.11**
///
/// **How this differs from `layout_mode_test.dart` (task 5.1).** That file is
/// the worked-examples baseline: it pins the six boundary widths
/// (599/600/601/1023/1024/1025), a hand-written totality/exclusivity sweep over
/// the integer range, and a handful of sub-320 and very-wide values. This file
/// states the same two obligations — totality and exclusivity — as a property
/// over *generated* widths, integer and real, drawn across `[320, 2560]` and
/// biased so the same six boundary widths are always visited through
/// `examples:` before the generated draws. A resolver that was right on the
/// sampled boundaries but wrong on some other width becomes a shrunk
/// counterexample here rather than escaping.
///
/// The two boundary constants `600` and `1024` are read from [Breakpoints]
/// rather than restated, so the property checks the implementation against its
/// own single authority and the breakpoint scanner (task 1.9's Flutter twin)
/// has nothing new to flag. The bias widths 599..1025 are plain generator
/// inputs, not media-query thresholds.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/layout/layout_mode.dart';

import '../support/props.dart';

/// The band a width belongs to according to the spec, stated independently of
/// [Breakpoints.resolve] so the property checks the resolver against the
/// requirement rather than against itself. Uses the same authoritative
/// thresholds so 600/1024 are never restated as literals here.
LayoutMode _expectedBand(double width) {
  final isCompact = width < Breakpoints.medium;
  final isMedium = width >= Breakpoints.medium && width < Breakpoints.expanded;
  if (isCompact) return LayoutMode.compact;
  if (isMedium) return LayoutMode.medium;
  return LayoutMode.expanded;
}

/// Asserts the property's three clauses on a single [width]:
/// resolution is total (returns a value), exclusive (exactly one predicate
/// holds), and correct (the returned mode is the one whose predicate holds).
void _checkResolution(double width) {
  final mode = Breakpoints.resolve(width);

  // Totality: `resolve` returns one of the three modes. `mode` is non-nullable
  // in Dart, so reaching here at all is the totality guarantee; assert it is a
  // real enum member for good measure.
  expect(
    LayoutMode.values.contains(mode),
    isTrue,
    reason: 'resolve($width) must return a LayoutMode',
  );

  // Exclusivity: exactly one band predicate holds.
  final isCompact = width < Breakpoints.medium;
  final isMedium = width >= Breakpoints.medium && width < Breakpoints.expanded;
  final isExpanded = width >= Breakpoints.expanded;
  final holding = <bool>[isCompact, isMedium, isExpanded]
      .where((held) => held)
      .length;
  expect(holding, 1, reason: 'width $width matched $holding bands');

  // Correctness: the returned mode is the one whose predicate holds.
  expect(mode, _expectedBand(width), reason: 'width $width');
}

void main() {
  group('Property 1 — Layout_Mode resolution (Mobile_Client)', () {
    // The six boundary widths the design fixes, always visited before the
    // generated draws so the bias is exhaustive rather than probabilistic.
    const boundaryWidths = <double>[599, 600, 601, 1023, 1024, 1025];

    // Integer widths in [320, 2560], biased towards the six boundaries.
    forAll<int>(
      'resolve is total, exclusive and correct over integer widths',
      any.biasedTowards<int>(
        any.intBetween(320, 2560),
        boundaryWidths.map((w) => w.toInt()).toList(),
      ),
      (width) => _checkResolution(width.toDouble()),
      examples: boundaryWidths.map((w) => w.toInt()).toList(),
    );

    // Real widths in [320, 2560], biased towards the six boundaries. Reals
    // exercise the half-open boundary semantics between integers as well.
    forAll<double>(
      'resolve is total, exclusive and correct over real widths',
      any.biasedTowards<double>(
        any.doubleBetween(320, 2560),
        boundaryWidths,
      ),
      _checkResolution,
      examples: boundaryWidths,
    );

    // Totality extends below the responsive floor too: a sub-320 width still
    // resolves rather than being undefined (Requirement 2.11).
    forAll<double>(
      'resolve is total, exclusive and correct below the responsive floor',
      any.doubleBetween(0, 319),
      _checkResolution,
      examples: const <double>[0, 1, 100, 319],
    );
  });
}

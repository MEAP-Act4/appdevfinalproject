/// Property 21 — every spacing token is a multiple of eight and every
/// Token_Extension is documented. Mobile_Client half.
///
/// Requirements 1.8 and 1.9.
///
/// **How this differs from `wattvision_constants_test.dart` (task 1.10).** That
/// file pins the registry *as it stands today*: it walks `kTokenExtensions`
/// once with a `for` loop and asserts the Requirement 1.9 rationale/consumer
/// obligation over exactly the entries present, and it pins the fixed §5
/// constants in `kLayoutScale` — twelve columns, base 8, the four enumerated
/// steps 8/16/24/32. Those are example tests over a fixed table, which is the
/// right shape for a criterion that names exact values.
///
/// This file is the **property** form of the same two obligations. The input is
/// the registry itself — the layout-spacing set and the Token_Extension set —
/// drawn through the generator harness rather than iterated inline, so the
/// invariant is stated over *whatever those sets contain* rather than over
/// today's membership. Phase 2 adds `accentText` and the High_Contrast_Dark
/// overrides, phases 3 and 5 add layout values; each new entry is a new input
/// to these properties with no edit here. The two forms are complementary: the
/// example test catches a changed value, the property catches an added entry
/// that does not satisfy the rule.
///
/// **The multiple-of-8 filter is data-driven, not an exception list.** Both
/// registries carry `layoutSpacing` for exactly this purpose: it marks the
/// values Requirement 1.8 is about — layout gaps, gutters and outer padding —
/// and leaves everything else out of scope. Two length entries are deliberately
/// **not** selected, and neither is a multiple of eight:
///
/// * `s1` (4px) — an intra-component inset, a half-step below the §5 scale;
/// * `cardPadding` (20px) — a WattVision §3 component value, not a layout gap.
///
/// A filter is only trustworthy if it is doing work, so the `flag does real
/// work` group asserts that both of those exist, that both really do fail the
/// modulo test, and that both are excluded — and that the selected set is
/// non-empty and covers every enumerated §5 step. Without that, flipping every
/// flag to `false` would leave this property passing vacuously.
///
/// The bidirectional registry/stylesheet clause of Property 21 is not restated
/// here. The web side pins it exhaustively over the finite declaration set in
/// `react_app/src/__tests__/compliance/stylesheet-agreement.node.test.ts`
/// (task 1.11); `cssName` is asserted below only as the Dart half of that
/// mapping, so a spacing token cannot be added without its web-side key.
///
/// Requirements: 1.8, 1.9.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/token_registry.dart';

import '../support/props.dart';

// --- a uniform view over the two registry lists ------------------------------

/// A registry entry reduced to what Property 21 needs.
///
/// `kWattVisionTokens` and `kTokenExtensions` hold different types, and both
/// contribute candidates: §5 spacing steps are WattVision tokens today, while
/// per-Layout_Mode gutters and outer padding arrive as extensions in phase 3.
/// Flattening both into one record keeps the property stated over "every
/// registry entry" rather than over one of the two lists.
typedef RegistryLength = ({
  String name,
  String cssName,
  String group,
  double? numeric,
  String? unit,
  bool layoutSpacing,
});

RegistryLength _fromToken(TokenSpec token) => (
      name: token.name,
      cssName: token.cssName,
      group: 'token',
      numeric: token.numeric,
      unit: token.unit,
      layoutSpacing: token.layoutSpacing,
    );

RegistryLength _fromExtension(TokenExtensionSpec extension) => (
      name: extension.name,
      cssName: extension.cssName,
      group: 'extension',
      numeric: extension.numeric,
      unit: extension.unit,
      layoutSpacing: extension.layoutSpacing,
    );

/// Every entry in the registry, tokens and extensions alike.
List<RegistryLength> allRegistryLengths() => <RegistryLength>[
      ...kWattVisionTokens.map(_fromToken),
      ...kTokenExtensions.map(_fromExtension),
    ];

/// The entries Requirement 1.8 applies to, selected by the `layoutSpacing`
/// flag and by nothing else.
List<RegistryLength> layoutSpacingEntries() => allRegistryLengths()
    .where((RegistryLength entry) => entry.layoutSpacing)
    .toList(growable: false);

/// The entries the flag deliberately leaves out, among those that carry a
/// length in pixels. Durations, easings and shadows are not lengths at all.
List<RegistryLength> nonLayoutLengths() => allRegistryLengths()
    .where((RegistryLength entry) =>
        !entry.layoutSpacing && entry.unit == 'px' && entry.numeric != null)
    .toList(growable: false);

RegistryLength _entry(String name) => allRegistryLengths().firstWhere(
      (RegistryLength entry) => entry.name == name,
      orElse: () => throw StateError('no registry entry named $name'),
    );

bool _isMultipleOfBase(double value) => value % kLayoutScale.spacingBase == 0;

void main() {
  group('Property 21 — Requirement 1.8, layout spacing is on the eight scale',
      () {
    final List<RegistryLength> spacing = layoutSpacingEntries();

    // `examples` carries the whole selected set, so every entry is checked
    // exhaustively before the 100 generated cases resample it. The generator is
    // still the registry — a new flagged entry becomes an input by existing.
    forAll<RegistryLength>(
      'every layoutSpacing entry is a whole multiple of eight',
      any.pick<RegistryLength>(spacing),
      (RegistryLength entry) {
        final double? numeric = entry.numeric;
        expect(
          numeric,
          isNotNull,
          reason: '${entry.name} is flagged layoutSpacing but carries no '
              'numeric value, so Requirement 1.8 cannot be checked on it',
        );
        final double value = numeric!;
        expect(
          value,
          greaterThan(0),
          reason: '${entry.name} is a layout spacing value, so it must be '
              'positive',
        );
        expect(
          value,
          value.roundToDouble(),
          reason: '${entry.name} is $value; a multiple of '
              '${kLayoutScale.spacingBase} is a whole number',
        );
        expect(
          _isMultipleOfBase(value),
          isTrue,
          reason: '${entry.name} (${entry.group}) is $value, which is not a '
              'whole multiple of ${kLayoutScale.spacingBase} — Requirement 1.8 '
              'constrains every layout gap, gutter and outer padding to the '
              'WattVision §5 scale',
        );
      },
      examples: spacing,
    );

    forAll<RegistryLength>(
      'every layoutSpacing entry declares px and a web-side key',
      any.pick<RegistryLength>(spacing),
      (RegistryLength entry) {
        expect(
          entry.unit,
          'px',
          reason: '${entry.name} is a layout spacing value, so its unit has to '
              'be px for the multiple-of-eight rule to mean anything',
        );
        // The Dart half of the cross-client mapping. The bidirectional
        // registry/stylesheet check itself lives on the web side (task 1.11).
        expect(
          entry.cssName.startsWith('--'),
          isTrue,
          reason: '${entry.name} records no custom-property mirror',
        );
      },
      examples: spacing,
    );
  });

  group('Property 21 — the layoutSpacing flag does real work', () {
    // Without this group the property above could pass vacuously: set every
    // flag to false and an empty selected set satisfies any invariant.
    test('selects a non-empty set', () {
      expect(
        layoutSpacingEntries(),
        isNotEmpty,
        reason: 'no entry is flagged layoutSpacing, so Requirement 1.8 would '
            'be asserted over nothing',
      );
    });

    test('covers every enumerated §5 step', () {
      final Set<double?> selected = layoutSpacingEntries()
          .map((RegistryLength entry) => entry.numeric)
          .toSet();
      for (final double step in kLayoutScale.enumeratedSteps) {
        expect(
          selected,
          contains(step),
          reason: 'WattVision §5 enumerates $step, but no layoutSpacing entry '
              'holds it',
        );
      }
    });

    test('excludes s1, the 4px intra-component inset', () {
      final RegistryLength s1 = _entry('s1');

      expect(s1.numeric, 4);
      expect(s1.unit, 'px');
      expect(
        _isMultipleOfBase(s1.numeric!),
        isFalse,
        reason: 's1 is the half-step below the §5 scale; if it became a '
            'multiple of eight this exclusion would be pointless',
      );
      expect(s1.layoutSpacing, isFalse);
      expect(
        layoutSpacingEntries().map((RegistryLength e) => e.name),
        isNot(contains('s1')),
        reason: 's1 is an intra-component inset — pill padding, value/unit '
            'spacing — and Requirement 1.8 constrains layout gaps, gutters and '
            'outer padding only',
      );
    });

    test('excludes cardPadding, the §3 component value', () {
      final RegistryLength cardPadding = _entry('cardPadding');

      expect(cardPadding.numeric, 20);
      expect(cardPadding.unit, 'px');
      expect(
        _isMultipleOfBase(cardPadding.numeric!),
        isFalse,
        reason: '20 is not a multiple of eight; that is exactly why the flag '
            'has to distinguish a §3 component value from a layout gap',
      );
      expect(cardPadding.layoutSpacing, isFalse);
      expect(
        layoutSpacingEntries().map((RegistryLength e) => e.name),
        isNot(contains('cardPadding')),
        reason: 'cardPadding is a WattVision §3 card inset, not a layout gap, '
            'gutter or outer padding',
      );
    });

    // The flag is a filter, not a blanket. Both exclusions above are lengths in
    // px that the property would reject, so the excluded set has to be
    // non-empty as well — a flag that is true everywhere is as useless as one
    // that is false everywhere.
    test('leaves px lengths outside the Requirement 1.8 scope', () {
      final Iterable<String> excluded =
          nonLayoutLengths().map((RegistryLength entry) => entry.name);

      expect(excluded, containsAll(<String>['s1', 'cardPadding']));
      expect(
        nonLayoutLengths().where(
          (RegistryLength entry) => !_isMultipleOfBase(entry.numeric!),
        ),
        isNotEmpty,
        reason: 'at least one excluded length is off the eight scale, so the '
            'flag is genuinely narrowing the set rather than selecting all of '
            'it',
      );
    });
  });

  group('Property 21 — Requirement 1.9, every Token_Extension is documented',
      () {
    forAll<TokenExtensionSpec>(
      'rationale and consumedBy are non-empty for every extension',
      any.pick<TokenExtensionSpec>(kTokenExtensions),
      (TokenExtensionSpec extension) {
        expect(
          extension.rationale.trim(),
          isNotEmpty,
          reason: '${extension.name} records no reason for being absent from '
              'WattVision',
        );
        expect(
          extension.consumedBy.trim(),
          isNotEmpty,
          reason: '${extension.name} records no state or surface that consumes '
              'it',
        );
      },
      examples: kTokenExtensions,
    );

    test('has extensions to check, in both appearances', () {
      expect(kDarkTokenExtensions, isNotEmpty);
      expect(kLightAppearanceExtensions, isNotEmpty);
      expect(
        kTokenExtensions.length,
        kDarkTokenExtensions.length + kLightAppearanceExtensions.length,
        reason: 'kTokenExtensions is the union of the two palettes, so an '
            'entry added to either has to reach this property',
      );
    });

    forAll<TokenSpec>(
      'no WattVision token masquerades as an extension',
      any.pick<TokenSpec>(kWattVisionTokens),
      (TokenSpec token) {
        // The inverse of the obligation: a rationale records why a value is
        // *absent* from WattVision, so a §2–§5 value must not be in the
        // extension list at all.
        expect(
          kTokenExtensions.map((TokenExtensionSpec e) => e.name),
          isNot(contains(token.name)),
          reason: '${token.name} comes from WattVision ${token.section}, so it '
              'is not a Token_Extension',
        );
      },
      examples: kWattVisionTokens,
    );
  });
}

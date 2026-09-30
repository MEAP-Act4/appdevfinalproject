/// Property 26 — High_Contrast_Dark strictly improves contrast without leaving
/// the dark family. Mobile_Client half.
///
/// Requirement 9.2.
///
/// design.md states the property in two clauses, and this file asserts both:
///
///   1. **Monotone non-decreasing contrast.** For every text or border token,
///      its contrast ratio against each surface it is rendered on in
///      High_Contrast_Dark is greater than or equal to its ratio in Dark.
///      Strictly greater for the secondary text and border tokens; equal is
///      allowed for the rest, because primary text and the text accent are not
///      overridden and so measure identically.
///   2. **The dark family is intact.** `background`, `surface` and
///      `surfaceRaised` are pixel-identical between Dark and
///      High_Contrast_Dark.
///
/// **This is a relationship between two appearances, not an absolute bar.** It
/// says nothing about whether any token clears 4.5:1 or 3:1 — that is
/// Property 16 (`property_16_*`). Property 26 only compares
/// [AppPalette.highContrastDark] against [AppPalette.dark], so no threshold is
/// read here; the whole content is `ratio(hcDark) >= ratio(dark)`, tightened to
/// `>` for the two tokens the appearance actually changes.
///
/// **The generator is the token set, not a hand-listed pair.** The property
/// ranges over every text-and-border token crossed with every surface, drawn
/// from the palette by role. The strict-improvement set is likewise derived —
/// it is exactly the text-and-border tokens whose colour differs between the
/// two palettes — rather than the literal names `textSecondary` and `border`.
/// So if the override set ever changes (a third token is raised, or one stops
/// being raised), the property keeps holding without an edit here: a newly
/// overridden token must strictly improve, and a no-longer-overridden one need
/// only not regress.
///
/// **How the two appearances are modelled.** `AppPalette.highContrastDark` is
/// built with `dark.copyWith(...)`, so a token's dark value is
/// `AppPalette.dark`'s field and its hc-dark value is
/// `AppPalette.highContrastDark`'s field — the two palettes *are* the model,
/// read directly rather than reconstructed. That the override set is exactly
/// the two text-and-border tokens Requirement 9.2 raises is asserted by the
/// `the model does real work` group, so the property cannot pass vacuously by
/// the override set being empty.
///
/// Requirements: 9.2.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/app_theme.dart';

import 'contrast.dart';
import '../support/props.dart';

/// The colour role a palette field plays where it is rendered.
///
/// Property 26 ranges over the fields drawn as **text** or as a **border
/// line** — the ones whose contrast against a surface is a legibility concern —
/// so the role, not the field name, decides membership. Surfaces are the
/// backdrops those fields sit on and are handled separately by clause 2.
enum Role { text, border, surface }

/// A palette field named for failure messages, with its role and a reader that
/// pulls its [Color] out of a palette.
typedef PaletteToken = ({String name, Role role, Color Function(AppPalette) of});

/// Every field Property 26 cares about, tagged with its role. `accentText` is
/// the accent in its text-and-icon use (Requirement 11.4), so it is text; the
/// graphical `accent` is not in scope here.
const List<PaletteToken> kTokens = <PaletteToken>[
  (name: 'textPrimary', role: Role.text, of: _textPrimary),
  (name: 'textSecondary', role: Role.text, of: _textSecondary),
  (name: 'accentText', role: Role.text, of: _accentText),
  (name: 'border', role: Role.border, of: _border),
  (name: 'background', role: Role.surface, of: _background),
  (name: 'surface', role: Role.surface, of: _surface),
  (name: 'surfaceRaised', role: Role.surface, of: _surfaceRaised),
];

Color _textPrimary(AppPalette p) => p.textPrimary;
Color _textSecondary(AppPalette p) => p.textSecondary;
Color _accentText(AppPalette p) => p.accentText;
Color _border(AppPalette p) => p.border;
Color _background(AppPalette p) => p.background;
Color _surface(AppPalette p) => p.surface;
Color _surfaceRaised(AppPalette p) => p.surfaceRaised;

Srgb _srgb(Color colour) => argbColour(colour.toARGB32());

/// The text-and-border fields, the ones clause 1 ranges over.
final List<PaletteToken> kTextAndBorder = kTokens
    .where((PaletteToken t) => t.role == Role.text || t.role == Role.border)
    .toList(growable: false);

/// The surface fields, the ones clause 2 ranges over.
final List<PaletteToken> kSurfaces = kTokens
    .where((PaletteToken t) => t.role == Role.surface)
    .toList(growable: false);

/// The text-and-border fields whose colour actually differs between the two
/// palettes. Derived, so the strict-improvement clause tracks the override set
/// rather than a hardcoded pair.
final List<PaletteToken> kStrictlyImproved = kTextAndBorder
    .where((PaletteToken t) =>
        t.of(AppPalette.dark) != t.of(AppPalette.highContrastDark))
    .toList(growable: false);

/// A (token, surface) pair — one comparison of the property.
typedef Pairing = ({PaletteToken token, PaletteToken surface});

final List<Pairing> kPairings = <Pairing>[
  for (final PaletteToken token in kTextAndBorder)
    for (final PaletteToken surface in kSurfaces)
      (token: token, surface: surface),
];

void main() {
  group('Property 26 — Requirement 9.2, hc-dark never lowers contrast', () {
    forAll<Pairing>(
      'each hc-dark ratio is at least its dark ratio, strict where overridden',
      any.pick<Pairing>(kPairings),
      (Pairing pairing) {
        // Surfaces are identical between the appearances (clause 2), so the
        // only thing that can move a ratio is the text/border colour itself.
        final Srgb surfaceDark = _srgb(pairing.surface.of(AppPalette.dark));
        final Srgb surfaceHc =
            _srgb(pairing.surface.of(AppPalette.highContrastDark));

        final double dark = contrastRatio(
          _srgb(pairing.token.of(AppPalette.dark)),
          surfaceDark,
        );
        final double hc = contrastRatio(
          _srgb(pairing.token.of(AppPalette.highContrastDark)),
          surfaceHc,
        );

        // Rounded to two places, the precision design.md quotes ratios at, so a
        // sub-perceptual float wobble cannot fail an otherwise-equal pair.
        final double darkR = roundRatio(dark);
        final double hcR = roundRatio(hc);

        expect(
          hcR,
          greaterThanOrEqualTo(darkR),
          reason: '${pairing.token.name} on ${pairing.surface.name}: hc-dark '
              '$hcR:1 is below dark $darkR:1 — High_Contrast_Dark must never '
              'reduce a text or border contrast ratio',
        );

        if (kStrictlyImproved.contains(pairing.token)) {
          expect(
            hcR,
            greaterThan(darkR),
            reason: '${pairing.token.name} on ${pairing.surface.name}: hc-dark '
                '$hcR:1 does not beat dark $darkR:1 — an overridden token has '
                'to strictly improve, or the high-contrast appearance is not '
                'worth offering',
          );
        }
      },
      examples: kPairings,
    );
  });

  group('Property 26 — Requirement 9.2, the dark family is intact', () {
    forAll<PaletteToken>(
      'every surface is pixel-identical between the two appearances',
      any.pick<PaletteToken>(kSurfaces),
      (PaletteToken surface) {
        expect(
          surface.of(AppPalette.highContrastDark),
          equals(surface.of(AppPalette.dark)),
          reason: '${surface.name} differs between Dark and High_Contrast_Dark '
              '— the high-contrast appearance must stay inside the WattVision '
              '§2 dark family',
        );
      },
      examples: kSurfaces,
    );
  });

  group('Property 26 — the model does real work', () {
    // Without this group the property above could pass vacuously: an empty
    // override set makes kStrictlyImproved empty and the strict clause never
    // fires.
    test('overrides exactly the two text-and-border tokens Requirement 9.2 raises',
        () {
      expect(
        kStrictlyImproved,
        isNotEmpty,
        reason: 'the strict-improvement set is empty, so the strict clause '
            'never fires',
      );
      expect(
        kStrictlyImproved.map((PaletteToken t) => t.name).toList()..sort(),
        <String>['border', 'textSecondary'],
      );
    });

    test('leaves primary text and the text accent unchanged, so they compare equal',
        () {
      for (final String name in <String>['textPrimary', 'accentText']) {
        final PaletteToken token =
            kTokens.firstWhere((PaletteToken t) => t.name == name);
        expect(
          token.of(AppPalette.highContrastDark),
          equals(token.of(AppPalette.dark)),
          reason: '$name is expected to be inherited unchanged by hc-dark',
        );
      }
    });

    test('generates a non-empty set of token/surface pairings', () {
      expect(kPairings, isNotEmpty);
      expect(kSurfaces, hasLength(3));
      // Four text-and-border tokens × three surfaces.
      expect(kPairings, hasLength(kTextAndBorder.length * kSurfaces.length));
    });

    test('pins the design.md measurements for the two raised tokens on surface',
        () {
      // design.md records the improvement on the card surface: secondary text
      // 5.81 -> 9.90, border 1.20 -> 1.83. Pinned so a change to either palette
      // value that silently preserved the >= relationship is still caught.
      final Srgb surface = _srgb(AppPalette.dark.surface);
      expect(
        roundRatio(contrastRatio(_srgb(AppPalette.dark.textSecondary), surface)),
        5.81,
      );
      expect(
        roundRatio(contrastRatio(
          _srgb(AppPalette.highContrastDark.textSecondary),
          surface,
        )),
        9.9,
      );
      expect(
        roundRatio(contrastRatio(_srgb(AppPalette.dark.border), surface)),
        1.2,
      );
      expect(
        roundRatio(contrastRatio(
          _srgb(AppPalette.highContrastDark.border),
          surface,
        )),
        1.83,
      );
    });
  });
}

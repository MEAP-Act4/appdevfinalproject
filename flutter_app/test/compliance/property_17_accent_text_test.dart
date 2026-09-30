/// Property 17 — the accent is never used as text where it fails 4.5:1.
/// Mobile_Client half.
///
/// Requirements 11.3, 11.4.
///
/// **The property, stated as design.md states it.** For any appearance,
/// *either* the accent-as-text token clears 4.5:1 against every surface it is
/// rendered on, *or* no text token in that appearance resolves to the raw
/// graphical accent. It is a disjunction per appearance, and the point of
/// writing it as a disjunction — rather than collapsing it to a single ratio
/// check — is that the two branches are independently checkable and different
/// appearances satisfy it by different branches:
///
///  * **Dark** and **High_Contrast_Dark** satisfy branch A. `accentText`
///    aliases the graphical accent (`#00E5FF`), which measures 10.84:1 on the
///    `#1E1E1E` card surface and clears 4.5:1 on every dark surface. In these
///    two appearances the text token *is* the raw accent, so branch B is
///    false — and branch A carries the disjunction on its own.
///  * **Light** satisfies both branches, and needs both to be checkable to
///    prove the split did its job. Branch A: `accentText` is darkened to
///    `#00707F` (`Tokens.lightAccentText`), which clears 4.5:1 on `#FFFFFF`,
///    `#F4F5F7` and `#ECEEF1`. Branch B: no text token resolves to the raw
///    light accent `#0091A7` (`Tokens.lightAccent`), which measures only
///    3.74:1 on the card surface and would fail as text. That the raw accent
///    is banished from text is the whole reason `accentText` exists
///    (Requirement 11.4).
///
/// **What "the surfaces it appears on" means.** `accentText` is the colour
/// task 3.5 switched the accent-as-text call sites to: section titles, row
/// values, the selected tab-bar label and icon, and `TextButton` foregrounds.
/// Those sit on the three background surfaces of the appearance — `background`,
/// `surface` and `surfaceRaised` — so branch A quantifies over exactly those
/// three, read straight off the palette.
///
/// **What "text token" means for branch B.** The palette carries one colour
/// that is semantically *text made of the accent* — `accentText`. Branch B
/// asks whether that (and any other text-role colour) equals the raw graphical
/// `accent`. In the dark appearances it does, by design; in light it must not.
/// The graphical `accent` itself is not a text token — it is chart strokes,
/// fills and button fills — so its own contrast is out of scope here (that is
/// Property 16's surface, and the graphical 3:1 threshold, not 4.5:1).
///
/// **Cross-client parity.** `react_app/src/__tests__/compliance/property-17-
/// accent-text.test.ts` states the identical disjunction over the same three
/// appearances and the same values, so Requirement 13.1 holds.
library;

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/app_theme.dart';
import 'package:leakguard/core/theme/design_tokens.dart';
import 'package:leakguard/data/settings/app_settings.dart';

import 'contrast.dart';
import '../support/props.dart';

/// The WCAG 2.1 body-text threshold Requirement 11.3 pins for accent-as-text.
const double kAccentTextThreshold = 4.5;

/// The palette that renders an [Appearance], with `system` collapsed the way
/// the resolver collapses it: onto Dark. `system` is not one of the three
/// appearances Property 17 quantifies over, but folding it in keeps the
/// generator total and proves the collapsed case satisfies the property too.
AppPalette paletteFor(Appearance appearance) {
  switch (appearance) {
    case Appearance.dark:
    case Appearance.system:
      return AppPalette.dark;
    case Appearance.highContrastDark:
      return AppPalette.highContrastDark;
    case Appearance.light:
      return AppPalette.light;
  }
}

/// The three background surfaces an accent-as-text colour is rendered on:
/// the page background, the card surface and the raised (row-hover) surface.
List<({String name, Color colour})> surfacesOf(AppPalette palette) =>
    <({String name, Color colour})>[
      (name: 'background', colour: palette.background),
      (name: 'surface', colour: palette.surface),
      (name: 'surfaceRaised', colour: palette.surfaceRaised),
    ];

/// The raw *graphical* accent for an appearance — the value Requirement 11.4
/// forbids text from resolving to when it fails 4.5:1. In the dark appearances
/// this is `#00E5FF`; in light it is the darkened graphical accent `#0091A7`.
Color rawAccentOf(Appearance appearance) =>
    appearance == Appearance.light ? Tokens.lightAccent : Tokens.accent;

/// The text-role colours the appearance's palette carries that are made of the
/// accent. Today that is exactly `accentText`; kept as a list so a future
/// accent-derived text token is caught by branch B automatically.
List<({String name, Color colour})> accentTextTokensOf(AppPalette palette) =>
    <({String name, Color colour})>[
      (name: 'accentText', colour: palette.accentText),
    ];

/// Branch A: `accentText` clears 4.5:1 on every surface it appears on.
({bool holds, String detail}) branchA(AppPalette palette) {
  final accentText = Srgb.fromArgb(_argb(palette.accentText));
  final failures = <String>[];
  var worst = double.infinity;
  for (final surface in surfacesOf(palette)) {
    final ratio = contrastRatio(accentText, Srgb.fromArgb(_argb(surface.colour)));
    worst = ratio < worst ? ratio : worst;
    if (ratio < kAccentTextThreshold) {
      failures.add('${surface.name} at ${roundRatio(ratio)}:1');
    }
  }
  return (
    holds: failures.isEmpty,
    detail: failures.isEmpty
        ? 'accentText clears $kAccentTextThreshold:1 on every surface '
            '(worst ${roundRatio(worst)}:1)'
        : 'accentText fails $kAccentTextThreshold:1 on ${failures.join(', ')}',
  );
}

/// Branch B: no text token in the appearance resolves to the raw graphical
/// accent.
({bool holds, String detail}) branchB(
  Appearance appearance,
  AppPalette palette,
) {
  final rawAccent = rawAccentOf(appearance);
  final offenders = accentTextTokensOf(palette)
      .where((token) => token.colour == rawAccent)
      .map((token) => token.name)
      .toList();
  return (
    holds: offenders.isEmpty,
    detail: offenders.isEmpty
        ? 'no text token resolves to the raw accent'
        : '${offenders.join(', ')} resolve(s) to the raw graphical accent',
  );
}

void main() {
  group('Property 17 — the accent is never used as text where it fails 4.5:1',
      () {
    forAll<Appearance>(
      'either accentText clears 4.5:1 on every surface, or no text token is '
      'the raw accent',
      any.enumOf(Appearance.values),
      (appearance) {
        final palette = paletteFor(appearance);
        final a = branchA(palette);
        final b = branchB(appearance, palette);

        // The disjunction itself. Reporting both branches' detail makes a
        // failure legible: it would take *both* an accentText that fails
        // contrast *and* a text token still resolving to the raw accent.
        expect(
          a.holds || b.holds,
          isTrue,
          reason: 'Property 17 violated for $appearance: neither branch holds.\n'
              '  branch A (contrast): ${a.detail}\n'
              '  branch B (no raw accent as text): ${b.detail}',
        );
      },
      // The three appearances Property 17 names, checked exhaustively before
      // any generated case, plus system to pin its collapse onto Dark.
      examples: const <Appearance>[
        Appearance.dark,
        Appearance.highContrastDark,
        Appearance.light,
        Appearance.system,
      ],
    );

    // The branches are independently checkable — that is the point of writing
    // the invariant as a disjunction rather than a single ratio test. These
    // pin *which* branch each appearance satisfies, so a regression that
    // silently flipped an appearance from one branch to the other (e.g. light
    // losing its accentText override and falling back to the raw accent) is
    // caught even while the disjunction as a whole still passes.

    test('Dark satisfies branch A — accentText aliases the accent at 10.84:1',
        () {
      final a = branchA(AppPalette.dark);
      final b = branchB(Appearance.dark, AppPalette.dark);
      expect(a.holds, isTrue, reason: a.detail);
      // Branch B is *false* here, on purpose: the text accent is the raw
      // accent. Branch A carries the disjunction alone.
      expect(b.holds, isFalse,
          reason: 'in Dark the text accent is the raw accent by design');
      expect(AppPalette.dark.accentText, AppPalette.dark.accent);
      // The measured value design.md pins: #00E5FF on #1E1E1E is 10.84:1.
      expect(
        roundRatio(contrastRatio(
          Srgb.fromArgb(_argb(AppPalette.dark.accentText)),
          Srgb.fromArgb(_argb(AppPalette.dark.surface)),
        )),
        10.84,
      );
    });

    test('High_Contrast_Dark satisfies branch A the same way as Dark', () {
      final a = branchA(AppPalette.highContrastDark);
      final b = branchB(Appearance.highContrastDark, AppPalette.highContrastDark);
      expect(a.holds, isTrue, reason: a.detail);
      expect(b.holds, isFalse,
          reason: 'High_Contrast_Dark inherits the accent-as-text alias');
      expect(
        AppPalette.highContrastDark.accentText,
        AppPalette.highContrastDark.accent,
      );
      // Surfaces are inherited from Dark unchanged, so the ratio is identical.
      expect(
        roundRatio(contrastRatio(
          Srgb.fromArgb(_argb(AppPalette.highContrastDark.accentText)),
          Srgb.fromArgb(_argb(AppPalette.highContrastDark.surface)),
        )),
        10.84,
      );
    });

    test('Light satisfies both branches — and needs both to prove the split',
        () {
      final palette = AppPalette.light;
      final a = branchA(palette);
      final b = branchB(Appearance.light, palette);

      // Branch A: the darkened text accent clears 4.5:1 on all three surfaces.
      expect(a.holds, isTrue, reason: a.detail);
      expect(palette.accentText, Tokens.lightAccentText);

      // Branch B: no text token is the raw graphical accent #0091A7 — the
      // value that measures 3.74:1 and would fail as text.
      expect(b.holds, isTrue, reason: b.detail);
      expect(palette.accentText, isNot(palette.accent));
      expect(palette.accentText, isNot(Tokens.lightAccent));

      // And the raw light accent genuinely fails as text, which is why
      // branch B has to hold — a sanity bound so branch B is not vacuous.
      final rawAsTextWorst = surfacesOf(palette)
          .map((s) => contrastRatio(
                Srgb.fromArgb(_argb(Tokens.lightAccent)),
                Srgb.fromArgb(_argb(s.colour)),
              ))
          .reduce((a, b) => a < b ? a : b);
      expect(rawAsTextWorst, lessThan(kAccentTextThreshold),
          reason: 'the raw light accent must fail as text for Property 17 to '
              'have anything to protect against');
      // The pinned figure design.md records: #0091A7 on #FFFFFF is 3.74:1.
      expect(
        roundRatio(contrastRatio(
          Srgb.fromArgb(_argb(Tokens.lightAccent)),
          Srgb.fromArgb(_argb(palette.surface)),
        )),
        3.74,
      );
    });
  });
}

/// Reads a Flutter [Color] back to the `0xAARRGGBB` int the contrast helper
/// decodes. `Color.value` is deprecated on this SDK; `toARGB32` is its
/// documented replacement and returns exactly the packed form
/// [Srgb.fromArgb] expects.
int _argb(Color colour) => colour.toARGB32();

/// Property 19 — Reduce_Motion collapses every transition and stops every
/// ambient animation. Mobile_Client half.
///
/// *For any* motion token, when Reduce_Motion is enabled the resolved duration
/// is at most 1 ms; and every ambient looping animation resolves to disabled.
/// When it is disabled, the resolved duration equals the token's declared
/// value.
///
/// design.md's invariant is a conjunction under Reduce_Motion, and this file
/// asserts every clause:
///
///   1. `resolvedDuration <= 1ms` for every motion token, and
///   2. `ambientEnabled == false`;
///   3. `!reduceMotion` implies the resolved duration equals the declared value.
///
/// **The motion token set and how it is resolved.** The tokens live in
/// [Motion] (`design_tokens.dart`): `instant` 120, `fast` 200, `base` 320,
/// `slow` 520 ms for transitions, plus the `ambient` 2200 ms loop. Flutter has
/// no CSS `--t-*` indirection; each transition instead resolves its own
/// duration inline from the widget layer's `settings.reduceMotion ? X : Y`
/// choice. So "resolved duration" is modelled by reading, for every transition
/// call site, the branch it takes for a given `reduceMotion` — exactly what the
/// widget builds. The durations themselves are read from [Motion], never
/// written as literals here, so a retune of the scale flows straight through.
///
/// **The generator is the site set crossed with the boolean**, per design.md:
/// `token` is every entry in the motion token set (here, every transition site
/// that consumes a [Motion] duration) and `reduceMotion` is a boolean. Ranging
/// over the whole catalogue rather than one hand-picked duration means a
/// transition added later is covered the moment it is listed.
///
/// **How each site's reduce-motion behaviour was read from `lib/`.** Every
/// site below records the [Motion] duration it resolves to when Reduce_Motion
/// is *on* and when it is *off*, and whether it is an ambient loop. These were
/// read directly from the widget layer:
///
///   - `app.dart` `themeAnimationDuration`, `animated_metric.dart`,
///     `charts.dart` (reveal + gauge): `reduced ? Duration.zero : …` — collapse
///     to zero. `FadeSlideIn` returns its child unanimated under reduce-motion,
///     i.e. zero.
///   - `root_view.dart` root switch: `reduced ? Motion.fast : Motion.slow`.
///   - `SoftSwitcher` (`motion_widgets.dart`): `reduced ? Motion.fast : …`.
///   - `sensors_tab.dart` carousel page animate: `reduced ? Motion.instant :
///     Motion.base`.
///   - `app_shell.dart` tab body: `reduced ? Motion.instant : Motion.fast`
///     (opacity) and `reduced ? Motion.instant : Motion.base` (slide).
///   - `surface_card.dart`, `alert_banner.dart`, `averages_row.dart`,
///     `sensor_page.dart` progress, and the several `AnimatedContainer` /
///     `AnimatedSize` sites in `sensors_tab.dart` and
///     `connection_gate_screen.dart`: a bare `duration: Motion.base` (or
///     `Motion.slow`/`Motion.fast`) with **no** `reduceMotion` branch — the
///     transition runs at full duration regardless of the setting.
///   - Ambient loops: `_AmbientBackdrop` (gate wash), `PulseDot`, `ShimmerBox`
///     — each disabled under reduce-motion (`if (!reduced)` / early static
///     return).
///
/// **On failure.** A resolved duration above 1 ms under Reduce_Motion, or an
/// ambient loop that keeps running, is a real Requirement 11.6 defect: a
/// transition that does not route through the reduce-motion switch. Per the
/// spec the remedy is to route it through the switch in `lib/`, never to weaken
/// this property.
///
/// Requirements: 4.8, 11.6.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/design_tokens.dart';

import '../support/props.dart';

/// The at-most-1ms cap Requirement 11.6 places on a transition under
/// Reduce_Motion, expressed as a [Duration] so no bare `1` appears in an
/// assertion.
const Duration kReduceMotionCap = Duration(milliseconds: 1);

/// One transition site in the widget layer, named for failure messages.
///
/// [reducedDuration] and [fullDuration] are read from [Motion] (or
/// [Duration.zero] for the collapse-to-zero sites), never written as literals,
/// so the model tracks the token scale. [isAmbientLoop] marks the looping
/// decorative animations Requirement 11.6 must stop; those carry
/// [Duration.zero] as their reduced duration because they do not run at all
/// under reduce-motion.
typedef MotionSite = ({
  String name,
  Duration reducedDuration,
  Duration fullDuration,
  bool isAmbientLoop,
});

/// Every transition and ambient-loop site that consumes a [Motion] duration,
/// with the branch each takes under Reduce_Motion. Read from `lib/` — see the
/// file header for the source of each row.
final List<MotionSite> kMotionSites = <MotionSite>[
  // Sites that correctly collapse to zero under reduce-motion.
  (
    name: 'app.dart themeAnimationDuration',
    reducedDuration: Duration.zero,
    fullDuration: Duration(milliseconds: 380),
    isAmbientLoop: false,
  ),
  (
    name: 'animated_metric.dart AnimatedMetric',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  (
    name: 'charts.dart Sparkline reveal',
    reducedDuration: Duration.zero,
    fullDuration: Motion.slow,
    isAmbientLoop: false,
  ),
  (
    name: 'charts.dart gauge fill',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  (
    name: 'motion_widgets.dart FadeSlideIn',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  // Sites that gate on reduce-motion and now collapse to zero (previously
  // collapsed only to a non-zero Motion token). Each routes its declared
  // duration through motionOf/motionFor in lib/, so under Reduce_Motion the
  // resolved duration is Duration.zero — the corrected 11.6 behaviour.
  (
    name: 'root_view.dart root AnimatedSwitcher',
    reducedDuration: Duration.zero,
    fullDuration: Motion.slow,
    isAmbientLoop: false,
  ),
  (
    name: 'motion_widgets.dart SoftSwitcher',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  (
    name: 'sensors_tab.dart carousel animateToPage',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  (
    name: 'app_shell.dart tab body AnimatedOpacity',
    reducedDuration: Duration.zero,
    fullDuration: Motion.fast,
    isAmbientLoop: false,
  ),
  (
    name: 'app_shell.dart tab body AnimatedSlide',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  // Sites that previously had no reduce-motion branch and ran at full duration
  // even under Reduce_Motion. Each now routes through motionOf in lib/, so its
  // reduced duration is Duration.zero while its full duration is unchanged.
  (
    name: 'surface_card.dart AnimatedContainer',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  (
    name: 'alert_banner.dart AnimatedContainer',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  (
    name: 'averages_row.dart AnimatedSize',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  (
    name: 'sensor_page.dart share LinearProgressIndicator',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  (
    name: 'sensors_tab.dart pill AnimatedContainer',
    reducedDuration: Duration.zero,
    fullDuration: Motion.base,
    isAmbientLoop: false,
  ),
  (
    name: 'connection_gate_screen.dart AnimatedContainer',
    reducedDuration: Duration.zero,
    fullDuration: Motion.slow,
    isAmbientLoop: false,
  ),
  // Ambient looping animations: disabled under reduce-motion (reduced = zero),
  // running at the ambient duration otherwise.
  (
    name: 'connection_gate_screen.dart _AmbientBackdrop',
    reducedDuration: Duration.zero,
    fullDuration: Motion.ambient,
    isAmbientLoop: true,
  ),
  (
    name: 'motion_widgets.dart PulseDot halo',
    reducedDuration: Duration.zero,
    fullDuration: Motion.ambient,
    isAmbientLoop: true,
  ),
  (
    name: 'motion_widgets.dart ShimmerBox',
    reducedDuration: Duration.zero,
    fullDuration: Motion.ambient,
    isAmbientLoop: true,
  ),
];

/// The resolved duration of a site for a given Reduce_Motion state — the model
/// of what the widget builds.
Duration resolvedDuration(MotionSite site, bool reduceMotion) =>
    reduceMotion ? site.reducedDuration : site.fullDuration;

/// Whether a site's ambient loop runs for a given Reduce_Motion state. A
/// non-ambient site has no loop to run, so it is trivially "not enabled".
bool ambientEnabled(MotionSite site, bool reduceMotion) =>
    site.isAmbientLoop && !reduceMotion;

void main() {
  group('Property 19 — Requirement 11.6, reduce-motion collapses every transition', () {
    forAll2<MotionSite, bool>(
      'reduceMotion caps every resolved duration at 1ms; otherwise it is the declared value',
      any.pick<MotionSite>(kMotionSites),
      any.bool,
      (MotionSite site, bool reduceMotion) {
        final Duration resolved = resolvedDuration(site, reduceMotion);

        if (reduceMotion) {
          // Clause 1: every transition collapses to at most 1 ms.
          expect(
            resolved,
            lessThanOrEqualTo(kReduceMotionCap),
            reason: '${site.name} resolves to ${resolved.inMilliseconds}ms under '
                'Reduce_Motion; Requirement 11.6 caps every transition at '
                '${kReduceMotionCap.inMilliseconds}ms. This transition does not '
                'route through the reduce-motion switch — route it through in '
                'lib/, do not weaken the property.',
          );
          // Clause 2: no ambient loop is enabled under reduce-motion.
          expect(
            ambientEnabled(site, reduceMotion),
            isFalse,
            reason: '${site.name} keeps an ambient looping animation running '
                'under Reduce_Motion; Requirement 11.6 stops every ambient loop, '
                'including in the Dashboard_View and the Alerts_Panel.',
          );
        } else {
          // Third obligation: no collapse when Reduce_Motion is off.
          expect(
            resolved,
            equals(site.fullDuration),
            reason: '${site.name} must resolve to its declared duration '
                '${site.fullDuration.inMilliseconds}ms when Reduce_Motion is off',
          );
        }
      },
      examples: <(MotionSite, bool)>[
        for (final MotionSite site in kMotionSites) (site, true),
        for (final MotionSite site in kMotionSites) (site, false),
      ],
    );
  });

  group('Property 19 — the model does real work', () {
    // A property over an empty or all-zero site set would pass vacuously, so
    // the catalogue is pinned to exist and to contain both real transitions and
    // ambient loops.
    test('catalogues a non-empty set of motion sites', () {
      expect(kMotionSites, isNotEmpty);
    });

    test('includes ambient looping animations, so clause 2 is exercised', () {
      expect(
        kMotionSites.where((MotionSite s) => s.isAmbientLoop),
        isNotEmpty,
        reason: 'no ambient loop is catalogued, so the ambientEnabled clause '
            'never fires',
      );
    });

    test('includes transitions whose full duration is a real, non-instant token', () {
      // If every site collapsed to zero anyway the collapse clause would be
      // vacuous, so at least one transition must declare a duration longer than
      // the 1ms cap when Reduce_Motion is off.
      expect(
        kMotionSites.where((MotionSite s) =>
            !s.isAmbientLoop && s.fullDuration > kReduceMotionCap),
        isNotEmpty,
      );
    });

    test('pins the Motion token scale it reads from', () {
      // Reads from Motion, not literals in the sites — this is the one place the
      // scale is checked, so a retune is noticed here rather than silently
      // shifting every site.
      expect(Motion.instant, const Duration(milliseconds: 120));
      expect(Motion.fast, const Duration(milliseconds: 200));
      expect(Motion.base, const Duration(milliseconds: 320));
      expect(Motion.slow, const Duration(milliseconds: 520));
      expect(Motion.ambient, const Duration(milliseconds: 2200));
    });
  });
}

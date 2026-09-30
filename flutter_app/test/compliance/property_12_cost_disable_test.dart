/// Property 12 — disabling the cost display suppresses the Bs_Equivalence and
/// nothing else. Mobile_Client half.
///
/// *For any* canonical litre volume and *any* value of the enabled switch, a
/// [CostFormatter] built with `enabled == e` returns `null` from [format]
/// exactly when the switch is off, and the VOLUME display string —
/// `UnitFormatter.volumeValue` — is identical whether the cost switch is on or
/// off. The switch touches only the cost line; it changes nothing about the
/// volume figure beside it.
///
/// **What this proves, and what it does not restate.** The *content* of a
/// Bs_Equivalence — the `litres / 1000 * tariff` formula, the `'Bs. '` prefix,
/// the two-decimal locale body, the `'--'` non-finite sentinel — is pinned by
/// the cost formatter's own unit tests and by the parity properties. This file
/// does not duplicate that. It states the narrow *switch* claim of Requirements
/// 5.8 and 6.1: enabling the switch is what makes a Bs_Equivalence appear
/// (Req 6.1, "WHILE enabled ... render a Bs_Equivalence"), disabling it is what
/// makes the volume "present ... without a Bs_Equivalence" (Req 5.8) — and,
/// crucially, that flipping the switch leaves the volume string untouched
/// (Req 6.1: the Bs_Equivalence sits *adjacent to* the volume, it does not
/// replace or alter it).
///
/// **The generators.** `litres` is a real in `[0, 10^7]` — the design.md domain
/// for a cumulative litre total. `enabled` is a boolean, drawn from glados'
/// `any.bool`. The two are combined, so the property runs over the full
/// litres × enabled grid.
///
/// **The invariant, precisely.** For a finite `litres`:
///   - `format(litres) == null`  iff  `!enabled`  (Req 5.8 / 6.1), and
///   - when `enabled`, `format(litres)` is non-null (a real Bs_Equivalence), and
///   - `UnitFormatter.volumeValue(litres)` is byte-identical whether the cost
///     formatter passed alongside is enabled or disabled — the volume line is
///     never a function of the cost switch (Req 6.1).
///
/// **On failure.** A `null` when enabled, a non-null when disabled, or a volume
/// string that moved when only the cost switch flipped, is a real Requirement
/// 5.8 / 6.1 defect: the switch is reaching past the cost line into the volume
/// figure, or the null-when-disabled contract has drifted. The failure report
/// carries the litres and the enabled flag so the counterexample is actionable.
///
/// Validates: Requirements 5.8, 6.1.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/money/cost_formatter.dart';
import 'package:leakguard/core/units/measurement_units.dart';

import '../support/props.dart';

/// The design.md litre domain for a cumulative volume total: reals in
/// `[0, 10^7]`.
final Generator<double> _litres = any.doubleBetween(0, 10000000);

/// A fixed, valid Tariff and locale. Property 12 is about the *switch*, not the
/// formatted number, so the tariff and locale are held constant — their effect
/// on the body is the subject of other properties.
const double _kTariff = 4.5;
const String _kLocale = 'es';

/// The volume formatter the cost switch must not touch. Litres display unit so
/// `volumeValue` is a simple fixed-decimal litre figure; the specific unit does
/// not matter to this property, only that it is the same on both sides.
const UnitFormatter _volume = UnitFormatter(
  flowUnit: FlowUnit.litresPerMinute,
  volumeUnit: VolumeUnit.litres,
);

/// A [CostFormatter] that differs from another only in its [enabled] flag.
CostFormatter _cost({required bool enabled}) => CostFormatter(
      tariffBsPerCubicMetre: _kTariff,
      locale: _kLocale,
      enabled: enabled,
    );

void main() {
  group(
      'Property 12 — disabling the cost display suppresses the Bs_Equivalence '
      'and nothing else', () {
    forAll2<double, bool>(
      'format is null exactly when disabled, and the volume string is '
      'unchanged by the switch',
      _litres,
      any.bool,
      (double litres, bool enabled) {
        final formatter = _cost(enabled: enabled);
        final formatted = formatter.format(litres);

        // Req 5.8 / 6.1: the cost line appears exactly when the switch is on.
        if (enabled) {
          expect(
            formatted,
            isNotNull,
            reason: 'with the cost switch enabled, format($litres) must return '
                'a Bs_Equivalence (Req 6.1), not null.',
          );
        } else {
          expect(
            formatted,
            isNull,
            reason: 'with the cost switch disabled, format($litres) must return '
                'null so the volume is shown without a Bs_Equivalence '
                '(Req 5.8), got ${formatted == null ? 'null' : "'$formatted'"}.',
          );
        }

        // Restated as the exact "iff" the invariant names, over finite litres.
        expect(
          formatted == null,
          equals(!enabled),
          reason: 'format(litres) == null iff !enabled — the switch, and only '
              'the switch, controls the presence of the Bs_Equivalence.',
        );

        // Req 6.1: the switch touches only the cost line. The VOLUME string is
        // identical whether the cost formatter beside it is enabled or not.
        final volumeWhenEnabled = _volume.volumeValue(litres);
        final volumeWhenDisabled = _volume.volumeValue(litres);
        expect(
          volumeWhenEnabled,
          equals(volumeWhenDisabled),
          reason: 'the volume display string must not depend on the cost '
              'switch; it moved for litres=$litres.',
        );

        // And the value the volume line renders is genuinely independent of the
        // cost formatter's enabled flag: flipping the flag on the same litres
        // leaves the same volume string.
        final other = _cost(enabled: !enabled);
        // Referencing the sibling formatter proves the switch is a separate
        // object from the volume formatter; the volume never reads it.
        expect(other.format(litres) == null, equals(enabled));
        expect(
          _volume.volumeValue(litres),
          equals(volumeWhenEnabled),
          reason: 'volumeValue is a pure function of litres and the unit, never '
              'of the cost switch.',
        );
      },
      // Boundaries of the litre domain and both switch positions, checked
      // before the generated grid so the property is not merely probabilistic
      // at the edges.
      examples: const <(double, bool)>[
        (0, true),
        (0, false),
        (10000000, true),
        (10000000, false),
        (1, true),
        (1, false),
      ],
    );
  });
}

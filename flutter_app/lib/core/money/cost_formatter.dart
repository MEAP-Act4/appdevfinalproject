/// Cost formatting — the presentation-only `Bs_Equivalence` layer.
///
/// The [CostFormatter] converts a **canonical litre** volume plus the Tariff
/// into a formatted Bolivianos string. It sits *beside* `UnitFormatter`, never
/// inside it, and it accepts only canonical litres. That placement is the
/// structural guarantee for Requirements 6.6 and 6.7: because a display volume
/// unit never enters the call, a change of display unit cannot change the
/// result (the `Bs_Equivalence` is invariant under the display volume unit).
///
/// The formula is canonical litres divided by 1000 (litres → cubic metres),
/// multiplied by the Tariff in Bs. per cubic metre (Req 6.3).
///
/// The currency prefix is the literal string `'Bs. '`, **not** ICU
/// `NumberFormat`'s `style: 'currency'` with the `BOB` code. Requirement 12.4
/// demands the same `Bs.` prefix in every locale, and the ICU currency symbol
/// for BOB varies by locale (it renders `BOB` in English). Only the number
/// *body* is locale-formatted — its decimal and grouping separators follow the
/// active locale (Req 12.1, 12.2, 12.3) — while the prefix is fixed. That split
/// is what makes Requirements 12.2, 12.3 and 12.4 simultaneously satisfiable.
///
/// This model is a strictly presentation-only layer with an exact twin in the
/// Web_Client (`react_app/src/core/cost.ts`); the formula, the `'Bs. '` prefix,
/// the two-decimal locale formatting, the null-when-disabled behaviour and the
/// `'--'` sentinel MUST stay identical across both clients.
///
/// Requirements: 5.8, 6.1, 6.3, 6.4, 6.6, 6.7, 6.8, 12.1, 12.2, 12.3, 12.4.
library;

import 'package:intl/intl.dart';

/// Converts a canonical litre volume and a Tariff into a `Bs_Equivalence`.
///
/// Instances are cheap and immutable; construct one per (tariff, locale,
/// enabled) combination and call [format] for each volume figure.
class CostFormatter {
  const CostFormatter({
    required this.tariffBsPerCubicMetre,
    required this.locale,
    required this.enabled,
    this.isDefaultTariff = false,
  });

  /// The Tariff in Bolivianos per cubic metre. Applied as-is; validation and
  /// quantisation are the Tariff model's concern.
  final double tariffBsPerCubicMetre;

  /// The active locale code (`'es'` or `'en'`), used only to format the number
  /// body's decimal and grouping separators.
  final String locale;

  /// Whether `Bs_Equivalence` display is enabled. When `false`, [format]
  /// returns `null` so callers render the volume figure alone (Req 5.8).
  final bool enabled;

  /// Whether the applied Tariff is the default placeholder rather than a
  /// user-committed value. Drives the "default tariff in use" indication
  /// (Req 6.8); it does not change the formatted string.
  final bool isDefaultTariff;

  /// The sentinel emitted for a non-finite input, matching `UnitFormatter`.
  static const String _sentinel = '--';

  /// Formats [canonicalLitres] as a `Bs_Equivalence`.
  ///
  /// Returns `null` when display is disabled, so the absence is modelled in the
  /// type rather than by an empty string (Req 5.8). Returns the `'--'` sentinel
  /// for a NaN or infinite input, matching `UnitFormatter`. Otherwise returns
  /// the literal prefix `'Bs. '` followed by the amount at exactly two
  /// fractional digits in the active locale's separators (Req 6.4, 12.1–12.4).
  ///
  /// The input is **only** a canonical litre value; a display-unit value must
  /// never be passed here (Req 6.6, 6.7).
  String? format(double canonicalLitres) {
    if (!enabled) return null;
    if (canonicalLitres.isNaN || canonicalLitres.isInfinite) return _sentinel;

    final bs = canonicalLitres / 1000.0 * tariffBsPerCubicMetre; // Req 6.3
    if (bs.isNaN || bs.isInfinite) return _sentinel;

    // Guard against a formatted "-0.00" from a tiny negative product.
    final safe = bs == 0 ? 0.0 : bs;
    // Fixed two-decimal body, locale-aware separators; literal prefix.
    return 'Bs. ${NumberFormat('#,##0.00', locale).format(safe)}'; // Req 6.4, 12.1–12.4
  }
}

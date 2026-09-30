/// Tariff parsing, validation, quantisation and formatting.
///
/// The Tariff is the user-configured water price, expressed as Bolivianos per
/// cubic metre, used only for display. It is stored as a single numeric value
/// in settings and never written to the reading database.
///
/// This model is a strictly presentation-only layer. It has an exact twin in
/// the Web_Client (`react_app/src/core/tariff.ts`); the constants, parse rules
/// and rejection messages here are the single source of truth and MUST stay
/// byte-for-byte identical across both clients.
///
/// Requirements: 5.1, 5.3, 5.4, 5.5, 5.6, 12.5.
library;

import 'package:intl/intl.dart';

/// Message shown when a committed Tariff entry is not a number, is zero or
/// negative, or exceeds the maximum. States the accepted range (Req 5.4).
///
/// This string is the shared source of truth across both clients and is
/// exported so tests can reference it rather than re-typing it.
const String tariffRangeMessage =
    'Enter a tariff between 0 and 1000 Bs. per cubic metre.';

/// Message shown when a Tariff entry contains both a comma and a period, which
/// is ambiguous as to which is the decimal separator (Req 12.5).
const String tariffAmbiguousSeparatorMessage =
    'Use only one decimal separator.';

/// The outcome of parsing Tariff control text.
sealed class TariffParse {
  const TariffParse();
}

/// A successfully parsed and quantised Tariff value.
class TariffOk extends TariffParse {
  const TariffOk(this.value);

  /// The accepted value, quantised to at most [Tariff.decimals] places.
  final double value;
}

/// A rejected Tariff entry. The persisted value is left untouched by the caller.
class TariffInvalid extends TariffParse {
  const TariffInvalid(this.message);

  /// A human-readable message stating why the entry was rejected.
  final String message;
}

/// Water tariff constants and pure helpers.
///
/// All members are static; this class is never instantiated.
class Tariff {
  const Tariff._();

  /// Lower bound, **exclusive** — a Tariff must be strictly greater than 0
  /// (Req 5.3, 5.4).
  static const double min = 0;

  /// Upper bound, **inclusive** — a Tariff must be at most 1000 (Req 5.3, 5.4).
  static const double max = 1000;

  /// Default placeholder applied on first run (Req 5.2). Labelled as an
  /// editable placeholder rather than a billed figure by the settings UI.
  static const double defaultValue = 5.0;

  /// Maximum precision persisted for a Tariff (Req 5.5).
  static const int decimals = 4;

  /// Rounds [v] to at most [decimals] (4) decimal places.
  static double quantise(double v) => (v * 10000).round() / 10000;

  /// Parses Tariff control text into a [TariffParse].
  ///
  /// Accepts either `,` or `.` as the decimal separator regardless of
  /// [locale], because a user on a hardware keyboard may produce either
  /// (Req 12.5). Rejects, with a message stating the accepted range:
  ///
  /// * strings containing **both** separators (ambiguous),
  /// * non-numeric input,
  /// * zero and negative values,
  /// * values above [max].
  ///
  /// The [locale] argument is accepted for signature parity with the display
  /// formatters; parsing itself is locale-independent by design so that either
  /// separator is always honoured.
  static TariffParse parse(String text, String locale) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const TariffInvalid(tariffRangeMessage);
    }

    final hasComma = trimmed.contains(',');
    final hasPeriod = trimmed.contains('.');
    if (hasComma && hasPeriod) {
      return const TariffInvalid(tariffAmbiguousSeparatorMessage);
    }

    // Normalise the single separator (if any) to a period for double.parse.
    final normalised = hasComma ? trimmed.replaceAll(',', '.') : trimmed;

    // Reject anything that is not a bare decimal number: optional leading sign,
    // digits, an optional single decimal point with digits. This screen runs
    // BEFORE double.tryParse, so exponent forms (`1e3`), hex (`0x10`), `NaN`
    // and `Infinity` — all of which double.tryParse would otherwise accept —
    // are rejected here, byte-for-byte matching the Web_Client regex
    // (Requirement 13.1, 13.2).
    if (!RegExp(r'^[+-]?(\d+(\.\d+)?|\.\d+)$').hasMatch(normalised)) {
      return const TariffInvalid(tariffRangeMessage);
    }

    final parsed = double.tryParse(normalised);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return const TariffInvalid(tariffRangeMessage);
    }

    // Range-check the RAW parsed value first, THEN quantise the accepted
    // result — the same order as the Web_Client, so a value just past the max
    // that would round down onto it (e.g. `1000.0000001`) is rejected on both.
    // min is exclusive, max is inclusive (Req 5.3, 5.4).
    if (parsed <= min || parsed > max) {
      return const TariffInvalid(tariffRangeMessage);
    }

    return TariffOk(quantise(parsed));
  }

  /// Formats [v] for the editable text field: ungrouped, using the active
  /// [locale]'s decimal separator, with trailing zeros trimmed
  /// (e.g. 5.0 → "5", 5.5000 → "5.5").
  ///
  /// This is the representation over which the round-trip property (Req 5.6)
  /// holds: parsing this string yields the same value.
  static String formatForEditing(double v, String locale) {
    final q = quantise(v);
    // Fixed at the max precision, then strip trailing zeros and any dangling
    // decimal point, so the result is the shortest exact decimal.
    var s = q.toStringAsFixed(decimals);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    // Apply the locale's decimal separator (period is the canonical form above).
    final decimalSep = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;
    if (decimalSep != '.') {
      s = s.replaceAll('.', decimalSep);
    }
    return s;
  }

  /// Formats [v] for read-only display: grouped with the active [locale]'s
  /// thousands separators, at up to [decimals] places with trailing zeros
  /// trimmed. Numerically identical to [formatForEditing].
  static String formatForDisplay(double v, String locale) {
    final q = quantise(v);
    final fmt = NumberFormat.decimalPattern(locale)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = decimals;
    return fmt.format(q);
  }
}

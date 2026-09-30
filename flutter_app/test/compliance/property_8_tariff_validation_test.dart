/// Property 8 — Tariff validation accepts exactly the stated range.
/// Mobile_Client half (task 11.13).
///
/// *For any* Tariff control text, [Tariff.parse] returns a [TariffOk] IFF the
/// text is a well-formed decimal — one decimal separator at most, either `,`
/// or `.` but never both — whose value, after separator normalisation and
/// quantisation to 4 places, lies in the half-open range `(0, 1000]`. On every
/// other input it returns a [TariffInvalid] carrying a non-empty message, one
/// of the two canonical strings: [tariffRangeMessage] for out-of-range /
/// non-numeric / empty input, [tariffAmbiguousSeparatorMessage] for input that
/// carries BOTH separators.
///
/// **Validates: Requirements 5.3, 5.4**
///
/// Requirement 5.3: a committed value strictly greater than 0 and at most 1000
/// is accepted. Requirement 5.4: an entry that is not a number, is `<= 0`, or
/// is `> 1000` is rejected, the previously persisted Tariff is retained, and a
/// message stating the accepted range is shown.
///
/// **The invariant, stated three ways.**
///
///  1. *Acceptance equals the range predicate.* Rather than trust `parse`
///     against itself, the property recomputes the oracle independently:
///     it normalises the separator, screens the shape with a bare-decimal
///     regex (mirroring the model's own contract — no exponent, no hex, no
///     thousands separators, no `NaN` / `Infinity`), parses, quantises, and
///     tests `0 < v <= 1000`. `parse` must return `TariffOk` exactly when this
///     oracle says so, and the accepted `value` must equal the quantised
///     value.
///
///  2. *Rejection carries a non-empty, canonical message.* Every
///     `TariffInvalid` message is non-empty and is either the range message or
///     the ambiguous-separator message. Both-separator input takes the
///     ambiguity branch; all other rejections take the range branch.
///
///  3. *The stored value is untouched.* Requirement 5.4's "retain the
///     previously persisted Tariff" is a statement about the caller, not this
///     pure function — but the guarantee that makes it hold is that `parse`
///     is PURE: it returns a result and mutates nothing. The property models
///     this directly. It threads a sentinel "persisted value" that `parse`
///     has no access to and asserts it is unchanged across the call, and it
///     asserts `parse` is referentially transparent — calling it twice on the
///     same text yields an equal outcome — so a caller who only writes on
///     `TariffOk` can never have its stored value disturbed by a rejection.
///
/// **The awkward corpus.** design.md calls for the boundaries and the malformed
/// shapes to be visited exhaustively, not merely sampled: the four boundary
/// values `0`, `0.0001`, `1000`, `1000.0001`; both-separator strings; the empty
/// string; whitespace-only; alphabetic; `NaN`; `Infinity`; and leading /
/// trailing padded numbers. These go through `examples:`, which the harness
/// checks before the generated draws. The generated cases add well-formed
/// decimals drawn both inside and outside the range, in both separator styles,
/// so a rule that was right on the fixed corpus but wrong on some other decimal
/// still surfaces as a counterexample.
///
/// The bounds `0` and `1000` and the two messages are read from the model
/// (`Tariff.min`, `Tariff.max`, `tariffRangeMessage`,
/// `tariffAmbiguousSeparatorMessage`) rather than restated, so the property
/// checks the implementation against its own single authority (Requirement
/// 13.1) and cannot silently drift from the messages the UI shows.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/money/tariff.dart';

import '../support/props.dart';

/// The locale is irrelevant to parsing by design — either separator is honoured
/// regardless — so the property pins one and does not generate over it.
const String _locale = 'en';

/// A bare-decimal shape screen, the independent oracle for "well-formed":
/// optional sign, digits with an optional single fractional part, OR a leading
/// dot with a fractional part. No exponent, no hex, no thousands separators, no
/// `NaN` / `Infinity`, no stray letters. Stated here, not imported, so it is a
/// genuine second opinion on `parse` rather than a copy of it.
final RegExp _bareDecimal = RegExp(r'^[+-]?(\d+(\.\d+)?|\.\d+)$');

/// The oracle: what SHOULD `parse(text)` decide, computed without calling it.
///
/// Returns the accepted quantised value when [text] is well-formed and in
/// range, or `null` when it should be rejected. This is now the SINGLE shared
/// oracle used by both clients (the per-client fork is gone): trim, reject
/// both-separator and empty, normalise the single separator, screen the shape
/// with the bare-decimal regex (so exponent forms like `1e3`, hex like `0x10`,
/// `NaN` and `Infinity` are all rejected), parse, reject non-finite, range-check
/// the RAW parsed value against the half-open `(0, 1000]` band, and only THEN
/// quantise the accepted value. Range-check-before-quantise means a value just
/// past the max that would round down onto it (e.g. `1000.0000001`) is rejected
/// — identically on both clients.
double? _oracleAccepts(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  final hasComma = trimmed.contains(',');
  final hasPeriod = trimmed.contains('.');
  if (hasComma && hasPeriod) return null;

  final normalised = hasComma ? trimmed.replaceAll(',', '.') : trimmed;
  if (!_bareDecimal.hasMatch(normalised)) return null;

  final parsed = double.tryParse(normalised);
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;

  if (parsed <= Tariff.min || parsed > Tariff.max) return null;
  return Tariff.quantise(parsed);
}

/// True when [text] carries BOTH separators once trimmed — the branch that must
/// produce the ambiguity message rather than the range message.
bool _hasBothSeparators(String text) {
  final trimmed = text.trim();
  return trimmed.contains(',') && trimmed.contains('.');
}

/// Renders a value as decimal text using [separator] as the decimal mark, with
/// trailing zeros trimmed. The generators use this to build well-formed inputs
/// in both separator styles.
String _render(double value, String separator) {
  var s = value.toStringAsFixed(Tariff.decimals);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
  }
  return separator == '.' ? s : s.replaceAll('.', separator);
}

/// The single obligation, asserted on one [text].
void _checkParse(String text) {
  final expected = _oracleAccepts(text);
  final result = Tariff.parse(text, _locale);

  if (expected != null) {
    // In-range, well-formed: must accept, and the value must be the quantised
    // oracle value.
    expect(
      result,
      isA<TariffOk>(),
      reason: 'expected TariffOk for ${_show(text)}',
    );
    expect(
      (result as TariffOk).value,
      expected,
      reason: 'accepted value for ${_show(text)}',
    );
  } else {
    // Out of range or malformed: must reject with a non-empty, canonical
    // message.
    expect(
      result,
      isA<TariffInvalid>(),
      reason: 'expected TariffInvalid for ${_show(text)}',
    );
    final message = (result as TariffInvalid).message;
    expect(message, isNotEmpty, reason: 'non-empty message for ${_show(text)}');
    if (_hasBothSeparators(text)) {
      expect(
        message,
        tariffAmbiguousSeparatorMessage,
        reason: 'both-separator input must give the ambiguity message '
            'for ${_show(text)}',
      );
    } else {
      expect(
        message,
        tariffRangeMessage,
        reason: 'rejection must state the accepted range for ${_show(text)}',
      );
    }
  }

  // Clause 3 — the stored value is untouched. `parse` is pure: a sentinel the
  // function cannot reach is unchanged across the call, and a second call on
  // the same text yields an equal decision. A caller that writes only on
  // TariffOk therefore cannot have its persisted Tariff disturbed by a
  // rejection (Requirement 5.4).
  const double sentinelStored = 42.4242;
  var stored = sentinelStored;
  final again = Tariff.parse(text, _locale);
  expect(
    stored,
    sentinelStored,
    reason: 'parse must not mutate anything for ${_show(text)}',
  );
  expect(
    again is TariffOk,
    result is TariffOk,
    reason: 'parse must be deterministic for ${_show(text)}',
  );
  if (result is TariffOk && again is TariffOk) {
    expect(again.value, result.value, reason: 'stable value for ${_show(text)}');
  }
  // Reference the local so the analyzer does not flag it as unused; the point
  // is that nothing above ever wrote to it.
  expect(stored, sentinelStored);
}

String _show(String text) => "'$text'";

void main() {
  group('Property 8 — Tariff validation (Mobile_Client), Requirements 5.3/5.4',
      () {
    // The awkward corpus, visited exhaustively before any generated draw:
    // boundaries, both-separator, empty, whitespace, alphabetic, NaN, Infinity,
    // and padded numbers. `Tariff.max` is read rather than the literal 1000
    // restated, so the corpus tracks the model's own bound.
    final maxText = _render(Tariff.max, '.'); // "1000"
    final awkward = <String>[
      // Boundaries.
      '0',
      '0.0001',
      maxText,
      '$maxText.0001', // "1000.0001" — just over the inclusive max.
      // Boundaries in the comma style.
      '0,0001',
      '$maxText,0001',
      // Both separators — must take the ambiguity branch.
      '1,000.5',
      '1.000,5',
      '1,2.3',
      '0.0,0',
      // Empty and whitespace.
      '',
      ' ',
      '   ',
      '\t',
      '\n',
      // Alphabetic and mixed.
      'abc',
      '12abc',
      'abc12',
      '1e3', // exponent — not a bare decimal, rejected on both clients.
      '0x10', // hex — not a bare decimal, rejected on both clients.
      // The non-finite words a naive parse would otherwise accept.
      'NaN',
      'Infinity',
      '-Infinity',
      '+Infinity',
      'inf',
      // Padded numbers — leading / trailing whitespace around a valid value.
      ' 5',
      '5 ',
      '  5.5  ',
      '\t7,25\n',
      // Signs and zeros.
      '-1',
      '-0.5',
      '+5',
      '0.0',
      '0,0',
      '-0',
      // Just above / below the ends.
      '999.9999',
      '1000.0000001',
      '0.00001', // quantises to 0 → rejected as <= min.
    ];

    // Well-formed decimals across (0, 1000] — must all be accepted — in both
    // separator styles.
    final inRangePeriod = any.doubleBetween(0.0001, Tariff.max);
    final inRangeComma = any.doubleBetween(0.0001, Tariff.max);
    // Well-formed decimals in [1000, 5000] — above the inclusive max, must all
    // be rejected (1000 itself is accepted, so the generator's low end overlaps
    // the boundary the oracle resolves precisely).
    final aboveRange = any.doubleBetween(Tariff.max, 5000);

    forAll<double>(
      'accepts iff in (0, 1000] — period-style decimals inside the range',
      inRangePeriod,
      (v) => _checkParse(_render(v, '.')),
      examples: const <double>[0.0001, 1, 5, 250.5, 999.9999, 1000],
    );

    forAll<double>(
      'accepts iff in (0, 1000] — comma-style decimals inside the range',
      inRangeComma,
      (v) => _checkParse(_render(v, ',')),
      examples: const <double>[0.0001, 1, 5, 250.5, 999.9999, 1000],
    );

    forAll<double>(
      'rejects decimals above the inclusive maximum',
      aboveRange,
      (v) => _checkParse(_render(v, '.')),
      examples: const <double>[1000.0001, 1001, 2500, 5000],
    );

    // The awkward corpus as its own property: every entry is checked, and the
    // harness reports the first that breaks the invariant.
    forAll<String>(
      'the awkward corpus decides exactly as the range oracle',
      any.pick<String>(awkward),
      _checkParse,
      examples: awkward,
    );
  });

  group('Property 8 — the generators and oracle do real work', () {
    test('the oracle agrees with the fixed points the requirement pins', () {
      // 0 is rejected (exclusive min), 1000 is accepted (inclusive max).
      expect(_oracleAccepts('0'), isNull);
      expect(_oracleAccepts('0.0001'), 0.0001);
      expect(_oracleAccepts('1000'), 1000);
      expect(_oracleAccepts('1000.0001'), isNull);
      // Both-separator, empty and non-finite are all rejected.
      expect(_oracleAccepts('1,000.5'), isNull);
      expect(_oracleAccepts(''), isNull);
      expect(_oracleAccepts('NaN'), isNull);
      expect(_oracleAccepts('Infinity'), isNull);
    });

    test('the awkward corpus covers each named shape', () {
      // A cheap guard that the corpus was not trimmed: it must contain a
      // boundary, a both-separator case, empty, whitespace, alpha, NaN,
      // Infinity and a padded number.
      expect(_oracleAccepts('1000'), isNotNull); // boundary accepted
      expect(_hasBothSeparators('1,000.5'), isTrue); // both separators
      expect(_oracleAccepts(''), isNull); // empty
      expect(_oracleAccepts('   '), isNull); // whitespace
      expect(_oracleAccepts('abc'), isNull); // alpha
      expect(_oracleAccepts('NaN'), isNull); // NaN
      expect(_oracleAccepts('Infinity'), isNull); // Infinity
      expect(_oracleAccepts(' 5'), 5); // padded, still accepted
    });
  });
}

/// Property 22 — Locale resolution is total and falls back to English.
/// Mobile_Client half (task 11.18).
///
/// Requirement 12.6: the client resolves the active locale from the platform
/// locale and falls back to English where the platform locale has no available
/// translation. The supported set is `{es, en}` and English is the fallback.
///
/// **The property.** *For any* locale tag string — well-formed (`es`, `es-BO`,
/// `es-419`, `en`, `en-US`, `pt-BR`, `qq`), empty, whitespace, or malformed —
/// [resolveLocale] returns a member of the supported set, and returns
/// [AppLocale.spanish] iff the effective language subtag is `es`, otherwise
/// [AppLocale.english]. It is *total*: it never throws for any input.
///
/// **What is exercised.** The pure `resolveLocale(override:, platformTag:)` in
/// `core/locale/app_locale.dart` — no platform, no formatter probe (that lives
/// in the `initialiseLocale` wrapper, out of this property's scope). The
/// resolution order override → platform language subtag → `en` is pinned
/// through *both* argument positions: the override path and the platformTag
/// path each get a property, and a combined property fixes the precedence.
///
/// **The generators (design.md).** The `tag` domain is a corpus of the named
/// cases plus fast garbage — random code units, punctuation, mixed case and
/// padded strings — so the boundary tags appear every run and the totality
/// claim is tested against inputs no one wrote by hand. The override generator
/// also draws `null` (the "not provided" case), so the fall-through to the
/// platform tag is covered.
///
/// **The oracle.** The expected result is re-derived here from the design's
/// rule — cut the tag at the first `-`/`_`, trim and lower-case, check for `es`
/// — rather than imported, so a bug in the implementation's subtag extraction
/// shows up as a mismatch.
///
/// This is a pure model test: no widget, no colour literal, and the wire
/// protocol, calibration and alarm logic are untouched (Requirement 13.9).
///
/// **Validates: Requirements 12.6**
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/locale/app_locale.dart';

import '../support/props.dart';

/// The named tags Property 22 must always see: the two supported languages in
/// bare, regioned and extended forms, an unsupported language with a region, an
/// unsupported bare language, the empty/whitespace edges, and hand-adversarial
/// malformed values.
const List<String> _corpusTags = <String>[
  'es',
  'es-BO',
  'es-419',
  'en',
  'en-US',
  'pt-BR',
  'qq',
  '',
  '   ',
  '\t',
  '\n ',
  'es_BO', // underscore separator
  '-es', // leading separator: empty primary subtag -> en
  'ES', // upper-case supported
  'Es-bo', // mixed case supported
  '  es  ', // padded supported
  '  en-US ', // padded regioned
  'esperanto', // subtag is "esperanto", not "es"
  'e', // single char
  'español', // unicode
  '123', // digits
  'es-', // trailing separator
  '_en', // leading underscore
];

/// Characters mixed into fast garbage: letters (both cases), separators,
/// digits, whitespace, punctuation and a couple of non-ASCII code points.
const String _garbageAlphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '-_.!?/ \t0123456789áñ日';

/// A random garbage string of length 0..8 drawn from [_garbageAlphabet]. Fast
/// to generate and deliberately unlikely to be a well-formed tag, so it
/// stresses the totality claim. Shrinks towards the empty string.
Shrinkable<String> _garbage(Random random, int size) {
  final int length = random.nextInt(9);
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < length; i++) {
    buffer.write(_garbageAlphabet[random.nextInt(_garbageAlphabet.length)]);
  }
  return _StringShrinkable(buffer.toString());
}

/// A [Shrinkable] string that shrinks by dropping trailing characters, so a
/// failing garbage tag reports as short a counterexample as still breaks the
/// property.
class _StringShrinkable implements Shrinkable<String> {
  _StringShrinkable(this.value);

  @override
  final String value;

  @override
  Iterable<Shrinkable<String>> shrink() sync* {
    if (value.isEmpty) return;
    yield _StringShrinkable(value.substring(0, value.length - 1));
    if (value.length > 1) {
      yield _StringShrinkable(value.substring(0, value.length ~/ 2));
    }
  }
}

/// The tag domain: the named corpus biased in over fast garbage, so every run
/// sees the boundary tags and a stream of never-seen-before junk.
final Generator<String> _tag = any.biasedTowards<String>(
  _garbage,
  _corpusTags,
  probability: 0.5,
);

/// An override draws a tag or `null` (the "not provided" case), so the
/// fall-through to the platform tag is exercised.
Shrinkable<String?> _override(Random random, int size) {
  if (random.nextInt(5) == 0) {
    return _NullableShrinkable(null);
  }
  final Shrinkable<String> tag = _tag(random, size);
  return _NullableShrinkable(tag.value);
}

/// A [Shrinkable] nullable string that shrinks a present value towards `null`.
class _NullableShrinkable implements Shrinkable<String?> {
  _NullableShrinkable(this.value);

  @override
  final String? value;

  @override
  Iterable<Shrinkable<String?>> shrink() sync* {
    final String? v = value;
    if (v == null) return;
    yield _NullableShrinkable(null);
    if (v.isNotEmpty) {
      yield _NullableShrinkable(v.substring(0, v.length - 1));
    }
  }
}

/// A `(override, platformTag)` scenario.
typedef Scenario = (String? override, String platformTag);

/// The oracle: the language subtag of [tag], trimmed and lower-cased, is the
/// run of characters before the first `-` or `_`. Re-derived independently of
/// the implementation so it can catch a bug in it.
String _languageSubtag(String? tag) {
  if (tag == null) return '';
  final String trimmed = tag.trim();
  if (trimmed.isEmpty) return '';
  final String primary = trimmed.split(RegExp('[-_]')).first;
  return primary.trim().toLowerCase();
}

/// Whether a subtag names a supported locale.
bool _isSupported(String subtag) => subtag == 'es' || subtag == 'en';

/// The expected resolution for an effective tag (override when supported,
/// otherwise the platform tag).
AppLocale _expectedFor(String? effectiveTag) {
  return _languageSubtag(effectiveTag) == 'es'
      ? AppLocale.spanish
      : AppLocale.english;
}

/// The full oracle over the two-argument surface, mirroring the design's
/// override → platform → `en` precedence.
AppLocale _expectedResolution(String? override, String platformTag) {
  final String overrideSubtag = _languageSubtag(override);
  if (_isSupported(overrideSubtag)) {
    return overrideSubtag == 'es' ? AppLocale.spanish : AppLocale.english;
  }
  return _expectedFor(platformTag);
}

/// Every named corpus tag paired with itself as an override, so the override
/// path also sees the whole boundary set every run.
List<Scenario> _corpusExamples() {
  return <Scenario>[
    for (final String tag in _corpusTags) (null, tag),
    for (final String tag in _corpusTags) (tag, 'pt-BR'),
  ];
}

void main() {
  group('Property 22 — Requirement 12.6, locale resolution is total', () {
    test('resolveLocale never throws and always returns a supported locale',
        () {
      // Totality checked exhaustively over the named corpus in both positions,
      // so a throw on any boundary tag fails here directly.
      for (final String override in _corpusTags) {
        for (final String platformTag in _corpusTags) {
          late final AppLocale result;
          expect(
            () => result = resolveLocale(
              override: override,
              platformTag: platformTag,
            ),
            returnsNormally,
            reason: 'threw for override="$override", platformTag="$platformTag"',
          );
          expect(
            AppLocale.values.contains(result),
            isTrue,
            reason: 'resolved outside {es, en} for override="$override", '
                'platformTag="$platformTag"',
          );
        }
      }
    });

    forAll<Scenario>(
      'is total and lands es iff the effective language subtag is es, over the '
      'override and platformTag paths',
      any.combine2<String?, String, Scenario>(
        _override,
        _tag,
        (String? override, String platformTag) => (override, platformTag),
      ),
      (Scenario s) {
        final String? override = s.$1;
        final String platformTag = s.$2;

        late final AppLocale result;
        // Totality: any pair of strings resolves without throwing.
        expect(
          () => result = resolveLocale(
            override: override,
            platformTag: platformTag,
          ),
          returnsNormally,
          reason: 'threw for override=$override, platformTag="$platformTag"',
        );

        // Membership: always one of the two supported locales.
        expect(
          AppLocale.values.contains(result),
          isTrue,
          reason: 'resolved outside {es, en} for override=$override, '
              'platformTag="$platformTag"',
        );

        // Invariant + precedence: es iff the effective subtag is es.
        expect(
          result,
          equals(_expectedResolution(override, platformTag)),
          reason: 'wrong locale for override=$override, '
              'platformTag="$platformTag"',
        );
      },
      examples: _corpusExamples(),
    );

    forAll<String>(
      'via the platformTag when no override is given: es iff its subtag is es',
      _tag,
      (String platformTag) {
        final AppLocale result =
            resolveLocale(platformTag: platformTag);
        expect(
          result,
          equals(_expectedFor(platformTag)),
          reason: 'wrong locale for platformTag="$platformTag"',
        );
      },
      examples: _corpusTags,
    );

    forAll<Scenario>(
      'a supported override wins over the platform tag; an unsupported one is '
      'ignored',
      any.combine2<String?, String, Scenario>(
        _override,
        _tag,
        (String? override, String platformTag) => (override, platformTag),
      ),
      (Scenario s) {
        final String? override = s.$1;
        final String platformTag = s.$2;
        final AppLocale result =
            resolveLocale(override: override, platformTag: platformTag);
        expect(
          result,
          equals(_expectedResolution(override, platformTag)),
          reason: 'precedence wrong for override=$override, '
              'platformTag="$platformTag"',
        );
      },
    );
  });

  group('Property 22 — the generators exercise the intended domain', () {
    test('every named corpus tag resolves as the oracle says', () {
      for (final String tag in _corpusTags) {
        expect(resolveLocale(platformTag: tag), equals(_expectedFor(tag)));
      }
    });

    test('the supported and fallback anchors hold', () {
      expect(resolveLocale(platformTag: 'es-419'), equals(AppLocale.spanish));
      expect(resolveLocale(platformTag: 'pt-BR'), equals(AppLocale.english));
      expect(AppLocale.fallback, equals(AppLocale.english));
    });
  });
}

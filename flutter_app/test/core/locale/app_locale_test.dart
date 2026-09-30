/// Unit tests for [resolveLocale] (task 11.3).
///
/// Requirement 12.6.
///
/// The resolution chain is override → platform language subtag → `en`, and the
/// result is always one of the two supported locales. These examples pin:
///
///   1. an explicit override wins over the platform locale;
///   2. an unsupported or blank override is ignored and the platform locale is
///      consulted next;
///   3. the platform locale is matched on its language subtag, so region and
///      script extensions (`es-BO`, `es-419`, `en-US`) resolve the same as the
///      bare subtag;
///   4. anything unsupported — `pt-BR`, `qq`, empty, whitespace, malformed,
///      `null` — falls back to `en`; and
///   5. matching is case-insensitive and tolerates the `_` separator.
///
/// Property 22 (resolution is total and always yields a supported locale over a
/// broad tag corpus) is task 11.18 and is deliberately not written here.
library;

import 'package:leakguard/core/locale/app_locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveLocale', () {
    test('an explicit override wins over the platform locale', () {
      expect(
        resolveLocale(override: 'es', platformTag: 'en-US'),
        AppLocale.spanish,
      );
      expect(
        resolveLocale(override: 'en', platformTag: 'es-BO'),
        AppLocale.english,
      );
    });

    test('an override tag resolves on its language subtag', () {
      expect(
        resolveLocale(override: 'es-419', platformTag: 'en-US'),
        AppLocale.spanish,
      );
    });

    test('an unsupported override defers to the platform locale', () {
      expect(
        resolveLocale(override: 'pt-BR', platformTag: 'es-BO'),
        AppLocale.spanish,
      );
    });

    test('a blank override defers to the platform locale', () {
      expect(
        resolveLocale(override: '   ', platformTag: 'es'),
        AppLocale.spanish,
      );
    });

    test('the platform language subtag is matched across regions', () {
      expect(resolveLocale(platformTag: 'es'), AppLocale.spanish);
      expect(resolveLocale(platformTag: 'es-BO'), AppLocale.spanish);
      expect(resolveLocale(platformTag: 'es-419'), AppLocale.spanish);
      expect(resolveLocale(platformTag: 'en'), AppLocale.english);
      expect(resolveLocale(platformTag: 'en-US'), AppLocale.english);
    });

    test('unsupported platform locales fall back to English', () {
      expect(resolveLocale(platformTag: 'pt-BR'), AppLocale.english);
      expect(resolveLocale(platformTag: 'qq'), AppLocale.english);
    });

    test('absent, empty and malformed inputs fall back to English', () {
      expect(resolveLocale(), AppLocale.english);
      expect(resolveLocale(override: '', platformTag: ''), AppLocale.english);
      expect(resolveLocale(platformTag: '   '), AppLocale.english);
      expect(resolveLocale(platformTag: '-'), AppLocale.english);
      expect(resolveLocale(platformTag: '_'), AppLocale.english);
    });

    test('matching is case-insensitive and tolerates the underscore separator',
        () {
      expect(resolveLocale(platformTag: 'ES-bo'), AppLocale.spanish);
      expect(resolveLocale(platformTag: 'es_BO'), AppLocale.spanish);
      expect(resolveLocale(override: 'EN'), AppLocale.english);
    });
  });
}

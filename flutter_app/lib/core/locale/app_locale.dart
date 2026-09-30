/// Locale resolution for the app.
///
/// The app ships number, currency and date formatting in two locales — Spanish
/// and English — with English as the fallback. Full Spanish interface copy is
/// out of scope; this is presentation formatting only (Requirement 12.6).
///
/// The resolution chain is, in order:
///   1. An explicit user override from settings, if one is set.
///   2. The platform locale's language subtag, if it is `es` or `en`.
///   3. `en`.
///
/// The pure entry point [resolveLocale] takes an override and a platform locale
/// tag as plain strings so it is directly testable without touching the
/// platform. It is *total*: it never throws for any input, and its result is
/// always one of the two supported locales.
library;

import 'dart:developer' as developer;
import 'dart:ui' show PlatformDispatcher;

import 'package:intl/intl.dart';

/// The locales the app formats for. The result of resolution is always one of
/// these two.
enum AppLocale {
  spanish('es'),
  english('en');

  const AppLocale(this.code);

  /// The BCP 47 language subtag, used as the `locale` argument to
  /// [NumberFormat] and [DateFormat].
  final String code;

  /// The fallback used whenever nothing else resolves.
  static const AppLocale fallback = AppLocale.english;
}

/// Resolves the active locale from an explicit [override] and a [platformTag].
///
/// Both arguments are raw strings so this function can be exercised without the
/// platform. `null` means "not provided". Either may be a full BCP 47 tag
/// (`es-BO`, `en-US`, `es-419`), a bare language subtag (`es`), an unsupported
/// tag (`pt-BR`, `qq`), empty, whitespace, or otherwise malformed — the result
/// is always [AppLocale.spanish] when the resolved language subtag is `es`, and
/// [AppLocale.english] in every other case. This function never throws.
AppLocale resolveLocale({String? override, String? platformTag}) {
  // (1) An explicit user override wins, if it names a supported locale.
  final overrideLocale = _matchSupported(override);
  if (overrideLocale != null) return overrideLocale;

  // (2) The platform locale's language subtag, if supported.
  final platformLocale = _matchSupported(platformTag);
  if (platformLocale != null) return platformLocale;

  // (3) Fall back to English.
  return AppLocale.fallback;
}

/// Extracts the language subtag from a locale [tag] and matches it against the
/// supported set. Returns `null` when the tag is absent, blank or unsupported.
///
/// The language subtag is the portion before the first `-` or `_` separator,
/// compared case-insensitively (`ES-bo` resolves the same as `es-BO`).
AppLocale? _matchSupported(String? tag) {
  if (tag == null) return null;
  final trimmed = tag.trim();
  if (trimmed.isEmpty) return null;

  // Split on either separator; the language subtag is the first segment.
  final language = trimmed.split(RegExp('[-_]')).first.toLowerCase();
  for (final locale in AppLocale.values) {
    if (locale.code == language) return locale;
  }
  return null;
}

/// Resolves the active locale using the live platform locale and applies it to
/// `Intl.defaultLocale`. Call once at startup.
///
/// The [override] is the user's settings choice, if any. The platform locale is
/// read from [PlatformDispatcher.instance.locale]. After resolution this probes
/// [NumberFormat] and [DateFormat] construction for the resolved locale; if
/// either fails it downgrades to English and records a diagnostic line rather
/// than letting the failure surface inside a build method later.
AppLocale initialiseLocale({String? override}) {
  final platformTag = PlatformDispatcher.instance.locale.toLanguageTag();
  var resolved = resolveLocale(override: override, platformTag: platformTag);

  if (!_formattersAvailable(resolved.code)) {
    developer.log(
      'Locale "${resolved.code}" failed formatter construction; '
      'downgrading to "${AppLocale.fallback.code}".',
      name: 'app_locale',
    );
    resolved = AppLocale.fallback;
  }

  Intl.defaultLocale = resolved.code;
  return resolved;
}

/// Returns whether both a [NumberFormat] and a [DateFormat] can be constructed
/// for [localeCode]. Construction is where `intl` validates locale data, so a
/// bad locale fails here rather than at the first format call inside a widget.
bool _formattersAvailable(String localeCode) {
  try {
    NumberFormat('#,##0.00', localeCode);
    DateFormat('d MMM · HH:mm:ss', localeCode);
    return true;
  } catch (_) {
    return false;
  }
}

/// Example tests pinning every fixed WattVision constant for the
/// Mobile_Client.
///
/// Requirements 1.6 and 1.7 name exact values, so these are example tests
/// rather than properties: there is nothing to generate over, and a property
/// would only restate the table. The point is that a later phase cannot drift
/// one of these numbers without a test going red.
///
/// Everything is asserted against `lib/core/theme/token_registry.dart`, which
/// task 1.6 made the single machine-readable record of the user-supplied
/// DESIGN.md. The expected values below are written as the hex text and the
/// plain numbers DESIGN.md itself uses, and compared through
/// `contrast.dart`'s parser, so the comparison runs DESIGN.md → parser →
/// registry rather than registry → registry.
///
/// **How the eleven Requirement 1.6 colours are selected.** By the
/// `requirement16` flag, never by `section == '§2'`. The registry labels
/// `gradientGreen`, `surfaceRaised`, `border` and `alertBoxFill` as `§3`
/// because that is where DESIGN.md puts them, while Requirement 1.6 still
/// enumerates them alongside the §2 colours. Filtering on section would find
/// seven, not eleven — the registry records this as a resolved ambiguity, and
/// the arithmetic is asserted below so the distinction cannot quietly rot.
///
/// Deliberately **not** covered here:
/// * The multiple-of-8 spacing property and the `layoutSpacing` filtering —
///   task 1.12 (Property 21). `kLayoutScale` is pinned here only as the fixed
///   §5 constants: twelve columns, base 8, the four enumerated steps.
/// * The contrast arithmetic behind `accentText`, `lightAccentText` and the two
///   High_Contrast_Dark overrides — `contrast_test.dart` (task 1.4) pins the
///   measured ratios, and Properties 16, 17 and 26 generalise them in tasks
///   3.9, 3.10 and 3.12. What is asserted here is that the four tokens exist at
///   the right values, in the right appearances, documented. Until task 3.1
///   this group asserted their *absence*, so they could not arrive by accident.
///
/// `../support/props.dart` is deliberately not imported: these are example
/// tests, so the generator harness has nothing to do here.
///
/// Requirements: 1.6, 1.7, 1.9, 1.10.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:leakguard/core/theme/token_registry.dart';

import 'contrast.dart';

// --- the fixed values, as DESIGN.md states them ------------------------------

/// The eleven colours Requirement 1.6 enumerates, in the order the criterion
/// lists them, with the WattVision section each value actually comes from.
const List<({String name, String hex, int argb, String section})>
    kRequirement16Colours =
    <({String name, String hex, int argb, String section})>[
  (name: 'background', hex: '#121212', argb: 0xFF121212, section: '§2'),
  (name: 'surface', hex: '#1E1E1E', argb: 0xFF1E1E1E, section: '§2'),
  (name: 'accent', hex: '#00E5FF', argb: 0xFF00E5FF, section: '§2'),
  (name: 'alert', hex: '#FF453A', argb: 0xFFFF453A, section: '§2'),
  (name: 'normal', hex: '#32D74B', argb: 0xFF32D74B, section: '§2'),
  (name: 'gradientGreen', hex: '#30D158', argb: 0xFF30D158, section: '§3'),
  (name: 'surfaceRaised', hex: '#252525', argb: 0xFF252525, section: '§3'),
  (name: 'border', hex: '#2C2C2E', argb: 0xFF2C2C2E, section: '§3'),
  (name: 'textPrimary', hex: '#FFFFFF', argb: 0xFFFFFFFF, section: '§2'),
  (name: 'textSecondary', hex: '#98989D', argb: 0xFF98989D, section: '§2'),
  (name: 'alertBoxFill', hex: '#3A1C1C', argb: 0xFF3A1C1C, section: '§3'),
];

/// The six numeric values Requirement 1.7 enumerates: card radius 16, card
/// padding 20, hairline 1, title 24, KPI 32, body 14.
const List<({String name, double value, String section})>
    kRequirement17Numerics = <({String name, double value, String section})>[
  (name: 'radiusCard', value: 16, section: '§3'),
  (name: 'cardPadding', value: 20, section: '§3'),
  (name: 'hairline', value: 1, section: '§3'),
  (name: 'sizeTitle', value: 24, section: '§4'),
  (name: 'sizeKpi', value: 32, section: '§4'),
  (name: 'sizeBody', value: 14, section: '§4'),
];

/// The four tokens task 3.1 added, with the value and appearance each carries.
///
/// `accentText` is the Requirement 11.4 accent-as-text token, aliasing the
/// graphical accent in the dark appearances; `lightAccentText` is its light
/// counterpart, darkened because the light accent fails as text. The other two
/// are the High_Contrast_Dark overrides of Requirement 9.2.
///
/// Until 3.1 this list recorded the same four names as values that must *not*
/// exist yet, so they could not appear without a deliberate edit here. That
/// edit is this one.
const List<({String name, String hex, int argb, TokenAppearance appearance})>
    kTask31Tokens =
    <({String name, String hex, int argb, TokenAppearance appearance})>[
  (
    name: 'accentText',
    hex: '#00E5FF',
    argb: 0xFF00E5FF,
    appearance: TokenAppearance.dark,
  ),
  (
    name: 'hcTextSecondary',
    hex: '#C7C7CC',
    argb: 0xFFC7C7CC,
    appearance: TokenAppearance.highContrastDark,
  ),
  (
    name: 'hcBorder',
    hex: '#48484A',
    argb: 0xFF48484A,
    appearance: TokenAppearance.highContrastDark,
  ),
  (
    name: 'lightAccentText',
    hex: '#00707F',
    argb: 0xFF00707F,
    appearance: TokenAppearance.light,
  ),
];

/// The custom-property name the accent-text split is keyed by on the web side.
const String kAccentTextCssName = '--accent-text';

/// The amber WATCH Token_Extension of Requirement 1.10, and the two §2 values
/// its rationale has to name as the gap it fills.
const String kWatchHex = '#FFD60A';
const String kSecondaryAccentHex = '#32D74B';
const String kAlertAccentHex = '#FF453A';

// --- registry lookups --------------------------------------------------------

TokenSpec _token(String name) {
  return kWattVisionTokens.firstWhere(
    (TokenSpec token) => token.name == name,
    orElse: () => throw StateError('no WattVision token named $name'),
  );
}

TokenExtensionSpec _extension(String name) {
  return kTokenExtensions.firstWhere(
    (TokenExtensionSpec extension) => extension.name == name,
    orElse: () => throw StateError('no Token_Extension named $name'),
  );
}

int _argbOf(TokenSpec token) {
  final argb = token.argb;
  if (argb == null) {
    throw StateError('${token.name} is not a colour token');
  }
  return argb;
}

Iterable<String> _allRegisteredNames() => <String>[
      ...kWattVisionTokens.map((TokenSpec t) => t.name),
      ...kTokenExtensions.map((TokenExtensionSpec e) => e.name),
    ];

Iterable<String> _allRegisteredCssNames() => <String>[
      ...kWattVisionTokens.map((TokenSpec t) => t.cssName),
      ...kTokenExtensions.map((TokenExtensionSpec e) => e.cssName),
    ];

void main() {
  group('Requirement 1.6 — the eleven enumerated colours', () {
    test('the requirement16 flag selects exactly eleven tokens', () {
      final flagged = kWattVisionTokens
          .where((TokenSpec token) => token.requirement16)
          .map((TokenSpec token) => token.name)
          .toList();

      expect(flagged, hasLength(11));
      expect(
        flagged,
        containsAll(
          kRequirement16Colours.map(
            (({String name, String hex, int argb, String section}) c) => c.name,
          ),
        ),
      );
    });

    test('section is not the selector: §2 alone would find only seven', () {
      // The registry labels row hover, the card border, the alert box fill and
      // the chart gradient partner as §3 because that is where DESIGN.md puts
      // them. Requirement 1.6 still enumerates them. Both facts, asserted.
      final section2 = kWattVisionTokens.where(
        (TokenSpec token) => token.isColour && token.section == '§2',
      );
      expect(section2, hasLength(7));
      expect(
        kWattVisionTokens.where((TokenSpec t) => t.isColour),
        hasLength(11),
        reason: 'the eleven colours split 7 in §2 and 4 in §3',
      );

      for (final name in <String>[
        'gradientGreen',
        'surfaceRaised',
        'border',
        'alertBoxFill',
      ]) {
        final token = _token(name);
        expect(token.section, '§3', reason: '$name is honestly labelled §3');
        expect(
          token.requirement16,
          isTrue,
          reason: '$name is still one of the eleven Requirement 1.6 colours',
        );
      }
    });

    for (final colour in kRequirement16Colours) {
      test('${colour.name} is ${colour.hex}', () {
        final token = _token(colour.name);

        expect(token.kind, TokenValueKind.color);
        expect(token.requirement16, isTrue);
        expect(token.section, colour.section);
        expect(_argbOf(token), colour.argb);
        // DESIGN.md's hex text, parsed, must land on the registry's argb.
        expect(argbColour(_argbOf(token)), equals(hexColour(colour.hex)));
      });
    }

    test('every flagged token is an opaque colour with a value', () {
      for (final token
          in kWattVisionTokens.where((TokenSpec t) => t.requirement16)) {
        expect(token.kind, TokenValueKind.color, reason: token.name);
        expect(token.argb, isNotNull, reason: token.name);
        expect(
          (_argbOf(token) >> 24) & 0xFF,
          0xFF,
          reason: '${token.name} must be fully opaque',
        );
        expect(token.spec.trim(), isNotEmpty, reason: token.name);
      }
    });

    test('no token name or css name is registered twice', () {
      final names = _allRegisteredNames().toList();
      expect(names.toSet(), hasLength(names.length));

      // Light entries share a cssName with their dark counterpart by design,
      // so uniqueness is asserted per appearance rather than globally.
      for (final appearance in TokenAppearance.values) {
        final cssNames = <String>[
          ...kWattVisionTokens
              .where((TokenSpec t) => t.appearance == appearance)
              .map((TokenSpec t) => t.cssName),
          ...kTokenExtensions
              .where((TokenExtensionSpec e) => e.appearance == appearance)
              .map((TokenExtensionSpec e) => e.cssName),
        ];
        expect(
          cssNames.toSet(),
          hasLength(cssNames.length),
          reason: 'duplicate css name within ${appearance.name}',
        );
      }
    });
  });

  group('Requirement 1.7 — the six enumerated numeric values', () {
    test('the requirement17 flag selects exactly six tokens', () {
      final flagged = kWattVisionTokens
          .where((TokenSpec token) => token.requirement17)
          .map((TokenSpec token) => token.name)
          .toList();

      expect(flagged, hasLength(6));
      expect(
        flagged,
        containsAll(
          kRequirement17Numerics.map(
            (({String name, double value, String section}) n) => n.name,
          ),
        ),
      );
    });

    for (final numeric in kRequirement17Numerics) {
      test('${numeric.name} is ${numeric.value.toInt()}px', () {
        final token = _token(numeric.name);

        expect(token.kind, TokenValueKind.length);
        expect(token.requirement17, isTrue);
        expect(token.section, numeric.section);
        expect(token.numeric, numeric.value);
        expect(token.unit, 'px');
        expect(token.value, '${numeric.value.toInt()}px');
      });
    }

    test('the §4 families are Inter for text and JetBrains Mono for KPIs', () {
      // The sizes above are only half of §4; the families they are set in are
      // the other half, and the weights live in the recorded spec text.
      final sans = _token('fontSans');
      expect(sans.kind, TokenValueKind.fontFamily);
      expect(sans.section, '§4');
      expect(sans.value, startsWith("'Inter'"));
      expect(sans.spec, contains('Inter SemiBold'));
      expect(sans.spec, contains('Inter Regular'));

      final mono = _token('fontMono');
      expect(mono.kind, TokenValueKind.fontFamily);
      expect(mono.section, '§4');
      expect(mono.value, startsWith("'JetBrains Mono'"));
      expect(mono.spec, contains('Bold'));

      expect(_token('sizeTitle').numeric, 24);
      expect(_token('sizeKpi').numeric, 32);
      expect(_token('sizeBody').numeric, 14);
    });
  });

  group('the two §2/§3 greens stay distinct', () {
    test('normal is #32D74B and gradientGreen is #30D158', () {
      expect(argbColour(_argbOf(_token('normal'))), hexColour('#32D74B'));
      expect(
        argbColour(_argbOf(_token('gradientGreen'))),
        hexColour('#30D158'),
      );
      expect(_argbOf(_token('normal')), isNot(_argbOf(_token('gradientGreen'))));
    });

    test('both are WattVision values, neither is a Token_Extension', () {
      // `rationale` and `consumedBy` only exist on TokenExtensionSpec, so
      // absence from kTokenExtensions is exactly "carries no rationale".
      for (final name in <String>['normal', 'gradientGreen']) {
        expect(_token(name).requirement16, isTrue, reason: name);
        expect(
          kTokenExtensions.map((TokenExtensionSpec e) => e.name),
          isNot(contains(name)),
          reason: '$name is a WattVision value, not a Token_Extension',
        );
      }
    });
  });

  group('WattVision §5 layout constants', () {
    test('Grid_12 has twelve columns on a base of eight', () {
      expect(kLayoutScale.section, '§5');
      expect(kLayoutScale.columns, 12);
      expect(kLayoutScale.spacingBase, 8);
    });

    test('the enumerated steps are 8, 16, 24 and 32', () {
      expect(kLayoutScale.enumeratedSteps, <double>[8, 16, 24, 32]);
      for (final step in kLayoutScale.enumeratedSteps) {
        expect(step % kLayoutScale.spacingBase, 0, reason: '$step');
      }
    });
  });

  group('Requirement 1.9 — every Token_Extension is documented', () {
    // The property form of this, over the generated extension set, is task
    // 1.12 (Property 21). Pinned here as an example over the registry as it
    // stands, so a phase-2 addition without documentation fails immediately.
    test('rationale and consumedBy are non-empty for every extension', () {
      expect(kTokenExtensions, isNotEmpty);
      for (final extension in kTokenExtensions) {
        expect(
          extension.rationale.trim(),
          isNotEmpty,
          reason: '${extension.name} records no reason for its existence',
        );
        expect(
          extension.consumedBy.trim(),
          isNotEmpty,
          reason: '${extension.name} records no consumer',
        );
      }
    });

    test('the light palette carries a rationale at palette scope too', () {
      expect(kLightAppearanceRationale.appearance, TokenAppearance.light);
      expect(kLightAppearanceRationale.rationale.trim(), isNotEmpty);
      expect(kLightAppearanceRationale.consumedBy.trim(), isNotEmpty);
    });
  });

  group('Requirement 1.10 — the amber WATCH extension', () {
    test('watch is #FFD60A and is a declared Token_Extension', () {
      final watch = _extension('watch');

      expect(watch.kind, TokenValueKind.color);
      expect(watch.argb, 0xFFFFD60A);
      expect(argbColour(watch.argb!), equals(hexColour(kWatchHex)));
      expect(watch.requirement, '1.10');
      expect(
        kWattVisionTokens.map((TokenSpec t) => t.name),
        isNot(contains('watch')),
        reason: 'watch is absent from WattVision, so it cannot be a §2 token',
      );
    });

    test('its rationale records the gap between #32D74B and #FF453A', () {
      final watch = _extension('watch');

      expect(watch.rationale, contains('intermediate advisory'));
      expect(watch.rationale, contains(kSecondaryAccentHex));
      expect(watch.rationale, contains(kAlertAccentHex));
      expect(watch.consumedBy, contains('WATCH'));
      // Requirement 1.11: amber never carries the state on its own.
      expect(watch.statusAffordance?.trim(), isNotEmpty);
    });
  });

  group('the accent-text and High_Contrast_Dark tokens of task 3.1', () {
    for (final token in kTask31Tokens) {
      test('${token.name} is ${token.hex} in the ${token.appearance.name} '
          'appearance', () {
        final extension = _extension(token.name);

        expect(extension.kind, TokenValueKind.color);
        expect(extension.argb, token.argb);
        expect(argbColour(extension.argb!), equals(hexColour(token.hex)));
        expect(extension.appearance, token.appearance);
        // Requirement 1.9. None of the four comes from WattVision, so each has
        // to say why it exists and what uses it.
        expect(extension.rationale.trim(), isNotEmpty);
        expect(extension.consumedBy.trim(), isNotEmpty);
        expect(
          kWattVisionTokens.map((TokenSpec t) => t.name),
          isNot(contains(token.name)),
          reason: '${token.name} is absent from WattVision, so it cannot be a '
              '§2–§5 token',
        );
      });
    }

    test('both accent-text values share the one web-side key', () {
      // On the web these are two declarations of --accent-text in two
      // selectors; here they are two entries separated by appearance. The
      // mapping only works if the cssName agrees.
      for (final name in <String>['accentText', 'lightAccentText']) {
        expect(_extension(name).cssName, kAccentTextCssName, reason: name);
      }
      expect(_allRegisteredCssNames(), contains(kAccentTextCssName));
    });

    test('accentText aliases the graphical accent in dark and differs in light',
        () {
      // The whole point of the split: nothing changes in the dark appearances,
      // and the light appearance gets somewhere to differ.
      expect(_extension('accentText').argb, _argbOf(_token('accent')));
      expect(
        _extension('lightAccentText').argb,
        isNot(_extension('lightAccent').argb),
      );
      expect(_extension('accentText').requirement, '11.4');
      expect(_extension('lightAccentText').requirement, '11.4');
    });

    test('the high-contrast overrides are exactly two, and only text and border',
        () {
      final hcEntries = kTokenExtensions
          .where((TokenExtensionSpec e) =>
              e.appearance == TokenAppearance.highContrastDark)
          .map((TokenExtensionSpec e) => e.name)
          .toList()
        ..sort();

      expect(hcEntries, <String>['hcBorder', 'hcTextSecondary']);
      // Requirement 9.2 — the appearance stays inside the §2 dark family, so
      // no surface value may be overridden.
      for (final surface in <String>['background', 'surface', 'surfaceRaised']) {
        expect(
          hcEntries,
          isNot(contains('hc${surface[0].toUpperCase()}${surface.substring(1)}')),
          reason: 'High_Contrast_Dark must inherit $surface unchanged',
        );
      }
      expect(_extension('hcTextSecondary').requirement, '9.2');
      expect(_extension('hcBorder').requirement, '9.2');
    });

    test('High_Contrast_Dark carries a rationale at palette scope', () {
      expect(
        kHighContrastDarkRationale.appearance,
        TokenAppearance.highContrastDark,
      );
      expect(kHighContrastDarkRationale.rationale.trim(), isNotEmpty);
      expect(kHighContrastDarkRationale.consumedBy.trim(), isNotEmpty);
      expect(kHighContrastDarkRationale.constraint, contains('9.2'));
    });

    test('the appearances are any, dark, High_Contrast_Dark and light', () {
      expect(
        TokenAppearance.values,
        <TokenAppearance>[
          TokenAppearance.any,
          TokenAppearance.dark,
          TokenAppearance.highContrastDark,
          TokenAppearance.light,
        ],
      );
    });
  });
}

/// Machine-readable `Design_Token_Registry` for the Mobile_Client.
///
/// This file is data, not presentation. `design_tokens.dart` is what widgets
/// read; this registry is what the compliance suite reads, and it carries the
/// metadata a `const Color` cannot: which WattVision section a value comes
/// from, whether a value is a Token_Extension, why an extension exists, and
/// what consumes it.
///
/// It mirrors `react_app/src/styles/token-registry.json` value for value. That
/// file is keyed by CSS custom-property name and carries a `flutterName` on
/// every entry; the `cssName` field here is the other half of that mapping, so
/// the cross-client agreement check (Requirements 13.1 and 13.2, task 1.11) can
/// walk the relationship in both directions.
///
/// Requirements: 1.1 (one named token per WattVision §2–§5 value), 1.9 (every
/// Token_Extension records its reason and its consumer), 1.10 (the amber WATCH
/// colour is a declared extension), 9.8 (the pastel definition is explicit).
///
/// Deliberately **not** registered here:
/// * Per-Layout_Mode gutters, outer padding and the Expanded content cap —
///   owned by task 5.1 (`lib/core/layout/layout_mode.dart`). [kLayoutScale]
///   records the column count and the spacing base only.
library;

// ---------------------------------------------------------------------------
// Shape
// ---------------------------------------------------------------------------

/// What kind of value a registry entry holds.
///
/// [registryName] is the string the React registry writes in its `type` field,
/// so the two sides compare without a translation table.
enum TokenValueKind {
  color('color'),
  length('length'),
  fontFamily('font-family'),
  duration('duration'),
  durationAlias('duration-alias'),
  easing('easing'),
  shadow('shadow');

  const TokenValueKind(this.registryName);

  /// The `type` string used by the React registry mirror.
  final String registryName;
}

/// Which appearance an entry's value belongs to.
///
/// The React registry expresses this through the CSS selector the declaration
/// lives in; this is the same fact without the CSS syntax. [any] means the
/// value is appearance-independent (declared once, on `:root`).
///
/// [highContrastDark] holds only the values that appearance *overrides*. It is
/// not a full palette: every other value is inherited from [dark] unchanged,
/// which is precisely what Requirement 9.2 means by staying inside the
/// WattVision §2 dark family. On the web side the same relationship is a
/// grouped selector rather than a duplicated block.
enum TokenAppearance { any, dark, highContrastDark, light }

/// A value sourced from WattVision itself.
///
/// Colours carry [argb] in `0xAARRGGBB` form; lengths and durations carry
/// [numeric] with its [unit]; font stacks and other string-valued tokens carry
/// [value].
class TokenSpec {
  const TokenSpec({
    required this.name,
    required this.cssName,
    required this.kind,
    required this.section,
    required this.spec,
    this.appearance = TokenAppearance.any,
    this.argb,
    this.numeric,
    this.unit,
    this.value,
    this.requirement16 = false,
    this.requirement17 = false,
    this.layoutSpacing = false,
    this.note,
  });

  /// The Dart-side name, matching the `flutterName` in the React mirror.
  final String name;

  /// The CSS custom-property name this entry is keyed by on the web side.
  final String cssName;

  final TokenValueKind kind;

  /// The WattVision section the value actually comes from: `§2`, `§3`, `§4` or
  /// `§5`.
  ///
  /// Honest rather than convenient. Row hover, the card border and the alert
  /// box fill are §3 values even though Requirement 1.6 enumerates them
  /// alongside the §2 colours; [requirement16] is the flag that records that
  /// membership, so the two facts stay separable.
  final String section;

  /// What WattVision says about this value, close to verbatim.
  final String spec;

  final TokenAppearance appearance;

  /// `0xAARRGGBB`, for [TokenValueKind.color] entries only.
  final int? argb;

  /// The numeric part of a length or duration.
  final double? numeric;

  /// The unit [numeric] is expressed in: `px` or `ms`.
  final String? unit;

  /// The raw declared value, for entries that are neither a colour nor a
  /// single number.
  final String? value;

  /// One of the eleven colours Requirement 1.6 enumerates.
  final bool requirement16;

  /// One of the six numeric values Requirement 1.7 enumerates: card radius 16,
  /// card padding 20, hairline 1, title 24, KPI 32, body 14.
  final bool requirement17;

  /// Whether this value is used for layout gaps, gutters or outer padding, and
  /// so falls under the Requirement 1.8 multiple-of-8 rule.
  ///
  /// A data-driven flag, not an exception list: `cardPadding` (20) is a §3
  /// component value rather than a layout gap, so it is `false` and the
  /// property test simply does not select it.
  final bool layoutSpacing;

  /// Anything worth recording that the fields above do not carry.
  final String? note;

  bool get isColour => kind == TokenValueKind.color;
}

/// A value the interface needs that WattVision does not supply.
///
/// Requirement 1.9 is the whole reason this type is separate from [TokenSpec]:
/// [rationale] records why the value is absent from WattVision, and
/// [consumedBy] records the state or surface that uses it. Both are required,
/// so an extension cannot be added without documenting it.
class TokenExtensionSpec {
  const TokenExtensionSpec({
    required this.name,
    required this.cssName,
    required this.kind,
    required this.rationale,
    required this.consumedBy,
    this.appearance = TokenAppearance.any,
    this.argb,
    this.numeric,
    this.unit,
    this.value,
    this.derivedFrom,
    this.aliasOf,
    this.reduceMotionMillis,
    this.layoutSpacing = false,
    this.requirement,
    this.statusAffordance,
    this.floorNote,
    this.conflict,
    this.note,
  });

  /// The Dart-side name, matching the `flutterName` in the React mirror.
  final String name;

  /// The CSS custom-property name this entry is keyed by on the web side.
  ///
  /// Light-appearance entries share a `cssName` with their dark counterpart —
  /// the web side separates them by selector, this side by [appearance] and by
  /// the `light` prefix on [name].
  final String cssName;

  final TokenValueKind kind;

  /// Requirement 1.9 — why the value is absent from WattVision.
  final String rationale;

  /// Requirement 1.9 — the state or surface that consumes the value.
  final String consumedBy;

  final TokenAppearance appearance;

  /// `0xAARRGGBB`, for [TokenValueKind.color] entries only.
  final int? argb;

  final double? numeric;

  final String? unit;

  /// The raw declared value, for easing curves and shadows.
  final String? value;

  /// The token this value is derived from, and the relationship followed.
  final String? derivedFrom;

  /// For [TokenValueKind.durationAlias]: the motion token this resolves to
  /// when Reduce_Motion is off.
  final String? aliasOf;

  /// For [TokenValueKind.durationAlias]: the duration this collapses to when
  /// Reduce_Motion is on.
  final double? reduceMotionMillis;

  /// See [TokenSpec.layoutSpacing]. `s1` (4) is `false` by design.
  final bool layoutSpacing;

  /// The acceptance criterion that calls for this extension, where one does.
  final String? requirement;

  /// Requirement 1.11 — how the value is presented without relying on colour.
  final String? statusAffordance;

  final String? floorNote;

  /// A WattVision rule this value knowingly contradicts.
  final String? conflict;

  final String? note;

  bool get isColour => kind == TokenValueKind.color;
}

/// A rationale that applies to a whole palette rather than to one token.
class PaletteRationale {
  const PaletteRationale({
    required this.appearance,
    required this.rationale,
    required this.consumedBy,
    required this.constraint,
  });

  final TokenAppearance appearance;

  /// Requirement 1.9, at palette scope.
  final String rationale;

  final String consumedBy;

  /// The criterion that constrains the palette's values.
  final String constraint;
}

/// The WattVision §5 layout scale.
class LayoutScaleSpec {
  const LayoutScaleSpec({
    required this.section,
    required this.columns,
    required this.spacingBase,
    required this.enumeratedSteps,
    required this.rule,
    required this.note,
  });

  final String section;

  /// Grid_12 — twelve equal columns.
  final int columns;

  /// Spacing is expressed in whole multiples of this.
  final double spacingBase;

  /// The steps WattVision §5 names explicitly.
  final List<double> enumeratedSteps;

  final String rule;

  final String note;
}

/// The computable definition of "pastel".
///
/// WattVision §6 forbids pastel colours without defining them. Undefined, the
/// criterion is unverifiable, so the thresholds live here as the single
/// definition both clients test against.
class PastelRuleSpec {
  const PastelRuleSpec({
    required this.requirement,
    required this.wattVisionSection,
    required this.definition,
    required this.lightnessAbove,
    required this.saturationBelow,
    required this.predicate,
    required this.invariant,
    required this.lightnessFormula,
    required this.saturationFormula,
    required this.hslNote,
    required this.achromatic,
    required this.neutral,
    required this.thresholdProvenance,
    required this.consumedBy,
    required this.knownLiteralRuleHits,
  });

  final String requirement;
  final String wattVisionSection;
  final String definition;

  /// A colour is pastel only when its HSL lightness exceeds this.
  final double lightnessAbove;

  /// A colour is pastel only when its HSL saturation falls below this.
  final double saturationBelow;

  final String predicate;
  final String invariant;

  /// HSL lightness, over channels normalised to `[0, 1]`.
  final String lightnessFormula;

  /// HSL saturation, over the same normalised channels.
  final String saturationFormula;

  final String hslNote;

  final AchromaticRuleSpec achromatic;

  /// The near-neutral carve-out. Strictly wider than [achromatic].
  final NeutralRuleSpec neutral;

  /// Why these particular numbers.
  final String thresholdProvenance;

  final String consumedBy;

  final KnownPastelHits knownLiteralRuleHits;
}

/// The achromatic exclusion that keeps the pastel rule from rejecting white.
class AchromaticRuleSpec {
  const AchromaticRuleSpec({
    required this.definition,
    required this.saturationAtMost,
    required this.excludedExamples,
    required this.reason,
  });

  final String definition;

  /// Saturation at or below this counts as achromatic.
  final double saturationAtMost;

  final List<String> excludedExamples;
  final String reason;
}

/// The near-neutral carve-out from the pastel rule.
///
/// [AchromaticRuleSpec] excludes colours with *no* hue at all. This excludes
/// colours with barely any: a grey carrying a faint cast is still read as a
/// grey, not as a pastel. The two are separate types because they are separate
/// facts — achromatic is arithmetic (three equal channels), this is a
/// judgement call with a threshold someone chose.
class NeutralRuleSpec {
  const NeutralRuleSpec({
    required this.definition,
    required this.saturationAtMost,
    required this.excludedExamples,
    required this.reason,
    required this.decidedBy,
    required this.supersedes,
  });

  final String definition;

  /// Saturation at or below this counts as near-neutral.
  ///
  /// Wider than [AchromaticRuleSpec.saturationAtMost], which it subsumes: a
  /// colour with saturation 0 is neutral too.
  final double saturationAtMost;

  final List<String> excludedExamples;
  final String reason;

  /// Who chose the threshold, and on what grounds.
  final String decidedBy;

  /// What the carve-out replaced.
  final String supersedes;
}

/// Values the pastel predicate flags as literally written.
///
/// Informational, not part of the rule. Recorded so a finding is not
/// rediscovered as a surprise.
class KnownPastelHits {
  const KnownPastelHits({
    required this.appearance,
    required this.values,
    required this.note,
  });

  final TokenAppearance appearance;
  final List<String> values;
  final String note;
}

// ---------------------------------------------------------------------------
// WattVision values
// ---------------------------------------------------------------------------

/// Every value sourced from WattVision §2, §3, §4 and §5.
///
/// Eleven entries carry [TokenSpec.requirement16] — the colours Requirement 1.6
/// enumerates. Six carry [TokenSpec.requirement17] — 16, 20, 1, 24, 32, 14.
const List<TokenSpec> kWattVisionTokens = <TokenSpec>[
  // --- §2 / §3 colours ---------------------------------------------------
  TokenSpec(
    name: 'background',
    cssName: '--bg',
    kind: TokenValueKind.color,
    section: '§2',
    appearance: TokenAppearance.dark,
    argb: 0xFF121212,
    spec: 'Primary background',
    requirement16: true,
  ),
  TokenSpec(
    name: 'surface',
    cssName: '--surface',
    kind: TokenValueKind.color,
    section: '§2',
    appearance: TokenAppearance.dark,
    argb: 0xFF1E1E1E,
    spec: 'Card surface; §3 repeats it as the card background',
    requirement16: true,
  ),
  TokenSpec(
    name: 'accent',
    cssName: '--accent',
    kind: TokenValueKind.color,
    section: '§2',
    argb: 0xFF00E5FF,
    spec: 'Primary accent (data) — charts, main KPIs, action buttons',
    requirement16: true,
  ),
  TokenSpec(
    name: 'alert',
    cssName: '--alert',
    kind: TokenValueKind.color,
    section: '§2',
    argb: 0xFFFF453A,
    spec: 'Alert accent — consumption spikes, vampire alerts; §3 reuses it '
        'for alert text and the 4px left border',
    requirement16: true,
  ),
  TokenSpec(
    name: 'normal',
    cssName: '--normal',
    kind: TokenValueKind.color,
    section: '§2',
    argb: 0xFF32D74B,
    spec: 'Secondary accent — live status and normal values',
    requirement16: true,
    note: 'Distinct from gradientGreen. WattVision §2 names this as the '
        'secondary accent and §3 names #30D158 for the chart area gradient; '
        'they are two WattVision values, so both are plain tokens and '
        'neither is a Token_Extension.',
  ),
  TokenSpec(
    name: 'gradientGreen',
    cssName: '--gradient-green',
    kind: TokenValueKind.color,
    section: '§3',
    argb: 0xFF30D158,
    spec: 'Chart area gradient partner',
    requirement16: true,
    note: 'A WattVision value in its own right, not a Token_Extension and '
        'not a variant of normal.',
  ),
  TokenSpec(
    name: 'surfaceRaised',
    cssName: '--surface-raised',
    kind: TokenValueKind.color,
    section: '§3',
    appearance: TokenAppearance.dark,
    argb: 0xFF252525,
    spec: 'Table row hover background',
    requirement16: true,
  ),
  TokenSpec(
    name: 'border',
    cssName: '--border',
    kind: TokenValueKind.color,
    section: '§3',
    appearance: TokenAppearance.dark,
    argb: 0xFF2C2C2E,
    spec: 'Subtle 1px card border, chart grid lines, table row bottom border',
    requirement16: true,
  ),
  TokenSpec(
    name: 'textPrimary',
    cssName: '--text-primary',
    kind: TokenValueKind.color,
    section: '§2',
    appearance: TokenAppearance.dark,
    argb: 0xFFFFFFFF,
    spec: 'Primary text',
    requirement16: true,
  ),
  TokenSpec(
    name: 'textSecondary',
    cssName: '--text-secondary',
    kind: TokenValueKind.color,
    section: '§2',
    appearance: TokenAppearance.dark,
    argb: 0xFF98989D,
    spec: 'Secondary text (labels)',
    requirement16: true,
  ),
  TokenSpec(
    name: 'alertBoxFill',
    cssName: '--alert-fill',
    kind: TokenValueKind.color,
    section: '§3',
    appearance: TokenAppearance.dark,
    argb: 0xFF3A1C1C,
    spec: 'Alert box background',
    requirement16: true,
  ),

  // --- §3 geometry -------------------------------------------------------
  TokenSpec(
    name: 'radiusCard',
    cssName: '--radius-card',
    kind: TokenValueKind.length,
    section: '§3',
    numeric: 16,
    unit: 'px',
    value: '16px',
    spec: 'Cards: border-radius 16px',
    requirement17: true,
  ),
  TokenSpec(
    name: 'cardPadding',
    cssName: '--card-padding',
    kind: TokenValueKind.length,
    section: '§3',
    numeric: 20,
    unit: 'px',
    value: '20px',
    spec: 'Cards: internal padding 20px',
    requirement17: true,
    note: '20 is not a multiple of 8. It is a WattVision §3 component value, '
        'not a layout gap, gutter or outer padding, so Requirement 1.8 does '
        'not apply to it. layoutSpacing is false.',
  ),
  TokenSpec(
    name: 'hairline',
    cssName: '--hairline',
    kind: TokenValueKind.length,
    section: '§3',
    numeric: 1,
    unit: 'px',
    value: '1px',
    spec: 'Cards: subtle border 1px solid #2C2C2E; tables: row border-bottom '
        '1px',
    requirement17: true,
  ),

  // --- §4 type -----------------------------------------------------------
  TokenSpec(
    name: 'fontSans',
    cssName: '--font-sans',
    kind: TokenValueKind.fontFamily,
    section: '§4',
    value: "'Inter', system-ui, -apple-system, 'Segoe UI', sans-serif",
    spec: 'Titles: Inter SemiBold; Body: Inter Regular',
    note: 'Inter is the WattVision family. The trailing stack is a platform '
        'fallback chain, not a WattVision value.',
  ),
  TokenSpec(
    name: 'fontMono',
    cssName: '--font-mono',
    kind: TokenValueKind.fontFamily,
    section: '§4',
    value: "'JetBrains Mono', 'Fira Code', ui-monospace, 'SF Mono', monospace",
    spec: 'KPI metrics (Watts, kWh, Bs): JetBrains Mono (or Fira Code) Bold',
    note: 'Both WattVision-sanctioned families are listed in the declared '
        'order. The remainder is a platform fallback chain.',
  ),
  TokenSpec(
    name: 'sizeTitle',
    cssName: '--size-title',
    kind: TokenValueKind.length,
    section: '§4',
    numeric: 24,
    unit: 'px',
    value: '24px',
    spec: 'Titles: Inter SemiBold 24px',
    requirement17: true,
  ),
  TokenSpec(
    name: 'sizeKpi',
    cssName: '--size-kpi',
    kind: TokenValueKind.length,
    section: '§4',
    numeric: 32,
    unit: 'px',
    value: '32px',
    spec: 'KPI metrics: JetBrains Mono Bold 32px',
    requirement17: true,
  ),
  TokenSpec(
    name: 'sizeBody',
    cssName: '--size-body',
    kind: TokenValueKind.length,
    section: '§4',
    numeric: 14,
    unit: 'px',
    value: '14px',
    spec: 'Body: Inter Regular 14px',
    requirement17: true,
  ),

  // --- §5 spacing --------------------------------------------------------
  TokenSpec(
    name: 's2',
    cssName: '--s2',
    kind: TokenValueKind.length,
    section: '§5',
    numeric: 8,
    unit: 'px',
    value: '8px',
    spec: 'Spacing in multiples of 8px (8, 16, 24, 32)',
    layoutSpacing: true,
  ),
  TokenSpec(
    name: 's3',
    cssName: '--s3',
    kind: TokenValueKind.length,
    section: '§5',
    numeric: 16,
    unit: 'px',
    value: '16px',
    spec: 'Spacing in multiples of 8px (8, 16, 24, 32)',
    layoutSpacing: true,
  ),
  TokenSpec(
    name: 's4',
    cssName: '--s4',
    kind: TokenValueKind.length,
    section: '§5',
    numeric: 24,
    unit: 'px',
    value: '24px',
    spec: 'Spacing in multiples of 8px (8, 16, 24, 32)',
    layoutSpacing: true,
  ),
  TokenSpec(
    name: 's5',
    cssName: '--s5',
    kind: TokenValueKind.length,
    section: '§5',
    numeric: 32,
    unit: 'px',
    value: '32px',
    spec: 'Spacing in multiples of 8px (8, 16, 24, 32)',
    layoutSpacing: true,
  ),
  TokenSpec(
    name: 's6',
    cssName: '--s6',
    kind: TokenValueKind.length,
    section: '§5',
    numeric: 40,
    unit: 'px',
    value: '40px',
    spec: 'Further step on the §5 multiple-of-8 scale',
    layoutSpacing: true,
    note: '§5 enumerates 8, 16, 24 and 32 as examples of the multiple-of-8 '
        'rule. 40 continues the same scale and satisfies it.',
  ),
  TokenSpec(
    name: 's7',
    cssName: '--s7',
    kind: TokenValueKind.length,
    section: '§5',
    numeric: 48,
    unit: 'px',
    value: '48px',
    spec: 'Further step on the §5 multiple-of-8 scale',
    layoutSpacing: true,
    note: 'As s6.',
  ),
];

/// WattVision §5: twelve columns, spacing on multiples of eight.
///
/// Per-Layout_Mode gutters, outer padding and the Expanded content cap are
/// deliberately absent — they belong to `lib/core/layout/layout_mode.dart`
/// (task 5.1) and its React counterpart, and restating them here would create
/// two places to change one number.
const LayoutScaleSpec kLayoutScale = LayoutScaleSpec(
  section: '§5',
  columns: 12,
  spacingBase: 8,
  enumeratedSteps: <double>[8, 16, 24, 32],
  rule: 'Gaps, gutters and outer padding are whole multiples of spacingBase.',
  note: 'Per-Layout_Mode gutter, outer padding and content cap values are '
      'owned by flutter_app/lib/core/layout/layout_mode.dart (task 5.1) and '
      'react_app/src/core/layout.ts (task 5.2). They are deliberately not '
      'restated here, and not in CSS.',
);

// ---------------------------------------------------------------------------
// Token_Extensions — values WattVision does not supply
// ---------------------------------------------------------------------------

/// Extensions that apply to the dark appearance or to every appearance.
///
/// Every entry carries its Requirement 1.9 rationale and consumer.
const List<TokenExtensionSpec> kDarkTokenExtensions = <TokenExtensionSpec>[
  TokenExtensionSpec(
    name: 'watch',
    cssName: '--watch',
    kind: TokenValueKind.color,
    argb: 0xFFFFD60A,
    rationale: 'WattVision §2 supplies no intermediate advisory colour '
        'between the secondary accent (#32D74B) and the alert accent '
        '(#FF453A). The firmware Status vocabulary requires one for WATCH, '
        'which is a deviation observed but not yet confirmed.',
    consumedBy: 'WATCH Status pill, WATCH alert banner, envelope gauge '
        'negative breach, WATCH Alert_Entry rows',
    requirement: '1.10',
    statusAffordance: 'Required. Requirement 1.11 forbids conveying WATCH by '
        'colour alone, so every amber presentation carries a text label or '
        'shape alongside it.',
  ),
  TokenExtensionSpec(
    name: 'watchBoxFill',
    cssName: '--watch-fill',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.dark,
    argb: 0xFF3A331C,
    rationale: 'WattVision §3 specifies an alert box fill (#3A1C1C) only for '
        'the alert state. The WATCH state needs the same boxed treatment, so '
        'this value is the §3 recipe applied to the amber Token_Extension at '
        'the same lightness and chroma relationship.',
    consumedBy: 'WATCH alert banner background, WATCH Alert_Entry row '
        'background',
    derivedFrom: 'watch, following the §3 alert / alertBoxFill relationship',
  ),
  TokenExtensionSpec(
    name: 'normalBoxFill',
    cssName: '--normal-fill',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.dark,
    argb: 0xFF17301C,
    rationale: 'As watchBoxFill: WattVision §3 gives a boxed fill for the '
        'alert state only, and the OK state needs the same treatment to read '
        'as a peer of WATCH and LEAK rather than as unstyled text.',
    consumedBy: 'OK Status banner background, OK Alert_Entry row background',
    derivedFrom: 'normal, following the §3 alert / alertBoxFill relationship',
  ),
  TokenExtensionSpec(
    name: 'idle',
    cssName: '--idle',
    kind: TokenValueKind.color,
    argb: 0xFF636366,
    rationale: 'WattVision §2 has no neutral inactive colour. The firmware '
        'Status vocabulary includes IDLE (no flow and no link activity), '
        'which must be visually distinct from OK rather than borrowing the '
        'secondary accent, since IDLE is not a healthy-flow signal.',
    consumedBy: 'IDLE Status pill, disconnected link chip, disabled controls, '
        'chart series with no data',
  ),
  TokenExtensionSpec(
    name: 'accentText',
    cssName: '--accent-text',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.dark,
    argb: 0xFF00E5FF,
    rationale: 'WattVision §2 names one accent and uses it for both charts '
        'and text without distinguishing the two. Passing as a graphic and '
        'passing as text are different thresholds, so Requirement 11.4 needs '
        'the accent split into a graphical token and a text token. In the '
        'dark appearances the text token aliases the accent unchanged — '
        '#00E5FF measures 10.84:1 on #1E1E1E and clears 4.5:1 — so this '
        'extension buys the light appearance a place to differ without '
        'changing anything in dark.',
    consumedBy: 'Every text and icon use of the accent: section titles, row '
        'values, accent-coloured labels and tab indicators. The graphical '
        'accent keeps chart strokes, fills, gauges and button backgrounds.',
    derivedFrom: 'accent — aliased unchanged in both dark appearances',
    requirement: '11.4',
    note: 'High_Contrast_Dark inherits this value rather than overriding it, '
        'so there is no separate hcAccentText entry. The light appearance '
        'value is recorded separately as lightAccentText.',
  ),
  TokenExtensionSpec(
    name: 'hcTextSecondary',
    cssName: '--text-secondary',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.highContrastDark,
    argb: 0xFFC7C7CC,
    rationale: 'WattVision §2 supplies one secondary text colour, #98989D, '
        'which measures 5.80:1 on the §3 card surface. That clears '
        'Requirement 11.1 but leaves no headroom, and Requirement 9.2 asks '
        'for an appearance that raises text contrast without leaving the dark '
        'family. This is the same neutral lightened to 9.90:1 on #1E1E1E.',
    consumedBy: 'High_Contrast_Dark secondary text, labels, axis ticks and '
        'timestamps',
    derivedFrom: 'textSecondary, lightened along the same neutral ramp',
    requirement: '9.2',
  ),
  TokenExtensionSpec(
    name: 'hcBorder',
    cssName: '--border',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.highContrastDark,
    argb: 0xFF48484A,
    rationale: 'The §3 hairline #2C2C2E is deliberately subtle and sits at '
        '1.20:1 against the card surface, so card edges, chart grid lines and '
        'table row separators are barely perceptible. Requirement 9.2 asks '
        'for raised border contrast; this is the same hairline made visible '
        'at 1.83:1 without thickening it, which §3 forbids.',
    consumedBy: 'High_Contrast_Dark card borders, chart grid lines, table row '
        'bottom borders, control outlines',
    derivedFrom: 'border, lightened along the same neutral ramp',
    requirement: '9.2',
  ),
  TokenExtensionSpec(
    name: 'radiusControl',
    cssName: '--radius-control',
    kind: TokenValueKind.length,
    numeric: 12,
    unit: 'px',
    value: '12px',
    rationale: 'WattVision §3 specifies a 16px radius for cards only. '
        'Controls nested inside a 16px card need a smaller radius so the '
        'corners stay visually concentric rather than competing with the '
        'card edge.',
    consumedBy: 'Buttons, inputs, the Tariff field, segmented switchers, '
        'dialog surfaces',
  ),
  TokenExtensionSpec(
    name: 'radiusPill',
    cssName: '--radius-pill',
    kind: TokenValueKind.length,
    numeric: 999,
    unit: 'px',
    value: '999px',
    rationale: 'WattVision §3 specifies no pill geometry. Status pills need a '
        'fully rounded shape, which is expressed as an arbitrarily large '
        'radius rather than a computed half-height.',
    consumedBy: 'Status pills, link chips, channel selector chips',
  ),
  TokenExtensionSpec(
    name: 's1',
    cssName: '--s1',
    kind: TokenValueKind.length,
    numeric: 4,
    unit: 'px',
    value: '4px',
    rationale: 'WattVision §5 puts spacing on multiples of 8. 4px is a '
        'half-step below the scale, kept for intra-component insets — the '
        'gap between a value and its unit suffix, or a pill vertical padding '
        '— where an 8px step is visibly loose.',
    consumedBy: 'Intra-component insets only: pill padding, value/unit '
        'spacing, icon/label spacing',
    note: 'Deliberately flagged layoutSpacing: false. Requirement 1.8 '
        'constrains layout gaps, gutters and outer padding; s1 must never be '
        'used for any of those, and the compliance suite excludes it from the '
        'multiple-of-8 assertion on that basis.',
  ),
  TokenExtensionSpec(
    name: 'sizeLabel',
    cssName: '--size-label',
    kind: TokenValueKind.length,
    numeric: 12,
    unit: 'px',
    value: '12px',
    rationale: 'WattVision §4 defines three sizes (24 title, 32 KPI, 14 '
        'body) and names secondary text as label text in §2 without giving '
        'it a size. Dense surfaces — table headers, axis ticks, timestamps — '
        'need a step below body.',
    consumedBy: 'Calibration_Table headers, chart axis labels, Alert_Entry '
        'timestamps, KPI unit suffixes',
    floorNote: 'Requirement 8.7 treats this as the floor: Calibration_Table '
        'text must not shrink below the label size in Compact.',
  ),
  TokenExtensionSpec(
    name: 'motionInstant',
    cssName: '--motion-instant',
    kind: TokenValueKind.duration,
    numeric: 120,
    unit: 'ms',
    value: '120ms',
    rationale: 'WattVision §1–§6 specify no motion durations. A named scale '
        'is required so the Reduce_Motion contract is one attribute flip '
        'rather than a hunt through the CSS.',
    consumedBy: 'Hover and focus state changes, pill colour transitions',
  ),
  TokenExtensionSpec(
    name: 'motionFast',
    cssName: '--motion-fast',
    kind: TokenValueKind.duration,
    numeric: 200,
    unit: 'ms',
    value: '200ms',
    rationale: 'As motionInstant.',
    consumedBy: 'Chip and button presses, small enter/exit transitions',
  ),
  TokenExtensionSpec(
    name: 'motionBase',
    cssName: '--motion-base',
    kind: TokenValueKind.duration,
    numeric: 320,
    unit: 'ms',
    value: '320ms',
    rationale: 'As motionInstant.',
    consumedBy: 'Animated metric interpolation, Bs_Equivalence changes, '
        'Layout_Mode transitions',
  ),
  TokenExtensionSpec(
    name: 'motionSlow',
    cssName: '--motion-slow',
    kind: TokenValueKind.duration,
    numeric: 520,
    unit: 'ms',
    value: '520ms',
    rationale: 'As motionInstant.',
    consumedBy: 'Carousel page transitions, sheet and dialog presentation',
  ),
  TokenExtensionSpec(
    name: 'easeEnter',
    cssName: '--ease-enter',
    kind: TokenValueKind.easing,
    value: 'cubic-bezier(0.22, 1, 0.36, 1)',
    rationale: 'WattVision specifies no easing curves. Entering and exiting '
        'motion need different curves so arrival reads as settling rather '
        'than stopping.',
    consumedBy: 'Every enter transition in both clients',
  ),
  TokenExtensionSpec(
    name: 'easeExit',
    cssName: '--ease-exit',
    kind: TokenValueKind.easing,
    value: 'cubic-bezier(0.55, 0, 1, 0.45)',
    rationale: 'As easeEnter.',
    consumedBy: 'Every exit transition in both clients',
  ),
  TokenExtensionSpec(
    name: 'tFast',
    cssName: '--t-fast',
    kind: TokenValueKind.durationAlias,
    value: 'var(--motion-fast)',
    aliasOf: 'motionFast',
    reduceMotionMillis: 1,
    rationale: 'Not a WattVision concept. An indirection layer so '
        'Reduce_Motion collapses every transition by redefining three '
        "properties, which is what makes Requirement 11.6's at-most-1ms "
        'guarantee checkable in one place.',
    consumedBy: 'Every transition that would otherwise reference motionFast '
        'directly',
  ),
  TokenExtensionSpec(
    name: 'tBase',
    cssName: '--t-base',
    kind: TokenValueKind.durationAlias,
    value: 'var(--motion-base)',
    aliasOf: 'motionBase',
    reduceMotionMillis: 1,
    rationale: 'As tFast.',
    consumedBy: 'Every transition that would otherwise reference motionBase '
        'directly',
  ),
  TokenExtensionSpec(
    name: 'tSlow',
    cssName: '--t-slow',
    kind: TokenValueKind.durationAlias,
    value: 'var(--motion-slow)',
    aliasOf: 'motionSlow',
    reduceMotionMillis: 1,
    rationale: 'As tFast.',
    consumedBy: 'Every transition that would otherwise reference motionSlow '
        'directly',
  ),
  TokenExtensionSpec(
    name: 'onAccent',
    cssName: '--on-accent',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.dark,
    argb: 0xFF121212,
    rationale: 'WattVision §2 names the accent as a fill for action buttons '
        'but gives no colour for text sitting on that fill. Primary text '
        '(#FFFFFF) on #00E5FF fails contrast, so the background colour is '
        'reused as the on-accent foreground.',
    consumedBy: 'Label and icon colour inside filled accent buttons and '
        'filled chips',
    note: 'Equal to background in the dark appearance by construction; '
        '#FFFFFF in the light appearance, recorded separately as '
        'lightOnAccent.',
  ),
  TokenExtensionSpec(
    name: 'shadowDark',
    cssName: '--shadow',
    kind: TokenValueKind.shadow,
    appearance: TokenAppearance.dark,
    value: '0 18px 40px rgba(0, 0, 0, 0.45)',
    rationale: 'WattVision §3 describes card separation through a subtle 1px '
        'border and forbids thick border lines; it specifies no elevation. A '
        'low-opacity shadow lifts modal surfaces off the background without '
        'adding a competing border.',
    consumedBy: 'Dialogs, the Diagnostics_Sheet, dropdown surfaces',
    note: 'The only rgba() literal in the registry. On the web side it lives '
        'inside tokens.css, the single file the literal-colour scanner '
        'exempts.',
  ),
];

/// Why High_Contrast_Dark is two overrides rather than a palette.
///
/// Recorded at palette scope because the interesting fact is what the
/// appearance does *not* change: Requirement 9.2 asks for higher text and
/// border contrast while staying inside the WattVision §2 dark family, and the
/// only way to keep that promise checkably is to inherit the three surface
/// values rather than restate them.
const PaletteRationale kHighContrastDarkRationale = PaletteRationale(
  appearance: TokenAppearance.highContrastDark,
  rationale: 'WattVision supplies one dark palette. Requirement 9.2 asks for a '
      'second dark appearance that raises text and border contrast, which no '
      '§2 value provides, so the appearance is a Token_Extension made of '
      'exactly two overrides — hcTextSecondary and hcBorder. Everything else, '
      'including accentText, is inherited from the dark palette unchanged.',
  consumedBy: 'The High_Contrast_Dark appearance, offered alongside Dark and '
      'Follow system as a primary appearance choice',
  constraint: 'Requirement 9.2 — background, surface and surfaceRaised must be '
      'identical to the dark appearance, and every overridden token must be at '
      'least as contrasting as the value it replaces. Measured: secondary text '
      'on the card surface rises from 5.81:1 to 9.90:1, and the hairline from '
      '1.20:1 to 1.83:1.',
);

/// Why the entire light palette is a Token_Extension.
///
/// WattVision §6 forbids white backgrounds, so no light value can be sourced
/// from §2. Requirement 1.9 is satisfied at palette scope here and again per
/// entry in [kLightAppearanceExtensions].
const PaletteRationale kLightAppearanceRationale = PaletteRationale(
  appearance: TokenAppearance.light,
  rationale: 'The entire light palette is a Token_Extension. WattVision §6 '
      'forbids white backgrounds, so no light value can be sourced from §2. '
      'The palette is retained because Requirement 9.3 keeps a light '
      'appearance available as an accessibility affordance, presented with '
      'the Requirement 9.4 advisory rather than as a peer appearance.',
  consumedBy: 'The light appearance only, reachable from the accessibility '
      'section of the Settings tab',
  constraint: 'Requirement 9.5 requires the light appearance to meet the '
      'Requirement 11 contrast criteria, which is why the accents are '
      'darkened rather than reused.',
);

/// The derived light palette. Every entry is a Token_Extension in its own
/// right, named `light<Token>` after its dark counterpart.
const List<TokenExtensionSpec> kLightAppearanceExtensions =
    <TokenExtensionSpec>[
  TokenExtensionSpec(
    name: 'lightBackground',
    cssName: '--bg',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFFF4F5F7,
    rationale: 'A near-neutral off-white stands in for the §2 #121212 '
        'background. It is deliberately not pure white, since §6 forbids '
        'white backgrounds outright.',
    consumedBy: 'Light appearance page background',
  ),
  TokenExtensionSpec(
    name: 'lightSurface',
    cssName: '--surface',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFFFFFFFF,
    rationale: 'Card surfaces need to sit above the light background, and the '
        'only value above #F4F5F7 in this family is white. This is the single '
        'point where the light appearance contradicts WattVision §6, and it '
        'is the reason the light appearance carries the Requirement 9.4 '
        'advisory instead of appearing as a peer appearance option.',
    consumedBy: 'Light appearance card surface',
    conflict: 'WattVision §6 — no white backgrounds',
  ),
  TokenExtensionSpec(
    name: 'lightSurfaceRaised',
    cssName: '--surface-raised',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFFECEEF1,
    rationale: 'The §3 row hover treatment needs to darken rather than '
        'lighten in a light appearance, so the raised surface inverts its '
        'relationship to the base surface.',
    consumedBy: 'Light appearance table row hover and focus background',
  ),
  TokenExtensionSpec(
    name: 'lightBorder',
    cssName: '--border',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFFD9DDE3,
    rationale: 'The §3 hairline #2C2C2E is invisible-by-inversion on a light '
        'surface; this is its light-appearance counterpart at an equivalent '
        'perceived weight.',
    consumedBy: 'Light appearance card borders, chart grid lines, table row '
        'bottom borders',
  ),
  TokenExtensionSpec(
    name: 'lightTextPrimary',
    cssName: '--text-primary',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFF121212,
    rationale: 'Primary text inverts to the §2 background value, which keeps '
        'the light appearance inside the WattVision hue family and gives '
        '17.4:1 on white.',
    consumedBy: 'Light appearance primary text',
  ),
  TokenExtensionSpec(
    name: 'lightTextSecondary',
    cssName: '--text-secondary',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFF5B5F66,
    rationale: 'The §2 secondary text #98989D measures below 4.5:1 on a '
        'light surface, so the light appearance needs a darker neutral to '
        'satisfy Requirements 9.5 and 11.1.',
    consumedBy: 'Light appearance secondary text and labels',
  ),
  TokenExtensionSpec(
    name: 'lightAccent',
    cssName: '--accent',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFF0091A7,
    rationale: 'Neon cyan #00E5FF is near-white in luminance and fails '
        'contrast against a light surface. The light appearance darkens the '
        'same hue so the accent stays recognisable while remaining legible.',
    consumedBy: 'Light appearance charts, KPI emphasis, action button fills',
  ),
  TokenExtensionSpec(
    name: 'lightAccentText',
    cssName: '--accent-text',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFF00707F,
    rationale: 'Double extension, and the reason the accentText split exists '
        'at all. lightAccent #0091A7 measures 3.74:1 on #FFFFFF, so the '
        'darkened accent is legible as a chart stroke but fails the '
        'Requirement 11.1 body-text threshold. Requirement 11.4 allows either '
        'dropping the accent from text or giving text its own value; this '
        'takes the second option and darkens the same hue again to 5.79:1 on '
        '#FFFFFF, 5.31:1 on #F4F5F7 and 4.99:1 on #ECEEF1 — clearing 4.5:1 on '
        'all three light surfaces.',
    consumedBy: 'Light appearance section titles, row values and every other '
        'text or icon use of the accent',
    derivedFrom: 'lightAccent, darkened at constant hue until 4.5:1 clears on '
        'the lightest surface',
    requirement: '11.4',
  ),
  TokenExtensionSpec(
    name: 'lightAlert',
    cssName: '--alert',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFFD3261C,
    rationale: 'As lightAccent: the §2 alert red is darkened for legibility '
        'on a light surface while holding the same hue.',
    consumedBy: 'Light appearance LEAK and FAULT text, alert left border',
  ),
  TokenExtensionSpec(
    name: 'lightNormal',
    cssName: '--normal',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFF1E8E33,
    rationale: 'As lightAccent: the §2 secondary accent darkened for a light '
        'surface.',
    consumedBy: 'Light appearance OK Status, live indicators',
  ),
  TokenExtensionSpec(
    name: 'lightGradientGreen',
    cssName: '--gradient-green',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFF1E8E33,
    rationale: 'The §2/§3 green distinction collapses in the light '
        'appearance: at the darkened lightness needed for legibility, '
        '#32D74B and #30D158 converge to the same value, so both resolve to '
        'one colour here.',
    consumedBy: 'Light appearance chart area gradient',
    note: 'Equal to lightNormal by construction. The normal / gradientGreen '
        'distinction holds in the dark appearances only.',
  ),
  TokenExtensionSpec(
    name: 'lightWatch',
    cssName: '--watch',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFF9A7B00,
    rationale: 'Double extension: the amber WATCH colour is itself absent '
        'from WattVision (see the watch extension), and #FFD60A is illegible '
        'on a light surface, so the light appearance uses a dark amber.',
    consumedBy: 'Light appearance WATCH Status pill and banner',
  ),
  TokenExtensionSpec(
    name: 'lightIdle',
    cssName: '--idle',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFF8E9299,
    rationale: 'As the idle extension, adjusted so the IDLE neutral still '
        'reads as inactive against a light surface.',
    consumedBy: 'Light appearance IDLE Status pill, disconnected link chip, '
        'disabled controls',
  ),
  TokenExtensionSpec(
    name: 'lightAlertBoxFill',
    cssName: '--alert-fill',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFFFCE8E6,
    rationale: 'The §3 alert box fill #3A1C1C is a darkened tint of the '
        'alert red; on a light surface the same recipe produces a lightened '
        'tint instead.',
    consumedBy: 'Light appearance alert box background, LEAK and FAULT '
        'Alert_Entry rows',
  ),
  TokenExtensionSpec(
    name: 'lightWatchBoxFill',
    cssName: '--watch-fill',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFFFBF3D9,
    rationale: 'As lightAlertBoxFill, applied to the amber Token_Extension.',
    consumedBy: 'Light appearance WATCH banner background, WATCH Alert_Entry '
        'rows',
  ),
  TokenExtensionSpec(
    name: 'lightNormalBoxFill',
    cssName: '--normal-fill',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFFD8F5DF,
    rationale: 'As lightAlertBoxFill, applied to the secondary accent. The '
        'value was #E6F5E9 until task 3.1: at HSL saturation 0.429 it was the '
        'one recorded pastel hit the neutral carve-out below does not reach, '
        'and it was visibly washed out beside its two siblings — #FCE8E6 at '
        '0.786 and #FBF3D9 at 0.810. #D8F5DF is the same green at saturation '
        '0.592, which clears the §6 pastel rule and puts the three state fills '
        'in the same family.',
    consumedBy: 'Light appearance OK banner background, OK Alert_Entry rows',
    note: 'Changed from #E6F5E9 to #D8F5DF by task 3.1, alongside the '
        'identical change to --normal-fill in the Web_Client light block '
        '(task 3.2). The two clients must hold the same value — Requirements '
        '13.1 and 13.2. Primary text on the new fill measures 16.10:1 and '
        'secondary text 5.51:1, so the Requirement 9.5 / 11.1 thresholds still '
        'hold for the text that sits on it.',
  ),
  TokenExtensionSpec(
    name: 'lightOnAccent',
    cssName: '--on-accent',
    kind: TokenValueKind.color,
    appearance: TokenAppearance.light,
    argb: 0xFFFFFFFF,
    rationale: 'As the onAccent extension, inverted: the darkened light '
        'accent needs a white foreground to pass contrast.',
    consumedBy: 'Light appearance label and icon colour inside filled accent '
        'buttons and chips',
  ),
  TokenExtensionSpec(
    name: 'lightShadow',
    cssName: '--shadow',
    kind: TokenValueKind.shadow,
    appearance: TokenAppearance.light,
    value: '0 12px 30px rgba(18, 18, 18, 0.10)',
    rationale: 'As the shadowDark extension, at a lower opacity because a '
        'light surface shows shadow more readily.',
    consumedBy: 'Light appearance dialogs, the Diagnostics_Sheet, dropdown '
        'surfaces',
  ),
];

/// Every Token_Extension in the app, dark and light.
///
/// This is the list Requirement 1.9 is asserted over: `rationale` and
/// `consumedBy` non-empty for every entry.
const List<TokenExtensionSpec> kTokenExtensions = <TokenExtensionSpec>[
  ...kDarkTokenExtensions,
  ...kLightAppearanceExtensions,
];

// ---------------------------------------------------------------------------
// The pastel rule (Requirement 9.8)
// ---------------------------------------------------------------------------

/// The explicit, computable definition of a pastel colour.
///
/// The HSL maths itself lives in the compliance suite's colour helper, not
/// here — this records the thresholds and the formulas the two clients agree
/// on, so tuning the judgement call is a one-place edit.
const PastelRuleSpec kPastelRule = PastelRuleSpec(
  requirement: '9.8',
  wattVisionSection: '§6 — no pastel colours, no white backgrounds',
  definition: 'A colour is pastel when it carries enough hue to read as a '
      'colour rather than a grey — HSL saturation above 0.2 — and its HSL '
      'lightness exceeds 0.8 while its HSL saturation falls below 0.5. '
      'Near-neutral colours, which includes every achromatic one, are excluded '
      'from the rule.',
  lightnessAbove: 0.8,
  saturationBelow: 0.5,
  predicate: 'isPastel(c) = !isNeutral(c) && hslLightness(c) > 0.8 && '
      'hslSaturation(c) < 0.5, where isNeutral(c) = hslSaturation(c) <= 0.2',
  invariant: "!isPastel(c) for every colour in every appearance's palette",
  lightnessFormula: '(max + min) / 2, over channels normalised to [0, 1]',
  saturationFormula: 'max == min ? 0 : (max - min) / (lightness > 0.5 ? '
      '(2 - max - min) : (max + min))',
  hslNote: 'Standard HSL, not HSV. Both are computed from the raw sRGB '
      'channels without gamma linearisation; linearisation belongs to the '
      'contrast helper, not here.',
  achromatic: AchromaticRuleSpec(
    definition: 'A colour is achromatic when its HSL saturation is 0, i.e. '
        'its three channels are equal.',
    saturationAtMost: 0,
    excludedExamples: <String>['#FFFFFF', '#000000'],
    reason: 'Pure white has lightness 1.0 and saturation 0 and would '
        'otherwise be flagged as pastel, which would make the rule reject '
        'the §2 primary text colour. Greys carry no hue and so cannot be '
        'pastel.',
  ),
  neutral: NeutralRuleSpec(
    definition: 'A colour is near-neutral when its HSL saturation is at most '
        '0.2. Achromatic colours are the saturation-0 case of this, so the '
        'neutral set contains the achromatic set.',
    saturationAtMost: 0.2,
    excludedExamples: <String>[
      'lightBackground #F4F5F7 (S 0.158)',
      'lightSurfaceRaised #ECEEF1 (S 0.152)',
      'lightBorder #D9DDE3 (S 0.152)',
    ],
    reason: 'A grey carrying a faint cast is still read as a grey. The three '
        'light-appearance surface values above are off-whites tinted a degree '
        'or two towards blue so they do not look flat; treating them as '
        'pastels would mean the §6 rule forbids the light appearance from '
        'having a background at all, which is not what §6 is about. §6 is '
        'about the chalky, desaturated palette a data product should not use '
        'for its accents, and an accent at saturation 0.2 is not a colour '
        'anyone would choose.',
    decidedBy: 'The user, when task 3.1 put the choice to them. WattVision §6 '
        'gives no definition of "pastel", so where the neutral boundary sits '
        'is a judgement call rather than a derivation. Recorded here so it is '
        'one number in one place, auditable and tunable, instead of an '
        'exception list that grows.',
    supersedes: 'The four-value knownLiteralRuleHits list phase 1 recorded. '
        'Three of the four are cleared by this carve-out. The fourth, '
        'lightNormalBoxFill, sat at saturation 0.429 — above the carve-out and '
        'below 0.5 — so it was a real hit and the colour itself changed, from '
        '#E6F5E9 to #D8F5DF at saturation 0.592.',
  ),
  thresholdProvenance: 'WattVision §6 forbids pastels without defining them. '
      'Undefined, the criterion is unverifiable, so the thresholds are '
      'recorded here as the single explicit definition both clients test '
      'against. They are a judgement call and are tuned in one place. Two '
      'numbers were taken from the common reading of "pastel" — light (HSL '
      'lightness > 0.8) and washed out (HSL saturation < 0.5) — and the third, '
      'the neutral floor at saturation 0.2, was chosen by the user in task 3.1 '
      'after phase 1 found the literal predicate flagging near-neutral greys. '
      'The first two have not been loosened; the carve-out narrows what counts '
      'as a colour at all, and any value above it is still judged by the '
      'original two.',
  consumedBy: 'Property 20 in both compliance suites '
      '(flutter_app/test/compliance/, react_app/src/__tests__/compliance/)',
  knownLiteralRuleHits: KnownPastelHits(
    appearance: TokenAppearance.light,
    values: <String>[],
    note: 'Empty, and deliberately kept rather than deleted. Phase 1 recorded '
        'four hits in the light palette: lightBackground #F4F5F7, '
        'lightSurfaceRaised #ECEEF1 and lightBorder #D9DDE3 at saturations '
        '0.158, 0.152 and 0.152, plus lightNormalBoxFill #E6F5E9 at 0.429. '
        'Task 3.1 resolved all four: the first three fall inside the neutral '
        'carve-out recorded above and were never pastels under the sharpened '
        'definition, and the fourth was genuinely a pastel and was changed to '
        '#D8F5DF at saturation 0.592. No palette value in any appearance is '
        'flagged now, so the rule has nothing left to record — which is what '
        'Property 20 asserts rather than what it assumes.',
  ),
);

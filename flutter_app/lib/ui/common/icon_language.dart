/// The WattVision Icon_Language for the Mobile_Client (task 15.8).
///
/// Requirements 10.1, 10.2, 10.3, 10.5.
///
/// This file is the single source of the five *domain* glyphs the product is
/// allowed to draw — droplet, valve, gauge/meter, pipe, wave — plus the
/// declaration of the *structural* glyphs that are deliberately EXEMPT from
/// that vocabulary.
///
/// ## Why a CustomPainter and not `flutter_svg`
///
/// The glyphs are authored once as SVGs under `design/icons/*.svg` (task 15.7)
/// and shared with the Web_Client, which inlines the same path data
/// (`react_app/src/components/icons.tsx`, task 15.9). On this side the SVG path
/// data is transcribed by hand into Dart [Path] construction and drawn by a
/// small [CustomPainter]. Rendering through a painter rather than adding
/// `flutter_svg` avoids a new runtime dependency, which the design records as a
/// toolchain we cannot resolve in this environment.
///
/// ## Domain vocabulary (Requirement 10.1)
///
/// The allowed set is [AppGlyph] — exactly `{droplet, valve, gauge, pipe,
/// wave}`. The keys match `test_fixtures/icons/manifest.json` and the React
/// client so a cross-client parity test can assert both agree. There is no
/// lightbulb or other illumination glyph here (Requirement 10.2).
///
/// ## Colour and size (Requirement 10.5)
///
/// Every glyph is stroked in a token colour — [AppIcon.color] when given,
/// otherwise `AppPalette.of(context).textPrimary`. Never a colour literal.
/// Sizes come off the spacing scale or the type scale (`Tokens.s*`,
/// `Tokens.bodySize`, `Tokens.titleSize`, …); [AppIcon.size] defaults to
/// `Tokens.s4` (24), the viewBox size.
///
/// ## Accessible name (Requirement 10.4)
///
/// [AppIcon] takes an optional [AppIcon.semanticLabel]. When supplied the glyph
/// is exposed to assistive tech under that name; when a call site pairs the
/// icon with its own visible text label it should pass `semanticLabel: null`
/// (the default) and let the label carry the meaning. Requirement 10.4 is
/// satisfied at each call site, not here.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';

/// The closed WattVision domain-icon vocabulary (Requirement 10.1).
///
/// These are the ONLY glyphs functional UI may draw. The names are the shared
/// glyph keys — they must stay equal to `test_fixtures/icons/manifest.json`
/// and to the React client's exports.
enum AppGlyph {
  /// A water droplet — flow, water, a channel reading.
  droplet,

  /// An inline valve/gate — a control or a shut-off.
  valve,

  /// A gauge/meter with a needle — a measured rate or pressure.
  gauge,

  /// A run of pipe with a branch — plumbing topology, a sensor location.
  pipe,

  /// Stacked waves — a signal, a live link, an ambient flow.
  wave,
}

/// The structural glyphs that are EXEMPT from the Icon_Language vocabulary
/// (Requirement 10.5, and the design's narrowing of Requirement 10.1).
///
/// These carry no water-domain meaning: they are chrome for navigation and
/// controls. They stay as Material [Icons] on this client (and simple inline
/// SVG on the Web_Client) and must NOT be reimplemented as [AppGlyph] entries.
///
/// The set is deliberately closed and documented so task 15.11's icon swap —
/// and any lint that walks the UI for stray glyph sources — can tell an exempt
/// structural icon from a domain one. Adding to this set is a design decision,
/// not an implementation detail.
///
/// The keys mirror the Web_Client's structural set exactly:
/// `{chevron, close, check, plus, refresh, expand}`.
enum StructuralGlyph {
  /// Directional chevron — back/forward, disclosure, carousel paging.
  chevron,

  /// Close/dismiss — sheets, dialogs, banners.
  close,

  /// Confirmation tick — selection, success, "applied".
  check,

  /// Add — a new item, an increment control.
  plus,

  /// Refresh/retry — re-run, reconnect, reload.
  refresh,

  /// Expand/collapse — a section or a panel toggle.
  expand,
}

/// The canonical Material icon each [StructuralGlyph] resolves to on this
/// client. Provided so the exemption is not just a name list: call sites and
/// the swap task read the concrete icon from one place.
const Map<StructuralGlyph, IconData> kStructuralIcons = <StructuralGlyph, IconData>{
  StructuralGlyph.chevron: Icons.chevron_right,
  StructuralGlyph.close: Icons.close,
  StructuralGlyph.check: Icons.check,
  StructuralGlyph.plus: Icons.add,
  StructuralGlyph.refresh: Icons.refresh,
  StructuralGlyph.expand: Icons.expand_more,
};

/// A domain glyph from the [AppGlyph] vocabulary, drawn at a token size in a
/// token colour.
///
/// ```dart
/// AppIcon(AppGlyph.droplet, size: Tokens.bodySize, color: palette.accent)
/// // or the named convenience constructor:
/// AppIcon.gauge(size: 20)
/// ```
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.glyph, {
    super.key,
    this.size = Tokens.s4,
    this.color,
    this.semanticLabel,
  });

  /// Droplet convenience constructor.
  const AppIcon.droplet(
      {Key? key, double size = Tokens.s4, Color? color, String? semanticLabel})
      : this(AppGlyph.droplet,
            key: key, size: size, color: color, semanticLabel: semanticLabel);

  /// Valve convenience constructor.
  const AppIcon.valve(
      {Key? key, double size = Tokens.s4, Color? color, String? semanticLabel})
      : this(AppGlyph.valve,
            key: key, size: size, color: color, semanticLabel: semanticLabel);

  /// Gauge convenience constructor.
  const AppIcon.gauge(
      {Key? key, double size = Tokens.s4, Color? color, String? semanticLabel})
      : this(AppGlyph.gauge,
            key: key, size: size, color: color, semanticLabel: semanticLabel);

  /// Pipe convenience constructor.
  const AppIcon.pipe(
      {Key? key, double size = Tokens.s4, Color? color, String? semanticLabel})
      : this(AppGlyph.pipe,
            key: key, size: size, color: color, semanticLabel: semanticLabel);

  /// Wave convenience constructor.
  const AppIcon.wave(
      {Key? key, double size = Tokens.s4, Color? color, String? semanticLabel})
      : this(AppGlyph.wave,
            key: key, size: size, color: color, semanticLabel: semanticLabel);

  /// Which domain glyph to draw.
  final AppGlyph glyph;

  /// Side length in logical pixels. Defaults to the 24-unit viewBox size
  /// (`Tokens.s4`). Callers should pass a spacing- or type-scale value.
  final double size;

  /// Stroke/fill colour. When null, resolves to `AppPalette.textPrimary` from
  /// the ambient theme — never a literal.
  final Color? color;

  /// Accessible name. When non-null the glyph is announced under this label;
  /// when null the glyph is decorative and its meaning is expected to come
  /// from an adjacent text label (Requirement 10.4).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color resolved = color ?? AppPalette.of(context).textPrimary;
    final Widget painted = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        size: Size.square(size),
        painter: _GlyphPainter(glyph: glyph, color: resolved),
      ),
    );
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: painted,
    );
  }
}

/// Paints a single [AppGlyph] by transcribing its `design/icons/*.svg` path
/// data onto the canvas.
///
/// All source paths live in a 24×24 viewBox with stroke width 1.75, round caps
/// and round joins. The painter scales that viewBox to the requested [Size]
/// and scales the stroke width with it, so the glyph reads the same at any
/// size. Filled sub-paths (the gauge needle dot) are drawn with a fill Paint;
/// the droplet, valve, pipe and wave are stroke-only.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({required this.glyph, required this.color});

  final AppGlyph glyph;
  final Color color;

  /// The viewBox the source SVGs are authored in.
  static const double _viewBox = 24;

  /// The authored stroke width, in viewBox units.
  static const double _strokeWidth = 1.75;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / _viewBox;
    canvas.save();
    canvas.scale(scale);

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (glyph) {
      case AppGlyph.droplet:
        _paintDroplet(canvas, stroke);
      case AppGlyph.valve:
        _paintValve(canvas, stroke);
      case AppGlyph.gauge:
        _paintGauge(canvas, stroke);
      case AppGlyph.pipe:
        _paintPipe(canvas, stroke);
      case AppGlyph.wave:
        _paintWave(canvas, stroke);
    }

    canvas.restore();
  }

  // --- droplet.svg ----------------------------------------------------------
  //   <path d="M12 3.2C12 3.2 5.5 10 5.5 14.5a6.5 6.5 0 0 0 13 0
  //            C18.5 10 12 3.2 12 3.2Z"/>
  //   <path d="M9 14.5a3 3 0 0 0 3 3"/>
  void _paintDroplet(Canvas canvas, Paint stroke) {
    final Path body = Path()
      ..moveTo(12, 3.2)
      // C12 3.2 5.5 10 5.5 14.5
      ..cubicTo(12, 3.2, 5.5, 10, 5.5, 14.5)
      // a6.5 6.5 0 0 0 13 0  -> relative arc from (5.5,14.5) to (18.5,14.5)
      ..arcToPoint(
        const Offset(18.5, 14.5),
        radius: const Radius.circular(6.5),
        largeArc: false,
        clockwise: true,
      )
      // C18.5 10 12 3.2 12 3.2
      ..cubicTo(18.5, 10, 12, 3.2, 12, 3.2)
      ..close();
    canvas.drawPath(body, stroke);

    // The inner highlight: M9 14.5 a3 3 0 0 0 3 3 -> arc to (12,17.5).
    final Path highlight = Path()
      ..moveTo(9, 14.5)
      ..arcToPoint(
        const Offset(12, 17.5),
        radius: const Radius.circular(3),
        largeArc: false,
        clockwise: true,
      );
    canvas.drawPath(highlight, stroke);
  }

  // --- valve.svg ------------------------------------------------------------
  //   <path d="M3 14v-4h5l4 2 4-2h5v4h-5l-4-2-4 2H3Z"/>
  //   <path d="M12 12V6"/>
  //   <path d="M8.5 6h7"/>
  void _paintValve(Canvas canvas, Paint stroke) {
    final Path bowtie = Path()
      ..moveTo(3, 14)
      ..relativeLineTo(0, -4) // v-4
      ..relativeLineTo(5, 0) // h5
      ..relativeLineTo(4, 2) // l4 2
      ..relativeLineTo(4, -2) // l4 -2
      ..relativeLineTo(5, 0) // h5
      ..relativeLineTo(0, 4) // v4
      ..relativeLineTo(-5, 0) // h-5
      ..relativeLineTo(-4, -2) // l-4 -2
      ..relativeLineTo(-4, 2) // l-4 2
      ..lineTo(3, 14) // H3 (x back to 3, y already 14)
      ..close();
    canvas.drawPath(bowtie, stroke);

    // Stem: M12 12 V6
    final Path stem = Path()
      ..moveTo(12, 12)
      ..lineTo(12, 6);
    canvas.drawPath(stem, stroke);

    // Handle: M8.5 6 h7
    final Path handle = Path()
      ..moveTo(8.5, 6)
      ..relativeLineTo(7, 0);
    canvas.drawPath(handle, stroke);
  }

  // --- gauge.svg ------------------------------------------------------------
  //   <path d="M4 17a8 8 0 1 1 16 0"/>
  //   <path d="M12 13.5 16 9"/>
  //   <circle cx="12" cy="14" r="1.4" fill="currentColor" stroke="none"/>
  void _paintGauge(Canvas canvas, Paint stroke) {
    // Semicircular dial: M4 17 a8 8 0 1 1 16 0 -> large arc to (20,17).
    final Path dial = Path()
      ..moveTo(4, 17)
      ..arcToPoint(
        const Offset(20, 17),
        radius: const Radius.circular(8),
        largeArc: true,
        clockwise: true,
      );
    canvas.drawPath(dial, stroke);

    // Needle: M12 13.5 L16 9
    final Path needle = Path()
      ..moveTo(12, 13.5)
      ..lineTo(16, 9);
    canvas.drawPath(needle, stroke);

    // Hub dot: filled, no stroke (fill="currentColor" stroke="none").
    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(const Offset(12, 14), 1.4, fill);
  }

  // --- pipe.svg -------------------------------------------------------------
  //   <path d="M3 8h9a3 3 0 0 1 3 3v10"/>
  //   <path d="M3 12h8a1 1 0 0 1 1 1v8"/>
  //   <path d="M3 6v4"/>
  //   <path d="M13 21h4"/>
  void _paintPipe(Canvas canvas, Paint stroke) {
    // Upper run + elbow: M3 8 h9 a3 3 0 0 1 3 3 v10
    final Path upper = Path()
      ..moveTo(3, 8)
      ..relativeLineTo(9, 0) // h9 -> (12,8)
      ..arcToPoint(
        const Offset(15, 11), // corner rounds to (15,11)
        radius: const Radius.circular(3),
        largeArc: false,
        clockwise: true,
      )
      ..relativeLineTo(0, 10); // v10
    canvas.drawPath(upper, stroke);

    // Lower run + elbow: M3 12 h8 a1 1 0 0 1 1 1 v8
    final Path lower = Path()
      ..moveTo(3, 12)
      ..relativeLineTo(8, 0) // h8 -> (11,12)
      ..arcToPoint(
        const Offset(12, 13),
        radius: const Radius.circular(1),
        largeArc: false,
        clockwise: true,
      )
      ..relativeLineTo(0, 8); // v8
    canvas.drawPath(lower, stroke);

    // Left cap: M3 6 v4
    final Path leftCap = Path()
      ..moveTo(3, 6)
      ..relativeLineTo(0, 4);
    canvas.drawPath(leftCap, stroke);

    // Bottom cap: M13 21 h4
    final Path bottomCap = Path()
      ..moveTo(13, 21)
      ..relativeLineTo(4, 0);
    canvas.drawPath(bottomCap, stroke);
  }

  // --- wave.svg -------------------------------------------------------------
  //   Three identical rows, each:
  //   M2 <y> c2 0 2.5 -2.5 5 -2.5 S14 <y> 14.5 <y> c2.5 0 3 -2.5 5 -2.5
  //   at y = 9, 14, 19.
  void _paintWave(Canvas canvas, Paint stroke) {
    for (final double y in const <double>[9, 14, 19]) {
      final Path row = Path()
        ..moveTo(2, y)
        // c2 0 2.5 -2.5 5 -2.5  (relative cubic from (2,y))
        ..relativeCubicTo(2, 0, 2.5, -2.5, 5, -2.5)
        // S14 y 14.5 y  (smooth cubic: control1 is the reflection of the
        // previous control2 about the current point (7,y-2.5); reflection of
        // (4.5,y-2.5) is (9.5,y-2.5)). End at (14.5,y).
        ..cubicTo(9.5, y - 2.5, 14, y, 14.5, y)
        // c2.5 0 3 -2.5 5 -2.5  (relative cubic from (14.5,y))
        ..relativeCubicTo(2.5, 0, 3, -2.5, 5, -2.5);
      canvas.drawPath(row, stroke);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

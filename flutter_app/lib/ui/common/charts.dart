import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import 'motion_widgets.dart';

/// Area sparkline for one or more flow series.
///
/// DESIGN.md §3/§6: grid lines in `#2C2C2E`, data stroke in the accent, area
/// gradient blending the accent into `#30D158`, no heavy borders, and area charts
/// preferred so spikes read as shape rather than noise.
///
/// Requirement 3.9 needs all three channels plottable at once, so the widget is
/// multi-series at heart: [FlowSparkline.multi] takes a list of series and a
/// matching list of stroke colours, and draws one area gradient per series in
/// draw order. The historical single-series constructor is retained as a thin
/// delegate — it wraps its one series and colour into single-element lists — so
/// the carousel's call sites do not change.
class FlowSparkline extends StatelessWidget {
  /// Single-series form, kept as a thin delegate to [FlowSparkline.multi] so
  /// existing call sites are untouched. When [color] is null the accent token
  /// is resolved at build time.
  FlowSparkline({
    super.key,
    required List<double> values,
    this.height = 96,
    Color? color,
    this.showGrid = true,
    this.gridDivisions = 3,
    this.minRange = 0.5,
    this.alarmMask,
  })  : series = <List<double>>[values],
        colors = color == null ? const <Color>[] : <Color>[color];

  /// Multi-series form. [series] and [colors] are drawn in order; each series
  /// gets the stroke and area gradient of the colour at the same index. When
  /// [colors] is shorter than [series] the accent token fills the remainder.
  const FlowSparkline.multi({
    super.key,
    required this.series,
    required this.colors,
    this.height = 96,
    this.showGrid = true,
    this.gridDivisions = 3,
    this.minRange = 0.5,
    this.alarmMask,
  });

  /// Opacity applied to a series' stroke colour at the top of its area
  /// gradient — the first of the three stops. DESIGN.md §3/§6 keeps the fills
  /// low-alpha so three overlapping series still read (see [DashboardView]).
  ///
  /// Exposed as a named constant so the snapshot example test (task 9.15) can
  /// pin the gradient recipe without a fragile pixel golden. Mirrors the React
  /// twin's `stopOpacity="0.34"`.
  static const double gradientStopTopOpacity = 0.34;

  /// Opacity applied to the [AppPalette.gradientGreen] partner at the middle
  /// stop of the area gradient. Mirrors the React `stopOpacity="0.1"`.
  static const double gradientStopMidOpacity = 0.10;

  /// Opacity at the bottom stop — the gradient fades fully out. Mirrors the
  /// React `stopOpacity="0"`.
  static const double gradientStopBottomOpacity = 0.0;

  /// The three gradient stop offsets, `0` → `0.6` → `1`, index-aligned with the
  /// three opacities above. Mirrors the React `offset` `0% / 60% / 100%`.
  static const List<double> gradientStopOffsets = <double>[0, 0.6, 1];

  /// Stroke width of a data series line, in logical pixels. Requirement 3.8
  /// caps series strokes at 2; this pins the value the painter draws.
  static const double seriesStrokeWidth = 2;

  /// Stroke width of a grid line, in logical pixels. The grid is the faint
  /// border-token backdrop (Requirement 3.8), thinner than the data stroke.
  static const double gridStrokeWidth = 1;

  /// Series in canonical L/min, oldest first. An all-empty set renders the
  /// empty state.
  final List<List<double>> series;

  /// Stroke colour per series, index-aligned with [series]. Comes from theme
  /// tokens; shorter lists fall back to the accent for the remaining series.
  final List<Color> colors;

  final double height;
  final bool showGrid;
  final int gridDivisions;

  /// Floor on the vertical span, so a flat-zero series does not amplify noise
  /// into a mountain range.
  final double minRange;

  /// Optional per-point alarm flags aligned with the first series; alarming
  /// spans tint red.
  final List<bool>? alarmMask;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final reduced = reduceMotionOf(context);

    // Resolve one stroke per non-empty series, filling any gap with the accent.
    final strokes = <Color>[
      for (var i = 0; i < series.length; i++)
        i < colors.length ? colors[i] : palette.accent,
    ];
    final hasData = series.any((s) => s.isNotEmpty);

    if (!hasData) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Waiting for data',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: 1),
        duration: reduced ? Duration.zero : Motion.slow,
        curve: Motion.enter,
        builder: (context, reveal, _) {
          return CustomPaint(
            painter: _SparklinePainter(
              series: series,
              strokes: strokes,
              gradientEnd: palette.gradientGreen,
              gridColor: palette.border,
              alarmColor: palette.alert,
              showGrid: showGrid,
              gridDivisions: gridDivisions,
              minRange: minRange,
              reveal: reveal,
              alarmMask: alarmMask,
            ),
          );
        },
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.series,
    required this.strokes,
    required this.gradientEnd,
    required this.gridColor,
    required this.alarmColor,
    required this.showGrid,
    required this.gridDivisions,
    required this.minRange,
    required this.reveal,
    required this.alarmMask,
  });

  /// One entry per plotted channel, oldest sample first.
  final List<List<double>> series;

  /// Stroke colour per series, index-aligned with [series].
  final List<Color> strokes;
  final Color gradientEnd;
  final Color gridColor;
  final Color alarmColor;
  final bool showGrid;
  final int gridDivisions;
  final double minRange;
  final double reveal;
  final List<bool>? alarmMask;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // A shared vertical span keeps the series comparable — the tallest sample
    // across every channel sets the scale, floored by [minRange].
    var maxValue = minRange;
    for (final values in series) {
      for (final value in values) {
        if (value > maxValue) maxValue = value;
      }
    }
    final span = maxValue;

    if (showGrid) {
      final gridPaint = Paint()
        ..color = gridColor
        ..strokeWidth = FlowSparkline.gridStrokeWidth;
      for (var i = 0; i <= gridDivisions; i++) {
        final y = size.height * (i / gridDivisions);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    // Draw one area gradient plus stroke per series, in draw order.
    for (var s = 0; s < series.length; s++) {
      final values = series[s];
      if (values.length < 2) continue;
      final stroke = s < strokes.length ? strokes[s] : strokes.last;
      final points = _pointsFor(values, size, span);
      if (points.length < 2) continue;
      _paintSeries(canvas, size, points, stroke);
    }

    // Tint the vertical band behind any alarming sample, keyed to the first
    // series' geometry.
    final mask = alarmMask;
    if (mask != null && series.isNotEmpty && mask.length == series.first.length) {
      final base = series.first;
      final points = _pointsFor(base, size, span);
      final count = base.length;
      final dx = count <= 1 ? size.width : size.width / (count - 1);
      final alarmPaint = Paint()..color = alarmColor.withValues(alpha: 0.14);
      for (var i = 0; i < points.length; i++) {
        if (!mask[i]) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            points[i].dx - dx / 2,
            0,
            math.max(dx, 2),
            size.height,
          ),
          alarmPaint,
        );
      }
    }
  }

  /// Sample positions for one series, revealed up to [reveal].
  List<Offset> _pointsFor(List<double> values, Size size, double span) {
    final count = values.length;
    final visibleCount = math.max(2, (count * reveal).round());
    final dx = count <= 1 ? size.width : size.width / (count - 1);
    // Leave 6px of headroom so a peak does not clip against the card edge.
    final usable = size.height - 6;
    return List<Offset>.generate(math.min(visibleCount, count), (i) {
      final x = dx * i;
      final normalised = (values[i] / span).clamp(0.0, 1.0);
      final y = size.height - normalised * usable;
      return Offset(x, y);
    });
  }

  /// Draws the area gradient, stroke and leading dot for a single series.
  void _paintSeries(Canvas canvas, Size size, List<Offset> points, Color stroke) {
    // Catmull-Rom through the samples, converted to cubic Béziers. Smoother than
    // straight segments without the overshoot a plain spline would add.
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[i] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = (i + 2 < points.length) ? points[i + 2] : p2;

      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      linePath.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    final areaPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            stroke.withValues(alpha: FlowSparkline.gradientStopTopOpacity),
            gradientEnd.withValues(alpha: FlowSparkline.gradientStopMidOpacity),
            gradientEnd
                .withValues(alpha: FlowSparkline.gradientStopBottomOpacity),
          ],
          stops: FlowSparkline.gradientStopOffsets,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = FlowSparkline.seriesStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Leading dot on the newest sample.
    final head = points.last;
    canvas
      ..drawCircle(head, 5, Paint()..color = stroke.withValues(alpha: 0.22))
      ..drawCircle(head, 2.6, Paint()..color = stroke);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) {
    if (old.reveal != reveal || old.series.length != series.length) return true;
    if (!_listEquals(old.strokes, strokes)) return true;
    for (var s = 0; s < series.length; s++) {
      final a = old.series[s];
      final b = series[s];
      if (a.length != b.length || !_sameTail(a, b)) return true;
    }
    return false;
  }

  static bool _listEquals(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Comparing the last few samples is enough: the series is append-only.
  static bool _sameTail(List<double> a, List<double> b) {
    final n = math.min(4, math.min(a.length, b.length));
    for (var i = 1; i <= n; i++) {
      if (a[a.length - i] != b[b.length - i]) return false;
    }
    return true;
  }
}

/// Horizontal gauge showing how far the current balance sits inside the
/// calibrated tolerance envelope.
///
/// The track spans -threshold..+threshold. A marker rides at the live balance.
/// Once the marker leaves the track the bar turns into the alert colour, which is
/// the visual equivalent of the firmware's `WATCH` -> `LEAK` escalation.
class EnvelopeGauge extends StatelessWidget {
  const EnvelopeGauge({
    super.key,
    required this.balanceLpm,
    required this.thresholdLpm,
    required this.expectedLpm,
    this.height = 44,
    this.label,
  });

  final double balanceLpm;
  final double thresholdLpm;
  final double expectedLpm;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final reduced = reduceMotionOf(context);

    final threshold = thresholdLpm <= 0 ? 0.5 : thresholdLpm;
    final ratio = (balanceLpm / threshold).clamp(-2.0, 2.0);
    final breaching = balanceLpm.abs() > threshold;
    final markerColor = breaching
        ? (balanceLpm > 0 ? palette.alert : palette.watch)
        : palette.normal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label!.toUpperCase(),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: palette.textSecondary, letterSpacing: 1),
          ),
          const SizedBox(height: Tokens.s2),
        ],
        SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: ratio),
            duration: reduced ? Duration.zero : Motion.base,
            curve: Motion.value,
            builder: (context, animatedRatio, _) {
              return CustomPaint(
                painter: _EnvelopePainter(
                  ratio: animatedRatio,
                  trackColor: palette.surfaceRaised,
                  borderColor: palette.border,
                  safeColor: palette.normal,
                  markerColor: markerColor,
                  tickColor: palette.textSecondary,
                  expectedRatio:
                      (expectedLpm / threshold).clamp(-1.0, 1.0).toDouble(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Tokens.s2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              '-${threshold.toStringAsFixed(2)}',
              style: AppText.mono(
                size: 11,
                weight: FontWeight.w500,
                color: palette.textSecondary,
              ),
            ),
            Text(
              'balanced',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textSecondary,
                fontSize: 11,
              ),
            ),
            Text(
              '+${threshold.toStringAsFixed(2)}',
              style: AppText.mono(
                size: 11,
                weight: FontWeight.w500,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  _EnvelopePainter({
    required this.ratio,
    required this.trackColor,
    required this.borderColor,
    required this.safeColor,
    required this.markerColor,
    required this.tickColor,
    required this.expectedRatio,
  });

  /// Balance divided by threshold, clamped to -2..2.
  final double ratio;
  final Color trackColor;
  final Color borderColor;
  final Color safeColor;
  final Color markerColor;
  final Color tickColor;
  final double expectedRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final centreY = size.height / 2;
    final trackHeight = 10.0;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, centreY - trackHeight / 2, size.width, trackHeight),
      const Radius.circular(Tokens.radiusPill),
    );

    canvas
      ..drawRRect(trackRect, Paint()..color = trackColor)
      ..drawRRect(
        trackRect,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

    // The safe band is the middle half of the track, i.e. |ratio| <= 1 maps to
    // the inner 50% either side of centre.
    final safeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.25,
        centreY - trackHeight / 2,
        size.width * 0.5,
        trackHeight,
      ),
      const Radius.circular(Tokens.radiusPill),
    );
    canvas.drawRRect(
      safeRect,
      Paint()..color = safeColor.withValues(alpha: 0.22),
    );

    // Centre tick.
    canvas.drawLine(
      Offset(size.width / 2, centreY - trackHeight),
      Offset(size.width / 2, centreY + trackHeight),
      Paint()
        ..color = tickColor.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    // Expected-bias tick: where a healthy rig is meant to sit.
    final expectedX = size.width / 2 + (expectedRatio / 2) * size.width / 2;
    canvas.drawLine(
      Offset(expectedX, centreY - trackHeight * 0.7),
      Offset(expectedX, centreY + trackHeight * 0.7),
      Paint()
        ..color = tickColor.withValues(alpha: 0.85)
        ..strokeWidth = 1.5,
    );

    // Marker.
    final markerX = (size.width / 2 + (ratio / 2) * size.width / 2)
        .clamp(6.0, size.width - 6.0);
    canvas
      ..drawCircle(
        Offset(markerX, centreY),
        11,
        Paint()..color = markerColor.withValues(alpha: 0.2),
      )
      ..drawCircle(Offset(markerX, centreY), 6, Paint()..color = markerColor);
  }

  @override
  bool shouldRepaint(_EnvelopePainter old) =>
      old.ratio != ratio ||
      old.markerColor != markerColor ||
      old.expectedRatio != expectedRatio;
}

/// Thin progress ring used on the calibration dialog.
class RingProgress extends StatelessWidget {
  const RingProgress({
    super.key,
    required this.progress,
    this.size = 84,
    this.strokeWidth = 6,
    this.color,
    this.child,
  });

  /// 0..1
  final double progress;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
            duration: Motion.base,
            curve: Motion.value,
            builder: (context, value, _) => CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                progress: value,
                track: palette.border,
                stroke: color ?? palette.accent,
                strokeWidth: strokeWidth,
              ),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.track,
    required this.stroke,
    required this.strokeWidth,
  });

  final double progress;
  final Color track;
  final Color stroke;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    canvas
      ..drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      )
      ..drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.stroke != stroke;
}

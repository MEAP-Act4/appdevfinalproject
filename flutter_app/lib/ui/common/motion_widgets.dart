import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/settings/settings_controller.dart';

/// Reads the user's "reduce motion" preference. Every transition and ambient
/// animation checks this. Under Reduce_Motion, Requirement 11.6 collapses every
/// transition to at most 1ms (effectively instant) and stops every ambient loop
/// — there is no "shorter but still animating" middle ground. This matches the
/// token registry's `--t-*` contract, which resolves every transition alias to
/// `reduceMotionMillis: 1` when Reduce_Motion is on.
bool reduceMotionOf(BuildContext context) {
  return context.select<SettingsController, bool>(
    (controller) => controller.settings.reduceMotion,
  );
}

/// Resolves a transition duration against the Reduce_Motion contract.
///
/// The Flutter analogue of the web client's `--t-*` alias indirection: rather
/// than repeating `reduced ? Duration.zero : full` at every call site, every
/// transition routes its declared [full] duration through here. Under
/// Reduce_Motion it collapses to [Duration.zero] (satisfying Requirement 11.6's
/// at-most-1ms cap); otherwise it is [full] unchanged. This is the one place
/// the reduce-motion transition contract lives, so Property 19 is checkable
/// against a single switch.
Duration motionOf(BuildContext context, Duration full) {
  return reduceMotionOf(context) ? Duration.zero : full;
}

/// [motionOf] for callers that have already resolved the preference (e.g. from
/// a `settings.reduceMotion` read outside a build that uses [reduceMotionOf]).
Duration motionFor({required bool reduceMotion, required Duration full}) {
  return reduceMotion ? Duration.zero : full;
}

/// Entrance animation: fades and lifts a child into place.
///
/// Use [index] to stagger siblings — each step adds [stagger] to the delay, which
/// is what makes a column of cards feel like it settles rather than snapping in.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 55),
    this.duration = Motion.base,
    this.offset = 18,
    this.enabled = true,
  });

  final Widget child;
  final int index;
  final Duration stagger;
  final Duration duration;
  final double offset;
  final bool enabled;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _curved = CurvedAnimation(
    parent: _controller,
    curve: Motion.enter,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _controller.value = 1;
      return;
    }
    Future<void>.delayed(widget.stagger * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotionOf(context)) {
      // Skip the translation and the stagger entirely.
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        return Opacity(
          opacity: _curved.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - _curved.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// The "live" dot: a solid core with a soft breathing halo.
/// Stops breathing when reduce-motion is on or [active] is false.
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    this.size = 10,
    this.active = true,
  });

  final Color color;
  final double size;
  final bool active;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final core = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );

    final box = widget.size * 2.2;

    if (reduceMotionOf(context) || !widget.active) {
      return SizedBox(width: box, height: box, child: Center(child: core));
    }

    return SizedBox(
      width: box,
      height: box,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: widget.size * (1.2 + t),
                height: widget.size * (1.2 + t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.28 * (1 - t)),
                ),
              ),
              child!,
            ],
          );
        },
        child: core,
      ),
    );
  }
}

/// Cross-fades and slightly scales between states in the same slot, so content
/// swaps never pop. Honours reduce-motion by dropping the scale.
class SoftSwitcher extends StatelessWidget {
  const SoftSwitcher({
    super.key,
    required this.child,
    this.duration = Motion.base,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotionOf(context);
    return AnimatedSwitcher(
      duration: motionOf(context, duration),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: alignment,
        children: <Widget>[
          ...previousChildren,
          ?currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        if (reduced) return FadeTransition(opacity: animation, child: child);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Horizontal shimmer used on skeleton placeholders while the first sample or
/// the first aggregate query is still in flight.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surface;
    final highlight = Theme.of(context).colorScheme.onSurface.withValues(
          alpha: 0.06,
        );

    if (reduceMotionOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: highlight,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 2 - 0.4, 0),
              end: Alignment(-1 + t * 2 + 0.4, 0),
              colors: <Color>[base, highlight, base],
            ),
          ),
        );
      },
    );
  }
}

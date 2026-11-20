import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Press feedback for anything tappable: a small scale-down while held, plus
/// hover and keyboard focus from the underlying [InkWell].
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.borderRadius,
    this.haptic = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final BorderRadius? borderRadius;

  /// A light selection tick on tap (no-op where the platform has none).
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final radius = widget.borderRadius ?? BorderRadius.circular(Radii.md);
    final scale = (_down && !context.reduceMotion) ? widget.scale : 1.0;
    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onHighlightChanged: enabled
              ? (value) {
                  if (mounted && _down != value) setState(() => _down = value);
                }
              : null,
          onTap: widget.onTap == null
              ? null
              : () {
                  if (widget.haptic) HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  widget.onLongPress!();
                },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades and lifts its child once, the first time it appears. Stagger with
/// [index]; only the first few items in a list should use it.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
    this.enabled = true,
  });

  final Widget child;
  final int index;
  final double offset;
  final bool enabled;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || context.reduceMotion) {
      _controller.value = 1;
      return;
    }
    final delay = Duration(milliseconds: math.min(widget.index, 7) * 45);
    Future<void>.delayed(delay, () {
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
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * widget.offset),
            child: child,
          ),
        );
      },
    );
  }
}

/// Wraps the first [limit] items of a list in [Reveal]; later items appear
/// normally so scrolling never feels busy.
Widget revealAt(int index, Widget child, {int limit = 8}) {
  if (index >= limit) return child;
  return Reveal(index: index, child: child);
}

/// A horizontal bar whose fill animates to [value] (0..1).
class AnimatedBar extends StatelessWidget {
  const AnimatedBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.track,
  });

  final double value;
  final double height;
  final Color? color;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? context.scheme.primary;
    final back = track ?? context.palette.subtle;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: Motion.slow,
      curve: Motion.out,
      builder: (context, v, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: back)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: ColoredBox(color: fill),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A circular progress ring with an optional centre widget.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 56,
    this.stroke = 5,
    this.color,
    this.track,
    this.child,
  });

  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Color? track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? context.scheme.primary;
    final back = track ?? fill.withValues(alpha: 0.16);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: Motion.slow,
      curve: Motion.out,
      child: child,
      builder: (context, v, child) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: v,
              stroke: stroke,
              color: fill,
              track: back,
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.stroke,
    required this.color,
    required this.track,
  });

  final double progress;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(rect.center, rect.width / 2, base);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.stroke != stroke ||
      old.color != color ||
      old.track != track;
}

/// Small animated "sound bars". Static when [active] is false or when the
/// platform asks for reduced motion.
class Equalizer extends StatefulWidget {
  const Equalizer({
    super.key,
    this.color,
    this.size = 18,
    this.active = true,
    this.bars = 4,
  });

  final Color? color;
  final double size;
  final bool active;
  final int bars;

  @override
  State<Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant Equalizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active && !context.reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.scheme.primary;
    final barWidth = widget.size / (widget.bars * 1.7);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < widget.bars; i++)
                Container(
                  width: barWidth,
                  height: widget.size *
                      (0.28 +
                          0.72 *
                              (0.5 +
                                  0.5 *
                                      math.sin(
                                        math.pi *
                                            2 *
                                            (_controller.value + i * 0.23),
                                      ))),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(barWidth),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A dot that breathes while something is in progress.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(Tween<double>(begin: 0.35, end: 1)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Animates between days with a short horizontal slide that follows the
/// direction of travel, and lets a horizontal swipe step between days.
class DaySwitcher extends StatefulWidget {
  const DaySwitcher({
    super.key,
    required this.day,
    required this.builder,
    this.onSwipe,
  });

  final DateTime day;
  final Widget Function(BuildContext context, DateTime day) builder;

  /// Called with +1 (next day) or -1 (previous day).
  final ValueChanged<int>? onSwipe;

  @override
  State<DaySwitcher> createState() => _DaySwitcherState();
}

class _DaySwitcherState extends State<DaySwitcher> {
  int _direction = 1;

  static int _code(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  @override
  void didUpdateWidget(covariant DaySwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_code(oldWidget.day) != _code(widget.day)) {
      _direction = _code(widget.day) > _code(oldWidget.day) ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = ValueKey<int>(_code(widget.day));
    final content = AnimatedSwitcher(
      duration: context.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        fit: StackFit.passthrough,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == key;
        final dx = 0.06 * _direction * (incoming ? 1 : -1);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(dx, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: key, child: widget.builder(context, widget.day)),
    );
    if (widget.onSwipe == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 320) return;
        widget.onSwipe!(v < 0 ? 1 : -1);
      },
      child: content,
    );
  }
}

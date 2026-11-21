import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Frosted surface for bars that float over scrolling content: the bottom
/// navigation, the collapsed large-title bar and the in-editor toolbar.
///
/// This is the only place a [BackdropFilter] should be used. Cards sit on a
/// flat background where there is nothing to blur, so they stay matte.
///
/// Falls back to an opaque card when the user asks for higher contrast.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.sigma = 22,
    this.borderSides = const [],
    this.shadow = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double sigma;

  /// Hairlines to draw for a flat bar (e.g. just the top edge). Leave empty
  /// and give [borderRadius] for a floating, fully outlined surface.
  final List<AxisDirection> borderSides;

  /// A single, very soft drop shadow for floating surfaces.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final opaque = context.highContrast;
    final fill = opaque ? palette.card : palette.glass;
    final hairline = BorderSide(color: palette.border);

    final Border? border = borderSides.isEmpty
        ? (borderRadius == BorderRadius.zero ? null : Border.fromBorderSide(hairline))
        : Border(
            top: borderSides.contains(AxisDirection.up) ? hairline : BorderSide.none,
            bottom: borderSides.contains(AxisDirection.down) ? hairline : BorderSide.none,
          );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: border,
      ),
      child: child,
    );

    Widget surface = ClipRRect(
      borderRadius: borderRadius,
      child: opaque
          ? decorated
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: decorated,
            ),
    );

    if (shadow) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: palette.isDark ? 0.30 : 0.07),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: surface,
      );
    }
    return RepaintBoundary(child: surface);
  }
}

enum StatusTone { neutral, positive, attention, critical, accent }

/// Small status indicator: a dot and a short label. Use it for state that can
/// change (signed in, session expired, last backup) rather than for
/// categories, which stay on `SourceChip`.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
  });

  final String label;
  final StatusTone tone;

  Color _color(BuildContext context) {
    final palette = context.palette;
    return switch (tone) {
      StatusTone.neutral => palette.mutedText,
      StatusTone.positive => palette.success,
      StatusTone.attention => palette.warning,
      StatusTone.critical => context.scheme.error,
      StatusTone.accent => context.scheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.text.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small section label that sits above a group. Sentence case, tracked out a
/// little; quieter than a title so the content carries the page.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.label, {super.key, this.padding});

  final String label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(left: Insets.xs, bottom: Insets.sm),
      child: Text(
        label,
        style: context.text.labelMedium?.copyWith(
          color: context.palette.mutedText,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

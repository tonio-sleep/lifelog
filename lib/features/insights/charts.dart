import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';

/// Bars that grow into place. Zero values stay visible as small stubs so a
/// gap reads as a gap rather than missing data.
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.values,
    required this.color,
    this.height = 88,
    this.labels,
    this.showBaseline = true,
    this.emptyLabel,
    this.highlightIndex,
    this.labelColor,
    this.trackColor,
  });

  final List<double> values;
  final Color color;
  final double height;
  final List<String>? labels;
  final bool showBaseline;
  final String? emptyLabel;

  /// When set, other bars are softened so one stands out.
  final int? highlightIndex;

  /// Overrides for charts drawn on a dark or coloured surface.
  final Color? labelColor;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            emptyLabel ?? 'Nothing to chart yet',
            style: context.text.bodySmall?.copyWith(color: palette.dimText),
          ),
        ),
      );
    }
    final maxValue = values.fold<double>(0, math.max);
    final dense = values.length > 40;
    final sidePad = dense ? 0.5 : (values.length > 14 ? 1.5 : 3.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: sidePad),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: values[i] <= 0 || maxValue <= 0
                                ? 3
                                : math.max(4, height * (values[i] / maxValue) * t),
                            decoration: BoxDecoration(
                              color: values[i] <= 0
                                  ? (trackColor ?? palette.subtle)
                                  : color.withValues(
                                      alpha: highlightIndex == null ||
                                              highlightIndex == i
                                          ? 1
                                          : 0.5,
                                    ),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(dense ? 1.5 : 5),
                                bottom: const Radius.circular(1.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (showBaseline) ...[
          const SizedBox(height: 4),
          Container(height: 1, color: palette.border),
        ],
        if (labels != null && labels!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in labels!)
                Text(
                  label,
                  style: context.text.labelSmall?.copyWith(
                    color: labelColor ?? palette.dimText,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A labelled horizontal bar with an animated fill.
class HorizontalMetricBar extends StatelessWidget {
  const HorizontalMetricBar({
    super.key,
    required this.label,
    required this.value,
    required this.maxValue,
    this.color,
    this.trailing,
    this.caption,
  });

  final String label;
  final double value;
  final double maxValue;
  final Color? color;
  final String? trailing;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: text.labelMedium?.copyWith(
                    color: palette.mutedText,
                    fontFeatures: tabularFigures,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedBar(
            value: maxValue <= 0 ? 0 : value / maxValue,
            color: color,
            height: 6,
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: text.labelSmall?.copyWith(color: palette.dimText),
            ),
          ],
        ],
      ),
    );
  }
}

/// A calendar-like grid of cells shaded by value.
class ActivityHeatGrid extends StatelessWidget {
  const ActivityHeatGrid({
    super.key,
    required this.values,
    this.cell = 12,
    this.gap = 4,
  });

  final List<double> values;
  final double cell;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.scheme;
    final maxValue = values.fold<double>(0, math.max);
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final value in values)
          Container(
            width: cell,
            height: cell,
            decoration: BoxDecoration(
              color: value <= 0 || maxValue <= 0
                  ? palette.subtle
                  : scheme.primary.withValues(
                      alpha: 0.25 + 0.75 * (value / maxValue),
                    ),
              borderRadius: BorderRadius.circular(cell * 0.28),
            ),
          ),
      ],
    );
  }
}

/// One horizontal bar split into coloured shares, with a legend.
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.segments,
    this.height = 12,
  });

  final List<({String label, double value, Color color})> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = segments.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) return const SizedBox.shrink();
    final shown = segments.where((s) => s.value > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: Motion.slow,
          curve: Motion.out,
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: math.max(1, (shown[i].value / total * 1000).round()),
                      child: ColoredBox(color: shown[i].color),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.lg,
          runSpacing: 4,
          children: [
            for (final s in shown)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${s.label} ${s.value.round()}',
                    style: context.text.labelSmall?.copyWith(
                      color: palette.mutedText,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

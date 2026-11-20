import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/timeline.dart';

import 'motion.dart';
export 'motion.dart';

/// Tabular figures keep changing numbers from jittering.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// The one surface used for grouped content: opaque, hairline-edged, no
/// shadow. Depth comes from the contrast between page and card, not from
/// blur or elevation.
class QuietCard extends StatelessWidget {
  const QuietCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.color,
    this.radius = Radii.lg,
    this.border = false,
    this.margin,
    this.gradient,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final bool border;
  final EdgeInsetsGeometry? margin;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shape = BorderRadius.circular(radius);

    Widget surface = ClipRRect(
      borderRadius: shape,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? palette.card) : null,
          gradient: gradient,
          borderRadius: shape,
          border: border ? Border.all(color: palette.border) : null,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );

    if (onTap != null || onLongPress != null) {
      surface = Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
        scale: 0.99,
        borderRadius: shape,
        child: surface,
      );
    }
    if (margin != null) surface = Padding(padding: margin!, child: surface);
    return surface;
  }
}

/// Simple page title. Screens normally use `ScreenFrame`; this stays for
/// content that lays itself out.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.headlineMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: text.bodySmall?.copyWith(
                      color: context.palette.mutedText,
                    ),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty) Wrap(spacing: Insets.xs, children: actions),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.only(top: Insets.xl, bottom: Insets.sm),
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final palette = context.palette;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: text.bodySmall?.copyWith(color: palette.mutedText),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Quiet empty state: one icon, one sentence of what this is, one action.
/// Nothing moves; an empty screen should feel settled, not like it is waiting.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final palette = context.palette;
    final accent = color ?? palette.mutedText;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? Insets.lg : Insets.xxl,
        horizontal: Insets.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 48 : 60,
                height: compact ? 48 : 60,
                decoration: BoxDecoration(
                  color: palette.subtle,
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                child: Icon(icon, size: compact ? 22 : 26, color: accent),
              ),
              SizedBox(height: compact ? Insets.md : Insets.lg),
              Text(title, textAlign: TextAlign.center, style: text.titleMedium),
              const SizedBox(height: Insets.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: palette.mutedText),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: Insets.lg),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SourceChip extends StatelessWidget {
  const SourceChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.scheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Insets.sm : Insets.md,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: accent),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
                fontSize: dense ? 10.5 : 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TagPill extends StatelessWidget {
  const TagPill(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 3),
      decoration: BoxDecoration(
        color: palette.subtle,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        '#$label',
        style: context.text.labelSmall?.copyWith(color: palette.mutedText),
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = 38,
    this.iconSize = 19,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(icon, size: iconSize, color: accent),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.accent,
    this.compact = false,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    return Container(
      padding: EdgeInsets.all(compact ? Insets.md : Insets.lg),
      decoration: BoxDecoration(
        color: palette.subtle,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: accent ?? palette.mutedText),
            const SizedBox(height: Insets.sm),
          ],
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (compact ? text.titleLarge : text.headlineSmall)?.copyWith(
              fontFeatures: tabularFigures,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: palette.mutedText),
          ),
        ],
      ),
    );
  }
}

class MoodBadge extends StatelessWidget {
  const MoodBadge(this.mood, {super.key, this.showLabel = true});
  final int mood;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final score = mood.clamp(1, 10);
    final color = moodColor(score, context.scheme);
    final label = showLabel ? MoodScore.label(score) : '$score';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: context.text.labelMedium?.copyWith(
            color: context.palette.mutedText,
          ),
        ),
      ],
    );
  }
}

/// Color for a 1-10 mood score (low = warm/red, high = cool/green-blue).
Color moodColor(int mood, ColorScheme scheme) {
  final t = ((mood.clamp(1, 10) - 1) / 9.0);
  const low = Color(0xFFD4566B);
  const mid = Color(0xFFD9A13E);
  const high = Color(0xFF3FA27C);
  final color = t < 0.5
      ? Color.lerp(low, mid, t * 2)!
      : Color.lerp(mid, high, (t - 0.5) * 2)!;
  return color;
}

/// Compact picker for selecting a mood score from 1 to 10.
class MoodScorePicker extends StatelessWidget {
  const MoodScorePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var score = 1; score <= 10; score++)
              _MoodChip(
                score: score,
                selected: value == score,
                onTap: () => onChanged(value == score ? null : score),
              ),
          ],
        ),
        const SizedBox(height: Insets.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Low', style: text.labelSmall?.copyWith(color: palette.dimText)),
            if (value != null)
              Text(
                '${value!}/10 · ${MoodScore.label(value!)}',
                style: text.labelSmall?.copyWith(
                  color: moodColor(value!, context.scheme),
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Text(
                'Tap a number (optional)',
                style: text.labelSmall?.copyWith(color: palette.dimText),
              ),
            Text('High', style: text.labelSmall?.copyWith(color: palette.dimText)),
          ],
        ),
      ],
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({
    required this.score,
    required this.selected,
    required this.onTap,
  });

  final int score;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = moodColor(score, context.scheme);
    final scheme = context.scheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Mood $score out of 10, ${MoodScore.label(score)}',
      child: Pressable(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.out,
          // At least 44 logical pixels; grows with larger text sizes.
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            '$score',
            style: context.text.labelMedium?.copyWith(
              color: selected ? scheme.onPrimary : color,
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
      ),
    );
  }
}

IconAndColor sourceStyle(TimelineSource source, ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  return switch (source) {
    TimelineSource.manual => IconAndColor(
      Icons.edit_note_rounded,
      dark ? const Color(0xFFA3AAC8) : const Color(0xFF6B7390),
    ),
    TimelineSource.journal => IconAndColor(
      Icons.menu_book_rounded,
      scheme.primary,
    ),
    TimelineSource.tracker => IconAndColor(
      Icons.check_circle_outline_rounded,
      scheme.tertiary,
    ),
    TimelineSource.location => IconAndColor(
      Icons.place_rounded,
      dark ? const Color(0xFF6CB8E8) : const Color(0xFF2F86B8),
    ),
    TimelineSource.music => IconAndColor(
      Icons.graphic_eq_rounded,
      dark ? const Color(0xFFBE9BFF) : const Color(0xFF8B5CD6),
    ),
    TimelineSource.photo => IconAndColor(
      Icons.photo_rounded,
      dark ? const Color(0xFFF0B866) : const Color(0xFFC77D1E),
    ),
    TimelineSource.meal => IconAndColor(
      Icons.restaurant_rounded,
      scheme.secondary,
    ),
  };
}

class IconAndColor {
  const IconAndColor(this.icon, this.color);
  final IconData icon;
  final Color color;
}

/// Wrapping choice pills for short option sets (settings, ranges).
class ChoicePills<T> extends StatelessWidget {
  const ChoicePills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final palette = context.palette;
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: Insets.sm,
        runSpacing: Insets.sm,
        children: [
          for (final value in values)
            Semantics(
              button: true,
              selected: value == selected,
              label: labelFor(value),
              child: Pressable(
                borderRadius: BorderRadius.circular(Radii.pill),
                haptic: true,
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.lg,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? scheme.primary.withValues(alpha: 0.14)
                        : palette.subtle,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    labelFor(value),
                    style: context.text.labelMedium?.copyWith(
                      color: value == selected
                          ? scheme.primary
                          : palette.mutedText,
                      fontWeight: value == selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Constrains wide layouts without stretching text lines. The bottom gap is
/// deliberately small: the navigation bar already owns the bottom edge.
class ContentColumn extends StatelessWidget {
  const ContentColumn({
    super.key,
    required this.child,
    this.maxWidth = 760,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final compact = context.compact;
    final resolved =
        padding ??
        EdgeInsets.fromLTRB(
          compact ? Insets.page : Insets.xl,
          compact ? Insets.sm : Insets.xl,
          compact ? Insets.page : Insets.xl,
          Insets.xl,
        );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: resolved, child: child),
      ),
    );
  }
}

/// App mark used on the splash, sidebar and onboarding: a flat serif
/// monogram. No gradient, no glyph borrowed from the icon set.
class LifelogMark extends StatelessWidget {
  const LifelogMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.scheme.primary,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        'L',
        style: AppTheme.serif(
          null,
          size: size * 0.58,
          weight: FontWeight.w500,
        ).copyWith(color: context.scheme.onPrimary, height: 1),
      ),
    );
  }
}

Future<T?> guard<T>(
  BuildContext context,
  Future<T> future, {
  String? errorPrefix,
}) async {
  try {
    return await future;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
            errorPrefix == null ? '$error' : '$errorPrefix: $error',
          ),
        ),
      );
    }
    return null;
  }
}

void showSnack(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: duration));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

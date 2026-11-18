import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/timeline.dart';

import 'motion.dart';
export 'motion.dart';

/// Tabular figures keep changing numbers from jittering.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// The one surface used for grouped content.
class QuietCard extends StatelessWidget {
  const QuietCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.color,
    this.radius = Radii.lg,
    this.border = true,
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
    Widget card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? palette.card) : null,
        gradient: gradient,
        borderRadius: shape,
        border: border ? Border.all(color: palette.border) : null,
        boxShadow: palette.isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF1B2140).withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap != null || onLongPress != null) {
      card = Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
        scale: 0.985,
        borderRadius: shape,
        child: card,
      );
    }
    if (margin != null) card = Padding(padding: margin!, child: card);
    return card;
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

/// Friendly empty state with a softly breathing icon.
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
              _EmptyArt(
                icon: icon,
                size: compact ? 72 : 104,
                color: color ?? context.scheme.primary,
              ),
              SizedBox(height: compact ? Insets.sm : Insets.md),
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

class _EmptyArt extends StatefulWidget {
  const _EmptyArt({
    required this.icon,
    required this.size,
    required this.color,
  });

  final IconData icon;
  final double size;
  final Color color;

  @override
  State<_EmptyArt> createState() => _EmptyArtState();
}

class _EmptyArtState extends State<_EmptyArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
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
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: size * (0.5 + i * 0.25) * (0.97 + 0.06 * t),
                  height: size * (0.5 + i * 0.25) * (0.97 + 0.06 * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.12 - i * 0.035),
                  ),
                ),
              Transform.translate(
                offset: Offset(0, -2 * t),
                child: Icon(
                  widget.icon,
                  size: size * 0.3,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
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
  const MoodBadge(this.mood, {super.key});
  final Mood mood;

  @override
  Widget build(BuildContext context) {
    final color = moodColor(mood, context.scheme);
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
          mood.label,
          style: context.text.labelMedium?.copyWith(
            color: context.palette.mutedText,
          ),
        ),
      ],
    );
  }
}

Color moodColor(Mood mood, ColorScheme scheme) => switch (mood) {
  Mood.awful => const Color(0xFFD4566B),
  Mood.low => const Color(0xFFD98F3E),
  Mood.okay => const Color(0xFF8E96B3),
  Mood.good => const Color(0xFF3FA27C),
  Mood.great => const Color(0xFF3B8DDE),
};

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
            Pressable(
              borderRadius: BorderRadius.circular(Radii.pill),
              haptic: true,
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: Motion.fast,
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

/// App mark used on the splash, sidebar and onboarding.
class LifelogMark extends StatelessWidget {
  const LifelogMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = context.scheme.primary;
    final dark = context.palette.isDark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary,
            Color.lerp(primary, dark ? const Color(0xFFBE9BFF) : const Color(0xFF8B5CD6), 0.7)!,
          ],
        ),
      ),
      child: Icon(
        Icons.auto_stories_rounded,
        size: size * 0.52,
        color: dark ? const Color(0xFF12163A) : Colors.white,
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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/dates.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// A round-cornered icon button used in screen headers.
class HeaderButton extends StatelessWidget {
  const HeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = color ?? (filled ? context.scheme.onPrimary : context.scheme.onSurface);
    return Padding(
      padding: const EdgeInsets.only(left: Insets.xs),
      child: Tooltip(
        message: tooltip,
        child: Pressable(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Radii.md),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: filled ? context.scheme.primary : palette.subtle,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}

/// Compact title row. Pushed pages get a back button automatically.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Row(
          children: [
            if (showBack)
              Padding(
                padding: const EdgeInsets.only(right: Insets.sm),
                child: Tooltip(
                  message: 'Back',
                  child: Pressable(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: SizedBox(
                      width: 40,
                      height: 42,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: context.scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineMedium,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: context.palette.mutedText,
                      ),
                    ),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// The shared page scaffold: compact header, lazy scrolling, optional
/// pull-to-refresh, centred max width on desktop and a small bottom gap.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({
    super.key,
    this.title = '',
    this.subtitle,
    this.actions = const [],
    this.children = const [],
    this.slivers = const [],
    this.header,
    this.onRefresh,
    this.maxWidth = 720,
    this.background,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  /// Extra slivers appended after [children]; padded to match.
  final List<Widget> slivers;

  /// Replaces the standard header.
  final Widget? header;
  final Future<void> Function()? onRefresh;
  final double maxWidth;

  /// Painted behind the scrolling content.
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final pushed = ModalRoute.of(context)?.canPop ?? false;
    final headerWidget =
        header ??
        ScreenHeader(
          title: title,
          subtitle: subtitle,
          actions: actions,
          showBack: pushed,
        );

    Widget body = LayoutBuilder(
      builder: (context, constraints) {
        final base = context.compact ? Insets.page : Insets.xl;
        final side = math.max(base, (constraints.maxWidth - maxWidth) / 2);
        final bottom = Insets.xl + MediaQuery.paddingOf(context).bottom;
        final scroll = CustomScrollView(
          physics: onRefresh != null
              ? const AlwaysScrollableScrollPhysics()
              : null,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, Insets.sm, side, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([headerWidget, ...children]),
              ),
            ),
            for (final sliver in slivers)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: side),
                sliver: sliver,
              ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        );
        if (onRefresh == null) return scroll;
        return RefreshIndicator(onRefresh: onRefresh!, child: scroll);
      },
    );

    if (background != null) {
      body = Stack(
        children: [
          Positioned.fill(child: IgnorePointer(child: background!)),
          body,
        ],
      );
    }
    if (pushed) {
      return Scaffold(body: SafeArea(bottom: false, child: body));
    }
    return body;
  }
}

/// Previous / next day with a tappable label. Swipe handling lives in
/// `DaySwitcher`; this is the explicit control.
class DayNavigator extends StatelessWidget {
  const DayNavigator({
    super.key,
    required this.day,
    required this.onChanged,
    this.trailing,
  });

  final DateTime day;
  final ValueChanged<DateTime> onChanged;
  final Widget? trailing;

  DateTime _shift(int days) => DateTime(day.year, day.month, day.day + days);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final isToday = sameDay(day, DateTime.now());
    final key = ValueKey<int>(day.year * 10000 + day.month * 100 + day.day);
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () => onChanged(_shift(-1)),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Pressable(
              borderRadius: BorderRadius.circular(Radii.pill),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: day,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) onChanged(dayStart(picked));
              },
              child: AnimatedSwitcher(
                duration: Motion.fast,
                child: Column(
                  key: key,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      relativeDayLabel(day),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall,
                    ),
                    Text(
                      formatDayLong(day),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(
                        color: palette.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.out,
            child: isToday
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(right: Insets.xs),
                    child: TextButton(
                      onPressed: () => onChanged(dayStart(DateTime.now())),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Today'),
                    ),
                  ),
          ),
          ?trailing,
          IconButton(
            tooltip: 'Next day',
            onPressed: () => onChanged(_shift(1)),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

/// Inset grouped list (settings, library): one card, hairline dividers.
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children, this.title, this.footer});

  final List<Widget> children;
  final String? title;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: Insets.xs, bottom: Insets.sm),
              child: Text(
                title!,
                style: context.text.labelLarge?.copyWith(
                  color: palette.mutedText,
                ),
              ),
            ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, indent: 60, color: palette.border),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.xs, Insets.sm, Insets.xs, 0),
              child: Text(
                footer!,
                style: context.text.bodySmall?.copyWith(color: palette.dimText),
              ),
            ),
        ],
      ),
    );
  }
}

class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.scheme;
    final accent = destructive ? scheme.error : (iconColor ?? scheme.primary);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg,
            vertical: Insets.md,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                IconBadge(icon: icon!, color: accent, size: 32, iconSize: 17),
                const SizedBox(width: Insets.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: destructive ? scheme.error : null,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          subtitle!,
                          style: context.text.bodySmall?.copyWith(
                            color: palette.mutedText,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
              if (chevron)
                Icon(Icons.chevron_right_rounded, size: 20, color: palette.dimText),
            ],
          ),
        ),
      ),
    );
  }
}

int _fnv(String input) {
  var hash = 2166136261;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return hash;
}

/// Album artwork with a deterministic gradient fallback. Honours the
/// "Show album artwork" setting: when off, no image request is ever made.
class Artwork extends ConsumerWidget {
  const Artwork({
    super.key,
    this.url,
    required this.size,
    this.seed = '',
    this.radius,
    this.circle = false,
    this.icon = Icons.music_note_rounded,
  });

  final String? url;
  final double size;

  /// Text used to pick the fallback colour (artist or track name).
  final String seed;
  final double? radius;
  final bool circle;
  final IconData icon;

  /// Last.fm serves one grey placeholder star for missing art.
  static const _placeholder = '2a96cbd8b46e442fc41c2b86b821562f';

  static bool usable(String? url) =>
      url != null && url.isNotEmpty && !url.contains(_placeholder);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(settingsProvider.select((s) => s.showArtwork));
    final dark = context.palette.isDark;
    final hue = (_fnv(seed.isEmpty ? 'lifelog' : seed) % 360).toDouble();
    final a = HSLColor.fromAHSL(1, hue, 0.5, dark ? 0.30 : 0.60).toColor();
    final b = HSLColor.fromAHSL(1, (hue + 48) % 360, 0.55, dark ? 0.20 : 0.48)
        .toColor();
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.42,
          color: Colors.white.withValues(alpha: 0.82),
        ),
      ),
    );

    Widget content = fallback;
    if (enabled && usable(url)) {
      final cache = (size * MediaQuery.devicePixelRatioOf(context)).round();
      content = Stack(
        fit: StackFit.expand,
        children: [
          fallback,
          Image.network(
            url!,
            fit: BoxFit.cover,
            cacheWidth: cache,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            frameBuilder: (context, child, frame, sync) {
              if (sync) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: Motion.base,
                child: child,
              );
            },
            errorBuilder: (context, error, stack) => fallback,
          ),
        ],
      );
    }
    return ClipRRect(
      borderRadius: circle
          ? BorderRadius.circular(size)
          : BorderRadius.circular(radius ?? size * 0.2),
      child: SizedBox(width: size, height: size, child: content),
    );
  }
}

/// A horizontally scrolling single-select chip row. [T] may be nullable
/// (for an "All" entry).
class FilterRow<T> extends StatelessWidget {
  const FilterRow({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
    this.iconFor,
    this.colorFor,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;
  final IconData? Function(T value)? iconFor;
  final Color? Function(T value)? colorFor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: Insets.sm),
        itemBuilder: (context, index) {
          final value = values[index];
          final isSelected = value == selected;
          final accent = colorFor?.call(value) ?? context.scheme.primary;
          final icon = iconFor?.call(value);
          return Pressable(
            borderRadius: BorderRadius.circular(Radii.pill),
            haptic: true,
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: Motion.fast,
              padding: const EdgeInsets.symmetric(horizontal: Insets.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: 0.15)
                    : palette.subtle,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 15,
                      color: isSelected ? accent : palette.mutedText,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    labelFor(value),
                    style: context.text.labelMedium?.copyWith(
                      color: isSelected ? accent : palette.mutedText,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Equal-width segmented control with a sliding thumb.
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final index = math.max(0, values.indexOf(selected));
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.subtle,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / values.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: Motion.base,
                curve: Motion.out,
                left: width * index,
                width: width,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    boxShadow: palette.isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final value in values)
                    Expanded(
                      child: Pressable(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        scale: 0.98,
                        onTap: () => onChanged(value),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: Motion.fast,
                            style: (context.text.labelLarge ?? const TextStyle())
                                .copyWith(
                                  color: value == selected
                                      ? context.scheme.onSurface
                                      : palette.mutedText,
                                ),
                            child: Text(labelFor(value)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Opens a bottom sheet that scrolls, avoids the keyboard and caps its width
/// on desktop.
Future<T?> showLifelogSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.page,
              0,
              Insets.page,
              Insets.xl,
            ),
            child: builder(sheetContext),
          ),
        ),
      );
    },
  );
}

class SheetTitle extends StatelessWidget {
  const SheetTitle({super.key, required this.title, this.subtitle, this.leading});

  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: Insets.md)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.headlineSmall),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.text.bodySmall?.copyWith(
                      color: context.palette.mutedText,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/dates.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'surfaces.dart';

/// Icon button for screen headers. Bare by default (like a native navigation
/// bar); [filled] marks the one primary action with a soft accent tint.
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
    final primary = context.scheme.primary;
    final fg = color ?? (filled ? primary : context.scheme.onSurface);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Pressable(
          onTap: onPressed,
          scale: 0.9,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.out,
            // 44pt is the minimum comfortable touch target.
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled
                  ? primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: fg),
          ),
        ),
      ),
    );
  }
}

/// The shared page scaffold: a large title that collapses into a frosted bar
/// on scroll, lazy scrolling, optional pull-to-refresh, a centred max width on
/// desktop and bottom padding that clears the floating navigation bar.
///
/// Pass [header] to replace the title block entirely (Today does this).
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

  /// Replaces the standard large title.
  final Widget? header;
  final Future<void> Function()? onRefresh;
  final double maxWidth;

  /// Painted behind the scrolling content.
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final pushed = ModalRoute.of(context)?.canPop ?? false;

    Widget body = LayoutBuilder(
      builder: (context, constraints) {
        final base = context.compact ? Insets.page : Insets.xl;
        final side = math.max(base, (constraints.maxWidth - maxWidth) / 2);
        // The root tab bar is translucent and drawn under the scroll view.
        final tabBarSpace = pushed ? 0.0 : 49.0;
        final bottom =
            Insets.xl + tabBarSpace + MediaQuery.paddingOf(context).bottom;
        final scroll = CustomScrollView(
          physics: onRefresh != null
              ? const AlwaysScrollableScrollPhysics()
              : null,
          slivers: [
            if (header == null)
              SliverPersistentHeader(
                pinned: true,
                delegate: _LargeTitleDelegate(
                  title: title,
                  subtitle: subtitle,
                  actions: actions,
                  showBack: pushed,
                  side: side,
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, Insets.sm, side, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([?header, ...children]),
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

/// Large system title that scales away into a compact, frosted bar. Only the
/// collapsed state blurs, so the expanded page stays flat and quiet.
class _LargeTitleDelegate extends SliverPersistentHeaderDelegate {
  _LargeTitleDelegate({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.showBack,
    required this.side,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  final double side;

  static const double _bar = 52;

  @override
  double get minExtent => _bar;

  @override
  double get maxExtent => _bar + (subtitle == null ? 52 : 72);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final t = (shrinkOffset / range).clamp(0.0, 1.0);
    final collapsed = t > 0.92;
    final text = context.text;
    final palette = context.palette;
    final reduce = context.reduceMotion;

    final bar = SizedBox(
      height: _bar,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: math.max(0.0, side - 12)),
        child: Row(
          children: [
            if (showBack)
              HeaderButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: AnimatedOpacity(
                duration: reduce ? Duration.zero : Motion.fast,
                opacity: collapsed ? 1 : 0,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ...actions,
            const SizedBox(width: 4),
          ],
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Frosted bar fades in only once the large title has gone.
        AnimatedOpacity(
          duration: reduce ? Duration.zero : Motion.fast,
          opacity: collapsed ? 1 : 0,
          child: const GlassSurface(
            borderSides: [AxisDirection.down],
            child: SizedBox.expand(),
          ),
        ),
        Positioned(
          left: side,
          right: side,
          bottom: 10,
          child: Opacity(
            opacity: (1 - t * 1.6).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -t * 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineMedium,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: palette.mutedText),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: bar),
      ],
    );
  }

  // Actions are closures built by the parent, so there is nothing cheap to
  // compare. The delegate is trivial to rebuild.
  @override
  bool shouldRebuild(covariant _LargeTitleDelegate old) => true;
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
        color: palette.card.withValues(alpha: palette.isDark ? 0.55 : 0.72),
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
          if (title != null) Eyebrow(title!),
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
              padding: const EdgeInsets.fromLTRB(
                Insets.xs,
                Insets.sm,
                Insets.xs,
                0,
              ),
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
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: palette.dimText,
                ),
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
    final b = HSLColor.fromAHSL(
      1,
      (hue + 48) % 360,
      0.55,
      dark ? 0.20 : 0.48,
    ).toColor();
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
          color: context.palette.onPhoto.withValues(alpha: 0.95),
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
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: values.length,
      separatorBuilder: (_, _) => const SizedBox(width: Insets.sm),
      itemBuilder: (context, index) {
        final value = values[index];
        final isSelected = value == selected;
        final accent = colorFor?.call(value) ?? context.scheme.primary;
        final icon = iconFor?.call(value);
        return Semantics(
          button: true,
          selected: isSelected,
          label: labelFor(value),
          child: Pressable(
            borderRadius: BorderRadius.circular(Radii.pill),
            haptic: true,
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: Motion.fast,
              constraints: const BoxConstraints(minHeight: 44),
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
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
      constraints: const BoxConstraints(minHeight: 44),
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
                      child: Semantics(
                        button: true,
                        selected: value == selected,
                        label: labelFor(value),
                        child: Pressable(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          scale: 0.98,
                          onTap: () => onChanged(value),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: Motion.fast,
                                style:
                                    (context.text.labelLarge ??
                                            const TextStyle())
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

/// Builds controls that stay visible below a sheet's scrollable body.
typedef LifelogSheetFooterBuilder = Widget Function(BuildContext context);

/// Opens a bottom sheet that scrolls, avoids the keyboard and caps its width
/// on desktop. Sheets use the root navigator by default so an app navigation
/// bar or a nested tab navigator can never paint over the controls.
Future<T?> showLifelogSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  LifelogSheetFooterBuilder? footerBuilder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) {
      final keyboardHeight = MediaQuery.viewInsetsOf(sheetContext).bottom;
      final keyboardOpen = keyboardHeight > 0;
      final availableHeight =
          MediaQuery.sizeOf(sheetContext).height - keyboardHeight - 8;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: availableHeight > 0 ? availableHeight : 0,
        ),
        child: GestureDetector(
          // Tapping anywhere that is not a field lowers the keyboard without
          // dismissing the sheet, like a native iOS keyboard.
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(sheetContext).unfocus(),
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        Insets.page,
                        0,
                        Insets.page,
                        footerBuilder == null ? Insets.xl : Insets.md,
                      ),
                      child: builder(sheetContext),
                    ),
                  ),
                ),
                if (footerBuilder != null)
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: context.scheme.surface,
                      border: Border(
                        top: BorderSide(color: context.scheme.outlineVariant),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      Insets.page,
                      Insets.sm,
                      Insets.page,
                      Insets.sm,
                    ),
                    child: SafeArea(
                      top: false,
                      child: footerBuilder(sheetContext),
                    ),
                  ),
                // Multiline fields show a newline key instead of "Done" on iOS,
                // so give every sheet an explicit accessory bar with Done.
                if (keyboardOpen)
                  KeyboardDoneBar(
                    onDone: () => FocusScope.of(sheetContext).unfocus(),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Sticky accessory bar that guarantees a visible way to lower the keyboard.
/// It only unfocuses — sheets and pages keep their own explicit Cancel/Save.
class KeyboardDoneBar extends StatelessWidget {
  const KeyboardDoneBar({super.key, this.onDone, this.trailing});

  final VoidCallback? onDone;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Opaque surface so the bar stays legible when a keyboard or sheet has no
    // backdrop filter. It deliberately never pops a route: Done only unfocuses.
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isDark ? 0.28 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            const Spacer(),
            ...(trailing ?? const <Widget>[]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              child: Semantics(
                button: true,
                label: 'Dismiss keyboard',
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 44),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed:
                      onDone ??
                      () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: Text(
                    'Done',
                    style: context.text.labelLarge?.copyWith(
                      color: context.scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SheetTitle extends StatelessWidget {
  const SheetTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
  });

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

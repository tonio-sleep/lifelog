import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../features/insights/insights_screen.dart';
import '../../features/journal/journal_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/memories/memories_screen.dart';
import '../../features/music/music_screen.dart';
import '../../features/photos/photos_screen.dart';
import '../../features/places/map_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/timeline/timeline_screen.dart';
import '../../features/today/quick_add.dart';
import '../../features/today/today_screen.dart';
import '../../features/trackers/trackers_screen.dart';

enum AppDestination {
  today('Today', Icons.wb_sunny_outlined, Icons.wb_sunny_rounded),
  journal('Journal', Icons.menu_book_outlined, Icons.menu_book_rounded),
  trackers('Habits', Icons.task_alt_outlined, Icons.task_alt_rounded),
  timeline('Timeline', Icons.timeline_outlined, Icons.timeline_rounded),
  memories('Memories', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
  photos('Media', Icons.photo_library_outlined, Icons.photo_library_rounded),
  places('Places', Icons.place_outlined, Icons.place_rounded),
  music('Music', Icons.graphic_eq_outlined, Icons.graphic_eq_rounded),
  insights('Insights', Icons.insights_outlined, Icons.insights_rounded),
  search('Search', Icons.search_outlined, Icons.search_rounded),
  settings('Settings', Icons.settings_outlined, Icons.settings_rounded);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  AppDestination _destination = AppDestination.today;
  int _tab = 0;

  static const _tabNames = ['today', 'journal', 'trackers', 'library'];

  void _select(AppDestination destination) {
    if (_destination == destination) return;
    setState(() => _destination = destination);
  }

  void _openPage(AppDestination destination) {
    final Widget screen = switch (destination) {
      AppDestination.photos => const PhotosScreen(),
      AppDestination.places => const MapScreen(),
      AppDestination.music => const MusicScreen(),
      AppDestination.memories => const MemoriesScreen(),
      AppDestination.timeline => const TimelineScreen(),
      AppDestination.insights => const InsightsScreen(),
      AppDestination.search => const SearchScreen(),
      AppDestination.settings => const SettingsScreen(),
      _ => const SizedBox.shrink(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _navigateByName(String name) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    for (final destination in AppDestination.values) {
      if (destination.name != name) continue;
      if (desktop) {
        _select(destination);
        return;
      }
      final tab = _tabNames.indexOf(name);
      if (tab >= 0) {
        setState(() => _tab = tab);
      } else {
        _openPage(destination);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;

    if (desktop) {
      return Scaffold(
        body: Row(
          children: [
            _SideNavigation(
              selected: _destination,
              onSelected: _select,
              onAdd: () => showQuickAdd(context, ref),
            ),
            Expanded(
              child: _TabStack(
                index: _destination.index,
                children: [
                  TodayScreen(onNavigate: _navigateByName),
                  const JournalScreen(),
                  const TrackersScreen(),
                  const TimelineScreen(),
                  const MemoriesScreen(),
                  const PhotosScreen(),
                  const MapScreen(),
                  const MusicScreen(),
                  const InsightsScreen(),
                  const SearchScreen(),
                  const SettingsScreen(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _TabStack(
          index: _tab,
          children: [
            TodayScreen(onNavigate: _navigateByName),
            const JournalScreen(),
            const TrackersScreen(),
            LibraryScreen(onOpen: _navigateByName),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        selected: _tab,
        onSelect: (index) {
          if (index != _tab) setState(() => _tab = index);
        },
        onAdd: () => showQuickAdd(context, ref),
      ),
    );
  }
}

/// Keeps every tab alive (so scroll positions survive) and fades the newly
/// selected one in.
class _TabStack extends StatefulWidget {
  const _TabStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<_TabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _TabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index && !context.reduceMotion) {
      _controller.forward(from: 0);
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
      opacity: _controller.drive(CurveTween(curve: Curves.easeOut)),
      child: IndexedStack(index: widget.index, children: widget.children),
    );
  }
}

/// Compact bottom bar: four destinations with the add action inline, so there
/// is no floating button hovering above content.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.selected,
    required this.onSelect,
    required this.onAdd,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            _NavItem(
              label: 'Today',
              icon: Icons.wb_sunny_outlined,
              selectedIcon: Icons.wb_sunny_rounded,
              selected: selected == 0,
              onTap: () => onSelect(0),
            ),
            _NavItem(
              label: 'Journal',
              icon: Icons.menu_book_outlined,
              selectedIcon: Icons.menu_book_rounded,
              selected: selected == 1,
              onTap: () => onSelect(1),
            ),
            Expanded(child: Center(child: _AddButton(onTap: onAdd))),
            _NavItem(
              label: 'Habits',
              icon: Icons.task_alt_outlined,
              selectedIcon: Icons.task_alt_rounded,
              selected: selected == 2,
              onTap: () => onSelect(2),
            ),
            _NavItem(
              label: 'Library',
              icon: Icons.grid_view_outlined,
              selectedIcon: Icons.grid_view_rounded,
              selected: selected == 3,
              onTap: () => onSelect(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final palette = context.palette;
    final color = selected ? scheme.primary : palette.mutedText;
    return Expanded(
      child: Pressable(
        scale: 0.92,
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: Motion.base,
              curve: Motion.out,
              width: selected ? 52 : 32,
              height: 28,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(selected ? selectedIcon : icon, size: 22, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: context.text.labelSmall?.copyWith(
                color: color,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final primary = context.scheme.primary;
    return Tooltip(
      message: 'Add',
      child: Pressable(
        scale: 0.9,
        haptic: true,
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primary, Color.lerp(primary, palette.music, 0.65)!],
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: palette.isDark ? 0.28 : 0.34),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(
            Icons.add_rounded,
            size: 26,
            color: context.scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({
    required this.selected,
    required this.onSelected,
    required this.onAdd,
  });

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;
  final VoidCallback onAdd;

  static const _groups = <List<AppDestination>>[
    [AppDestination.today, AppDestination.journal, AppDestination.trackers],
    [
      AppDestination.timeline,
      AppDestination.memories,
      AppDestination.photos,
      AppDestination.places,
      AppDestination.music,
    ],
    [AppDestination.insights, AppDestination.search],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.xl, Insets.xl, Insets.lg, Insets.lg),
              child: Row(
                children: [
                  const LifelogMark(size: 34),
                  const SizedBox(width: Insets.md),
                  Text('Lifelog', style: AppTheme.serif(context.text.titleLarge, size: 20)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.md),
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add'),
              ),
            ),
            const SizedBox(height: Insets.md),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: Insets.md),
                children: [
                  for (var g = 0; g < _groups.length; g++) ...[
                    if (g > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Insets.sm, horizontal: Insets.md),
                        child: Divider(color: palette.border),
                      ),
                    for (final destination in _groups[g])
                      _NavTile(
                        destination: destination,
                        selected: destination == selected,
                        onTap: () => onSelected(destination),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.md, 0, Insets.md, Insets.sm),
              child: _NavTile(
                destination: AppDestination.settings,
                selected: selected == AppDestination.settings,
                onTap: () => onSelected(AppDestination.settings),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.xl, Insets.sm, Insets.lg, Insets.lg),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 13, color: palette.dimText),
                  const SizedBox(width: 6),
                  Text(
                    'Encrypted, on this device',
                    style: context.text.labelSmall?.copyWith(color: palette.dimText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.scheme;
    final color = selected ? scheme.primary : palette.mutedText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Pressable(
        scale: 0.985,
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 20,
                color: color,
              ),
              const SizedBox(width: Insets.md),
              Text(
                destination.label,
                style: context.text.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

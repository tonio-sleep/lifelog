import 'package:flutter/cupertino.dart';
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

  /// Each mobile tab owns its own stack so pushing a detail page does not
  /// affect the other tabs and tapping the active tab can pop to root.
  final List<GlobalKey<NavigatorState>> _tabNavigators = List.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );

  static const _tabByName = <String, int>{
    'today': 0,
    'journal': 1,
    'trackers': 2,
    'settings': 4,
  };

  void _select(AppDestination destination) {
    if (_destination == destination) return;
    setState(() => _destination = destination);
  }

  void _openPage(AppDestination destination) {
    if (!mounted) return;
    // Tab destinations must never produce a blank pushed page.
    final tab = switch (destination) {
      AppDestination.today => 0,
      AppDestination.journal => 1,
      AppDestination.trackers => 2,
      AppDestination.settings => 4,
      _ => null,
    };
    if (tab != null) {
      setState(() => _tab = tab);
      return;
    }
    final Widget screen = switch (destination) {
      AppDestination.photos => const PhotosScreen(),
      AppDestination.places => const MapScreen(),
      AppDestination.music => const MusicScreen(),
      AppDestination.memories => const MemoriesScreen(),
      AppDestination.timeline => const TimelineScreen(),
      AppDestination.insights => const InsightsScreen(),
      AppDestination.search => const SearchScreen(),
      _ => Scaffold(
            appBar: AppBar(title: const Text('Unavailable')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This screen is not available: ${destination.name}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
    };
    Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => screen),
    );
  }

  void _navigateByName(String name) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    for (final destination in AppDestination.values) {
      if (destination.name != name) continue;
      if (desktop) {
        _select(destination);
        return;
      }
      final tab = _tabByName[name];
      if (tab != null) {
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
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

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

    // The translucent tab bar sits over the scroll view; ScreenFrame reserves
    // its height so the last card is never hidden behind it.
    return Scaffold(
      extendBody: keyboardHeight == 0,
      body: SafeArea(
        bottom: false,
        child: _TabStack(
          index: _tab,
          children: [
            Navigator(
              key: _tabNavigators[0],
              onGenerateRoute: (_) => CupertinoPageRoute<void>(
                builder: (_) => TodayScreen(onNavigate: _navigateByName),
              ),
            ),
            Navigator(
              key: _tabNavigators[1],
              onGenerateRoute: (_) => CupertinoPageRoute<void>(
                builder: (_) => const JournalScreen(),
              ),
            ),
            Navigator(
              key: _tabNavigators[2],
              onGenerateRoute: (_) => CupertinoPageRoute<void>(
                builder: (_) => const TrackersScreen(),
              ),
            ),
            Navigator(
              key: _tabNavigators[3],
              onGenerateRoute: (_) => CupertinoPageRoute<void>(
                builder: (_) => LibraryScreen(onOpen: _navigateByName),
              ),
            ),
            Navigator(
              key: _tabNavigators[4],
              onGenerateRoute: (_) => CupertinoPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: _BottomBar(
          selected: _tab,
          onSelect: (index) {
            if (index == _tab) {
              // iOS convention: tapping the active tab returns to its root.
              _tabNavigators[index].currentState?.popUntil(
                (route) => route.isFirst,
              );
              return;
            }
            setState(() => _tab = index);
          },
        ),
      ),
    );
  }
}

/// Keeps visited tabs alive (so scroll positions survive) and fades the newly
/// selected one in. Tabs are built on first visit, not all at once, and the
/// tickers of hidden tabs are muted so off-screen animations cost nothing.
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
    duration: Motion.base,
    value: 1,
  );
  late final Set<int> _visited = {widget.index};

  @override
  void didUpdateWidget(covariant _TabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.index);
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
      opacity: _controller.drive(CurveTween(curve: Motion.out)),
      child: IndexedStack(
        index: widget.index,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            if (_visited.contains(i))
              TickerMode(enabled: i == widget.index, child: widget.children[i])
            else
              const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// A native iOS tab bar. Five plain destinations, no floating button: quick
/// add lives in the Today header and in Library where it belongs.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  static const _items = <(String, IconData, IconData)>[
    ('Today', Icons.wb_sunny_outlined, Icons.wb_sunny_rounded),
    ('Journal', Icons.menu_book_outlined, Icons.menu_book_rounded),
    ('Habits', Icons.checklist_outlined, Icons.checklist_rounded),
    ('Library', Icons.grid_view_outlined, Icons.grid_view_rounded),
    ('Settings', Icons.settings_outlined, Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.scheme;
    return CupertinoTabBar(
      currentIndex: selected,
      onTap: onSelect,
      activeColor: scheme.primary,
      inactiveColor: palette.dimText,
      backgroundColor: palette.glass,
      border: Border(top: BorderSide(color: palette.border, width: 0.5)),
      items: [
        for (var i = 0; i < _items.length; i++)
          BottomNavigationBarItem(
            icon: Icon(_items[i].$2, size: 24),
            activeIcon: Icon(_items[i].$3, size: 24),
            label: _items[i].$1,
            tooltip: _items[i].$1,
          ),
      ],
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
                  Text('Lifelog', style: AppTheme.serif(context.text.titleLarge, size: 20, weight: FontWeight.w500)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.md),
              child: FilledButton.tonalIcon(
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
            color: selected ? palette.subtle : Colors.transparent,
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

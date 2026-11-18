import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../photos/photo_widgets.dart';

/// Everything that is not a daily-use tab. Each tile opens its screen by name;
/// the shell decides how to present it.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final palette = context.palette;
    String count(int n, String one, [String? many]) =>
        n == 0 ? 'Nothing yet' : '$n ${plural(n, one, many)}';

    final latestMedia = archive.media.isEmpty
        ? null
        : (archive.media.where((m) => m.isImage).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
              .firstOrNull;
    final latestPlay = archive.scrobbles.isEmpty
        ? null
        : archive.scrobbles.reduce(
            (a, b) => a.playedAt.isAfter(b.playedAt) ? a : b,
          );

    return ScreenFrame(
      title: 'Library',
      children: [
        Pressable(
          borderRadius: BorderRadius.circular(Radii.pill),
          onTap: () => onOpen('search'),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
            decoration: BoxDecoration(
              color: palette.subtle,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 20, color: palette.mutedText),
                const SizedBox(width: Insets.md),
                Text(
                  'Search everything',
                  style: context.text.bodyMedium?.copyWith(color: palette.mutedText),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.lg),
        Row(
          children: [
            Expanded(
              child: Reveal(
                index: 0,
                child: _LibraryTile(
                  icon: Icons.photo_library_rounded,
                  color: palette.photo,
                  title: 'Media',
                  subtitle: count(archive.media.length, 'item'),
                  onTap: () => onOpen('photos'),
                  background: latestMedia == null
                      ? null
                      : FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: 200,
                            height: 200,
                            child: EncryptedImage(
                              item: latestMedia,
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Reveal(
                index: 1,
                child: _LibraryTile(
                  icon: Icons.graphic_eq_rounded,
                  color: palette.music,
                  title: 'Music',
                  subtitle: count(archive.scrobbles.length, 'play'),
                  onTap: () => onOpen('music'),
                  background: latestPlay == null || !Artwork.usable(latestPlay.artworkUrl)
                      ? null
                      : FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: Artwork(
                            url: latestPlay.artworkUrl,
                            size: 200,
                            radius: 0,
                            seed: latestPlay.displayArtist,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.md),
        Row(
          children: [
            Expanded(
              child: Reveal(
                index: 2,
                child: _LibraryTile(
                  icon: Icons.place_rounded,
                  color: palette.place,
                  title: 'Places',
                  subtitle: count(archive.places.length, 'place'),
                  onTap: () => onOpen('places'),
                ),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Reveal(
                index: 3,
                child: _LibraryTile(
                  icon: Icons.auto_awesome_rounded,
                  color: palette.journal,
                  title: 'Memories',
                  subtitle: 'On this day',
                  onTap: () => onOpen('memories'),
                ),
              ),
            ),
          ],
        ),
        Reveal(
          index: 4,
          child: ListGroup(
            children: [
              ListRow(
                icon: Icons.timeline_rounded,
                iconColor: palette.manual,
                title: 'Timeline',
                subtitle: count(archive.events.length, 'event'),
                chevron: true,
                onTap: () => onOpen('timeline'),
              ),
              ListRow(
                icon: Icons.insights_rounded,
                iconColor: palette.tracker,
                title: 'Insights',
                subtitle: 'Patterns in what you recorded',
                chevron: true,
                onTap: () => onOpen('insights'),
              ),
            ],
          ),
        ),
        Reveal(
          index: 5,
          child: ListGroup(
            children: [
              ListRow(
                icon: Icons.settings_rounded,
                iconColor: palette.manual,
                title: 'Settings',
                chevron: true,
                onTap: () => onOpen('settings'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.background,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final palette = context.palette;
    final onImage = background != null;
    final fg = onImage ? Colors.white : context.scheme.onSurface;
    return Pressable(
      borderRadius: BorderRadius.circular(Radii.xl),
      scale: 0.97,
      onTap: onTap,
      child: Container(
        height: 132,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: color.withValues(alpha: palette.isDark ? 0.16 : 0.11),
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (background != null) background!,
            if (onImage)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.10),
                      Colors.black.withValues(alpha: 0.68),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  onImage
                      ? Icon(icon, color: Colors.white, size: 22)
                      : IconBadge(icon: icon, color: color, size: 38, iconSize: 19),
                  const Spacer(),
                  Text(title, style: text.titleMedium?.copyWith(color: fg)),
                  Text(
                    subtitle,
                    style: text.labelMedium?.copyWith(
                      color: onImage ? Colors.white70 : palette.mutedText,
                    ),
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

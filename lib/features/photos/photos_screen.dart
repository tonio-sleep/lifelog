import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/day_provider.dart';
import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/media.dart';
import '../today/quick_add.dart';
import 'photo_widgets.dart';

enum _MediaFilter { all, photos, videos, audio, favourites }

String _size(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  _MediaFilter _filter = _MediaFilter.all;

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    final palette = context.palette;

    final all = [...archive.media]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final filtered = all.where((item) {
      return switch (_filter) {
        _MediaFilter.all => true,
        _MediaFilter.photos => item.isImage,
        _MediaFilter.videos => item.isVideo,
        _MediaFilter.audio => item.isAudio,
        _MediaFilter.favourites => item.favorite,
      };
    }).toList();

    final byMonth = <String, List<MediaItem>>{};
    for (final item in filtered) {
      final key =
          '${item.createdAt.year}-${item.createdAt.month.toString().padLeft(2, '0')}';
      byMonth.putIfAbsent(key, () => []).add(item);
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    final totalBytes = all.fold<int>(0, (sum, item) => sum + item.bytes);

    final frameChildren = <Widget>[
      if (all.isNotEmpty)
        FilterRow<_MediaFilter>(
          values: _MediaFilter.values,
          selected: _filter,
          labelFor: (value) => switch (value) {
            _MediaFilter.all => 'All',
            _MediaFilter.photos => 'Photos',
            _MediaFilter.videos => 'Videos',
            _MediaFilter.audio => 'Audio',
            _MediaFilter.favourites => 'Favourites',
          },
          iconFor: (value) =>
              value == _MediaFilter.favourites ? Icons.star_rounded : null,
          onChanged: (value) => setState(() => _filter = value),
        ),
      if (all.isEmpty)
        EmptyState(
          icon: Icons.photo_library_outlined,
          color: palette.photo,
          title: 'No media yet',
          message: 'Photos and videos you add are encrypted before they are stored.',
          actionLabel: 'Add media',
          onAction: () =>
              importMediaForDay(context, ref, dayStart(selectedDay)),
        )
      else if (filtered.isEmpty)
        const EmptyState(
          icon: Icons.filter_list_off_rounded,
          title: 'Nothing here',
          message: 'No items match this filter.',
          compact: true,
        ),
    ];

    return ScreenFrame(
      title: 'Media',
      subtitle: all.isEmpty
          ? null
          : '${all.length} ${plural(all.length, 'item')}, ${_size(totalBytes)}, encrypted',
      actions: [
        HeaderButton(
          icon: Icons.add_photo_alternate_outlined,
          tooltip: 'Add media',
          filled: true,
          onPressed: () => importMediaForDay(context, ref, dayStart(selectedDay)),
        ),
      ],
      slivers: [
        for (final key in months) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.sm),
              child: Row(
                children: [
                  Text(
                    formatMonthYear(
                      DateTime(
                        int.parse(key.substring(0, 4)),
                        int.parse(key.substring(5, 7)),
                      ),
                    ),
                    style: context.text.titleMedium,
                  ),
                  const SizedBox(width: Insets.sm),
                  Text(
                    '${byMonth[key]!.length}',
                    style: context.text.labelMedium?.copyWith(
                      color: palette.dimText,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 132,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: byMonth[key]!.length,
            itemBuilder: (context, index) {
              final item = byMonth[key]![index];
              return MediaTile(
                key: ValueKey(item.id),
                item: item,
                heroScope: 'media',
                onTap: () => showMediaViewer(
                  context,
                  ref,
                  item,
                  items: filtered,
                  heroScope: 'media',
                ),
              );
            },
          ),
        ],
      ],
      children: frameChildren,
    );
  }
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/storage/media_store.dart';
import '../../core/util/dates.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/media.dart';

/// Decrypts and shows a stored image. Placeholders match the app surface so
/// loading never flashes white.
class EncryptedImage extends ConsumerStatefulWidget {
  const EncryptedImage({
    super.key,
    required this.item,
    this.thumbnail = true,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final MediaItem item;
  final bool thumbnail;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  ConsumerState<EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends ConsumerState<EncryptedImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EncryptedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.thumbnail != widget.thumbnail) {
      _load();
    }
  }

  void _load() {
    final store = ref.read(appServicesProvider).mediaStore;
    _future = widget.thumbnail
        ? store.readThumbnail(widget.item)
        : store.readOriginal(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final image = FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            color: palette.subtle,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(Insets.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: palette.dimText),
                const SizedBox(height: Insets.xs),
                Text(
                  snapshot.error is MediaUnavailableException
                      ? 'Not on this device'
                      : 'Could not decrypt',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: context.text.labelSmall?.copyWith(color: palette.dimText),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return ColoredBox(color: palette.subtle);
        }
        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) {
            if (sync) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: Motion.base,
              child: child,
            );
          },
          errorBuilder: (context, error, stack) => Container(
            color: palette.subtle,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image_outlined, color: palette.dimText),
          ),
        );
      },
    );

    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.circular(Radii.md),
      child: image,
    );
  }
}

String mediaHeroTag(String scope, MediaItem item) => 'media:$scope:${item.id}';

/// Media that belongs to a moment in the day: a horizontal strip of images at
/// their natural proportions, each with its own caption underneath. This is
/// deliberately not a grid.
class StoryStrip extends ConsumerWidget {
  const StoryStrip({
    super.key,
    required this.items,
    this.height = 148,
    this.scope = 'strip',
    this.showCaptions = true,
    this.padding = EdgeInsets.zero,
  });

  final List<MediaItem> items;
  final double height;

  /// Keeps hero tags unique when the same media appears on several screens.
  final String scope;
  final bool showCaptions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SizedBox.shrink();
    final hasCaptions =
        showCaptions && items.any((m) => m.caption.trim().isNotEmpty);
    final captionHeight = hasCaptions ? 42.0 : 0.0;
    return SizedBox(
      height: height + captionHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
        itemBuilder: (context, index) => _StoryTile(
          item: items[index],
          all: items,
          height: height,
          scope: scope,
          showCaption: hasCaptions,
        ),
      ),
    );
  }
}

class _StoryTile extends ConsumerWidget {
  const _StoryTile({
    required this.item,
    required this.all,
    required this.height,
    required this.scope,
    required this.showCaption,
  });

  final MediaItem item;
  final List<MediaItem> all;
  final double height;
  final String scope;
  final bool showCaption;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    var aspect = 1.25;
    if (item.isImage && item.width != null && item.height != null) {
      final h = item.height!;
      if (h > 0) aspect = (item.width! / h).clamp(0.8, 1.6);
    }
    final width = height * aspect;
    final radius = BorderRadius.circular(Radii.md + 2);
    final caption = item.caption.trim();
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: width,
            height: height,
            child: Pressable(
              borderRadius: radius,
              scale: 0.98,
              onTap: () => showMediaViewer(
                context,
                ref,
                item,
                items: all,
                heroScope: scope,
              ),
              child: Hero(
                tag: mediaHeroTag(scope, item),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.isImage)
                        EncryptedImage(item: item, borderRadius: radius)
                      else
                        Container(
                          color: palette.subtle,
                          child: Icon(
                            item.isVideo
                                ? Icons.movie_outlined
                                : Icons.audiotrack_outlined,
                            size: 30,
                            color: palette.dimText,
                          ),
                        ),
                      if (item.isVideo || item.isAudio)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              item.isVideo
                                  ? Icons.play_arrow_rounded
                                  : Icons.graphic_eq_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showCaption)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: caption.isEmpty
                  ? const SizedBox.shrink()
                  : Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.serif(
                        context.text.bodySmall,
                        size: 12.5,
                      ).copyWith(
                        fontStyle: FontStyle.italic,
                        height: 1.3,
                        color: palette.mutedText,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// A tight gallery grid. Used by the Media library, where browsing a whole
/// collection is the point; journal entries use [StoryStrip] instead.
class PhotoGrid extends ConsumerWidget {
  const PhotoGrid({
    super.key,
    required this.items,
    this.onOpen,
    this.crossAxisCount = 3,
    this.spacing = Insets.xs,
    this.shrinkWrap = true,
    this.heroScope = 'grid',
  });

  final List<MediaItem> items;
  final void Function(MediaItem item)? onOpen;
  final int crossAxisCount;
  final double spacing;
  final bool shrinkWrap;
  final String heroScope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => MediaTile(
        item: items[index],
        heroScope: heroScope,
        onTap: () {
          if (onOpen != null) {
            onOpen!(items[index]);
          } else {
            showMediaViewer(
              context,
              ref,
              items[index],
              items: items,
              heroScope: heroScope,
            );
          }
        },
      ),
    );
  }
}

/// One square thumbnail in a gallery grid.
class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.heroScope,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final String heroScope;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(Radii.sm);
    return Pressable(
      borderRadius: radius,
      scale: 0.97,
      onTap: onTap,
      child: Hero(
        tag: mediaHeroTag(heroScope, item),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.isImage)
                EncryptedImage(item: item, borderRadius: radius)
              else
                Container(
                  color: palette.subtle,
                  child: Icon(
                    item.isVideo ? Icons.movie_outlined : Icons.audiotrack_outlined,
                    color: palette.dimText,
                  ),
                ),
              if (item.isVideo || item.isAudio)
                const Positioned(
                  right: 6,
                  bottom: 6,
                  child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 20),
                ),
              if (item.favorite)
                const Positioned(
                  left: 6,
                  top: 6,
                  child: Icon(Icons.star_rounded, color: Color(0xFFF2C46D), size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the full-screen viewer. Pass [items] to swipe between siblings and
/// [heroScope] (matching the thumbnails' scope) for the shared-element
/// transition.
Future<void> showMediaViewer(
  BuildContext context,
  WidgetRef ref,
  MediaItem item, {
  List<MediaItem>? items,
  String heroScope = 'media',
}) {
  final list = (items == null || items.isEmpty) ? <MediaItem>[item] : items;
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.95),
      transitionDuration: Motion.slow,
      reverseTransitionDuration: Motion.base,
      pageBuilder: (_, _, _) => MediaViewerPage(
        items: list,
        initialId: item.id,
        heroScope: heroScope,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class MediaViewerPage extends ConsumerStatefulWidget {
  const MediaViewerPage({
    super.key,
    required this.items,
    required this.initialId,
    required this.heroScope,
  });

  final List<MediaItem> items;
  final String initialId;
  final String heroScope;

  @override
  ConsumerState<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends ConsumerState<MediaViewerPage> {
  late List<MediaItem> _items;
  late int _index;
  late final PageController _controller;
  bool _chrome = true;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _items = [...widget.items];
    final start = _items.indexWhere((m) => m.id == widget.initialId);
    _index = math.max(0, start);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  MediaItem _live(MediaItem base) =>
      ref.read(archiveProvider).mediaById(base.id) ?? base;

  @override
  Widget build(BuildContext context) {
    // Watching keeps favourite and caption edits live.
    ref.watch(archiveProvider);
    if (_items.isEmpty) return const SizedBox.shrink();
    final item = _live(_items[_index]);
    final text = context.text;
    final caption = item.caption.trim();

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: _items.length,
            onPageChanged: (i) => setState(() {
              _index = i;
              _zoomed = false;
            }),
            itemBuilder: (context, i) {
              final entry = _live(_items[i]);
              return _ViewerPage(
                key: ValueKey(entry.id),
                item: entry,
                heroTag: mediaHeroTag(widget.heroScope, entry),
                onTap: () => setState(() => _chrome = !_chrome),
                onZoomChanged: (zoomed) {
                  if (i == _index && zoomed != _zoomed) {
                    setState(() => _zoomed = zoomed);
                  }
                },
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _chrome ? 1 : 0,
              duration: Motion.fast,
              child: IgnorePointer(
                ignoring: !_chrome,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                          ),
                          if (_items.length > 1)
                            Text(
                              '${_index + 1} of ${_items.length}',
                              style: text.labelMedium?.copyWith(
                                color: Colors.white70,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          const Spacer(),
                          IconButton(
                            tooltip: item.favorite ? 'Remove favourite' : 'Favourite',
                            onPressed: () => guard(
                              context,
                              ref.read(archiveProvider.notifier).updateMedia(
                                item.copyWith(favorite: !item.favorite),
                              ),
                              errorPrefix: 'Could not update photo',
                            ),
                            icon: Icon(
                              item.favorite
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: item.favorite
                                  ? const Color(0xFFF2C46D)
                                  : Colors.white,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit caption',
                            onPressed: () => _editCaption(item),
                            icon: const Icon(Icons.edit_outlined, color: Colors.white),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _delete(item),
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _chrome ? 1 : 0,
              duration: Motion.fast,
              child: IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xDD000000), Color(0x00000000)],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.page,
                        Insets.xxl,
                        Insets.page,
                        Insets.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (caption.isNotEmpty)
                            Text(
                              caption,
                              style: AppTheme.serif(text.bodyLarge, size: 16)
                                  .copyWith(color: Colors.white, height: 1.4),
                            ),
                          if (item.tags.isNotEmpty) ...[
                            const SizedBox(height: Insets.xs),
                            Text(
                              item.tags.map((t) => '#$t').join('  '),
                              style: text.labelMedium?.copyWith(color: Colors.white60),
                            ),
                          ],
                          const SizedBox(height: Insets.xs),
                          Text(
                            '${formatDayLong(item.createdAt)}, '
                            '${formatTime(item.createdAt)}  ·  ${_formatBytes(item.bytes)}',
                            style: text.labelSmall?.copyWith(color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editCaption(MediaItem item) async {
    final controller = TextEditingController(text: item.caption);
    final caption = await showLifelogSheet<String>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(title: 'Caption'),
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            onEditingComplete: () =>
                FocusManager.instance.primaryFocus?.unfocus(),
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'What was happening?'),
          ),
          const SizedBox(height: Insets.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(controller.text),
              child: const Text('Save caption'),
            ),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 500), controller.dispose);
    if (caption == null || !mounted) return;
    await guard(
      context,
      ref.read(archiveProvider.notifier).updateMedia(
        item.copyWith(caption: caption.trim()),
      ),
      errorPrefix: 'Could not update photo',
    );
  }

  Future<void> _delete(MediaItem item) async {
    final linked = item.journalEntryId == null
        ? null
        : ref.read(archiveProvider).entryById(item.journalEntryId!);
    final ok = await confirm(
      context,
      title: 'Delete this ${item.kindLabel.toLowerCase()}?',
      message: linked == null
          ? 'The encrypted file will be permanently removed from this device.'
          : 'The encrypted file will be removed. The journal entry '
                '“${linked.displayTitle}” will remain.',
    );
    if (!ok || !mounted) return;
    await guard(
      context,
      ref.read(archiveProvider.notifier).deleteMedia(item.id),
      errorPrefix: 'Could not delete media',
    );
    if (!mounted) return;
    if (ref.read(archiveProvider).mediaById(item.id) != null) {
      return;
    }
    if (!mounted) return;
    if (_items.length <= 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _items.removeWhere((m) => m.id == item.id);
      _index = math.min(_index, _items.length - 1);
      _zoomed = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage({
    super.key,
    required this.item,
    required this.heroTag,
    required this.onTap,
    required this.onZoomChanged,
  });

  final MediaItem item;
  final String heroTag;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.02);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_transform.value.getMaxScaleOnAxis() > 1.02) {
      _transform.value = Matrix4.identity();
    } else {
      const scale = 2.5;
      _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
        ..setTranslationRaw(
          -_doubleTapAt.dx * (scale - 1),
          -_doubleTapAt.dy * (scale - 1),
          0,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
      onDoubleTap: item.isImage ? _toggleZoom : null,
      child: Center(
        child: Hero(
          tag: widget.heroTag,
          child: item.isImage
              ? InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: 5,
                  child: EncryptedImage(
                    item: item,
                    thumbnail: false,
                    fit: BoxFit.contain,
                    borderRadius: BorderRadius.zero,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(Insets.xxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.isVideo
                            ? Icons.movie_outlined
                            : item.isAudio
                            ? Icons.audiotrack_outlined
                            : Icons.insert_drive_file_outlined,
                        size: 56,
                        color: Colors.white38,
                      ),
                      const SizedBox(height: Insets.lg),
                      Text(
                        item.isVideo || item.isAudio
                            ? 'This ${item.kindLabel.toLowerCase()} is stored '
                                  'encrypted on this device. Playback is not '
                                  'available in this build.'
                            : 'No preview for this file type.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60, height: 1.5),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Adds a caption and tags before importing a picked file.
Future<({String caption, List<String> tags})?> askMediaDetails(
  BuildContext context, {
  required String fileName,
}) async {
  final captionController = TextEditingController();
  final tagsController = TextEditingController();
  final result = await showLifelogSheet<({String caption, List<String> tags})>(
    context,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          title: 'Add to your archive',
          subtitle: fileName,
        ),
        TextField(
          controller: captionController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Caption',
            hintText: 'Optional',
          ),
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: tagsController,
          decoration: const InputDecoration(
            labelText: 'Tags',
            hintText: 'family, garden',
          ),
        ),
        const SizedBox(height: Insets.md),
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: sheetContext.palette.dimText),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: Text(
                'Encrypted on this device before it is stored.',
                style: sheetContext.text.bodySmall?.copyWith(
                  color: sheetContext.palette.mutedText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Skip'),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop((
                  caption: captionController.text.trim(),
                  tags: normaliseTags(tagsController.text.split(',')),
                )),
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 500), () {
    captionController.dispose();
    tagsController.dispose();
  });
  return result;
}

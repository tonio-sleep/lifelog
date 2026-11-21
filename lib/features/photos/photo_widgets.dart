import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/storage/media_playback.dart';
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
  Future<Uint8List>? _future;
  String? _loadKey;

  /// Rebuilds the future whenever the item or the bytes on disk may have
  /// changed. A restore can replace the ciphertext behind an unchanged id, so
  /// watching the media revision is required for a truthful preview.
  void _ensureLoaded(String key) {
    if (_future != null && _loadKey == key) return;
    _loadKey = key;
    final store = ref.read(appServicesProvider).mediaStore;
    _future = widget.thumbnail
        ? store.readThumbnail(widget.item)
        : store.readOriginal(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final revision = ref.watch(mediaRevisionProvider);
    _ensureLoaded(
      '${widget.item.id}|${widget.thumbnail}|${widget.item.hasThumbnail}|$revision',
    );
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
                active: i == _index,
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
    required this.active,
    required this.heroTag,
    required this.onTap,
    required this.onZoomChanged,
  });

  final MediaItem item;
  final bool active;
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
              : item.isAudio
                  ? _AudioPlayerView(item: item, active: widget.active)
                  : item.isVideo
                  ? _VideoPlayerView(item: item, active: widget.active)
                  : Padding(
                      padding: const EdgeInsets.all(Insets.xxl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 56,
                            color: Colors.white38,
                          ),
                          const SizedBox(height: Insets.lg),
                          Text(
                            'No preview for this file type.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}

class _AudioPlayerView extends ConsumerStatefulWidget {
  const _AudioPlayerView({required this.item, required this.active});

  final MediaItem item;
  final bool active;

  @override
  ConsumerState<_AudioPlayerView> createState() => _AudioPlayerViewState();
}

class _AudioPlayerViewState extends ConsumerState<_AudioPlayerView> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _ready = false;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _playing = false;
        });
      }
    });
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final bytes = await ref.read(appServicesProvider).mediaStore.readOriginal(
            widget.item,
          );
      await _player.setSource(
        BytesSource(bytes, mimeType: widget.item.mimeType),
      );
      final duration = await _player.getDuration();
      if (!mounted) return;
      setState(() {
        _duration = duration ?? Duration.zero;
        _ready = true;
      });
      if (!widget.active) await _player.pause();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void didUpdateWidget(covariant _AudioPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active && _ready) {
      if (widget.active) {
        unawaited(_player.resume());
      } else {
        unawaited(_player.pause());
      }
    }
  }

  @override
  void dispose() {
    unawaited(_player.stop());
    unawaited(_player.release());
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_completeSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _PlaybackError(message: _error!);
    }
    if (!_ready) {
      return const CircularProgressIndicator(color: Colors.white70);
    }
    final maxMs = _duration.inMilliseconds;
    return Container(
      width: math.min(520.0, MediaQuery.sizeOf(context).width - 48),
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.audiotrack_outlined,
            size: 44,
            color: Colors.white.withValues(alpha: 0.8),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            widget.item.caption.trim().isEmpty
                ? (widget.item.originalName ?? 'Audio')
                : widget.item.caption.trim(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              IconButton(
                color: Colors.white,
                tooltip: _playing ? 'Pause' : 'Play',
                icon: Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  size: 34,
                ),
                onPressed: () async {
                  if (_playing) {
                    await _player.pause();
                  } else {
                    if (_duration > Duration.zero &&
                        _position >= _duration) {
                      await _player.seek(Duration.zero);
                    }
                    await _player.resume();
                  }
                },
              ),
              Expanded(
                child: Slider(
                  value: maxMs > 0
                      ? _position.inMilliseconds.clamp(0, maxMs).toDouble()
                      : 0,
                  max: maxMs > 0 ? maxMs.toDouble() : 1,
                  onChanged: maxMs > 0
                      ? (value) {
                          final next = Duration(milliseconds: value.round());
                          unawaited(_player.seek(next));
                          setState(() => _position = next);
                        }
                      : null,
                ),
              ),
              Text(
                '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerView extends ConsumerStatefulWidget {
  const _VideoPlayerView({required this.item, required this.active});

  final MediaItem item;
  final bool active;

  @override
  ConsumerState<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends ConsumerState<_VideoPlayerView> {
  VideoPlayerController? _controller;
  PlaybackFile? _playback;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final directory = await getTemporaryDirectory();
      final playback = await materializePlaybackFile(
        ref.read(appServicesProvider).mediaStore,
        widget.item,
        directory,
      );
      final controller = VideoPlayerController.file(playback.file);
      await controller.initialize();
      await controller.setLooping(true);
      controller.addListener(_onControllerChanged);
      if (!mounted) {
        await controller.dispose();
        await playback.delete();
        return;
      }
      setState(() {
        _controller = controller;
        _playback = playback;
        _ready = true;
      });
      if (widget.active) await controller.play();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _VideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null || widget.active == oldWidget.active) return;
    if (widget.active) {
      unawaited(controller.play());
    } else {
      unawaited(controller.pause());
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_onControllerChanged);
    unawaited(controller?.pause());
    unawaited(controller?.dispose());
    unawaited(_playback?.delete());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _PlaybackError(message: _error!);
    final controller = _controller;
    if (!_ready || controller == null) {
      return const CircularProgressIndicator(color: Colors.white70);
    }
    final value = controller.value;
    final aspect = value.aspectRatio.isFinite && value.aspectRatio > 0
        ? value.aspectRatio.clamp(0.4, 3.0)
        : 16.0 / 9.0;
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(controller),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () async {
                if (value.isPlaying) {
                  await controller.pause();
                } else {
                  await controller.play();
                }
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.md,
                  vertical: Insets.xs,
                ),
                color: Colors.black.withValues(alpha: 0.45),
                child: Row(
                  children: [
                    IconButton(
                      color: Colors.white,
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      onPressed: () async {
                        if (value.isPlaying) {
                          await controller.pause();
                        } else {
                          await controller.play();
                        }
                      },
                    ),
                    Expanded(
                      child: Slider(
                        value: value.duration.inMilliseconds > 0
                            ? value.position.inMilliseconds
                                .clamp(0, value.duration.inMilliseconds)
                                .toDouble()
                            : 0,
                        max: value.duration.inMilliseconds > 0
                            ? value.duration.inMilliseconds.toDouble()
                            : 1,
                        onChanged: value.duration.inMilliseconds > 0
                            ? (ms) => unawaited(
                                controller.seekTo(
                                  Duration(milliseconds: ms.round()),
                                ),
                              )
                            : null,
                      ),
                    ),
                    Text(
                      _formatDuration(value.position),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 40),
          const SizedBox(height: Insets.sm),
          Text(
            'Could not play this file. $message',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

enum MediaDetailsAction { add, addAll, skip, skipAll, cancel }

class MediaDetailsResult {
  const MediaDetailsResult({
    required this.action,
    this.caption = '',
    this.tags = const [],
  });

  final MediaDetailsAction action;
  final String caption;
  final List<String> tags;
}

/// Adds a caption and tags before importing a picked file. In a multi-file
/// pick, Add all applies these details to every remaining file without asking
/// again; Skip all / Cancel stop the batch cleanly.
Future<MediaDetailsResult?> askMediaDetails(
  BuildContext context, {
  required String fileName,
  int? index,
  int? total,
}) {
  // Media import uses the root navigator for both its progress dialog and its
  // details sheet. Keeping them on the same navigator guarantees the sheet is
  // visible and its Add/Skip result is delivered.
  return showLifelogSheet<MediaDetailsResult>(
    context,
    isDismissible: false,
    enableDrag: false,
    useRootNavigator: true,
    builder: (_) => _MediaDetailsSheet(
      fileName: fileName,
      index: index,
      total: total,
    ),
  );
}

class _MediaDetailsSheet extends StatefulWidget {
  const _MediaDetailsSheet({
    required this.fileName,
    this.index,
    this.total,
  });

  final String fileName;
  final int? index;
  final int? total;

  @override
  State<_MediaDetailsSheet> createState() => _MediaDetailsSheetState();
}

class _MediaDetailsSheetState extends State<_MediaDetailsSheet> {
  final _caption = TextEditingController();
  final _tags = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.index != null && widget.total != null
        ? '${widget.fileName}  •  ${widget.index} of ${widget.total}'
        : widget.fileName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          title: 'Add to your archive',
          subtitle: subtitle,
        ),
        TextField(
          controller: _caption,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Caption',
            hintText: 'Optional',
          ),
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _tags,
          decoration: const InputDecoration(
            labelText: 'Tags',
            hintText: 'family, garden',
          ),
        ),
        const SizedBox(height: Insets.md),
        Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: context.palette.dimText,
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: Text(
                'Encrypted on this device before it is stored.',
                style: context.text.bodySmall?.copyWith(
                  color: context.palette.mutedText,
                ),
              ),
            ),
          ],
        ),
        if ((widget.total ?? 1) > 1) ...[
          const SizedBox(height: Insets.sm),
          Text(
            'Add all uses these details for every file.',
            style: context.text.bodySmall?.copyWith(
              color: context.palette.dimText,
            ),
          ),
        ],
        const SizedBox(height: Insets.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(
                  const MediaDetailsResult(action: MediaDetailsAction.skip),
                ),
                child: const Text('Skip'),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(
                  const MediaDetailsResult(action: MediaDetailsAction.skipAll),
                ),
                child: const Text('Skip all'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(
                  MediaDetailsResult(
                    action: MediaDetailsAction.addAll,
                    caption: _caption.text.trim(),
                    tags: normaliseTags(_tags.text.split(',')),
                  ),
                ),
                child: const Text('Add all'),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  MediaDetailsResult(
                    action: MediaDetailsAction.add,
                    caption: _caption.text.trim(),
                    tags: normaliseTags(_tags.text.split(',')),
                  ),
                ),
                child: const Text('Add'),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(
              const MediaDetailsResult(action: MediaDetailsAction.cancel),
            ),
            child: const Text('Cancel import'),
          ),
        ),
      ],
    );
  }
}

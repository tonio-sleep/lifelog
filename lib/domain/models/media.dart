import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Metadata for a photo, video or audio file. The bytes live encrypted on
/// disk in the media vault; only public-safe metadata is stored here.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.createdAt,
    required this.mimeType,
    required this.bytes,
    this.caption = '',
    this.tags = const [],
    this.journalEntryId,
    this.favorite = false,
    this.hasThumbnail = false,
    this.width,
    this.height,
    this.originalName,
  });

  final String id;
  final DateTime createdAt;
  final String mimeType;
  final int bytes;
  final String caption;
  final List<String> tags;
  final String? journalEntryId;
  final bool favorite;

  /// Whether an encrypted thumbnail exists in the media vault.
  final bool hasThumbnail;
  final int? width;
  final int? height;
  final String? originalName;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');

  String get kindLabel {
    if (isImage) return 'Photo';
    if (isVideo) return 'Video';
    if (isAudio) return 'Audio';
    return 'File';
  }

  String get displayCaption =>
      caption.trim().isEmpty ? kindLabel : caption.trim();

  MediaItem copyWith({
    String? caption,
    List<String>? tags,
    String? journalEntryId,
    bool clearJournalEntry = false,
    bool? favorite,
    bool? hasThumbnail,
    int? width,
    int? height,
  }) {
    return MediaItem(
      id: id,
      createdAt: createdAt,
      mimeType: mimeType,
      bytes: bytes,
      caption: caption ?? this.caption,
      tags: tags ?? this.tags,
      journalEntryId:
          clearJournalEntry ? null : (journalEntryId ?? this.journalEntryId),
      favorite: favorite ?? this.favorite,
      hasThumbnail: hasThumbnail ?? this.hasThumbnail,
      width: width ?? this.width,
      height: height ?? this.height,
      originalName: originalName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'mimeType': mimeType,
    'bytes': bytes,
    'caption': caption,
    'tags': tags,
    'journalEntryId': journalEntryId,
    'favorite': favorite,
    'hasThumbnail': hasThumbnail,
    'width': width,
    'height': height,
    'originalName': originalName,
  };

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return MediaItem(
      id: json['id'] as String? ?? _uuid.v4(),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      caption: json['caption'] as String? ?? '',
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
      journalEntryId: json['journalEntryId'] as String?,
      favorite: json['favorite'] as bool? ?? false,
      hasThumbnail: json['hasThumbnail'] as bool? ?? false,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      originalName: json['originalName'] as String?,
    );
  }
}

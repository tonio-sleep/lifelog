import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Optional mood attached to a journal entry. Keeping this free-form is
/// intentional: an entry is never required to have a mood.
enum Mood {
  awful,
  low,
  okay,
  good,
  great;

  String get label => switch (this) {
    Mood.awful => 'Awful',
    Mood.low => 'Low',
    Mood.okay => 'Okay',
    Mood.good => 'Good',
    Mood.great => 'Great',
  };

  String get symbol => '';

  static Mood? tryParse(String? value) {
    if (value == null) return null;
    for (final mood in Mood.values) {
      if (mood.name == value) return mood;
    }
    return null;
  }
}

/// One free-form journal entry. Several entries per day are allowed.
/// Includes optional daily wellbeing check-in fields.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.title,
    required this.body,
    this.mood,
    this.energy,
    this.sleepHours,
    this.steps,
    this.meals = '',
    this.highlight = '',
    this.tags = const [],
    this.placeId,
    this.placeLabel,
    this.draft = false,
    this.archived = false,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String title;
  final String body;
  final Mood? mood;
  /// 1 (low) to 5 (high), optional.
  final int? energy;
  /// Hours of sleep, optional.
  final double? sleepHours;
  /// Step count for the day, optional.
  final int? steps;
  /// What I ate / meals notes.
  final String meals;
  /// Highlight, gratitude, or how the day went.
  final String highlight;
  final List<String> tags;
  final String? placeId;
  final String? placeLabel;

  /// Drafts are autosaved but presented separately until the user finishes.
  final bool draft;
  final bool archived;

  bool get isEmpty =>
      title.trim().isEmpty &&
      body.trim().isEmpty &&
      meals.trim().isEmpty &&
      highlight.trim().isEmpty &&
      tags.isEmpty &&
      mood == null &&
      energy == null &&
      sleepHours == null &&
      steps == null;

  String get displayTitle {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final firstLine = body.trim().split('\n').first.trim();
    if (firstLine.isNotEmpty) {
      return firstLine.length > 72 ? '${firstLine.substring(0, 72)}...' : firstLine;
    }
    return 'Untitled entry';
  }

  String get excerpt {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return 'No text';
    return text.length > 160 ? '${text.substring(0, 160)}...' : text;
  }

  JournalEntry copyWith({
    DateTime? createdAt,
    DateTime? updatedAt,
    String? title,
    String? body,
    Mood? mood,
    bool clearMood = false,
    int? energy,
    bool clearEnergy = false,
    double? sleepHours,
    bool clearSleepHours = false,
    int? steps,
    bool clearSteps = false,
    String? meals,
    String? highlight,
    List<String>? tags,
    String? placeId,
    bool clearPlace = false,
    String? placeLabel,
    bool? draft,
    bool? archived,
  }) {
    return JournalEntry(
      id: id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      title: title ?? this.title,
      body: body ?? this.body,
      mood: clearMood ? null : (mood ?? this.mood),
      energy: clearEnergy ? null : (energy ?? this.energy),
      sleepHours: clearSleepHours ? null : (sleepHours ?? this.sleepHours),
      steps: clearSteps ? null : (steps ?? this.steps),
      meals: meals ?? this.meals,
      highlight: highlight ?? this.highlight,
      tags: tags ?? this.tags,
      placeId: clearPlace ? null : (placeId ?? this.placeId),
      placeLabel: clearPlace ? null : (placeLabel ?? this.placeLabel),
      draft: draft ?? this.draft,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'title': title,
    'body': body,
    'mood': mood?.name,
    'energy': energy,
    'sleepHours': sleepHours,
    'steps': steps,
    'meals': meals,
    'highlight': highlight,
    'tags': tags,
    'placeId': placeId,
    'placeLabel': placeLabel,
    'draft': draft,
    'archived': archived,
  };

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return JournalEntry(
      id: json['id'] as String? ?? _uuid.v4(),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      mood: Mood.tryParse(json['mood'] as String?),
      energy: (json['energy'] as num?)?.toInt(),
      sleepHours: (json['sleepHours'] as num?)?.toDouble(),
      steps: (json['steps'] as num?)?.toInt(),
      meals: json['meals'] as String? ?? '',
      highlight: json['highlight'] as String? ?? '',
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
      placeId: json['placeId'] as String?,
      placeLabel: json['placeLabel'] as String?,
      draft: json['draft'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
    );
  }

  static JournalEntry blank(DateTime date) {
    final now = DateTime.now();
    return JournalEntry(
      id: _uuid.v4(),
      createdAt: DateTime(
        date.year,
        date.month,
        date.day,
        now.hour,
        now.minute,
      ),
      updatedAt: now,
      title: '',
      body: '',
      draft: true,
    );
  }
}

/// Normalise user-entered tags: trimmed, lowercase, unique, max 8.
List<String> normaliseTags(Iterable<String> input) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in input) {
    for (final piece in raw.split(',')) {
      final tag = piece.trim().toLowerCase();
      if (tag.isEmpty || !seen.add(tag)) continue;
      out.add(tag);
      if (out.length == 8) return out;
    }
  }
  return out;
}

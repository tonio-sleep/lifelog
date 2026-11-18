import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum TimelineSource {
  manual,
  journal,
  tracker,
  location,
  music,
  photo;

  String get label => switch (this) {
    TimelineSource.manual => 'Manual',
    TimelineSource.journal => 'Journal',
    TimelineSource.tracker => 'Tracker',
    TimelineSource.location => 'Location',
    TimelineSource.music => 'Music',
    TimelineSource.photo => 'Photo',
  };
}

enum TimelineConfidence {
  confirmed,
  suggested;

  String get label => switch (this) {
    TimelineConfidence.confirmed => 'Confirmed',
    TimelineConfidence.suggested => 'Suggested',
  };
}

/// A user-created timeline event. Journal entries, tracker records, visits and
/// music are *derived* into the timeline instead of being duplicated here.
class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.title,
    required this.occurredAt,
    this.notes = '',
    this.hidden = false,
  });

  final String id;
  final String title;
  final DateTime occurredAt;
  final String notes;
  final bool hidden;

  TimelineEvent copyWith({
    String? title,
    DateTime? occurredAt,
    String? notes,
    bool? hidden,
  }) {
    return TimelineEvent(
      id: id,
      title: title ?? this.title,
      occurredAt: occurredAt ?? this.occurredAt,
      notes: notes ?? this.notes,
      hidden: hidden ?? this.hidden,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'occurredAt': occurredAt.toIso8601String(),
    'notes': notes,
    'hidden': hidden,
  };

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      id: json['id'] as String? ?? _uuid.v4(),
      title: json['title'] as String? ?? 'Event',
      occurredAt:
          DateTime.tryParse(json['occurredAt'] as String? ?? '') ??
          DateTime.now(),
      notes: json['notes'] as String? ?? '',
      hidden: json['hidden'] as bool? ?? false,
    );
  }

  static TimelineEvent blank(DateTime date) {
    final now = DateTime.now();
    return TimelineEvent(
      id: _uuid.v4(),
      title: '',
      occurredAt: DateTime(
        date.year,
        date.month,
        date.day,
        now.hour,
        now.minute,
      ),
    );
  }
}

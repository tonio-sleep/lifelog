import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_service.dart';

/// Ephemeral UI state for one backup-to-cloud run. Nothing here is persisted:
/// progress is derived locally while packing and confirmed by the Worker after
/// every uploaded part.
enum BackupUploadStage {
  idle,
  preparing,
  media,
  packing,
  encrypting,
  uploading,
  done,
  failed;

  String get label => switch (this) {
        BackupUploadStage.idle => 'Ready',
        BackupUploadStage.preparing => 'Preparing',
        BackupUploadStage.media => 'Including media',
        BackupUploadStage.packing => 'Organizing records',
        BackupUploadStage.encrypting => 'Encrypting',
        BackupUploadStage.uploading => 'Uploading',
        BackupUploadStage.done => 'Synced',
        BackupUploadStage.failed => 'Failed',
      };
}

/// The kinds of encrypted bytes the app can put in R2. Audio is separate from
/// other media so a voice memo upload is visible on its own row.
enum CloudUploadKind {
  backup('Encrypted backup'),
  photo('Photos'),
  video('Videos'),
  audio('Audio'),
  otherMedia('Other files'),
  thumbnail('Thumbnails');

  const CloudUploadKind(this.label);
  final String label;
}

/// One server-confirmed byte row in the progress panel.
class CloudUploadRow {
  const CloudUploadRow({
    required this.kind,
    this.confirmedBytes = 0,
    this.totalBytes = 0,
    this.itemsDone = 0,
    this.itemsTotal = 0,
    this.detail = '',
  });

  final CloudUploadKind kind;
  final int confirmedBytes;
  final int totalBytes;
  final int itemsDone;
  final int itemsTotal;
  final String detail;

  double get fraction {
    if (totalBytes <= 0) return 0;
    final value = confirmedBytes / totalBytes;
    return value > 1 ? 1 : (value < 0 ? 0 : value);
  }

  bool get complete =>
      totalBytes > 0 && confirmedBytes >= totalBytes;

  CloudUploadRow copyWith({
    int? confirmedBytes,
    int? totalBytes,
    int? itemsDone,
    int? itemsTotal,
    String? detail,
  }) {
    return CloudUploadRow(
      kind: kind,
      confirmedBytes: confirmedBytes ?? this.confirmedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      itemsDone: itemsDone ?? this.itemsDone,
      itemsTotal: itemsTotal ?? this.itemsTotal,
      detail: detail ?? this.detail,
    );
  }
}

/// Events emitted by the cloud sync engine so the Settings card can show one
/// coherent run instead of unrelated counters.
enum CloudSyncEventType { begin, packed, plan, bytes, done, failed }

class CloudSyncProgressEvent {
  const CloudSyncProgressEvent._({
    required this.type,
    this.stage,
    this.current = 0,
    this.total = 0,
    this.label = '',
    this.rows,
    this.kind,
    this.confirmedBytes = 0,
    this.itemLabel = '',
    this.itemComplete = false,
  });

  final CloudSyncEventType type;
  final BackupPackStage? stage;
  final int current;
  final int total;
  final String label;
  final List<CloudUploadRow>? rows;
  final CloudUploadKind? kind;
  final int confirmedBytes;
  final String itemLabel;
  final bool itemComplete;

  factory CloudSyncProgressEvent.begin() =>
      const CloudSyncProgressEvent._(type: CloudSyncEventType.begin);

  factory CloudSyncProgressEvent.packed(
    BackupPackStage stage,
    int current,
    int total,
    String label,
  ) {
    return CloudSyncProgressEvent._(
      type: CloudSyncEventType.packed,
      stage: stage,
      current: current,
      total: total,
      label: label,
    );
  }

  factory CloudSyncProgressEvent.plan(List<CloudUploadRow> rows) =>
      CloudSyncProgressEvent._(
        type: CloudSyncEventType.plan,
        rows: rows,
      );

  factory CloudSyncProgressEvent.bytes(
    CloudUploadKind kind,
    int confirmedBytes, {
    int totalBytes = 0,
    String itemLabel = '',
    bool itemComplete = false,
  }) {
    return CloudSyncProgressEvent._(
      type: CloudSyncEventType.bytes,
      kind: kind,
      confirmedBytes: confirmedBytes,
      itemComplete: itemComplete,
      itemLabel: itemLabel,
      rows: totalBytes > 0
          ? [
              CloudUploadRow(
                kind: kind,
                totalBytes: totalBytes,
                itemsTotal: itemComplete ? 1 : 0,
              ),
            ]
          : null,
    );
  }

  factory CloudSyncProgressEvent.done() =>
      const CloudSyncProgressEvent._(type: CloudSyncEventType.done);

  factory CloudSyncProgressEvent.failed(String message) =>
      CloudSyncProgressEvent._(
        type: CloudSyncEventType.failed,
        label: message,
      );
}

class BackupUploadProgress {
  const BackupUploadProgress({
    this.stage = BackupUploadStage.idle,
    this.label = '',
    this.current = 0,
    this.total = 0,
    this.bytesSent = 0,
    this.bytesTotal = 0,
    this.rows = const [],
    this.currentItem = '',
    this.error,
    this.startedAt,
  });

  final BackupUploadStage stage;
  final String label;
  final int current;
  final int total;
  final int bytesSent;
  final int bytesTotal;
  final List<CloudUploadRow> rows;
  final String currentItem;
  final String? error;
  final DateTime? startedAt;

  bool get active => switch (stage) {
        BackupUploadStage.idle ||
        BackupUploadStage.done ||
        BackupUploadStage.failed =>
          false,
        _ => true,
      };

  double get itemFraction {
    if (total <= 0) return 0;
    final value = current / total;
    return value > 1 ? 1 : (value < 0 ? 0 : value);
  }

  double get byteFraction {
    if (bytesTotal <= 0) return 0;
    final value = bytesSent / bytesTotal;
    return value > 1 ? 1 : (value < 0 ? 0 : value);
  }

  BackupUploadProgress copyWith({
    BackupUploadStage? stage,
    String? label,
    int? current,
    int? total,
    int? bytesSent,
    int? bytesTotal,
    List<CloudUploadRow>? rows,
    String? currentItem,
    String? error,
    bool clearError = false,
    DateTime? startedAt,
  }) {
    return BackupUploadProgress(
      stage: stage ?? this.stage,
      label: label ?? this.label,
      current: current ?? this.current,
      total: total ?? this.total,
      bytesSent: bytesSent ?? this.bytesSent,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      rows: rows ?? this.rows,
      currentItem: currentItem ?? this.currentItem,
      error: clearError ? null : (error ?? this.error),
      startedAt: startedAt ?? this.startedAt,
    );
  }
}

final backupUploadProvider =
    NotifierProvider<BackupUploadController, BackupUploadProgress>(
  BackupUploadController.new,
);

/// Tracks a single sync attempt. A second Sync now resets the counters rather
/// than accumulating them from the previous run.
class BackupUploadController extends Notifier<BackupUploadProgress> {
  @override
  BackupUploadProgress build() => const BackupUploadProgress();

  /// Single entry point used by the automatic cloud-primary sync engine.
  void report(CloudSyncProgressEvent event) {
    switch (event.type) {
      case CloudSyncEventType.begin:
        begin();
      case CloudSyncEventType.packed:
        packed(event.stage!, event.current, event.total, event.label);
      case CloudSyncEventType.plan:
        plan(event.rows ?? const []);
      case CloudSyncEventType.bytes:
        confirmBytes(
          event.kind!,
          event.confirmedBytes,
          itemLabel: event.itemLabel,
          itemComplete: event.itemComplete,
          fallbackRow: event.rows?.first,
        );
      case CloudSyncEventType.done:
        finish();
      case CloudSyncEventType.failed:
        fail(event.label.isEmpty ? 'Sync failed.' : event.label);
    }
  }

  void begin() {
    state = BackupUploadProgress(
      stage: BackupUploadStage.preparing,
      label: 'Preparing encrypted backup',
      current: 0,
      total: 1,
      startedAt: DateTime.now(),
    );
  }

  void packed(BackupPackStage stage, int current, int total, String label) {
    state = state.copyWith(
      stage: switch (stage) {
        BackupPackStage.preparing => BackupUploadStage.preparing,
        BackupPackStage.media => BackupUploadStage.media,
        BackupPackStage.packing => BackupUploadStage.packing,
        BackupPackStage.encrypting => BackupUploadStage.encrypting,
        BackupPackStage.done => BackupUploadStage.encrypting,
      },
      label: label,
      current: current,
      total: total,
      clearError: true,
    );
  }

  /// Replaces the per-kind byte plan for this run.
  void plan(List<CloudUploadRow> rows) {
    state = state.copyWith(
      rows: rows,
      bytesSent: 0,
      bytesTotal: rows.fold<int>(0, (sum, row) => sum + row.totalBytes),
      clearError: true,
    );
  }

  /// Records bytes the Worker has confirmed for one kind. [fallbackRow] lets a
  /// caller without a plan still show an honest single row.
  void confirmBytes(
    CloudUploadKind kind,
    int confirmedBytes, {
    String itemLabel = '',
    bool itemComplete = false,
    CloudUploadRow? fallbackRow,
  }) {
    final next = <CloudUploadRow>[...state.rows];
    var index = next.indexWhere((row) => row.kind == kind);
    if (index < 0) {
      final row = fallbackRow ??
          CloudUploadRow(
            kind: kind,
            totalBytes: confirmedBytes,
            itemsTotal: itemComplete ? 1 : 0,
          );
      next.add(row);
      index = next.length - 1;
    }
    final row = next[index];
    // Without a plan, the first confirmed value also defines the row size.
    final effectiveTotal = row.totalBytes < confirmedBytes
        ? confirmedBytes
        : row.totalBytes;
    final effectiveRow =
        effectiveTotal == row.totalBytes ? row : row.copyWith(totalBytes: effectiveTotal);
    final safeBytes = confirmedBytes.clamp(0, effectiveTotal);
    next[index] = effectiveRow.copyWith(
      confirmedBytes: safeBytes,
      itemsDone: effectiveRow.itemsDone + (itemComplete ? 1 : 0),
      detail: itemLabel.isEmpty ? effectiveRow.detail : itemLabel,
    );
    state = state.copyWith(
      stage: BackupUploadStage.uploading,
      label: 'Confirming ${kind.label.toLowerCase()}',
      bytesSent: next.fold<int>(0, (sum, item) => sum + item.confirmedBytes),
      bytesTotal: next.fold<int>(0, (sum, item) => sum + item.totalBytes),
      rows: next,
      currentItem: itemLabel,
      clearError: true,
    );
  }

  void uploading(int sent, int total) {
    confirmBytes(
      CloudUploadKind.backup,
      sent,
      fallbackRow: CloudUploadRow(
        kind: CloudUploadKind.backup,
        totalBytes: total,
        itemsTotal: 1,
      ),
    );
  }

  void finish() {
    state = state.copyWith(
      stage: BackupUploadStage.done,
      label: 'Backup uploaded',
      current: 1,
      total: 1,
      bytesSent: state.bytesTotal,
      rows: state.rows
          .map((row) => row.copyWith(
                confirmedBytes: row.totalBytes,
                itemsDone: row.itemsTotal,
              ))
          .toList(),
      clearError: true,
    );
  }

  void fail(String message) {
    state = state.copyWith(
      stage: BackupUploadStage.failed,
      label: message,
      error: message,
    );
  }

  void clear() => state = const BackupUploadProgress();
}

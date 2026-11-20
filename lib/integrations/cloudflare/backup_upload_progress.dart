import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_service.dart';

/// Ephemeral UI state for one backup-to-cloud run. Nothing here is persisted:
/// progress is derived locally while packing and streaming the encrypted blob.
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
        BackupUploadStage.media => 'Including photos',
        BackupUploadStage.packing => 'Organizing records',
        BackupUploadStage.encrypting => 'Encrypting',
        BackupUploadStage.uploading => 'Uploading',
        BackupUploadStage.done => 'Synced',
        BackupUploadStage.failed => 'Failed',
      };
}

class BackupUploadProgress {
  const BackupUploadProgress({
    this.stage = BackupUploadStage.idle,
    this.label = '',
    this.current = 0,
    this.total = 0,
    this.bytesSent = 0,
    this.bytesTotal = 0,
    this.error,
    this.startedAt,
  });

  final BackupUploadStage stage;
  final String label;
  final int current;
  final int total;
  final int bytesSent;
  final int bytesTotal;
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

  void uploading(int sent, int total) {
    state = state.copyWith(
      stage: BackupUploadStage.uploading,
      label: 'Uploading encrypted backup',
      bytesSent: sent,
      bytesTotal: total,
      clearError: true,
    );
  }

  void finish() {
    state = state.copyWith(
      stage: BackupUploadStage.done,
      label: 'Backup uploaded',
      current: 1,
      total: 1,
      bytesSent: state.bytesTotal,
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

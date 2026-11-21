import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native, file-based iOS transcription. Recognition starts only after the
/// recorder has produced a complete file, so a long recording never depends on
/// a long-lived live speech session.
const String transcriptionMethodChannel = 'lifelog/transcription';
const String transcriptionEventChannel = 'lifelog/transcription/events';

class SpeechLanguage {
  const SpeechLanguage({required this.id, required this.name});

  final String id;
  final String name;

  factory SpeechLanguage.fromMap(Map<dynamic, dynamic> map) {
    final id = (map['id'] as String?)?.trim() ?? '';
    return SpeechLanguage(
      id: id,
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? (map['name'] as String).trim()
          : id,
    );
  }
}

class TranscriptionAvailability {
  const TranscriptionAvailability({
    required this.status,
    required this.localeId,
    required this.onDeviceAvailable,
    required this.languages,
  });

  final String status;
  final String localeId;
  final bool onDeviceAvailable;
  final List<SpeechLanguage> languages;

  bool get authorized => status == 'authorized';

  factory TranscriptionAvailability.fromMap(Map<String, dynamic> map) {
    final rawLanguages = map['languages'] as List? ?? const [];
    return TranscriptionAvailability(
      status: (map['status'] as String?) ?? 'unknown',
      localeId: (map['localeId'] as String?) ?? '',
      onDeviceAvailable: map['onDeviceAvailable'] == true,
      languages: rawLanguages
          .whereType<Map>()
          .map((language) => SpeechLanguage.fromMap(language))
          .where((language) => language.id.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class TranscriptionUpdate {
  const TranscriptionUpdate({
    required this.transcriptionId,
    required this.transcript,
    required this.fraction,
    required this.estimated,
    required this.isFinal,
  });

  final String transcriptionId;
  final String transcript;
  final double fraction;
  final bool estimated;
  final bool isFinal;

  factory TranscriptionUpdate.fromEvent(Object? event) {
    if (event is! Map) {
      throw ArgumentError.value(event, 'event', 'Expected a map.');
    }
    final map = Map<dynamic, dynamic>.from(event);
    final duration = _finitePositive(map['durationSeconds']);
    final recognized = _finitePositive(map['recognizedSeconds']);
    final elapsed = _finitePositive(map['elapsedSeconds']);
    final hasTimedSegments = map['hasTimedSegments'] == true;

    return TranscriptionUpdate(
      transcriptionId: (map['transcriptionId'] as String?) ?? '',
      transcript: (map['transcript'] as String?) ?? '',
      fraction: transcriptionProgressFraction(
        recognizedSeconds: recognized,
        durationSeconds: duration,
        hasTimedSegments: hasTimedSegments,
        elapsedSeconds: elapsed,
      ),
      estimated: !(hasTimedSegments && recognized > 0),
      isFinal: map['isFinal'] == true,
    );
  }
}

class TranscriptionResult {
  const TranscriptionResult({
    required this.transcriptionId,
    required this.transcript,
    required this.onDevice,
    required this.durationSeconds,
  });

  final String transcriptionId;
  final String transcript;
  final bool onDevice;
  final double durationSeconds;

  factory TranscriptionResult.fromMap(
    Map<String, dynamic> map, {
    required String transcriptionId,
  }) {
    return TranscriptionResult(
      transcriptionId: (map['transcriptionId'] as String?) ?? transcriptionId,
      transcript: (map['transcript'] as String?) ?? '',
      onDevice: map['onDevice'] == true,
      durationSeconds: _finitePositive(map['durationSeconds']),
    );
  }
}

class AudioTranscriptionException implements Exception {
  const AudioTranscriptionException({
    required this.code,
    required this.message,
    required this.partialTranscript,
    required this.fraction,
  });

  final String code;
  final String message;
  final String partialTranscript;
  final double fraction;

  factory AudioTranscriptionException.fromPlatformException(
    PlatformException exception,
  ) {
    final details = exception.details is Map
        ? Map<dynamic, dynamic>.from(exception.details as Map)
        : <dynamic, dynamic>{};
    final duration = _finitePositive(details['durationSeconds']);
    final recognized = _finitePositive(details['recognizedSeconds']);
    final elapsed = _finitePositive(details['elapsedSeconds']);
    final hasTimedSegments = details['hasTimedSegments'] == true;
    final message = (exception.message ?? '').trim();

    return AudioTranscriptionException(
      code: exception.code,
      message: message.isNotEmpty ? message : 'Transcription failed.',
      partialTranscript: (details['transcript'] as String?) ?? '',
      fraction: transcriptionProgressFraction(
        recognizedSeconds: recognized,
        durationSeconds: duration,
        hasTimedSegments: hasTimedSegments,
        elapsedSeconds: elapsed,
      ),
    );
  }

  @override
  String toString() => 'AudioTranscriptionException($code): $message';
}

double _clamp01(double value) {
  if (value.isNaN) return 0;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

double _finitePositive(Object? value) {
  final number = value is num ? value.toDouble() : 0.0;
  if (!number.isFinite || number <= 0) return 0;
  return number;
}

/// Progress from the recognizer's real word timings when available. Before the
/// recognizer reports timings, a conservative elapsed-time estimate is shown
/// and capped so it never pretends to be nearly finished.
double transcriptionProgressFraction({
  required double recognizedSeconds,
  required double durationSeconds,
  required bool hasTimedSegments,
  required double elapsedSeconds,
}) {
  final duration = _finitePositive(durationSeconds);
  if (duration == 0) return 0;

  final recognized = _finitePositive(recognizedSeconds);
  if (hasTimedSegments && recognized > 0) {
    final fraction = _clamp01(recognized / duration);
    return fraction >= 0.99 ? 0.99 : fraction;
  }

  final elapsed = _finitePositive(elapsedSeconds);
  if (elapsed == 0) return 0;
  final estimate = _clamp01(elapsed / duration);
  return estimate >= 0.9 ? 0.9 : estimate;
}

/// Thin Dart wrapper around the native Speech framework channel.
class AudioTranscriber {
  AudioTranscriber({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _method =
          methodChannel ?? const MethodChannel(transcriptionMethodChannel),
      _events = eventChannel ?? const EventChannel(transcriptionEventChannel);

  final MethodChannel _method;
  final EventChannel _events;
  StreamSubscription<dynamic>? _subscription;
  final Map<String, void Function(TranscriptionUpdate)> _listeners =
      <String, void Function(TranscriptionUpdate)>{};
  final Map<String, _PendingTranscription> _pending =
      <String, _PendingTranscription>{};
  int _nextId = 0;
  int _epoch = 0;
  bool _disposed = false;

  String _newId() {
    _nextId++;
    return 'transcription-${DateTime.now().microsecondsSinceEpoch}-$_nextId';
  }

  void _ensureListening() {
    if (_subscription != null) return;
    _subscription = _events.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object _) {},
    );
  }

  void _handleEvent(Object? event) {
    TranscriptionUpdate update;
    try {
      update = TranscriptionUpdate.fromEvent(event);
    } catch (_) {
      return;
    }
    final listener = _listeners[update.transcriptionId];
    if (listener == null) return;
    listener(update);
  }

  Future<TranscriptionAvailability> prepare({String? localeId}) async {
    try {
      final reply = await _method.invokeMapMethod<String, dynamic>(
        'prepare',
        <String, dynamic>{'localeId': localeId ?? ''},
      );
      if (reply == null) {
        return const TranscriptionAvailability(
          status: 'unknown',
          localeId: '',
          onDeviceAvailable: false,
          languages: <SpeechLanguage>[],
        );
      }
      return TranscriptionAvailability.fromMap(reply);
    } on PlatformException catch (e) {
      debugPrint('Speech prepare failed: ${e.code} ${e.message}');
      return const TranscriptionAvailability(
        status: 'unavailable',
        localeId: '',
        onDeviceAvailable: false,
        languages: <SpeechLanguage>[],
      );
    }
  }

  /// Transcribes one finished audio file. [onProgress] receives cumulative
  /// transcript text and a real-or-estimated fraction until the call returns.
  Future<TranscriptionResult> transcribe({
    required String path,
    required String? localeId,
    required void Function(TranscriptionUpdate) onProgress,
  }) {
    final id = _newId();
    final epoch = _epoch;
    // Register everything synchronously. An await here used to let cancel()
    // snapshot an empty pending set and leave this task running natively.
    _ensureListening();
    final pending = _PendingTranscription(
      id: id,
      epoch: epoch,
      onProgress: onProgress,
    );
    _listeners[id] = onProgress;
    _pending[id] = pending;
    if (_disposed || epoch < _epoch) {
      pending.fail(
        _cancelledException(
          code: _disposed ? 'DISPOSED' : 'CANCELLED',
          message: _disposed
              ? 'The transcriber was closed.'
              : 'Transcription was cancelled.',
        ),
      );
      _forget(pending);
      return pending.completer.future;
    }
    // Do not await here: cancel() must be able to complete this future even if
    // the native method result never arrives after a cancelled task.
    _invokeTranscribe(pending: pending, path: path, localeId: localeId);
    return pending.completer.future;
  }

  Future<void> _invokeTranscribe({
    required _PendingTranscription pending,
    required String path,
    required String? localeId,
  }) async {
    try {
      final reply = await _method.invokeMapMethod<String, dynamic>(
        'transcribe',
        <String, dynamic>{
          'path': path,
          'localeId': localeId ?? '',
          'transcriptionId': pending.id,
        },
      );
      if (reply == null) {
        pending.fail(
          const AudioTranscriptionException(
            code: 'NO_RESULT',
            message: 'The transcriber returned no result.',
            partialTranscript: '',
            fraction: 0,
          ),
        );
        return;
      }
      pending.complete(
        TranscriptionResult.fromMap(reply, transcriptionId: pending.id),
      );
    } on PlatformException catch (e) {
      pending.fail(AudioTranscriptionException.fromPlatformException(e));
    } catch (e) {
      pending.fail(
        AudioTranscriptionException(
          code: 'UNEXPECTED_ERROR',
          message: e.toString(),
          partialTranscript: '',
          fraction: 0,
        ),
      );
    } finally {
      _forget(pending);
    }
  }

  void _forget(_PendingTranscription pending) {
    _listeners.remove(pending.id);
    _pending.remove(pending.id);
  }

  AudioTranscriptionException _cancelledException({
    required String code,
    required String message,
  }) {
    return AudioTranscriptionException(
      code: code,
      message: message,
      partialTranscript: '',
      fraction: 0,
    );
  }

  Future<void> cancel() async {
    final cancelledAt = _epoch;
    _epoch++;
    // Snapshot every task that existed when cancel was requested, not just a
    // single "active" field: a late registration must not survive the await.
    final pendings = _pending.values
        .where((pending) => pending.epoch <= cancelledAt)
        .toList();
    try {
      await _method.invokeMethod<void>('cancel');
    } catch (_) {
      // Cancellation is best-effort; the native task is idempotent.
    }
    for (final pending in pendings) {
      pending.fail(
        _cancelledException(
          code: 'CANCELLED',
          message: 'Transcription was cancelled.',
        ),
      );
      _forget(pending);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final disposedAt = _epoch;
    _epoch++;
    final pendings = _pending.values
        .where((pending) => pending.epoch <= disposedAt)
        .toList();
    // The native recognizer must be cancelled even when no Dart future is
    // pending, otherwise it keeps running after the sheet is torn down.
    try {
      await _method.invokeMethod<void>('cancel');
    } catch (_) {
      // Best effort; dispose must still release the Dart subscription.
    }
    for (final pending in pendings) {
      pending.fail(
        _cancelledException(
          code: 'DISPOSED',
          message: 'The transcriber was closed.',
        ),
      );
      _forget(pending);
    }
    await _subscription?.cancel();
    _subscription = null;
    _listeners.clear();
    _pending.clear();
  }
}

class _PendingTranscription {
  _PendingTranscription({
    required this.id,
    required this.epoch,
    required this.onProgress,
  });

  final String id;
  final int epoch;
  final void Function(TranscriptionUpdate) onProgress;
  final Completer<TranscriptionResult> completer =
      Completer<TranscriptionResult>();

  void complete(TranscriptionResult result) {
    if (!completer.isCompleted) completer.complete(result);
  }

  void fail(Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }
}

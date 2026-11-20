import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import 'transcript_accumulator.dart';

class VoiceNoteResult {
  const VoiceNoteResult({
    required this.audioPath,
    required this.transcript,
    required this.mimeType,
    required this.fileName,
  });

  final String audioPath;
  final String transcript;
  final String mimeType;
  final String fileName;
}

/// The sheet is deliberately not dismissible by backdrop or drag. Closing it
/// while recording always goes through a guard so a stray tap cannot throw
/// away the audio and transcript.
Future<VoiceNoteResult?> showVoiceNoteSheet(BuildContext context) {
  return showLifelogSheet<VoiceNoteResult>(
    context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _VoiceNoteSheet(),
  );
}

class _VoiceNoteSheet extends StatefulWidget {
  const _VoiceNoteSheet();

  @override
  State<_VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

class _VoiceNoteSheetState extends State<_VoiceNoteSheet>
    with WidgetsBindingObserver {
  final AudioRecorder _recorder = AudioRecorder();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TranscriptAccumulator _transcript = TranscriptAccumulator();

  bool _initializing = true;
  bool _recording = false;
  bool _saving = false;
  bool _saveInFlight = false;
  bool _speechAvailable = false;
  bool _listenPending = false;
  bool _restartInFlight = false;
  bool _speechEnded = false;
  bool _userStopping = false;
  bool _abandoned = false;
  bool _resultHandedOff = false;
  String _status = 'Preparing microphone and transcription...';
  String? _error;
  String? _audioPath;
  String? _localeId;
  List<stt.LocaleName> _locales = const [];
  DateTime? _startedAt;
  DateTime? _lastListenAttempt;
  DateTime? _lastResultAt;
  DateTime? _nextRestartAt;
  Timer? _ticker;
  int _generation = 0;
  int _retryDelayMs = 400;

  bool get _hasWork => _recording || !_transcript.isEmpty || _audioPath != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      if (kIsWeb) {
        setState(() {
          _error = 'Voice notes are not available on web in this build.';
          _status = 'Unavailable';
          _initializing = false;
        });
        return;
      }
      final micOk = await _recorder.hasPermission();
      if (!mounted) return;
      if (!micOk) {
        setState(() {
          _error =
              'Microphone permission is needed to record a voice note. You can still type your entry.';
          _status = 'Microphone permission not granted';
          _initializing = false;
        });
        return;
      }
      try {
        _speechAvailable = await _speech.initialize(
          onStatus: (status) {
            if (!mounted) return;
            final listening = status.toLowerCase() == 'listening';
            setState(() => _speechEnded = !listening);
          },
          onError: (error) {
            if (!mounted) return;
            final message = error.errorMsg.trim();
            setState(() {
              _speechEnded = true;
              if (message.isNotEmpty) {
                _error = 'Transcription paused: $message. Recording continues.';
              }
            });
          },
        );
      } catch (_) {
        _speechAvailable = false;
      }
      if (_speechAvailable) {
        try {
          _locales = await _speech.locales();
          final system = await _speech.systemLocale();
          _localeId = system?.localeId;
        } catch (_) {
          _locales = const [];
        }
      }
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = _speechAvailable
            ? 'Ready. Recording can transcribe on supported devices.'
            : 'Ready. Audio recording is available; live transcription may be unavailable.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not prepare voice recording: $e';
        _status = 'Unavailable';
      });
    }
  }

  Future<void> _start() async {
    if (_initializing || _recording || _saving || _saveInFlight) return;

    // A failed save can leave a temporary file behind. A fresh recording gets
    // a fresh file, so remove the old one instead of leaking it.
    final oldPath = _audioPath;
    if (oldPath != null) {
      try {
        final old = File(oldPath);
        if (await old.exists()) await old.delete();
      } catch (_) {}
    }
    if (!mounted) return;

    setState(() {
      _error = null;
      _transcript.reset();
      _userStopping = false;
      _abandoned = false;
      _resultHandedOff = false;
      _saveInFlight = false;
      _restartInFlight = false;
      _speechEnded = false;
      _retryDelayMs = 400;
      _nextRestartAt = null;
      _generation++;
    });
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}${Platform.pathSeparator}voice_note_$ts.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      _audioPath = path;
      _startedAt = DateTime.now();
      _lastListenAttempt = DateTime.now();
      _lastResultAt = null;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        _checkSpeechSession();
      });
      setState(() {
        _recording = true;
        _status = 'Recording...';
      });
      if (_speechAvailable) unawaited(_listenOnce());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _error = 'Could not start recording: $e';
        _status = 'Could not start recording';
      });
    }
  }

  /// Starts one recognition session. Sessions are short on purpose: the
  /// platform ends long sessions silently, so we restart and keep the text.
  Future<void> _listenOnce() async {
    if (!_recording || _userStopping || _abandoned || !_speechAvailable) return;
    if (_listenPending || _speech.isListening || !mounted) return;
    _listenPending = true;
    _lastListenAttempt = DateTime.now();
    _speechEnded = false;
    _nextRestartAt = null;
    final session = _transcript.nextSession();
    _transcript.startNewSession();
    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            if (result.recognizedWords.trim().isNotEmpty) {
              // A fresh result means speech is healthy again: clear stale
              // errors and restart the silence watchdog.
              _lastResultAt = DateTime.now();
              _speechEnded = false;
              _error = null;
              _retryDelayMs = 400;
            }
            _transcript.addResult(
              eventSession: session,
              recognizedWords: result.recognizedWords,
              isFinal: result.finalResult,
            );
          });
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: _localeId,
          partialResults: true,
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 4),
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          sampleRate: 44100,
          autoPunctuation: !kIsWeb && Platform.isIOS,
        ),
      );
      _retryDelayMs = 400;
    } catch (_) {
      // The ticker will retry while recording continues.
    } finally {
      _listenPending = false;
    }
  }

  DateTime? _lastSpeechSignal() {
    final dates = <DateTime>[
      ?_lastResultAt,
      ?_lastListenAttempt,
      ?_startedAt,
    ];
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  Duration _silenceSinceLastSignal() {
    final last = _lastSpeechSignal() ?? DateTime.now();
    return DateTime.now().difference(last);
  }

  /// Detects a recognition session that the platform ended on its own and
  /// restarts it without dropping the words already captured.
  ///
  /// `isListening` is not enough: iOS can end a session silently and leave the
  /// plugin's flag set. A long silence therefore forces a restart too. The
  /// next-restart timestamp prevents the 1-second ticker from cancelling a
  /// backoff before it fires.
  void _checkSpeechSession() {
    if (!_recording ||
        _userStopping ||
        _abandoned ||
        _saveInFlight ||
        !_speechAvailable ||
        _listenPending ||
        _restartInFlight) {
      return;
    }
    final now = DateTime.now();
    final next = _nextRestartAt;
    if (next != null && now.isBefore(next)) return;

    final silentEnd = !_speech.isListening ||
        _speechEnded ||
        _silenceSinceLastSignal() >= const Duration(seconds: 12);
    if (!silentEnd) {
      _retryDelayMs = 400;
      return;
    }

    _nextRestartAt = now.add(Duration(milliseconds: _retryDelayMs));
    final error = _speech.lastError?.errorMsg.trim() ?? '';
    if (error.isNotEmpty && mounted) {
      setState(() {
        _error = 'Transcription paused: $error. Recording continues.';
      });
    }
    unawaited(_restartListening(_generation));
  }

  Future<void> _restartListening(int generation) async {
    if (_restartInFlight) return;
    _restartInFlight = true;
    final delay = _retryDelayMs;
    _retryDelayMs = (_retryDelayMs * 2).clamp(400, 4000);
    try {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted ||
          generation != _generation ||
          !_recording ||
          _userStopping ||
          _abandoned ||
          _saveInFlight) {
        return;
      }
      _transcript.finalizePartial();
      if (_speech.isListening) {
        try {
          await _speech.cancel();
        } catch (_) {}
      }
      if (!mounted ||
          generation != _generation ||
          !_recording ||
          _userStopping ||
          _abandoned ||
          _saveInFlight) {
        return;
      }
      _speechEnded = false;
      _nextRestartAt = null;
      unawaited(_listenOnce());
    } finally {
      if (generation == _generation) _restartInFlight = false;
    }
  }

  /// Used after an app lifecycle resume, where the platform may have revoked
  /// the speech audio session without telling us.
  Future<void> _forceSpeechRestart() async {
    if (!_recording ||
        _userStopping ||
        _abandoned ||
        _saveInFlight ||
        !_speechAvailable) {
      return;
    }
    _transcript.finalizePartial();
    _nextRestartAt = null;
    try {
      if (_speech.isListening) await _speech.cancel();
    } catch (_) {}
    if (!mounted || !_recording || _userStopping || _abandoned) return;
    _speechEnded = false;
    _lastListenAttempt = null;
    unawaited(_listenOnce());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || !_recording) return;
    if (state == AppLifecycleState.paused) {
      _transcript.finalizePartial();
      setState(() {
        _status = 'Recording paused by the system; captured words are safe.';
      });
    } else if (state == AppLifecycleState.resumed && !_userStopping) {
      setState(() => _status = 'Recording...');
      unawaited(_forceSpeechRestart());
    }
  }

  Future<void> _stopAndSave() async {
    if (_saving || _saveInFlight) return;
    // A failed stop can leave an audio file without an active recording. It is
    // still valid work and must be handable off instead of becoming a dead end.
    if (!_recording && _audioPath == null) return;

    setState(() => _saving = true);
    // Protect the temporary audio immediately: from here on it belongs to the
    // handoff, even if the sheet is closed while disk I/O is in flight.
    _saveInFlight = true;
    _resultHandedOff = true;
    _userStopping = true;
    _generation++;
    _nextRestartAt = null;
    try {
      if (_recording && _speechAvailable) {
        try {
          await _speech.stop();
          // Give the platform a moment to deliver its final result before the
          // sheet goes away; callbacks after Navigator.pop() are ignored.
          await Future<void>.delayed(const Duration(milliseconds: 900));
        } catch (_) {}
      }
      if (!mounted) return;
      _transcript.finalizePartial();
      String? path = _audioPath;
      if (_recording) {
        try {
          path = await _recorder.stop();
        } catch (_) {}
      }
      path ??= _audioPath;
      if (path == null || path.isEmpty) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _recording = false;
          _userStopping = false;
          _saveInFlight = false;
          _resultHandedOff = false;
          _error = 'No audio was captured.';
        });
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _recording = false;
          _userStopping = false;
          _saveInFlight = false;
          _resultHandedOff = false;
          _error = 'Recorded audio file was not found.';
        });
        return;
      }
      final name = path.split(Platform.pathSeparator).last;
      if (!mounted) return;
      Navigator.of(context).pop(
        VoiceNoteResult(
          audioPath: path,
          transcript: _transcript.text,
          mimeType: 'audio/mp4',
          fileName: name,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _recording = false;
        _userStopping = false;
        _saveInFlight = false;
        // The handoff failed, so the sheet still owns (and must delete) the
        // temporary recording on dispose.
        _resultHandedOff = false;
        _error = 'Could not save voice note: $e';
      });
    }
  }

  Future<void> _discard() async {
    _abandoned = true;
    _userStopping = true;
    _saveInFlight = false;
    _generation++;
    _ticker?.cancel();
    _nextRestartAt = null;
    try {
      if (_speechAvailable) await _speech.cancel();
    } catch (_) {}
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    final path = _audioPath;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _requestClose() async {
    // A save is already handing the audio to the editor. Popping here used to
    // dispose the sheet and delete the temporary recording mid-save.
    if (_saving || _saveInFlight) return;
    if (!_hasWork) {
      Navigator.of(context).pop();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep this voice note?'),
        content: const Text(
          'A recording is in progress. Save it and add the transcript to your entry, or discard it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'recording'),
            child: const Text('Keep recording'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save & close'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'discard') {
      await _discard();
    } else if (choice == 'save') {
      await _stopAndSave();
    }
  }

  Future<void> _pickLocale() async {
    if (_locales.isEmpty) return;
    final chosen = await showLifelogSheet<stt.LocaleName>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(
            title: 'Transcription language',
            subtitle: 'Used by your device speech service.',
          ),
          for (final locale in _locales)
            ListTile(
              title: Text(locale.name),
              subtitle: Text(locale.localeId),
              selected: locale.localeId == _localeId,
              onTap: () => Navigator.of(sheetContext).pop(locale),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _localeId = chosen.localeId);
    if (_recording) unawaited(_forceSpeechRestart());
  }

  String _elapsedLabel() {
    final start = _startedAt;
    if (start == null) return '0:00';
    final d = DateTime.now().difference(start);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _generation++;
    if (!_resultHandedOff && !_abandoned) {
      unawaited(_speech.cancel());
      final path = _audioPath;
      if (path != null) {
        unawaited(() async {
          try {
            final f = File(path);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }());
      }
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final liveText = _transcript.text;

    return PopScope<bool>(
      canPop: !_hasWork,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(
            title: 'Voice note',
            subtitle:
                'Record audio and transcribe to text. Both audio and transcript can be saved to this entry.',
          ),
          QuietCard(
            padding: const EdgeInsets.all(Insets.md),
            color: palette.subtle.withValues(alpha: 0.6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _recording ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color:
                          _recording ? context.scheme.error : palette.mutedText,
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(
                        _recording ? 'Recording ${_elapsedLabel()}' : _status,
                        style: text.bodyMedium?.copyWith(
                          color: _recording ? null : palette.mutedText,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_speechAvailable)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _speechListeningLabel(),
                      style: text.bodySmall?.copyWith(color: palette.mutedText),
                    ),
                  ),
                if (_locales.length > 1)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _recording ? null : _pickLocale,
                      icon: const Icon(Icons.translate_outlined, size: 16),
                      label: Text(_localeLabel()),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
          Text(
            'Transcript',
            style: text.labelMedium?.copyWith(color: palette.mutedText),
          ),
          const SizedBox(height: Insets.xs),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 90),
            padding: const EdgeInsets.all(Insets.md),
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Text(
              liveText.isEmpty
                  ? (_recording
                      ? 'Start speaking… transcription will appear here when available.'
                      : 'Your transcribed text will appear here.')
                  : liveText,
              style: text.bodyMedium?.copyWith(
                color: liveText.isEmpty ? palette.dimText : null,
                height: 1.5,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Insets.sm),
            Text(
              _error!,
              style: text.bodySmall?.copyWith(color: context.scheme.error),
            ),
          ],
          const SizedBox(height: Insets.md),
          if (_initializing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(Insets.md),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving || _saveInFlight ? null : _requestClose,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: FilledButton.icon(
                    // Errors are retryable; the old code disabled Start forever
                    // after one failed attempt.
                    onPressed: (_saving || _saveInFlight)
                        ? null
                        : (_recording ? _stopAndSave : _start),
                    icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                    label: Text(
                      _saving
                          ? 'Saving...'
                          : (_recording
                              ? 'Stop & save'
                              : (_error != null ? 'Retry recording' : 'Start recording')),
                    ),
                  ),
                ),
              ],
            ),
          if (!_speechAvailable && !_initializing)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Text(
                'If transcription is unavailable or inaccurate, the audio can still be saved and you can edit or type text manually.',
                style: text.bodySmall?.copyWith(color: palette.mutedText),
              ),
            ),
        ],
      ),
    );
  }

  String _speechListeningLabel() {
    if (!_recording) {
      return 'Transcription uses your device speech service when available.';
    }
    if (_status != 'Recording...') return _status;
    if (_speech.isListening &&
        !_speechEnded &&
        _silenceSinceLastSignal() < const Duration(seconds: 12)) {
      return 'Live transcription is listening.';
    }
    return 'Transcription is restarting; your recording and words are safe.';
  }

  String _localeLabel() {
    if (_localeId == null) return 'Transcription language: device default';
    final match = _locales.where((l) => l.localeId == _localeId).firstOrNull;
    return 'Language: ${match?.name ?? _localeId}';
  }
}

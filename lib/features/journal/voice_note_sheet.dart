import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../integrations/speech/audio_transcriber.dart';
import 'voice_note_session.dart';

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
/// while recording or transcribing always goes through a guard so a stray tap
/// cannot throw away the audio or words the recognizer already captured.
Future<VoiceNoteResult?> showVoiceNoteSheet(BuildContext context) async {
  final sheetKey = GlobalKey<_VoiceNoteSheetState>();
  final footerRevision = ValueNotifier<int>(0);
  try {
    return await showLifelogSheet<VoiceNoteResult>(
      context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) =>
          _VoiceNoteSheet(key: sheetKey, footerRevision: footerRevision),
      footerBuilder: (sheetContext) => ValueListenableBuilder<int>(
        valueListenable: footerRevision,
        builder: (_, _, _) {
          final state = sheetKey.currentState;
          if (state == null) {
            // The body mounts on this frame; its initState bumps the notifier
            // so the real controls replace this placeholder immediately.
            return const SizedBox(height: 48);
          }
          return state.buildFooter(sheetContext);
        },
      ),
    );
  } finally {
    footerRevision.dispose();
  }
}

class _VoiceNoteSheet extends StatefulWidget {
  const _VoiceNoteSheet({super.key, required this.footerRevision});

  final ValueNotifier<int> footerRevision;

  @override
  State<_VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

class _VoiceNoteSheetState extends State<_VoiceNoteSheet>
    with WidgetsBindingObserver {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioTranscriber _transcriber = AudioTranscriber();
  final VoiceNoteSession _session = VoiceNoteSession();

  bool _initializing = true;
  bool _transcriberAvailable = false;
  bool _onDeviceAvailable = false;
  bool _handingOff = false;
  bool _confirmingClose = false;
  bool _wakeLockEnabled = false;
  String _status = 'Preparing microphone and transcription...';
  String? _error;
  String? _notice;
  String? _audioPath;
  String? _localeId;
  List<SpeechLanguage> _languages = const <SpeechLanguage>[];
  DateTime? _startedAt;
  Timer? _ticker;
  int _generation = 0;

  bool get _hasWork =>
      _session.isBusy || _audioPath != null || _session.transcript.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The footer is built by the surrounding sheet, so tell it to render the
    // real controls once this state exists.
    widget.footerRevision.value++;
    unawaited(_init());
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (mounted) widget.footerRevision.value++;
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
          _error = 'Microphone permission is needed to record a voice note. You can still type your entry.';
          _status = 'Microphone permission not granted';
          _initializing = false;
        });
        return;
      }

      final availability = await _transcriber.prepare();
      if (!mounted) return;
      _transcriberAvailable = availability.authorized;
      _onDeviceAvailable = availability.onDeviceAvailable;
      _localeId = availability.localeId.isNotEmpty
          ? availability.localeId
          : null;
      _languages = availability.languages;

      if (!_transcriberAvailable) {
        _notice = 'Speech recognition is not authorized. Audio will still be recorded and saved.';
      } else if (!_onDeviceAvailable) {
        _notice = 'On-device transcription is not available for this language. Audio will still be recorded and saved.';
      }

      setState(() {
        _initializing = false;
        _status = _transcriberAvailable && _onDeviceAvailable
            ? 'Ready. Transcription runs on this device after recording.'
            : 'Ready. Audio recording is available; transcription may be unavailable.';
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

  Future<void> _enableWakeLock() async {
    if (_wakeLockEnabled) return;
    // Mark first so a release racing the platform call still disables it.
    _wakeLockEnabled = true;
    try {
      await WakelockPlus.enable();
    } catch (_) {
      _wakeLockEnabled = false;
      if (mounted) {
        setState(() {
          _notice = 'Could not keep the screen awake. Your recording may be interrupted if the screen turns off.';
        });
      }
    }
  }

  Future<void> _releaseWakeLock() async {
    if (!_wakeLockEnabled) return;
    _wakeLockEnabled = false;
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Nothing useful to do; the platform call is best-effort.
    }
  }

  Future<void> _start() async {
    if (_initializing || _session.isBusy || _handingOff || _confirmingClose) {
      return;
    }

    // Claim the session before any await. Otherwise a second tap can delete
    // the same file and call recorder.start() twice.
    final oldPath = _audioPath;
    final generation = ++_generation;
    setState(() {
      _session.beginRecording();
      _error = null;
      _notice = null;
      _audioPath = null;
      _startedAt = null;
      _status = 'Recording...';
    });

    if (oldPath != null) {
      try {
        final old = File(oldPath);
        if (await old.exists()) await old.delete();
      } catch (_) {}
    }
    if (!mounted || generation != _generation) return;

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
      if (!mounted || generation != _generation) {
        await _recorder.stop();
        await _releaseWakeLock();
        return;
      }
      _audioPath = path;
      _startedAt = DateTime.now();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
      await _enableWakeLock();
      if (!mounted || generation != _generation) return;
      setState(() => _status = 'Recording...');
    } catch (e) {
      await _releaseWakeLock();
      if (!mounted || generation != _generation) return;
      setState(() {
        _session.recordingFailed('Could not start recording: $e');
        _error = 'Could not start recording: $e';
        _status = 'Could not start recording';
      });
    }
  }

  Future<void> _stopAndSave() async {
    if (_handingOff ||
        _confirmingClose ||
        _session.isStopping ||
        _session.isTranscribing) {
      return;
    }
    if (_session.canHandOff) {
      await _handOff();
      return;
    }
    if (!_session.isRecording && _audioPath == null) return;

    // Claim the stopping phase before the first await so a second Stop tap or
    // a simultaneous Discard cannot close the same file twice.
    final generation = ++_generation;
    setState(() => _session.beginStopping());
    _ticker?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      // A failed stop still leaves a complete-enough temporary file to use.
    }
    await _releaseWakeLock();
    if (!mounted || generation != _generation || _session.abandoned) return;

    path ??= _audioPath;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      setState(() {
        _session.recordingFailed('No recorded audio was found.');
        _error = 'No recorded audio was found.';
        _status = 'No audio captured';
      });
      return;
    }
    _audioPath = path;

    if (!_transcriberAvailable || !_onDeviceAvailable) {
      const message =
          'On-device transcription is unavailable. The audio was saved without a transcript.';
      setState(() {
        _session.transcriptionFailed(
          message: message,
          partialTranscript: '',
          fraction: 0,
        );
      });
      await _reportAndHandOff(message);
      return;
    }

    setState(() => _session.beginTranscription());
    await _runTranscription(path);
  }

  Future<void> _runTranscription(String path) async {
    try {
      final result = await _transcriber.transcribe(
        path: path,
        localeId: _localeId,
        onProgress: (update) {
          if (!mounted || _session.abandoned || _session.handedOff) return;
          setState(() => _session.updateProgress(update));
        },
      );
      if (!mounted || _session.abandoned || _session.handedOff) return;
      setState(() => _session.transcriptionSucceeded(result.transcript));
      // While the close confirmation is open, popping here would dismiss the
      // dialog instead of the sheet. _requestClose finishes the handoff.
      if (_confirmingClose) return;
      await _handOff();
    } on AudioTranscriptionException catch (e) {
      if (!mounted || _session.abandoned || _session.handedOff) return;
      final percent = (e.fraction * 100).round();
      final message =
          'Transcription stopped at $percent%. ${e.message} The audio and the words captured so far were saved.';
      setState(() {
        _session.transcriptionFailed(
          message: message,
          partialTranscript: e.partialTranscript,
          fraction: e.fraction,
        );
      });
      await _reportAndHandOff(message);
    } catch (e) {
      if (!mounted || _session.abandoned || _session.handedOff) return;
      const message =
          'Transcription could not finish. The audio was saved without a new transcript.';
      setState(() {
        _session.transcriptionFailed(
          message: message,
          partialTranscript: '',
          fraction: 0,
        );
      });
      await _reportAndHandOff(message);
    }
  }

  Future<void> _reportAndHandOff(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
    if (_confirmingClose) return;
    await _handOff();
  }

  Future<void> _handOff() async {
    if (_handingOff || _confirmingClose) return;
    final path = _audioPath;
    if (path == null || path.isEmpty) return;
    if (!await File(path).exists()) {
      if (!mounted) return;
      setState(() {
        _error = 'Recorded audio file was not found.';
        _status = 'Audio file missing';
      });
      return;
    }
    _handingOff = true;
    _session.markHandedOff();
    final result = VoiceNoteResult(
      audioPath: path,
      transcript: _session.transcript,
      mimeType: 'audio/mp4',
      fileName: path.split(Platform.pathSeparator).last,
    );
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _discard() async {
    if (_handingOff) return;
    _generation++;
    _ticker?.cancel();
    _session.markAbandoned();
    await _transcriber.cancel();
    await _releaseWakeLock();
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    final path = _audioPath;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _requestClose() async {
    if (_handingOff || _confirmingClose) return;
    if (!_hasWork) {
      Navigator.of(context).pop();
      return;
    }

    // The confirmation dialog and the sheet share a navigator. Hold any
    // deferred handoff until it closes so we never pop the dialog by mistake.
    _confirmingClose = true;
    String? choice;
    try {
      if (_session.isStopping || _session.isTranscribing) {
        choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              _session.isStopping
                  ? 'The recording is still being saved'
                  : 'Transcription is still running',
            ),
            content: const Text(
              'The finished audio is being processed on this device. Keep waiting to save the words, or discard the whole recording.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'wait'),
                child: const Text('Keep waiting'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'discard'),
                child: const Text('Discard audio'),
              ),
            ],
          ),
        );
      } else {
        final isRecording = _session.isRecording;
        final saveLabel = _session.canHandOff
            ? (_session.phase == VoiceNotePhase.failed
                  ? 'Save audio only'
                  : 'Save audio + transcript')
            : 'Save & transcribe';
        choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Keep this voice note?'),
            content: Text(
              isRecording
                  ? 'A recording is in progress. Stop it to transcribe the finished audio, or discard it.'
                  : 'The audio is ready. Save it with the words captured so far, or discard it.',
            ),
            actions: [
              if (isRecording)
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
                child: Text(saveLabel),
              ),
            ],
          ),
        );
      }
    } finally {
      _confirmingClose = false;
    }

    if (!mounted) return;
    if (choice == 'discard') {
      await _discard();
      return;
    }
    if (choice == 'save') {
      if (_session.canHandOff) {
        await _handOff();
      } else {
        await _stopAndSave();
      }
      return;
    }
    // Work may have finished while the dialog was open. The deferred handoff
    // was skipped then, so finish the close now.
    if (_session.canHandOff && !_session.abandoned && !_session.handedOff) {
      await _handOff();
    }
  }

  Future<void> _pickLocale() async {
    if (_languages.isEmpty) return;
    final chosen = await showLifelogSheet<SpeechLanguage>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(
            title: 'Transcription language',
            subtitle: 'Used by on-device speech recognition.',
          ),
          for (final language in _languages)
            ListTile(
              title: Text(language.name),
              subtitle: Text(language.id),
              selected: language.id == _localeId,
              onTap: () => Navigator.of(sheetContext).pop(language),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _localeId = chosen.id);
    final availability = await _transcriber.prepare(localeId: chosen.id);
    if (!mounted) return;
    setState(() => _onDeviceAvailable = availability.onDeviceAvailable);
  }

  String _elapsedLabel() {
    final start = _startedAt;
    if (start == null) return '0:00';
    final difference = DateTime.now().difference(start);
    final minutes = difference.inMinutes;
    final seconds = difference.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _statusText() {
    if (_session.isRecording) return 'Recording ${_elapsedLabel()}';
    if (_session.isStopping) return 'Finishing the recording';
    if (_session.isTranscribing) {
      return 'Transcribing ${_session.percentLabel}';
    }
    if (_session.phase == VoiceNotePhase.ready) return 'Transcription complete';
    if (_session.phase == VoiceNotePhase.failed) return 'Recording ready';
    return _status;
  }

  String _detailText() {
    if (_session.isRecording) {
      return 'The screen stays on while recording. Transcription starts as soon as you stop.';
    }
    if (_session.isStopping) {
      return 'Closing the audio file now. On-device transcription starts next.';
    }
    if (_session.isTranscribing) {
      return 'Reading the finished audio file on this device. Partial words are kept if the app is briefly hidden.';
    }
    if (_session.phase == VoiceNotePhase.failed) {
      return 'The audio and any words captured so far can still be saved.';
    }
    if (!_transcriberAvailable || !_onDeviceAvailable) {
      return 'Audio recording is available; on-device transcription is not.';
    }
    return 'Transcription runs on your device after recording ends.';
  }

  String _primaryLabel() {
    if (_handingOff) return 'Saving...';
    if (_session.isStopping) return 'Stopping...';
    if (_session.isRecording) return 'Stop & transcribe';
    if (_session.isTranscribing) {
      return 'Transcribing ${_session.percentLabel}';
    }
    if (_session.phase == VoiceNotePhase.failed) return 'Save audio only';
    if (_session.phase == VoiceNotePhase.ready) {
      return 'Save audio + transcript';
    }
    return _error != null ? 'Retry recording' : 'Start recording';
  }

  void _primaryAction() {
    if (_handingOff || _confirmingClose || _session.isStopping) return;
    if (_session.isRecording) {
      unawaited(_stopAndSave());
      return;
    }
    if (_session.phase == VoiceNotePhase.idle) {
      unawaited(_start());
      return;
    }
    if (_session.canHandOff) {
      unawaited(_handOff());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || !_session.isRecording) return;
    if (state == AppLifecycleState.paused) {
      setState(() {
        _status = 'Recording paused by the system; the audio file is safe.';
      });
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _status = 'Recording...');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _generation++;
    if (!_session.handedOff && !_session.abandoned) {
      // Stop late progress/result callbacks from mutating state while teardown
      // is in flight, whatever phase the session was in.
      _session.markAbandoned();
      if (_session.isTranscribing || _session.isStopping) {
        unawaited(_transcriber.cancel());
      }
      final path = _audioPath;
      if (path != null) {
        unawaited(() async {
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }());
      }
    }
    unawaited(_releaseWakeLock());
    unawaited(_transcriber.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final transcript = _session.transcript;

    return PopScope<bool>(
      canPop: !_hasWork && !_handingOff,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(
            title: 'Voice note',
            subtitle: 'Record audio, then transcribe the finished file on this device. Both can be saved to this entry.',
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
                      _session.isRecording
                          ? Icons.mic_rounded
                          : (_session.isTranscribing
                                ? Icons.graphic_eq_rounded
                                : Icons.mic_none_rounded),
                      color: _session.isRecording
                          ? context.scheme.error
                          : palette.mutedText,
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(
                        _statusText(),
                        style: text.bodyMedium?.copyWith(
                          color: _session.isBusy ? null : palette.mutedText,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _detailText(),
                    style: text.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                ),
                if (_session.isTranscribing) ...[
                  const SizedBox(height: Insets.sm),
                  LinearProgressIndicator(
                    value: _session.progress <= 0 ? null : _session.progress,
                    minHeight: 4,
                  ),
                ],
                if (_languages.length > 1)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed:
                          (_initializing ||
                              _session.isBusy ||
                              _audioPath != null)
                          ? null
                          : _pickLocale,
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
              transcript.isEmpty
                  ? (_session.isTranscribing
                        ? 'Transcribing the finished recording...'
                        : (_session.isRecording
                              ? 'Words will appear here after recording stops.'
                              : 'Your transcribed text will appear here.'))
                  : transcript,
              style: text.bodyMedium?.copyWith(
                color: transcript.isEmpty ? palette.dimText : null,
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
          if (_notice != null && _error == null) ...[
            const SizedBox(height: Insets.sm),
            Text(
              _notice!,
              style: text.bodySmall?.copyWith(color: palette.mutedText),
            ),
          ],
          if (_initializing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(Insets.md),
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  /// Rendered outside the scrollable body by [showLifelogSheet], above the
  /// keyboard and the app navigation bar.
  Widget buildFooter(BuildContext context) {
    // Recording stays active: its primary action is "Stop & transcribe".
    // Only phases that cannot accept another primary tap are disabled.
    final busy =
        _session.isStopping ||
        _session.isTranscribing ||
        _handingOff ||
        _confirmingClose ||
        _initializing;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _handingOff ? null : _requestClose,
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: FilledButton.icon(
            onPressed: busy || _initializing ? null : _primaryAction,
            icon: Icon(
              _session.isRecording
                  ? Icons.stop_rounded
                  : (_session.isTranscribing
                        ? Icons.hourglass_top_rounded
                        : Icons.mic_rounded),
            ),
            label: Text(_primaryLabel()),
          ),
        ),
      ],
    );
  }

  String _localeLabel() {
    if (_localeId == null) return 'Language: device default';
    final match = _languages
        .where((language) => language.id == _localeId)
        .firstOrNull;
    return 'Language: ${match?.name ?? _localeId}';
  }
}

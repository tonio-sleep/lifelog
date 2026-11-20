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

Future<VoiceNoteResult?> showVoiceNoteSheet(BuildContext context) {
  return showLifelogSheet<VoiceNoteResult>(
    context,
    builder: (_) => const _VoiceNoteSheet(),
  );
}

class _VoiceNoteSheet extends StatefulWidget {
  const _VoiceNoteSheet();

  @override
  State<_VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

class _VoiceNoteSheetState extends State<_VoiceNoteSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initializing = true;
  bool _recording = false;
  bool _saving = false;
  bool _speechAvailable = false;
  bool _speechListening = false;
  String _transcript = '';
  String _partial = '';
  String _status = 'Preparing microphone and transcription...';
  String? _error;
  String? _audioPath;
  DateTime? _startedAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
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
          onStatus: (s) {
            if (!mounted) return;
            setState(() {
              _speechListening = s == 'listening';
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _speechListening = false;
            });
          },
        );
      } catch (_) {
        _speechAvailable = false;
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
    if (_initializing || _recording || _saving) return;
    setState(() {
      _error = null;
      _transcript = '';
      _partial = '';
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
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      setState(() {
        _recording = true;
        _status = 'Recording...';
      });
      if (_speechAvailable) {
        try {
          await _speech.listen(
            onResult: (result) {
              if (!mounted) return;
              setState(() {
                _partial = result.recognizedWords.trim();
                if (result.finalResult && _partial.isNotEmpty) {
                  _transcript = _transcript.isEmpty
                      ? _partial
                      : '$_transcript $_partial';
                  _partial = '';
                }
              });
            },
            listenFor: const Duration(minutes: 30),
            pauseFor: const Duration(seconds: 8),
            partialResults: true,
            cancelOnError: false,
            listenMode: stt.ListenMode.dictation,
          );
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _error = 'Could not start recording: $e';
        _status = 'Could not start recording';
      });
    }
  }

  Future<void> _stopAndSave() async {
    if (!_recording || _saving) return;
    setState(() => _saving = true);
    try {
      _ticker?.cancel();
      if (_speechAvailable) {
        try {
          await _speech.stop();
        } catch (_) {}
      }
      String? path;
      try {
        path = await _recorder.stop();
      } catch (_) {
        path = _audioPath;
      }
      path ??= _audioPath;
      final finalTranscript = [
        _transcript.trim(),
        _partial.trim(),
      ].where((s) => s.isNotEmpty).join(' ').trim();
      if (path == null || path.isEmpty) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _recording = false;
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
          _error = 'Recorded audio file was not found.';
        });
        return;
      }
      final name = path.split(Platform.pathSeparator).last;
      if (!mounted) return;
      Navigator.of(context).pop(
        VoiceNoteResult(
          audioPath: path,
          transcript: finalTranscript,
          mimeType: 'audio/mp4',
          fileName: name,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _recording = false;
        _error = 'Could not save voice note: $e';
      });
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    try {
      if (_speechAvailable) {
        await _speech.cancel();
      }
    } catch (_) {}
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
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
    _ticker?.cancel();
    unawaited(_speech.stop());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final liveText = [
      _transcript.trim(),
      _partial.trim(),
    ].where((s) => s.isNotEmpty).join(' ').trim();

    return Column(
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
                    color: _recording ? context.scheme.error : palette.mutedText,
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
                    _speechListening
                        ? 'Live transcription is listening.'
                        : (_recording
                            ? 'Transcription may pause briefly; recording continues.'
                            : 'Transcription uses your device speech service when available.'),
                    style: text.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        Text('Transcript', style: text.labelMedium?.copyWith(color: palette.mutedText)),
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
          Text(_error!, style: text.bodySmall?.copyWith(color: context.scheme.error)),
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
                  onPressed: _saving ? null : _cancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_saving || (_error != null && !_recording))
                      ? null
                      : (_recording ? _stopAndSave : _start),
                  icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : (_recording ? 'Stop & save' : 'Start recording'),
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
    );
  }
}

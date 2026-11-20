import '../../integrations/speech/audio_transcriber.dart';

enum VoiceNotePhase { idle, recording, transcribing, ready, failed }

/// State for the deferred voice-note flow. Recording and transcription are
/// separate phases: transcription never starts until the audio file is closed.
class VoiceNoteSession {
  VoiceNotePhase _phase = VoiceNotePhase.idle;
  double _progress = 0;
  bool _progressEstimated = false;
  String _transcript = '';
  String? _error;
  bool _handedOff = false;
  bool _abandoned = false;

  VoiceNotePhase get phase => _phase;
  double get progress => _progress;
  bool get progressEstimated => _progressEstimated;
  String get transcript => _transcript;
  String? get error => _error;
  bool get handedOff => _handedOff;
  bool get abandoned => _abandoned;

  bool get isRecording => _phase == VoiceNotePhase.recording;
  bool get isTranscribing => _phase == VoiceNotePhase.transcribing;
  bool get isBusy => isRecording || isTranscribing;
  bool get canHandOff =>
      _phase == VoiceNotePhase.ready || _phase == VoiceNotePhase.failed;

  String get percentLabel {
    final value = (_progress * 100).round().clamp(0, 100);
    return '${_progressEstimated ? '~' : ''}$value%';
  }

  void beginRecording() {
    _phase = VoiceNotePhase.recording;
    _progress = 0;
    _progressEstimated = false;
    _transcript = '';
    _error = null;
    _handedOff = false;
    _abandoned = false;
  }

  void beginTranscription() {
    if (_phase != VoiceNotePhase.recording) return;
    _phase = VoiceNotePhase.transcribing;
    _progress = 0;
    _progressEstimated = true;
  }

  void recordingFailed(String message) {
    _phase = VoiceNotePhase.failed;
    _error = message;
  }

  void updateProgress(TranscriptionUpdate update) {
    if (_phase != VoiceNotePhase.transcribing) return;
    _progress = update.fraction.clamp(0.0, 1.0).toDouble();
    _progressEstimated = update.estimated;
    if (update.transcript.trim().isNotEmpty) {
      _transcript = update.transcript.trim();
    }
  }

  void transcriptionSucceeded(String transcript) {
    _phase = VoiceNotePhase.ready;
    _transcript = transcript.trim();
    _progress = 1;
    _progressEstimated = false;
    _error = null;
  }

  /// Keeps whatever partial transcript arrived before the failure so a failed
  /// recognition never throws away words the person already heard.
  void transcriptionFailed({
    required String message,
    required String partialTranscript,
    required double fraction,
  }) {
    _phase = VoiceNotePhase.failed;
    _error = message;
    final partial = partialTranscript.trim();
    if (partial.isNotEmpty) _transcript = partial;
    _progress = fraction.clamp(0.0, 1.0).toDouble();
    _progressEstimated = true;
  }

  void markHandedOff() {
    _handedOff = true;
  }

  void markAbandoned() {
    _abandoned = true;
  }
}

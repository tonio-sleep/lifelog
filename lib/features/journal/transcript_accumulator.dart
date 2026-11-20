/// Merges speech recognition events into one stable transcript.
///
/// `speech_to_text` ends a listening session on native pauses/timeouts and the
/// iOS implementation can emit cumulative text. Each listen session gets its
/// own [session] number so late callbacks from an ended session are ignored.
/// Final results from a new session are appended, while cumulative finals from
/// the same session replace what is already there instead of duplicating it.
class TranscriptAccumulator {
  String _finalText = '';
  String _partial = '';
  int _session = 0;

  /// Starts a fresh listen session. Previously finalised text is kept.
  int nextSession() => ++_session;

  int get session => _session;

  /// Clears everything. Only an explicit "Start recording" should call this.
  void reset() {
    _finalText = '';
    _partial = '';
    _session = 0;
  }

  /// Drops the in-progress partial for a new session without losing final text.
  void startNewSession() => _partial = '';

  /// Accepts a recognition event belonging to [eventSession].
  void addResult({
    required int eventSession,
    required String recognizedWords,
    required bool isFinal,
  }) {
    if (eventSession != _session) return;
    final words = recognizedWords.trim();
    if (words.isEmpty) {
      if (isFinal) _partial = '';
      return;
    }
    if (isFinal) {
      if (_finalText.isEmpty) {
        _finalText = words;
      } else if (words.startsWith(_finalText)) {
        // iOS can send the whole session again as a cumulative final.
        _finalText = words;
      } else if (!_finalText.startsWith(words)) {
        _finalText = '$_finalText $words';
      }
      _partial = '';
    } else {
      _partial = words;
    }
  }

  /// Promotes the last partial into final text when a session ends abruptly.
  void finalizePartial() {
    final words = _partial.trim();
    if (words.isEmpty) return;
    if (_finalText.isEmpty) {
      _finalText = words;
    } else if (!_finalText.endsWith(words)) {
      _finalText = '$_finalText $words';
    }
    _partial = '';
  }

  /// Final text plus the live partial, ready to display or save.
  String get text {
    final parts = <String>[
      if (_finalText.isNotEmpty) _finalText,
      if (_partial.isNotEmpty) _partial,
    ];
    return parts.join(' ').trim();
  }

  String get finalText => _finalText;

  String get partial => _partial;

  bool get isEmpty => text.isEmpty;
}

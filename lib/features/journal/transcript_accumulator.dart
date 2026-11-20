/// Merges speech recognition events into one stable transcript.
///
/// `speech_to_text` can emit cumulative text, and iOS may end a listening
/// session silently. Each listen session gets its own [session] number so late
/// callbacks from an ended session are ignored. Finals are tracked relative to
/// the current session so a cumulative final replaces the session's text while
/// a genuinely new word repeated in a later session is still kept.
class TranscriptAccumulator {
  String _finalText = '';
  String _partial = '';
  int _session = 0;

  /// Index in [_finalText] where the current session's final text begins.
  int _sessionStart = 0;

  /// The cumulative final text produced by the current session.
  String _sessionFinal = '';

  /// Starts a fresh listen session. Previously finalised text is kept.
  int nextSession() {
    _session++;
    _sessionStart = _finalText.length;
    _sessionFinal = '';
    _partial = '';
    return _session;
  }

  int get session => _session;

  /// Clears everything. Only an explicit "Start recording" should call this.
  void reset() {
    _finalText = '';
    _partial = '';
    _session = 0;
    _sessionStart = 0;
    _sessionFinal = '';
  }

  /// Drops the in-progress partial for a new session without losing final text.
  void startNewSession() => _partial = '';

  String _prefixBeforeSession() =>
      _finalText.substring(0, _sessionStart).trimRight();

  void _setSessionFinal(String text) {
    final prefix = _prefixBeforeSession();
    _finalText = [if (prefix.isNotEmpty) prefix, if (text.isNotEmpty) text]
        .join(' ');
    _sessionFinal = text;
  }

  /// Adds a final result, accounting for cumulative finals within a session.
  void _addFinal(String words) {
    if (_sessionFinal.isEmpty) {
      _setSessionFinal(words);
      return;
    }
    if (words == _sessionFinal) return;
    if (words.startsWith(_sessionFinal)) {
      // Cumulative iOS final: replace the whole session with the longer text.
      _setSessionFinal(words);
      return;
    }
    if (_sessionFinal.startsWith(words)) {
      // An older, shorter final arrived late. It adds no new information.
      return;
    }
    // A distinct final in the same session (common on Android).
    _setSessionFinal('$_sessionFinal $words');
  }

  /// Returns only the words in [words] not already finalised in this session.
  String _newPartial(String words) {
    if (_sessionFinal.isEmpty) return words;
    if (words.startsWith(_sessionFinal)) {
      return words.substring(_sessionFinal.length).trimLeft();
    }
    if (_sessionFinal.startsWith(words) || _finalText.endsWith(words)) return '';
    return words;
  }

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
      _addFinal(words);
      _partial = '';
    } else {
      _partial = _newPartial(words);
    }
  }

  /// Promotes the last partial into final text when a session ends abruptly.
  void finalizePartial() {
    final words = _partial.trim();
    _partial = '';
    if (words.isEmpty) return;
    _addFinal(words);
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

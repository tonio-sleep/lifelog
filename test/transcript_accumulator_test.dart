import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/features/journal/transcript_accumulator.dart';

void main() {
  test('partials and finals merge into one transcript', () {
    final transcript = TranscriptAccumulator();
    final session = transcript.nextSession();

    transcript
      ..addResult(
        eventSession: session,
        recognizedWords: 'hello',
        isFinal: false,
      )
      ..addResult(
        eventSession: session,
        recognizedWords: 'hello world',
        isFinal: true,
      )
      ..addResult(
        eventSession: session,
        recognizedWords: 'and more',
        isFinal: true,
      );

    expect(transcript.text, 'hello world and more');
  });

  test('cumulative iOS finals replace instead of duplicating', () {
    final transcript = TranscriptAccumulator();
    final session = transcript.nextSession();

    transcript.addResult(
      eventSession: session,
      recognizedWords: 'first phrase',
      isFinal: true,
    );
    transcript.addResult(
      eventSession: session,
      recognizedWords: 'first phrase continued',
      isFinal: true,
    );

    expect(transcript.text, 'first phrase continued');
  });

  test('a restarted session keeps earlier text and ignores stale callbacks', () {
    final transcript = TranscriptAccumulator();
    final first = transcript.nextSession();
    transcript.addResult(
      eventSession: first,
      recognizedWords: 'before pause',
      isFinal: true,
    );

    final second = transcript.nextSession();
    transcript.startNewSession();
    transcript.addResult(
      eventSession: first,
      recognizedWords: 'stale words',
      isFinal: true,
    );
    transcript.addResult(
      eventSession: second,
      recognizedWords: 'after pause',
      isFinal: true,
    );

    expect(transcript.text, 'before pause after pause');
  });

  test('the last partial is preserved when a session ends abruptly', () {
    final transcript = TranscriptAccumulator();
    final session = transcript.nextSession();
    transcript.addResult(
      eventSession: session,
      recognizedWords: 'almost lost',
      isFinal: false,
    );
    transcript.finalizePartial();
    expect(transcript.finalText, 'almost lost');
    expect(transcript.partial, isEmpty);
  });
}

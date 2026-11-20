import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/core/util/dates.dart';
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

  test('cumulative partials do not duplicate already-finalised words', () {
    final transcript = TranscriptAccumulator();
    final session = transcript.nextSession();

    transcript.addResult(
      eventSession: session,
      recognizedWords: 'one two',
      isFinal: true,
    );
    transcript.addResult(
      eventSession: session,
      recognizedWords: 'one two three',
      isFinal: false,
    );

    expect(transcript.text, 'one two three');

    transcript.finalizePartial();
    expect(transcript.finalText, 'one two three');
    expect(transcript.partial, isEmpty);
  });

  test('a partial shorter than the final text is ignored', () {
    final transcript = TranscriptAccumulator();
    final session = transcript.nextSession();

    transcript.addResult(
      eventSession: session,
      recognizedWords: 'alpha beta',
      isFinal: true,
    );
    transcript.addResult(
      eventSession: session,
      recognizedWords: 'alph',
      isFinal: false,
    );

    expect(transcript.text, 'alpha beta');
  });

  test('a word repeated in a later session is not mistaken for cumulative text', () {
    final transcript = TranscriptAccumulator();
    final first = transcript.nextSession();
    transcript.addResult(
      eventSession: first,
      recognizedWords: 'go now',
      isFinal: true,
    );

    final second = transcript.nextSession();
    transcript.addResult(
      eventSession: second,
      recognizedWords: 'go',
      isFinal: true,
    );

    expect(transcript.text, 'go now go');
  });

  test('a long dictation keeps every word exactly once', () {
    final transcript = TranscriptAccumulator();
    final words = List<String>.generate(60, (index) => 'word$index');

    for (var segment = 0; segment < 6; segment++) {
      final session = transcript.nextSession();
      transcript.startNewSession();
      final segmentWords = words.sublist(segment * 10, segment * 10 + 10);
      transcript.addResult(
        eventSession: session,
        recognizedWords: segmentWords.take(6).join(' '),
        isFinal: false,
      );
      transcript.addResult(
        eventSession: session,
        recognizedWords: segmentWords.join(' '),
        isFinal: true,
      );
    }

    expect(transcript.text, words.join(' '));
  });

  test('day helpers are stable across a DST transition', () {
    final before = DateTime(2026, 3, 7, 23);
    final after = DateTime(2026, 3, 8, 23);

    expect(dayEnd(before), DateTime(2026, 3, 8));
    expect(dayEnd(after), DateTime(2026, 3, 9));
    expect(
      relativeDayLabel(after, now: before),
      'Tomorrow',
    );
  });
}

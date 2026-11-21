import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/features/journal/voice_note_session.dart';
import 'package:lifelog/integrations/speech/audio_transcriber.dart';

void main() {
  group('deferred transcription progress', () {
    test('uses real word timings when the recognizer reports them', () {
      final fraction = transcriptionProgressFraction(
        recognizedSeconds: 15,
        durationSeconds: 60,
        hasTimedSegments: true,
        elapsedSeconds: 3,
      );
      expect(fraction, closeTo(0.25, 0.00001));
    });

    test('never reports more than 99 percent before the final result', () {
      final fraction = transcriptionProgressFraction(
        recognizedSeconds: 90,
        durationSeconds: 60,
        hasTimedSegments: true,
        elapsedSeconds: 30,
      );
      expect(fraction, 0.99);
    });

    test('falls back to a capped estimate before word timings arrive', () {
      final estimate = transcriptionProgressFraction(
        recognizedSeconds: 0,
        durationSeconds: 60,
        hasTimedSegments: false,
        elapsedSeconds: 6,
      );
      final capped = transcriptionProgressFraction(
        recognizedSeconds: 0,
        durationSeconds: 60,
        hasTimedSegments: false,
        elapsedSeconds: 120,
      );
      expect(estimate, closeTo(0.1, 0.00001));
      expect(capped, 0.9);
    });

    test('invalid audio duration does not invent progress', () {
      final fraction = transcriptionProgressFraction(
        recognizedSeconds: 10,
        durationSeconds: 0,
        hasTimedSegments: true,
        elapsedSeconds: 1,
      );
      expect(fraction, 0);
    });

    test('native progress events distinguish measured from estimated', () {
      final measured = TranscriptionUpdate.fromEvent(<String, dynamic>{
        'transcriptionId': 'one',
        'transcript': 'hello',
        'recognizedSeconds': 30.0,
        'durationSeconds': 60.0,
        'elapsedSeconds': 8.0,
        'hasTimedSegments': true,
        'isFinal': false,
      });
      final estimated = TranscriptionUpdate.fromEvent(<String, dynamic>{
        'transcriptionId': 'one',
        'transcript': 'hello',
        'recognizedSeconds': 0.0,
        'durationSeconds': 60.0,
        'elapsedSeconds': 6.0,
        'hasTimedSegments': false,
        'isFinal': false,
      });

      expect(measured.fraction, closeTo(0.5, 0.00001));
      expect(measured.estimated, isFalse);
      expect(estimated.fraction, closeTo(0.1, 0.00001));
      expect(estimated.estimated, isTrue);
    });

    test('platform errors keep the partial transcript and progress', () {
      final error = AudioTranscriptionException.fromPlatformException(
        PlatformException(
          code: 'RECOGNITION_FAILED',
          message: 'recognition stopped',
          details: <String, dynamic>{
            'transcript': 'words captured so far',
            'recognizedSeconds': 20.0,
            'durationSeconds': 40.0,
            'elapsedSeconds': 12.0,
            'hasTimedSegments': true,
          },
        ),
      );

      expect(error.partialTranscript, 'words captured so far');
      expect(error.fraction, closeTo(0.5, 0.00001));
      expect(error.message, contains('stopped'));
    });
  });

  group('voice note session state', () {
    test('transcription cannot start before the audio is finished', () {
      final session = VoiceNoteSession();
      session.beginTranscription();
      expect(session.isTranscribing, isFalse);
      expect(session.canHandOff, isFalse);
    });

    test('finished audio is transcribed with visible cumulative progress', () {
      final session = VoiceNoteSession();
      session.beginRecording();
      expect(session.isRecording, isTrue);
      expect(session.canHandOff, isFalse);

      session.beginStopping();
      session.beginTranscription();
      expect(session.isTranscribing, isTrue);
      expect(session.percentLabel, '~0%');

      session.updateProgress(
        const TranscriptionUpdate(
          transcriptionId: 'one',
          transcript: 'hello world',
          fraction: 0.42,
          estimated: false,
          isFinal: false,
        ),
      );
      expect(session.transcript, 'hello world');
      expect(session.percentLabel, '42%');

      session.transcriptionSucceeded('hello world again');
      expect(session.phase, VoiceNotePhase.ready);
      expect(session.canHandOff, isTrue);
      expect(session.progress, 1);
      expect(session.percentLabel, '100%');
      expect(session.transcript, 'hello world again');

      session.markHandedOff();
      expect(session.handedOff, isTrue);
    });

    test(
      'a failed transcription keeps captured words and can still hand off',
      () {
        final session = VoiceNoteSession();
        session.beginRecording();
        session.beginStopping();
        session.beginTranscription();
        session.updateProgress(
          const TranscriptionUpdate(
            transcriptionId: 'one',
            transcript: 'partial words',
            fraction: 0.7,
            estimated: true,
            isFinal: false,
          ),
        );

        session.transcriptionFailed(
          message: 'Transcription stopped.',
          partialTranscript: 'partial words captured',
          fraction: 0.7,
        );

        expect(session.phase, VoiceNotePhase.failed);
        expect(session.canHandOff, isTrue);
        expect(session.error, contains('stopped'));
        expect(session.transcript, 'partial words captured');
        expect(session.percentLabel, '~70%');
      },
    );

    test('stopping is an exclusive phase that blocks a second stop', () {
      final session = VoiceNoteSession();
      session.beginRecording();
      session.beginStopping();

      expect(session.phase, VoiceNotePhase.stopping);
      expect(session.isBusy, isTrue);
      expect(session.isRecording, isFalse);
      expect(session.canHandOff, isFalse);

      session.beginStopping();
      session.beginRecording();
      expect(session.phase, VoiceNotePhase.stopping);

      session.beginTranscription();
      expect(session.isTranscribing, isTrue);
    });

    test('abandoned sessions ignore late native progress and results', () {
      final session = VoiceNoteSession();
      session.beginRecording();
      session.beginStopping();
      session.beginTranscription();
      session.updateProgress(
        const TranscriptionUpdate(
          transcriptionId: 'one',
          transcript: 'partial words',
          fraction: 0.4,
          estimated: true,
          isFinal: false,
        ),
      );
      session.markAbandoned();

      session.updateProgress(
        const TranscriptionUpdate(
          transcriptionId: 'one',
          transcript: 'late words',
          fraction: 0.9,
          estimated: false,
          isFinal: false,
        ),
      );
      session.transcriptionSucceeded('late final words');

      expect(session.transcript, 'partial words');
      expect(session.phase, VoiceNotePhase.transcribing);
      expect(session.canHandOff, isFalse);
    });

    test('discard marks the recording abandoned', () {
      final session = VoiceNoteSession();
      session.beginRecording();
      session.markAbandoned();
      expect(session.abandoned, isTrue);
    });
  });
}

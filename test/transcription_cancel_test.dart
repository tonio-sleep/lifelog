import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/integrations/speech/audio_transcriber.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(transcriptionMethodChannel);
  final nativeCalls = <String>[];

  Completer<Map<String, dynamic>> neverCompletes() =>
      Completer<Map<String, dynamic>>();

  setUp(() {
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          nativeCalls.add(call.method);
          switch (call.method) {
            case 'transcribe':
              // A cancelled native task may never send its result back.
              return neverCompletes().future;
            case 'cancel':
            case 'prepare':
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test(
    'cancel completes an in-flight transcription even if native never returns',
    () async {
      final transcriber = AudioTranscriber(methodChannel: methodChannel);
      final future = transcriber.transcribe(
        path: '/tmp/voice.m4a',
        localeId: 'en-US',
        onProgress: (_) {},
      );
      final expectation = expectLater(
        future,
        throwsA(
          isA<AudioTranscriptionException>().having(
            (error) => error.code,
            'code',
            'CANCELLED',
          ),
        ),
      );

      await transcriber.cancel();
      await expectation;

      expect(nativeCalls, contains('cancel'));
    },
  );

  test(
    'dispose cancels the native task and closes a pending transcription',
    () async {
      final transcriber = AudioTranscriber(methodChannel: methodChannel);
      final future = transcriber.transcribe(
        path: '/tmp/voice.m4a',
        localeId: null,
        onProgress: (_) {},
      );
      final expectation = expectLater(
        future,
        throwsA(
          isA<AudioTranscriptionException>().having(
            (error) => error.code,
            'code',
            'DISPOSED',
          ),
        ),
      );

      await transcriber.dispose();
      await expectation;

      expect(nativeCalls, contains('cancel'));
    },
  );

  test(
    'a transcription started after dispose never calls native transcribe',
    () async {
      final transcriber = AudioTranscriber(methodChannel: methodChannel);
      await transcriber.dispose();
      nativeCalls.clear();

      final future = transcriber.transcribe(
        path: '/tmp/voice.m4a',
        localeId: null,
        onProgress: (_) {},
      );

      await expectLater(
        future,
        throwsA(
          isA<AudioTranscriptionException>().having(
            (error) => error.code,
            'code',
            'DISPOSED',
          ),
        ),
      );
      expect(nativeCalls, isEmpty);
    },
  );
}

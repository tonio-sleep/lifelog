import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/core/backup/backup_service.dart';
import 'package:lifelog/core/crypto/crypto_service.dart';
import 'package:lifelog/core/storage/media_playback.dart';
import 'package:lifelog/core/storage/media_store.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/integrations/maps/map_models.dart';
import 'package:lifelog/integrations/maps/map_platform.dart';
import 'package:path/path.dart' as p;

Directory createFeatureTestDir(String prefix) {
  final dir = Directory(
    p.join(
      Directory.systemTemp.path,
      '$prefix${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  dir.createSync(recursive: true);
  return dir;
}

CryptoService featureTestCrypto() => CryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native map data', () {
    const channel = MethodChannel('lifelog/map/search');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'search':
            return <Map<String, dynamic>>[
              {
                'latitude': 51.5034,
                'longitude': -0.1276,
                'title': '10 Downing Street',
                'subtitle': 'London, UK',
              },
            ];
          case 'reverse':
            return <String, dynamic>{
              'latitude': (call.arguments as Map)['latitude'],
              'longitude': (call.arguments as Map)['longitude'],
              'title': 'Buckingham Palace',
              'subtitle': 'London, UK',
            };
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('address search and reverse geocoding parse native results', () async {
      final service = MapSearchService();
      final results = await service.search('10 Downing Street');

      expect(results, hasLength(1));
      expect(results.single.title, '10 Downing Street');
      expect(results.single.subtitle, 'London, UK');
      expect(results.single.latitude, closeTo(51.5034, 0.00001));

      final reverse = await service.reverseGeocode(51.501, -0.141);
      expect(reverse, isNotNull);
      expect(reverse!.title, 'Buckingham Palace');
      expect(reverse.latitude, 51.501);
      expect(reverse.longitude, -0.141);
    });

    test('saved pins, inferred stops and route points are sent to MapKit', () {
      final data = LifelogMapData(
        places: [
          MapPoint(
            id: 'home',
            latitude: 51.5,
            longitude: -0.12,
            name: 'Home',
            kind: 'place',
          ),
        ],
        stops: [
          MapPoint(
            latitude: 51.51,
            longitude: -0.13,
            name: 'Brief stop',
            kind: 'stop',
          ),
        ],
        route: const [
          MapPoint(latitude: 51.49, longitude: -0.11, kind: 'route'),
          MapPoint(latitude: 51.52, longitude: -0.14, kind: 'route'),
        ],
        current: const MapPoint(
          latitude: 51.501,
          longitude: -0.126,
          kind: 'current',
        ),
        mapType: LifelogMapType.hybrid,
        crosshair: true,
      );

      final json = data.toJson();
      expect(json['places'], hasLength(1));
      expect((json['places'] as List).first['name'], 'Home');
      expect(json['stops'], hasLength(1));
      expect(json['route'], hasLength(2));
      expect((json['current'] as Map)['latitude'], 51.501);
      expect(json['mapType'], 'hybrid');
      expect(json['crosshair'], isTrue);
    });
  });

  group('audio and video media', () {
    test('import, backup, restore and playback files preserve every kind',
        () async {
      final root = createFeatureTestDir('lifelog-media-kinds-');
      addTearDown(() => root.deleteSync(recursive: true));
      final store = MediaStore(
        directory: Directory(p.join(root.path, 'vault')),
        crypto: featureTestCrypto(),
      );
      final audioBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
      final videoBytes = Uint8List.fromList([9, 8, 7, 6, 5, 4, 3]);

      final audio = await store.importBytes(
        bytes: audioBytes,
        fileName: 'voice.m4a',
        mimeType: 'audio/mp4',
      );
      final video = await store.importBytes(
        bytes: videoBytes,
        fileName: 'walk.mp4',
        mimeType: 'video/mp4',
      );

      expect(audio.isAudio, isTrue);
      expect(audio.isVideo, isFalse);
      expect(video.isVideo, isTrue);
      expect(video.isAudio, isFalse);
      expect(audio.hasThumbnail, isFalse);
      expect(video.hasThumbnail, isFalse);
      expect(await store.readOriginal(audio), equals(audioBytes));
      expect(await store.readOriginal(video), equals(videoBytes));

      final playbackDir = Directory(p.join(root.path, 'playback'));
      final playback = await materializePlaybackFile(
        store,
        video,
        playbackDir,
      );
      expect(p.extension(playback.file.path), '.mp4');
      expect(await playback.file.readAsBytes(), equals(videoBytes));
      await playback.delete();
      expect(await playback.file.exists(), isFalse);

      const backups = BackupService();
      final archive = Archive(media: [audio, video]);
      final bytes = await backups.createBackup(
        archive: archive,
        passphrase: 'correct horse battery',
        mediaStore: store,
      );
      final restored = await backups.readBackup(
        bytes: bytes,
        passphrase: 'correct horse battery',
      );

      expect(restored.includesMedia, isTrue);
      expect(restored.mediaFiles, hasLength(2));
      final byId = <String, Uint8List>{
        for (final file in restored.mediaFiles) file.id: file.originalBytes,
      };
      expect(byId[audio.id], equals(audioBytes));
      expect(byId[video.id], equals(videoBytes));
      expect(
        restored.archive.media.map((item) => item.mimeType),
        containsAll(<String>['audio/mp4', 'video/mp4']),
      );
      expect(
        restored.archive.media.map((item) => item.originalName),
        containsAll(<String>['voice.m4a', 'walk.mp4']),
      );
    });
  });
}

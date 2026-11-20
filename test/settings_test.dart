import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/domain/models/settings.dart';

void main() {
  test('remembered cloud passphrase survives a settings round trip', () {
    final settings = AppSettings(cloudflarePassphraseCipher: 'encrypted-value');

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.cloudflarePassphraseCipher, 'encrypted-value');
    expect(
      restored.copyWith(clearCloudflarePassphrase: true).cloudflarePassphraseCipher,
      isNull,
    );
  });

  test('older settings without a passphrase cipher still load', () {
    final json = AppSettings().toJson()..remove('cloudflarePassphraseCipher');

    expect(
      AppSettings.fromJson(json).cloudflarePassphraseCipher,
      isNull,
    );
  });
}

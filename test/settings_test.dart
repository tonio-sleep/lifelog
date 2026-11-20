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

  test('a remembered passphrase is account-scoped and cleared on sign-out', () {
    final settings = AppSettings(
      cloudflareUsername: 'me@example.com',
      cloudflarePassphraseCipher: 'encrypted-value',
      cloudflarePassphraseOwner: 'me@example.com',
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.cloudflarePassphraseOwner, 'me@example.com');
    expect(restored.hasRememberedCloudflarePassphrase, isTrue);

    final switched = restored.copyWith(cloudflareUsername: 'other');
    expect(switched.hasRememberedCloudflarePassphrase, isFalse);
    final signedOut = restored.copyWith(clearCloudflareSession: true);
    expect(signedOut.cloudflarePassphraseCipher, isNull);
    expect(signedOut.cloudflarePassphraseOwner, isNull);
  });

  test('legacy settings without an owner never reuse a passphrase', () {
    final json = AppSettings(
      cloudflareUsername: 'me',
      cloudflarePassphraseCipher: 'encrypted-value',
    ).toJson()
      ..remove('cloudflarePassphraseOwner');
    final restored = AppSettings.fromJson(json);

    expect(restored.cloudflarePassphraseCipher, 'encrypted-value');
    expect(restored.hasRememberedCloudflarePassphrase, isFalse);
  });
}

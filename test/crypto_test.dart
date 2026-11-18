import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/core/crypto/crypto_service.dart';

void main() {
  test('AES-256-GCM round trip preserves bytes and string content', () async {
    final key = SecretKey(List<int>.generate(32, (index) => index));
    final crypto = CryptoService(key);

    final clear = Uint8List.fromList([0, 1, 2, 250, 255]);
    final envelope = await crypto.encryptBytes(clear, aad: 'test-aad');
    final decrypted = await crypto.decryptBytes(envelope, aad: 'test-aad');

    expect(decrypted, equals(clear));

    final text = await crypto.encryptString('private journal', aad: 'entry');
    expect(await crypto.decryptString(text, aad: 'entry'), 'private journal');
  });

  test('ciphertext is authenticated and tampering fails', () async {
    final key = SecretKey(List<int>.generate(32, (index) => 255 - index));
    final crypto = CryptoService(key);
    final envelope = Uint8List.fromList(
      await crypto.encryptBytes([9, 9, 9], aad: 'aad'),
    );

    final tampered = Uint8List.fromList(envelope);
    tampered[tampered.length - 1] ^= 0x01;

    expect(
      () => crypto.decryptBytes(tampered, aad: 'aad'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    expect(
      () => crypto.decryptBytes(envelope, aad: 'wrong-aad'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('PIN hashes are salted and verifiable', () async {
    final first = await PinHasher.create('1234');
    final second = await PinHasher.create('1234');

    expect(first.$1, isNot(equals(second.$1)));
    expect(first.$2, isNot(equals(second.$2)));
    expect(
      await PinHasher.verify(pin: '1234', salt: first.$1, hash: first.$2),
      isTrue,
    );
    expect(
      await PinHasher.verify(pin: '4321', salt: first.$1, hash: first.$2),
      isFalse,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/integrations/cloudflare/cloudflare_sync_service.dart';

void main() {
  test('accepts the worker expiresIn field', () {
    final session = CloudflareSession.fromJson({
      'token': 'abc',
      'username': 'me',
      'expiresIn': 2592000,
      'obtainedAt': '2026-01-01T00:00:00.000Z',
    });
    expect(session.expiresInSeconds, 2592000);
  });

  test('still reads legacy sessions stored with expiresInSeconds', () {
    final session = CloudflareSession.fromJson({
      'token': 'abc',
      'username': 'me',
      'expiresInSeconds': 120,
      'obtainedAt': '2026-01-01T00:00:00.000Z',
    });
    expect(session.expiresInSeconds, 120);
  });

  test('round trips the expiry used by the status card', () {
    final session = CloudflareSession(
      token: 'abc',
      username: 'me',
      expiresInSeconds: 90,
      obtainedAt: DateTime.utc(2026),
    );
    final restored = CloudflareSession.fromJson(session.toJson());
    expect(restored.expiresInSeconds, 90);
    expect(restored.obtainedAt, DateTime.utc(2026));
  });
}

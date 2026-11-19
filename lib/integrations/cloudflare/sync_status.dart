import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/settings_provider.dart';
import '../../domain/models/settings.dart';
import 'cloudflare_sync_service.dart';

/// Where the optional cloud account stands. The UI reads this instead of
/// inferring state from scattered settings fields, so every screen shows the
/// same thing.
///
/// None of these states touch local data. They only decide what the sync card
/// offers.
enum SyncPhase {
  /// No account on this device.
  signedOut,

  /// Signed in with a session the server should accept.
  active,

  /// Signed in, but the token runs out within [SyncStatus.soonWindow].
  expiresSoon,

  /// The token is past its expiry, or the server rejected it (HTTP 401).
  expired,
}

class SyncStatus {
  const SyncStatus({
    required this.signedIn,
    this.username,
    this.host,
    this.lastSyncAt,
    this.expiresAt,
    this.rejected = false,
  });

  /// How far ahead to warn. Worker sessions last 30 days.
  static const soonWindow = Duration(days: 3);

  final bool signedIn;
  final String? username;
  final String? host;
  final DateTime? lastSyncAt;

  /// From the stored session (`obtainedAt + expiresInSeconds`). Null when the
  /// server did not say.
  final DateTime? expiresAt;

  /// The server answered 401 for the current session.
  final bool rejected;

  /// Evaluated on read so a long-running app crosses thresholds without a
  /// timer.
  SyncPhase get phase {
    if (!signedIn) return SyncPhase.signedOut;
    if (rejected) return SyncPhase.expired;
    final expiry = expiresAt;
    if (expiry == null) return SyncPhase.active;
    final left = expiry.difference(DateTime.now());
    if (left <= Duration.zero) return SyncPhase.expired;
    if (left < soonWindow) return SyncPhase.expiresSoon;
    return SyncPhase.active;
  }

  /// A backup or restore can be attempted.
  bool get canSync =>
      phase == SyncPhase.active || phase == SyncPhase.expiresSoon;

  /// Whole days left on the session, when known and still positive.
  int? get daysLeft {
    final expiry = expiresAt;
    if (expiry == null) return null;
    final left = expiry.difference(DateTime.now());
    if (left <= Duration.zero) return null;
    return (left.inHours / 24).ceil();
  }

  static String? hostOf(String? url) {
    final uri = Uri.tryParse((url ?? '').trim());
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host;
  }

  /// Synchronous status from settings alone (no expiry knowledge). Used until
  /// the stored session has been read, so the card never flickers.
  factory SyncStatus.fromSettings(
    AppSettings settings, {
    DateTime? rejectedSession,
  }) {
    return SyncStatus(
      signedIn: settings.cloudflareConnected,
      username: settings.cloudflareUsername,
      host: hostOf(settings.cloudflareWorkerUrl),
      lastSyncAt: settings.cloudflareLastSyncAt,
      rejected:
          rejectedSession != null &&
          rejectedSession == settings.cloudflareConnectedAt,
    );
  }
}

/// Remembers which session the server refused, so the UI can say "expired"
/// without deleting the account. A fresh sign-in gets a new `connectedAt` and
/// is therefore no longer considered rejected: nothing needs resetting.
class SyncSessionRejected extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void reject() {
    state = ref.read(settingsProvider).cloudflareConnectedAt;
  }
}

final syncSessionRejectedProvider =
    NotifierProvider<SyncSessionRejected, DateTime?>(SyncSessionRejected.new);

/// Full status, including the session expiry read from encrypted storage.
final syncStatusProvider = FutureProvider<SyncStatus>((ref) async {
  // Only the fields that matter, so unrelated setting changes (theme, week
  // start) do not trigger a decrypt.
  ref.watch(
    settingsProvider.select(
      (s) => (
        s.cloudflareSessionCipher,
        s.cloudflareWorkerUrl,
        s.cloudflareUsername,
        s.cloudflareConnectedAt,
        s.cloudflareLastSyncAt,
      ),
    ),
  );
  final settings = ref.read(settingsProvider);
  final rejectedSession = ref.watch(syncSessionRejectedProvider);
  final base = SyncStatus.fromSettings(
    settings,
    rejectedSession: rejectedSession,
  );
  if (!base.signedIn) return base;

  final json = await ref
      .read(settingsProvider.notifier)
      .cloudflareSessionJson();
  if (json == null) return base;
  try {
    final session = CloudflareSession.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );
    final obtained = session.obtainedAt;
    final seconds = session.expiresInSeconds;
    final expiresAt = (obtained != null && seconds != null)
        ? obtained.add(Duration(seconds: seconds))
        : null;
    return SyncStatus(
      signedIn: true,
      username: base.username,
      host: base.host,
      lastSyncAt: base.lastSyncAt,
      expiresAt: expiresAt,
      rejected: base.rejected,
    );
  } catch (_) {
    return base;
  }
});

/// Latest known status: the full one when loaded, otherwise the synchronous
/// one built from settings.
SyncStatus watchSyncStatus(WidgetRef ref) {
  final settings = ref.watch(settingsProvider);
  final rejected = ref.watch(syncSessionRejectedProvider);
  return ref.watch(syncStatusProvider).value ??
      SyncStatus.fromSettings(settings, rejectedSession: rejected);
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/crypto/crypto_service.dart';
import '../../domain/models/settings.dart';
import 'providers.dart';

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends Notifier<AppSettings> {
  static const _apiKeyAad = 'lifelog-lastfm-key-v1';

  @override
  AppSettings build() => ref.watch(appServicesProvider).settings;

  Future<void> update(
    AppSettings Function(AppSettings current) change,
  ) async {
    final next = change(state);
    state = next;
    await ref.read(appServicesProvider).settingsStore.save(next);
  }

  Future<void> setThemeMode(AppThemeMode mode) =>
      update((current) => current.copyWith(themeMode: mode));

  Future<void> setWeekStartsMonday(bool value) =>
      update((current) => current.copyWith(weekStartsMonday: value));

  Future<void> setShowArtwork(bool value) =>
      update((current) => current.copyWith(showArtwork: value));

  Future<void> setLocationTrackingEnabled(bool value) =>
      update((current) => current.copyWith(locationTrackingEnabled: value));

  Future<void> completeOnboarding() =>
      update((current) => current.copyWith(onboardingComplete: true));

  Future<void> resetOnboarding() =>
      update((current) => current.copyWith(onboardingComplete: false));

  Future<void> connectLastfm({
    required String username,
    String apiKey = '',
  }) async {
    final key = apiKey.trim();
    final cipher = key.isEmpty
        ? null
        : await ref
            .read(appServicesProvider)
            .crypto
            .encryptString(key, aad: _apiKeyAad);
    await update(
      (current) => current.copyWith(
        lastfmUsername: username.trim(),
        lastfmApiKeyCipher: cipher,
        clearLastfmApiKeyCipher: key.isEmpty,
        lastfmConnectedAt: DateTime.now(),
      ),
    );
  }

  Future<String?> lastfmApiKey() async {
    final cipher = state.lastfmApiKeyCipher;
    if (cipher == null) return null;
    try {
      return await ref
          .read(appServicesProvider)
          .crypto
          .decryptString(cipher, aad: _apiKeyAad);
    } catch (_) {
      return null;
    }
  }

  Future<void> recordLastfmSync(DateTime at, DateTime? oldest) => update(
    (current) => current.copyWith(
      lastfmLastSync: at,
      lastfmLastSyncFrom: oldest,
    ),
  );

  Future<void> disconnectLastfm() => update(
    (current) => current.copyWith(clearLastfmCredentials: true),
  );

  Future<void> setPin(String pin) async {
    final (salt, hash) = await PinHasher.create(pin);
    await update(
      (current) => current.copyWith(
        lockEnabled: true,
        pinSalt: salt,
        pinHash: hash,
      ),
    );
  }

  Future<void> disablePin() => update(
    (current) => current.copyWith(
      lockEnabled: false,
      clearPin: true,
    ),
  );

  Future<void> setAutoLockMinutes(int minutes) => update(
    (current) => current.copyWith(autoLockMinutes: minutes.clamp(0, 240)),
  );

  Future<void> setTodaySections(List<String> sections) => update(
    (current) => current.copyWith(todaySections: sections),
  );

  Future<bool> verifyPin(String pin) async {
    final salt = state.pinSalt;
    final hash = state.pinHash;
    if (salt == null || hash == null) return true;
    return PinHasher.verify(pin: pin, salt: salt, hash: hash);
  }

  Future<void> markBackup(DateTime at) =>
      update((current) => current.copyWith(lastBackupAt: at));

  Future<void> setBackupFolderPath(String path) =>
      update((current) => current.copyWith(backupFolderPath: path));

  Future<void> clearBackupFolderPath() =>
      update((current) => current.copyWith(clearBackupFolderPath: true));

  // --- Reminders (in-app) ---

  Future<void> saveReminder(ReminderItem reminder) => update((current) {
        final list = [...current.reminders];
        final index = list.indexWhere((r) => r.id == reminder.id);
        if (index >= 0) {
          list[index] = reminder;
        } else {
          list.add(reminder);
        }
        list.sort((a, b) {
          final at = a.hour * 60 + a.minute;
          final bt = b.hour * 60 + b.minute;
          return at.compareTo(bt);
        });
        return current.copyWith(reminders: list);
      });

  Future<void> toggleReminder(String id, bool enabled) => update((current) {
        final list = current.reminders
            .map((r) => r.id == id ? r.copyWith(enabled: enabled) : r)
            .toList();
        return current.copyWith(reminders: list);
      });

  Future<void> deleteReminder(String id) => update((current) {
        return current.copyWith(
          reminders: current.reminders.where((r) => r.id != id).toList(),
        );
      });

  // --- Cloudflare sync ---

  static const _cloudflareSessionAad = 'lifelog-cloudflare-session-v1';
  static const _cloudflarePassphraseAad = 'lifelog-cloudflare-passphrase-v1';

  Future<void> setCloudflareWorkerUrl(String url) => update(
        (current) => current.copyWith(
          cloudflareWorkerUrl: url.trim(),
        ),
      );

  /// Stores an authenticated Cloudflare session (encrypted at rest on device).
  /// [sessionJson] should contain the session token and minimal metadata.
  Future<void> saveCloudflareSession({
    required String workerUrl,
    required String username,
    required String sessionJson,
  }) async {
    final cipher = await ref
        .read(appServicesProvider)
        .crypto
        .encryptString(sessionJson, aad: _cloudflareSessionAad);
    await update(
      (current) => current.copyWith(
        cloudflareWorkerUrl: workerUrl.trim(),
        cloudflareUsername: username.trim(),
        cloudflareSessionCipher: cipher,
        cloudflareConnectedAt: DateTime.now(),
        cloudflareSetupDone: true,
      ),
    );
  }

  Future<String?> cloudflareSessionJson() async {
    final cipher = state.cloudflareSessionCipher;
    if (cipher == null) return null;
    try {
      return await ref
          .read(appServicesProvider)
          .crypto
          .decryptString(cipher, aad: _cloudflareSessionAad);
    } catch (_) {
      return null;
    }
  }

  /// Returns the backup passphrase remembered on this device, if any.
  Future<String?> cloudflareBackupPassphrase() async {
    final cipher = state.cloudflarePassphraseCipher;
    if (cipher == null || cipher.trim().isEmpty) return null;
    try {
      return await ref
          .read(appServicesProvider)
          .crypto
          .decryptString(cipher, aad: _cloudflarePassphraseAad);
    } catch (_) {
      return null;
    }
  }

  Future<void> rememberCloudflareBackupPassphrase(String passphrase) async {
    final cipher = await ref
        .read(appServicesProvider)
        .crypto
        .encryptString(passphrase, aad: _cloudflarePassphraseAad);
    await update(
      (current) => current.copyWith(cloudflarePassphraseCipher: cipher),
    );
  }

  Future<void> forgetCloudflareBackupPassphrase() => update(
        (current) =>
            current.copyWith(clearCloudflarePassphrase: true),
      );

  Future<void> recordCloudflareSync(DateTime at) => update(
        (current) => current.copyWith(cloudflareLastSyncAt: at),
      );

  Future<void> disconnectCloudflareSync() =>
      update((current) => current.copyWith(clearCloudflareSession: true));

  Future<void> clearCloudflareWorkerUrl() => update(
        (current) => current.copyWith(
          clearCloudflareWorkerUrl: true,
          clearCloudflareSession: true,
        ),
      );

  Future<void> hideInsightCategory(String category, bool hidden) => update(
    (current) => current.copyWith(
      hiddenInsightCategories: hidden
          ? {...current.hiddenInsightCategories, category}.toList()
          : current.hiddenInsightCategories
                .where((c) => c != category)
                .toList(),
    ),
  );
}

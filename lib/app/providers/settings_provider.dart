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

  Future<void> completeOnboarding() =>
      update((current) => current.copyWith(onboardingComplete: true));

  Future<void> resetOnboarding() =>
      update((current) => current.copyWith(onboardingComplete: false));

  Future<void> connectLastfm({
    required String username,
    required String apiKey,
  }) async {
    final cipher = await ref
        .read(appServicesProvider)
        .crypto
        .encryptString(apiKey.trim(), aad: _apiKeyAad);
    await update(
      (current) => current.copyWith(
        lastfmUsername: username.trim(),
        lastfmApiKeyCipher: cipher,
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

  // --- Google Drive sync ---

  static const _googleAuthAad = 'lifelog-google-auth-v1';

  Future<void> setGoogleClientConfig({
    required String clientId,
    String clientSecret = '',
  }) => update(
    (current) => current.copyWith(
      googleClientId: clientId.trim(),
      googleClientSecret: clientSecret.trim(),
    ),
  );

  Future<void> saveGoogleAuth({
    required String accountEmail,
    required String authJson,
    String? driveFolderId,
    String? driveFileId,
  }) async {
    final cipher = await ref
        .read(appServicesProvider)
        .crypto
        .encryptString(authJson, aad: _googleAuthAad);
    await update(
      (current) => current.copyWith(
        googleAccountEmail: accountEmail,
        googleAuthCipher: cipher,
        googleConnectedAt: DateTime.now(),
        googleDriveFolderId: driveFolderId ?? current.googleDriveFolderId,
        googleDriveFileId: driveFileId ?? current.googleDriveFileId,
      ),
    );
  }

  Future<String?> googleAuthJson() async {
    final cipher = state.googleAuthCipher;
    if (cipher == null) return null;
    return ref
        .read(appServicesProvider)
        .crypto
        .decryptString(cipher, aad: _googleAuthAad);
  }

  Future<void> updateGoogleAuthCipher(String authJson) async {
    final cipher = await ref
        .read(appServicesProvider)
        .crypto
        .encryptString(authJson, aad: _googleAuthAad);
    await update((current) => current.copyWith(googleAuthCipher: cipher));
  }

  Future<void> recordGoogleSync(DateTime at, {String? driveFileId, String? driveFolderId}) =>
      update(
        (current) => current.copyWith(
          googleLastSyncAt: at,
          googleDriveFileId: driveFileId ?? current.googleDriveFileId,
          googleDriveFolderId: driveFolderId ?? current.googleDriveFolderId,
        ),
      );

  Future<void> disconnectGoogleDrive() =>
      update((current) => current.copyWith(clearGoogleAuth: true));

  Future<void> clearGoogleClientConfig() => update(
        (current) => current.copyWith(
          clearGoogleClientId: true,
          clearGoogleClientSecret: true,
          clearGoogleAuth: true,
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

enum AppThemeMode {
  system,
  light,
  dark;

  String get label => switch (this) {
        AppThemeMode.system => 'System',
        AppThemeMode.light => 'Light',
        AppThemeMode.dark => 'Dark',
      };
}

enum ReminderRepeat {
  once,
  daily;

  String get label => switch (this) {
        ReminderRepeat.once => 'Once',
        ReminderRepeat.daily => 'Daily',
      };

  static ReminderRepeat tryParse(String? value) {
    for (final v in ReminderRepeat.values) {
      if (v.name == value) return v;
    }
    return ReminderRepeat.daily;
  }
}

/// A simple in-app reminder (time + message) stored locally.
class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.title,
    this.note = '',
    required this.hour,
    required this.minute,
    this.enabled = true,
    this.repeat = ReminderRepeat.daily,
  });

  final String id;
  final String title;
  final String note;
  final int hour;
  final int minute;
  final bool enabled;
  final ReminderRepeat repeat;

  String get timeLabel {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final suffix = hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $suffix';
  }

  ReminderItem copyWith({
    String? title,
    String? note,
    int? hour,
    int? minute,
    bool? enabled,
    ReminderRepeat? repeat,
  }) {
    return ReminderItem(
      id: id,
      title: title ?? this.title,
      note: note ?? this.note,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      enabled: enabled ?? this.enabled,
      repeat: repeat ?? this.repeat,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'hour': hour,
        'minute': minute,
        'enabled': enabled,
        'repeat': repeat.name,
      };

  factory ReminderItem.fromJson(Map<String, dynamic> json) {
    return ReminderItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Reminder',
      note: json['note'] as String? ?? '',
      hour: (json['hour'] as num?)?.toInt().clamp(0, 23) ?? 9,
      minute: (json['minute'] as num?)?.toInt().clamp(0, 59) ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      repeat: ReminderRepeat.tryParse(json['repeat'] as String?),
    );
  }
}

/// Sections on the Today dashboard. Stored by name so the order can be
/// customized without a schema migration.
enum TodaySection {
  status,
  quickAdd,
  highlight,
  timeline,
  trackers,
  places,
  music,
  recap;

  static const defaults = <TodaySection>[
    TodaySection.status,
    TodaySection.quickAdd,
    TodaySection.highlight,
    TodaySection.timeline,
    TodaySection.trackers,
    TodaySection.places,
    TodaySection.music,
    TodaySection.recap,
  ];

  String get label => switch (this) {
    TodaySection.status => 'Connection status',
    TodaySection.quickAdd => 'Quick add',
    TodaySection.highlight => 'Photo or memory highlight',
    TodaySection.timeline => 'Timeline preview',
    TodaySection.trackers => 'Tracker summary',
    TodaySection.places => 'Places and visits',
    TodaySection.music => 'Music summary',
    TodaySection.recap => 'Daily recap',
  };

  String get description => switch (this) {
    TodaySection.status => 'Honest integration and privacy indicators.',
    TodaySection.quickAdd => 'Write, log, attach, visit, event and music.',
    TodaySection.highlight => 'A recent photo or an on-this-day memory.',
    TodaySection.timeline => 'Your latest records in chronological order.',
    TodaySection.trackers => 'Today’s tracker values and quick actions.',
    TodaySection.places => 'Confirmed visits and saved places.',
    TodaySection.music => 'Listening totals when a source exists.',
    TodaySection.recap => 'A plain-language summary of stored records.',
  };

  static TodaySection? tryParse(String? value) {
    for (final section in TodaySection.values) {
      if (section.name == value) return section;
    }
    return null;
  }
}

class AppSettings {
  static const String defaultCloudflareWorkerUrl =
      'https://lifelog-cloudflare-sync.logginglife.workers.dev';

  const AppSettings({
    this.onboardingComplete = false,
    this.themeMode = AppThemeMode.system,
    this.lastfmUsername,
    this.lastfmApiKeyCipher,
    this.lastfmConnectedAt,
    this.lastfmLastSync,
    this.lastfmLastSyncFrom,
    this.weekStartsMonday = false,
    this.lockEnabled = false,
    this.pinSalt,
    this.pinHash,
    this.autoLockMinutes = 5,
    this.lastBackupAt,
    this.hiddenInsightCategories = const [],
    this.todaySections = const [],
    this.showArtwork = true,
    this.backupFolderPath,
    this.cloudflareWorkerUrl = defaultCloudflareWorkerUrl,
    this.cloudflareUsername,
    this.cloudflareSessionCipher,
    this.cloudflarePassphraseCipher,
    this.cloudflarePassphraseOwner,
    this.cloudflareConnectedAt,
    this.cloudflareLastSyncAt,
    this.cloudflareSetupDone = false,
    this.reminders = const [],
    this.locationTrackingEnabled = false,
    this.backgroundLocationEnabled = false,
    this.mealsMigrated = false,
  });

  final bool onboardingComplete;
  final AppThemeMode themeMode;

  final String? lastfmUsername;

  /// The Last.fm "API key" is not a secret in the same way as a shared secret,
  /// but it is still personal configuration: store it encrypted at rest.
  final String? lastfmApiKeyCipher;
  final DateTime? lastfmConnectedAt;
  final DateTime? lastfmLastSync;
  final DateTime? lastfmLastSyncFrom;

  final bool weekStartsMonday;

  /// A convenience screen lock. It does not replace disk encryption and is
  /// documented as such in the privacy notes.
  final bool lockEnabled;
  final String? pinSalt;
  final String? pinHash;
  final int autoLockMinutes;

  final DateTime? lastBackupAt;
  final List<String> hiddenInsightCategories;

  /// Stored Today section order. An empty list means use the defaults.
  final List<String> todaySections;

  /// Whether album artwork is fetched from Last.fm's image servers. Turning
  /// this off means browsing music makes no image requests at all.
  final bool showArtwork;

  /// Optional linked folder for saving backups (e.g. a synced/cloud folder).
  final String? backupFolderPath;

  /// Cloudflare Worker sync (client-side encrypted backups). Session token is stored encrypted.
  final String? cloudflareWorkerUrl;
  final String? cloudflareUsername;
  final String? cloudflareSessionCipher; // encrypted JSON: token and account metadata

  /// Backup passphrase, encrypted with the local archive key so it is only
  /// unlocked on this device. Lets sync/restore reuse it after the first entry.
  final String? cloudflarePassphraseCipher;

  /// Normalized account the remembered passphrase belongs to. A passphrase
  /// without a matching owner is never reused automatically.
  final String? cloudflarePassphraseOwner;

  final DateTime? cloudflareConnectedAt;
  final DateTime? cloudflareLastSyncAt;

  /// True once an account was set up on this install. Survives sign-out and
  /// session expiry, so those never send someone back to a sign-in wall.
  final bool cloudflareSetupDone;

  /// In-app reminders (time + message), stored locally in encrypted settings.
  final List<ReminderItem> reminders;

  /// When enabled, the app can record location samples on-device (with
  /// permission) to estimate visits and where time was spent each day.
  final bool locationTrackingEnabled;

  /// Opt-in for iOS visit/significant-change monitoring while the app is not
  /// foregrounded. Events are queued locally and flushed into the archive.
  final bool backgroundLocationEnabled;

  /// Set after the one-time migration of old meal habits and entry meal text.
  final bool mealsMigrated;

  bool get lastfmConnected =>
      lastfmUsername != null && lastfmUsername!.trim().isNotEmpty;

  bool get cloudflareConnected =>
      cloudflareWorkerUrl != null &&
      cloudflareWorkerUrl!.trim().isNotEmpty &&
      cloudflareUsername != null &&
      cloudflareUsername!.trim().isNotEmpty &&
      cloudflareSessionCipher != null &&
      cloudflareSessionCipher!.trim().isNotEmpty;

  /// True only when the remembered passphrase is scoped to the account that is
  /// currently signed in. Older settings without an owner do not qualify.
  bool get hasRememberedCloudflarePassphrase {
    final owner = cloudflarePassphraseOwner;
    final username = cloudflareUsername?.trim().toLowerCase();
    return owner != null &&
        owner.isNotEmpty &&
        username != null &&
        username.isNotEmpty &&
        owner == username &&
        cloudflarePassphraseCipher != null &&
        cloudflarePassphraseCipher!.trim().isNotEmpty;
  }

  AppSettings copyWith({
    bool? onboardingComplete,
    AppThemeMode? themeMode,
    String? lastfmUsername,
    bool clearLastfmUsername = false,
    String? lastfmApiKeyCipher,
    bool clearLastfmApiKeyCipher = false,
    bool clearLastfmCredentials = false,
    DateTime? lastfmConnectedAt,
    DateTime? lastfmLastSync,
    DateTime? lastfmLastSyncFrom,
    bool? weekStartsMonday,
    bool? lockEnabled,
    String? pinSalt,
    String? pinHash,
    bool clearPin = false,
    int? autoLockMinutes,
    DateTime? lastBackupAt,
    List<String>? hiddenInsightCategories,
    List<String>? todaySections,
    bool? showArtwork,
    String? backupFolderPath,
    bool clearBackupFolderPath = false,
    String? cloudflareWorkerUrl,
    bool clearCloudflareWorkerUrl = false,
    String? cloudflareUsername,
    bool clearCloudflareUsername = false,
    String? cloudflareSessionCipher,
    bool clearCloudflareSession = false,
    String? cloudflarePassphraseCipher,
    bool clearCloudflarePassphrase = false,
    String? cloudflarePassphraseOwner,
    bool clearCloudflarePassphraseOwner = false,
    DateTime? cloudflareConnectedAt,
    DateTime? cloudflareLastSyncAt,
    bool? cloudflareSetupDone,
    List<ReminderItem>? reminders,
    bool? locationTrackingEnabled,
    bool? backgroundLocationEnabled,
    bool? mealsMigrated,
  }) {
    final clearCloud = clearCloudflareSession;
    return AppSettings(
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      themeMode: themeMode ?? this.themeMode,
      lastfmUsername: clearLastfmCredentials || clearLastfmUsername
          ? null
          : (lastfmUsername ?? this.lastfmUsername),
      lastfmApiKeyCipher: clearLastfmCredentials || clearLastfmApiKeyCipher
          ? null
          : (lastfmApiKeyCipher ?? this.lastfmApiKeyCipher),
      lastfmConnectedAt: clearLastfmCredentials
          ? null
          : (lastfmConnectedAt ?? this.lastfmConnectedAt),
      lastfmLastSync: clearLastfmCredentials
          ? null
          : (lastfmLastSync ?? this.lastfmLastSync),
      lastfmLastSyncFrom: clearLastfmCredentials
          ? null
          : (lastfmLastSyncFrom ?? this.lastfmLastSyncFrom),
      weekStartsMonday: weekStartsMonday ?? this.weekStartsMonday,
      lockEnabled: lockEnabled ?? this.lockEnabled,
      pinSalt: clearPin ? null : (pinSalt ?? this.pinSalt),
      pinHash: clearPin ? null : (pinHash ?? this.pinHash),
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      hiddenInsightCategories:
          hiddenInsightCategories ?? this.hiddenInsightCategories,
      todaySections: todaySections ?? this.todaySections,
      showArtwork: showArtwork ?? this.showArtwork,
      backupFolderPath: clearBackupFolderPath
          ? null
          : (backupFolderPath ?? this.backupFolderPath),
      cloudflareWorkerUrl: clearCloud || clearCloudflareWorkerUrl
          ? null
          : (cloudflareWorkerUrl ?? this.cloudflareWorkerUrl),
      cloudflareUsername: clearCloud || clearCloudflareUsername
          ? null
          : (cloudflareUsername ?? this.cloudflareUsername),
      cloudflareSessionCipher: clearCloud
          ? null
          : (cloudflareSessionCipher ?? this.cloudflareSessionCipher),
      cloudflarePassphraseCipher:
          clearCloud || clearCloudflarePassphrase
              ? null
              : (cloudflarePassphraseCipher ?? this.cloudflarePassphraseCipher),
      cloudflarePassphraseOwner:
          clearCloud ||
                  clearCloudflarePassphrase ||
                  clearCloudflarePassphraseOwner
              ? null
              : (cloudflarePassphraseOwner ?? this.cloudflarePassphraseOwner),
      cloudflareConnectedAt:
          clearCloud ? null : (cloudflareConnectedAt ?? this.cloudflareConnectedAt),
      cloudflareLastSyncAt:
          clearCloud ? null : (cloudflareLastSyncAt ?? this.cloudflareLastSyncAt),
      cloudflareSetupDone: cloudflareSetupDone ?? this.cloudflareSetupDone,
      reminders: reminders ?? this.reminders,
      locationTrackingEnabled:
          locationTrackingEnabled ?? this.locationTrackingEnabled,
      backgroundLocationEnabled:
          backgroundLocationEnabled ?? this.backgroundLocationEnabled,
      mealsMigrated: mealsMigrated ?? this.mealsMigrated,
    );
  }

  Map<String, dynamic> toJson() => {
        'onboardingComplete': onboardingComplete,
        'themeMode': themeMode.name,
        'lastfmUsername': lastfmUsername,
        'lastfmApiKeyCipher': lastfmApiKeyCipher,
        'lastfmConnectedAt': lastfmConnectedAt?.toIso8601String(),
        'lastfmLastSync': lastfmLastSync?.toIso8601String(),
        'lastfmLastSyncFrom': lastfmLastSyncFrom?.toIso8601String(),
        'weekStartsMonday': weekStartsMonday,
        'lockEnabled': lockEnabled,
        'pinSalt': pinSalt,
        'pinHash': pinHash,
        'autoLockMinutes': autoLockMinutes,
        'lastBackupAt': lastBackupAt?.toIso8601String(),
        'hiddenInsightCategories': hiddenInsightCategories,
        'todaySections': todaySections,
        'showArtwork': showArtwork,
        'backupFolderPath': backupFolderPath,
        'cloudflareWorkerUrl': cloudflareWorkerUrl,
        'cloudflareUsername': cloudflareUsername,
        'cloudflareSessionCipher': cloudflareSessionCipher,
        'cloudflarePassphraseCipher': cloudflarePassphraseCipher,
        'cloudflarePassphraseOwner': cloudflarePassphraseOwner,
        'cloudflareConnectedAt': cloudflareConnectedAt?.toIso8601String(),
        'cloudflareLastSyncAt': cloudflareLastSyncAt?.toIso8601String(),
        'cloudflareSetupDone': cloudflareSetupDone,
        'reminders': reminders.map((r) => r.toJson()).toList(),
        'locationTrackingEnabled': locationTrackingEnabled,
        'backgroundLocationEnabled': backgroundLocationEnabled,
        'mealsMigrated': mealsMigrated,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final mode = AppThemeMode.values.firstWhere(
      (m) => m.name == json['themeMode'],
      orElse: () => AppThemeMode.system,
    );
    return AppSettings(
      onboardingComplete: json['onboardingComplete'] as bool? ?? false,
      themeMode: mode,
      lastfmUsername: json['lastfmUsername'] as String?,
      lastfmApiKeyCipher: json['lastfmApiKeyCipher'] as String?,
      lastfmConnectedAt: DateTime.tryParse(
        json['lastfmConnectedAt'] as String? ?? '',
      ),
      lastfmLastSync: DateTime.tryParse(
        json['lastfmLastSync'] as String? ?? '',
      ),
      lastfmLastSyncFrom: DateTime.tryParse(
        json['lastfmLastSyncFrom'] as String? ?? '',
      ),
      weekStartsMonday: json['weekStartsMonday'] as bool? ?? false,
      lockEnabled: json['lockEnabled'] as bool? ?? false,
      pinSalt: json['pinSalt'] as String?,
      pinHash: json['pinHash'] as String?,
      autoLockMinutes: (json['autoLockMinutes'] as num?)?.toInt() ?? 5,
      lastBackupAt: DateTime.tryParse(json['lastBackupAt'] as String? ?? ''),
      hiddenInsightCategories:
          (json['hiddenInsightCategories'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
      todaySections:
          (json['todaySections'] as List?)?.whereType<String>().toList() ??
          const [],
      showArtwork: json['showArtwork'] as bool? ?? true,
      backupFolderPath: json['backupFolderPath'] as String?,
      cloudflareWorkerUrl: (() {
        final value = (json['cloudflareWorkerUrl'] as String?)?.trim();
        if (value == null || value.isEmpty) {
          return AppSettings.defaultCloudflareWorkerUrl;
        }
        return value;
      })(),
      cloudflareUsername: json['cloudflareUsername'] as String?,
      cloudflareSessionCipher: json['cloudflareSessionCipher'] as String?,
      cloudflarePassphraseCipher:
          json['cloudflarePassphraseCipher'] as String?,
      cloudflarePassphraseOwner: json['cloudflarePassphraseOwner'] as String?,
      cloudflareConnectedAt:
          DateTime.tryParse(json['cloudflareConnectedAt'] as String? ?? ''),
      cloudflareLastSyncAt:
          DateTime.tryParse(json['cloudflareLastSyncAt'] as String? ?? ''),
      // Installs that were already signed in count as set up.
      cloudflareSetupDone: json['cloudflareSetupDone'] as bool? ??
          ((json['cloudflareSessionCipher'] as String?)?.isNotEmpty ?? false),
      reminders: (json['reminders'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ReminderItem.fromJson(Map<String, dynamic>.from(e)))
          .where((r) => r.id.isNotEmpty)
          .toList(),
      locationTrackingEnabled: json['locationTrackingEnabled'] as bool? ?? false,
      backgroundLocationEnabled:
          json['backgroundLocationEnabled'] as bool? ?? false,
      mealsMigrated: json['mealsMigrated'] as bool? ?? false,
    );
  }
}

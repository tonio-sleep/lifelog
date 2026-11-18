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
    this.googleClientId,
    this.googleClientSecret,
    this.googleAccountEmail,
    this.googleAuthCipher,
    this.googleConnectedAt,
    this.googleLastSyncAt,
    this.googleDriveFileId,
    this.googleDriveFolderId,
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

  /// Optional linked folder for saving backups (e.g. a Google Drive synced folder).
  final String? backupFolderPath;

  /// Google Drive sync (OAuth). Credentials/tokens stored encrypted separately where needed.
  final String? googleClientId;
  final String? googleClientSecret;
  final String? googleAccountEmail;
  final String? googleAuthCipher; // encrypted JSON: access/refresh tokens, expiry, scopes
  final DateTime? googleConnectedAt;
  final DateTime? googleLastSyncAt;
  final String? googleDriveFileId; // id of the synced backup file in Drive
  final String? googleDriveFolderId; // id of the Lifelog folder in Drive

  bool get lastfmConnected =>
      lastfmUsername != null && lastfmUsername!.trim().isNotEmpty;

  bool get googleDriveConnected =>
      googleAccountEmail != null && googleAuthCipher != null;

  AppSettings copyWith({
    bool? onboardingComplete,
    AppThemeMode? themeMode,
    String? lastfmUsername,
    bool clearLastfmUsername = false,
    String? lastfmApiKeyCipher,
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
    String? googleClientId,
    bool clearGoogleClientId = false,
    String? googleClientSecret,
    bool clearGoogleClientSecret = false,
    String? googleAccountEmail,
    bool clearGoogleAccountEmail = false,
    String? googleAuthCipher,
    bool clearGoogleAuth = false,
    DateTime? googleConnectedAt,
    DateTime? googleLastSyncAt,
    String? googleDriveFileId,
    bool clearGoogleDriveFileId = false,
    String? googleDriveFolderId,
    bool clearGoogleDriveFolderId = false,
  }) {
    return AppSettings(
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      themeMode: themeMode ?? this.themeMode,
      lastfmUsername: clearLastfmCredentials || clearLastfmUsername
          ? null
          : (lastfmUsername ?? this.lastfmUsername),
      lastfmApiKeyCipher: clearLastfmCredentials
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
      googleClientId: clearGoogleClientId ? null : (googleClientId ?? this.googleClientId),
      googleClientSecret: clearGoogleClientSecret ? null : (googleClientSecret ?? this.googleClientSecret),
      googleAccountEmail: clearGoogleAccountEmail || clearGoogleAuth
          ? null
          : (googleAccountEmail ?? this.googleAccountEmail),
      googleAuthCipher: clearGoogleAuth ? null : (googleAuthCipher ?? this.googleAuthCipher),
      googleConnectedAt: clearGoogleAuth ? null : (googleConnectedAt ?? this.googleConnectedAt),
      googleLastSyncAt: clearGoogleAuth ? null : (googleLastSyncAt ?? this.googleLastSyncAt),
      googleDriveFileId: clearGoogleAuth || clearGoogleDriveFileId
          ? null
          : (googleDriveFileId ?? this.googleDriveFileId),
      googleDriveFolderId: clearGoogleAuth || clearGoogleDriveFolderId
          ? null
          : (googleDriveFolderId ?? this.googleDriveFolderId),
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
    'googleClientId': googleClientId,
    'googleClientSecret': googleClientSecret,
    'googleAccountEmail': googleAccountEmail,
    'googleAuthCipher': googleAuthCipher,
    'googleConnectedAt': googleConnectedAt?.toIso8601String(),
    'googleLastSyncAt': googleLastSyncAt?.toIso8601String(),
    'googleDriveFileId': googleDriveFileId,
    'googleDriveFolderId': googleDriveFolderId,
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
      googleClientId: json['googleClientId'] as String?,
      googleClientSecret: json['googleClientSecret'] as String?,
      googleAccountEmail: json['googleAccountEmail'] as String?,
      googleAuthCipher: json['googleAuthCipher'] as String?,
      googleConnectedAt: DateTime.tryParse(json['googleConnectedAt'] as String? ?? ''),
      googleLastSyncAt: DateTime.tryParse(json['googleLastSyncAt'] as String? ?? ''),
      googleDriveFileId: json['googleDriveFileId'] as String?,
      googleDriveFolderId: json['googleDriveFolderId'] as String?,
    );
  }
}

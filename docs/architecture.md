# Architecture

Lifelog is a Flutter desktop-first application with a local, encrypted data
layer. It has no server component and no scheduled background work.

## Layers

```text
main.dart
  BootstrapApp
    AppServices.bootstrap()
      KeyVault → CryptoService
      ArchiveStore, MediaStore, SettingsStore
      LastfmService, BackupService
    ProviderScope
      LifelogApp
        OnboardingScreen or LockGate → AppShell
```

### Bootstrap (`lib/app/app_services.dart`)

`AppServices.bootstrap()` resolves the application support directory, creates
`<support>/lifelog`, loads or creates the root key, opens the encrypted archive,
loads plaintext preferences and returns one immutable `AppServices` object.
Every service is created once; screens never open databases or create clients.
If bootstrap fails, `main.dart` shows the real error with a retry action instead
of a blank window.

### State (`lib/app/providers/`)

- `appServicesProvider` is overridden at bootstrap with the real services.
- `archiveProvider` is a Riverpod `NotifierProvider` holding the in-memory
  archive. Every mutation creates a new `Archive`, updates state, then writes
  through a serialised queue. Writes are atomic: encrypted bytes go to a
  temporary file which is then renamed over the target.
- `settingsProvider` holds plaintext preferences and performs small writes.
  The Last.fm API key inside settings is encrypted separately.
- `sessionLockProvider` holds transient lock state, separate from settings, so
  a manual lock or inactivity timeout never changes stored preferences.

### Domain (`lib/domain/`)

Pure Dart models and calculations with no Flutter imports:

- `models/` — archive, journal, media, trackers, timeline, places, music,
  settings.
- `timeline_builder.dart` derives timeline rows from existing records. It does
  not duplicate storage.
- `search.dart` performs literal, case-insensitive search over the decrypted
  archive in memory.
- `memories.dart` groups records by day, computes on-this-day lists and calendar
  activity.

Keeping these files Flutter-free is what makes the unit tests fast.

### Core (`lib/core/`)

- `crypto/crypto_service.dart` — `KeyVault` (root key), `CryptoService`
  (AES-256-GCM), `PinHasher` (Argon2id PIN hash).
- `storage/archive_store.dart` — one encrypted archive document.
- `storage/media_store.dart` — encrypted originals and thumbnails in
  `media/<id>.bin` and `media/<id>.thumb.bin`.
- `storage/settings_store.dart` — `settings.json`, written atomically.
- `backup/backup_service.dart` — passphrase-encrypted exports.
- `util/dates.dart` — local-day helpers and formatting.

### Features (`lib/features/`)

One folder per destination. Screens are assembled from shared widgets in
`lib/app/widgets/common.dart` and the theme tokens in
`lib/app/theme/app_theme.dart`. Dialogs return plain model objects; the caller
persists them through `archiveProvider`. That keeps persistence in one place.

`features/security/lock_screen.dart` contains both `LockGate` (inactivity and
launch locking) and `LockScreen`. `LockGate` observes pointer and keyboard
activity and checks idle time on a 15-second timer.

### Shell (`lib/app/shell/app_shell.dart`)

Above 900 px the shell shows a fixed side navigation rail. Below 900 px it uses
a `NavigationBar`, an app bar with search and settings shortcuts, and a drawer
for all eleven destinations. The destinations live in an `IndexedStack`, so
switching tabs preserves scroll position and form state.

Navigation for detail screens uses the raw `Navigator` with
`MaterialPageRoute`; there is no router package.

## Data flow

```text
UI action
  → archiveProvider.notifier method
    → new Archive value
      → state update
        → encrypted write queue → archive.lifelog
```

Reads are synchronous because the archive is already in memory. This is the
main trade-off of the design: search and insights are instant and offline, but
the whole structured archive must fit in memory.

## Error handling

- Persistence failures set `lastSaveError` and are surfaced in the UI.
- Unsafe operations (restore, wipe, delete) require explicit confirmation and
  state exactly what will be destroyed.
- Media decryption failures show a placeholder with the reason; they never
  fabricate image content.
- Network failures are reported as failures, never as empty data.

## Testing

`test/` covers the security and calculation boundaries:

- AES-256-GCM round trip, authentication failure and PIN hashing.
- Tracker totals, averages, daily series and boolean behaviour.
- Timeline ordering and hidden-event filtering.
- Literal search behaviour and archived-entry exclusion.
- Backup round trip, wrong passphrase and short passphrase rejection.

Run `flutter analyze` and `flutter test` before shipping changes.

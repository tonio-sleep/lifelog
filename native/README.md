# Lifelog (native iOS)

This directory contains the native SwiftUI replacement for the Flutter Lifelog app. The Flutter implementation in `../lib` remains the authoritative reference for archive fields, date strings, crypto envelopes, PIN hashes, and backup formats. The native app is deliberately **local-first**: it works fully without an account, and Cloudflare sync is optional.

## Build and run

Requirements: macOS with Xcode 16 or newer and an iOS 17+ simulator or device.

1. Open `Lifelog.xcodeproj`.
2. Select the **Lifelog** scheme.
3. Build and run on an iOS 17+ simulator or device.
4. Run the **LifelogTests** scheme to check format golden vectors and domain behavior.

The Xcode project is generated. After adding or removing Swift files, run:

```sh
python3 generate_pbxproj.py
```

It regenerates `Lifelog.xcodeproj/project.pbxproj` and prints the number of app and test sources. `Info.plist` and `Lifelog.entitlements` are maintained by hand; the app target uses `GENERATE_INFOPLIST_FILE = NO`.

Health and location capabilities require the entitlements and usage-description strings already included in the project. Background location uses the `location` `UIBackgroundModes` entry.

## Navigation

The five primary destinations follow `LIFELOG_DEVELOPMENT_PROMPT.md`:

1. **Today** — current day, quick capture, and derived summaries.
2. **Timeline** — chronological records across recent days, with source filters.
3. **Map** — daily route, stops, saved places, filters, and a privacy mode.
4. **Memories** — calendar, journal, photos, and historical browsing.
5. **Insights** — statistics, patterns, and listening summaries.

Day-based journal editing remains available as a pushed route from Timeline and Memories. Settings and search are reachable from every primary destination, and quick add is available from the dock, sidebar, and toolbar.

## Local-first decision

The original product vision describes Lifelog as a private journal with no account requirement. The current Flutter app gates onboarding behind required Cloudflare authentication (`Onboarding → Cloudflare auth → Lock → …`). The native app intentionally resolves that contradiction in favor of the original vision:

- No account is required to create, read, or back up a journal.
- Cloudflare sync is an optional Settings feature that stores encrypted backup files.
- Signing out of Cloudflare never removes local data.
- Local encrypted backups work without networked services.

If a deployment requires mandatory accounts, that should be an explicit product decision rather than an inherited implementation detail.

## Storage and compatibility

All paths are relative to the app sandbox:

- Encrypted archive: `Library/Application Support/lifelog/archive.lifelog`
- Encrypted media: `Library/Application Support/lifelog/media/<uuid>.bin`
- Encrypted thumbnails: `Library/Application Support/lifelog/media/<uuid>.thumb.bin`
- Settings: `Library/Application Support/lifelog/settings.json`
- Local backup exports: `Documents/Backups/lifelog-<timestamp>.json`

The native app preserves the Flutter archive JSON schema and lenient decoding behavior. Dates in archive documents are local wall-clock ISO strings such as `2026-11-18T14:03:00.000`, with an optional three extra microsecond digits and a trailing `Z` only for UTC. `Domain/DateTools.swift` implements Dart-compatible encoding and parsing.

Crypto compatibility details live in `Core/Crypto.swift` and `Core/BackupService.swift`:

- Envelope layout: `nonce(12) || ciphertext || AES-256-GCM tag(16)`
- Archive AAD: `lifelog-archive-v1`
- Media AADs: `lifelog-media-v1`, `lifelog-media-thumb-v1`
- Backup AADs: `lifelog-backup-v1`, `lifelog-backup-v2`
- Last.fm key AAD: `lifelog-lastfm-key-v1`
- Cloudflare session AAD: `lifelog-cloudflare-session-v1`
- Backup key derivation: Argon2id, memory `19456 KiB`, iterations `2`, parallelism `1`, output `32 bytes`
- Master key: Keychain account `lifelog.master_key.v1`, with a `master.key` base64 fallback

The master key is written to the Keychain service `flutter_secure_storage_service`, which is the current `flutter_secure_storage` default on iOS, and to the bundle identifier for older readers. Reads also check the legacy `lifelog` service.

Backup files use the Flutter v2 container:

```json
{
  "format": "lifelog-backup",
  "version": 2,
  "payload": {
    "version": 2,
    "createdAt": "…Z",
    "includesMedia": true,
    "archive": {},
    "mediaFiles": []
  }
}
```

The encrypted payload key is wrapped in a v2 Argon2id envelope and authenticated with `lifelog-backup-v2`. The v1 container is still readable. Restoring replaces local archive and media data; the app stages files first and rolls back if any write fails.

## Privacy and permissions

- PIN length is 4–12 digits, matching Flutter. The PIN is a convenience screen lock; it is not the archive encryption key and has no recovery path.
- Health access is optional and read-only. iOS does not expose precise Health authorization status to third-party apps on iPhone, so Settings requests access and explains the result.
- Location samples and visits are stored locally in your encrypted archive. Displaying the Map screen sends the visible map region to Apple MapKit to draw tiles; "Hide exact coordinates" suppresses the route, pins, and coordinate display.
- Photo markers are not shown because the archive does not store photo coordinates. No locations are invented to fill the map.
- Screen Time / Family Controls are not implemented, matching the Flutter limitation.
- Reminders are local notifications only.

## Tests

`LifelogTests` covers:

- Argon2id golden vector and backup envelope format
- Dart-compatible date encoding and parsing
- Archive, PIN hash, and backup v1/v2 compatibility
- Search caps, streak counting, on-this-day behavior, and safe numeric decoding

Run them with `⌘U` in Xcode or via the `LifelogTests` scheme.

## Flutter parity notes

The native app intentionally preserves domain quirks that affect compatibility:

- Search returns at most 250 results.
- On This Day looks back 25 years.
- Music produces one daily timeline row rather than one row per scrobble.
- Mood uses a 1–10 scale.
- A tracker-record search hit reports the tracker ID as `sourceId`.
- `currentStreak` counts manual scrobbles but not manual timeline events or imported Last.fm rows.

Where the native UX improves on Flutter, it does so without changing stored formats.

# Lifelog

A private, local-first personal life archive built with Flutter. Lifelog keeps
journal entries, custom trackers, a unified timeline, encrypted photos and
files, places and visits, listening history, memories, insights and search in
one archive that stays on your device.

There is no analytics, crash reporting or map tile service. Optional encrypted
backup sync to Cloudflare R2 and optional iOS background visit monitoring are
available. The structured archive and every media file are encrypted at rest
with AES-256-GCM; location samples stay in that encrypted local archive.

## What is implemented

- **Encrypted archive** — the whole structured archive is serialised to JSON,
  encrypted as one document and written to `archive.lifelog`.
- **Journal** — entries with title, body, mood, tags, place, draft autosave,
  draft recovery and encrypted attachments.
- **Trackers** — yes/no, count, number, duration, rating, note and event
  trackers with templates, targets, history and derived statistics.
- **Timeline** — journal entries, tracker records, visits, music and photos are
  derived into one chronological day view. Manual events are stored separately.
- **Photos and files** — imported files and generated thumbnails are encrypted
  before they touch disk. Captions, tags and favourites live in the archive.
- **Meals** — first-class meal, drink and snack records with amount, notes and
  tags, plus a one-time migration from the old meal habit and entry text.
- **Places and visits** — saved places with optional coordinates, day-tracking
  samples, iOS background visit monitoring when you opt in with Always access,
  manually confirmed visits and a schematic map that downloads no tiles.
- **Music** — optional read-only Last.fm sync using your own API key, plus
  manual track entry.
- **Memories** — a real activity calendar, on-this-day records and day detail.
- **Insights** — counts, ranges, weekday rhythm, tracker trends and coverage
  rows. Nothing is modelled or predicted.
- **Search** — literal local search across journal text, tags, tracker notes,
  meals, places, visits, music and manual events.
- **Settings** — appearance, week start, PIN privacy screen with auto-lock,
  key/data details, local and Cloudflare backup sync with per-file progress,
  Last.fm, onboarding replay and wipe.
- **Backup** — passphrase-encrypted, versioned exports derived with Argon2id.
  The passphrase is remembered encrypted on the same device and is never sent
  to the sync server.

## Requirements

- Flutter 3.47.4 (Dart 3.13 or newer)
- macOS 15 with Xcode 26.1.1 for iOS builds (the CI runner provides this)
- iOS 15 or newer on the target device
- A Last.fm API key only if you want music sync

## Run

On a Mac with a connected iOS device:

```bash
flutter pub get
flutter run -d <ios-device-id>
```

Run the checks:

```bash
flutter analyze
flutter test
```

Build an unsigned iOS app bundle:

```bash
flutter build ios --release --no-codesign
```

`.github/workflows/build.yml` runs the checks, builds the app and packages the
unsigned IPA as the `lifelog-ios-unsigned-ipa` artifact.

See [docs/setup.md](docs/setup.md) for prerequisites, data locations and
troubleshooting.

## Documentation

- [Architecture](docs/architecture.md)
- [Data model](docs/data-model.md)
- [Privacy model](docs/privacy-model.md)
- [Backup and recovery](docs/backup-and-recovery.md)
- [Setup and troubleshooting](docs/setup.md)

## Known limitations

These are real limits of the current build, not placeholders:

- **Cloud sync is one encrypted backup blob, not a live merge.** The archive
  belongs to one install; uploading and restoring replaces it.
- **Backups exclude media bytes.** A restore replaces the archive and clears
  the current encrypted media vault. Copy media separately if you need it.
- **Background visits are not continuous GPS.** With Background visits on and
  Location Access set to Always, iOS reports visits and significant location
  changes. Arrival/departure still needs the app to run to flush the local
  queue into the archive.
- **The map is schematic.** It draws saved places, tracked samples and stops
  on a local canvas and requests no map tiles.
- **Last.fm is optional and read-only.** It needs your own API key and a
  username with public recent tracks. It may lag behind other scrobbling
  sources.
- **The PIN is an app-level privacy screen.** It is not a hardened key
  derivation step for the archive key and there is no PIN recovery.
- **The local key-file fallback is weaker.** When platform secure storage is
  unavailable, the root key is stored in a local file. This protects against
  casual access, not a determined attacker with file access.
- **No database engine.** The entire archive lives in memory while unlocked and
  is persisted as one encrypted document. This is simple and private, but it is
  not designed for archives with millions of records.

## Project layout

```text
lib/
  app/            bootstrap, shell, providers, theme, shared widgets
  core/           crypto, encrypted storage, backup, date helpers
  domain/         models, timeline builder, search, memories
  features/       onboarding, today, journal, trackers, timeline, memories,
                  photos, places, music, insights, search, settings, security
  integrations/   Last.fm client
test/             crypto, tracker math, timeline, search and backup tests
docs/             architecture, data model, privacy, backup, setup
```

The interface follows the specification in
`LIFELOG_DEVELOPMENT_PROMPT.md`.

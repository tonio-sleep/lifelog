# Lifelog

A private, local-first personal life archive built with Flutter. Lifelog keeps
journal entries, custom trackers, a unified timeline, encrypted photos and
files, places and visits, listening history, memories, insights and search in
one archive that stays on your device.

There is no Lifelog account, no analytics, no cloud sync and no background
location tracking. The structured archive and every media file are encrypted
at rest with AES-256-GCM.

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
- **Places and visits** — saved places with optional coordinates, manually
  confirmed visits, an optional single on-demand location fix and a schematic
  map that downloads no tiles.
- **Music** — optional read-only Last.fm sync using your own API key, plus
  manual track entry.
- **Memories** — a real activity calendar, on-this-day records and day detail.
- **Insights** — counts, ranges, weekday rhythm, tracker trends and coverage
  rows. Nothing is modelled or predicted.
- **Search** — literal local search across journal text, tags, tracker notes,
  places, visits, music and manual events.
- **Settings** — appearance, week start, PIN privacy screen with auto-lock,
  key/data details, backup and restore, Last.fm, onboarding replay and wipe.
- **Backup** — passphrase-encrypted, versioned exports derived with Argon2id.

## Requirements

- Flutter 3.47 or newer (Dart 3.13 or newer)
- Windows 10/11 for the primary desktop target (macOS and Linux are supported
  by Flutter; only Windows has been built and smoke-tested here)
- A Last.fm API key only if you want music sync

## Run

```powershell
flutter pub get
flutter run -d windows
```

Run the checks:

```powershell
flutter analyze
flutter test
```

Build a Windows executable:

```powershell
flutter build windows --release
```

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

- **No cloud sync or multi-device merge.** The archive belongs to one install.
- **Backups exclude media bytes.** A restore replaces the archive and clears
  the current encrypted media vault. Copy media separately if you need it.
- **No background GPS or automatic visit detection.** Visits are manual, with
  an optional single on-demand location fix.
- **The map is schematic.** It draws saved places and visits on a local canvas
  and requests no map tiles.
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

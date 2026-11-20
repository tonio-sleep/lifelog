# Data model

Lifelog stores one structured archive plus a media vault and a small settings
file. All three live under `<application support>/lifelog`.

```text
lifelog/
  archive.lifelog        AES-256-GCM encrypted archive document
  settings.json          preferences plus encrypted secret ciphers
  master.key             fallback root key, only if secure storage is unavailable
  media/
    <media-id>.bin       encrypted original
    <media-id>.thumb.bin encrypted JPEG thumbnail
```

## Archive document

`archive.lifelog` is the AES-256-GCM envelope of this JSON document:

```json
{
  "format": "lifelog-archive",
  "version": 1,
  "savedAt": "2026-05-10T09:00:00.000Z",
  "entries": [],
  "media": [],
  "trackers": [],
  "trackerRecords": [],
  "events": [],
  "places": [],
  "visits": [],
  "locationSamples": [],
  "meals": [],
  "scrobbles": []
}
```

Times are serialised as ISO-8601 strings. Lifelog writes UTC timestamps for
saved-at fields and local times for user-entered records, then interprets all
display values in the device's current local timezone.

### JournalEntry (`entries`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | UUID |
| `createdAt`, `updatedAt` | ISO string | |
| `title`, `body` | string | either may be empty |
| `mood` | string? | `awful`, `low`, `okay`, `good`, `great` |
| `tags` | string[] | free-form |
| `placeId`, `placeLabel` | string? | optional link to a saved place |
| `draft` | bool | drafts are autosaved but counted separately |
| `archived` | bool | hidden from lists and search |

### MediaItem (`media`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | also the encrypted file name |
| `createdAt` | ISO string | |
| `mimeType` | string | detected from the file extension |
| `bytes` | int | original size |
| `caption`, `tags` | string, string[] | |
| `journalEntryId` | string? | attachment link |
| `favorite` | bool | |
| `hasThumbnail` | bool | `media/<id>.thumb.bin` exists |
| `width`, `height` | int? | for images |
| `originalName` | string? | retained, not used as a file name |

The actual bytes never appear in the archive document.

### TrackerDefinition (`trackers`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | |
| `name` | string | |
| `type` | string | `boolean`, `count`, `number`, `duration`, `rating`, `text`, `event` |
| `createdAt` | ISO string | |
| `icon`, `colorValue` | string, int | presentation |
| `category`, `unit` | string | |
| `target` | double? | optional daily target |
| `active`, `archived` | bool | |
| `multiplePerDay` | bool | |
| `sortOrder` | int | |

### TrackerRecord (`trackerRecords`)

| Field | Type | Notes |
| --- | --- | --- |
| `id`, `trackerId` | string | |
| `recordedAt` | ISO string | |
| `value` | double? | numeric value or `1` for boolean/count |
| `text` | string | note-type value |
| `note` | string | optional annotation |

`TrackerMath` derives totals, averages, daily labels and series from these
records. Nothing is precomputed in storage.

### MealRecord (`meals`)

Food and drink are first-class records, not a habit. This key is additive and
missing in older archives, which read as an empty list. Legacy meal tracker
records and text embedded in journal entries are migrated once on launch.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | UUID |
| `at`, `createdAt` | ISO string | when eaten and when recorded |
| `day` | string? | optional local day key override |
| `kind` | string | `meal`, `drink` or `snack` |
| `name` | string | what was eaten or drunk |
| `amount`, `unit` | double?, string | optional quantity |
| `notes`, `tags` | string, string[] | free-form details |
| `legacyRef` | string? | source record for idempotent migration |

### TimelineEvent (`events`)

Manual events only. Journal entries, tracker records, visits, music and photos
are derived into the timeline at read time.

| Field | Type | Notes |
| --- | --- | --- |
| `id`, `title` | string | |
| `occurredAt` | ISO string | |
| `notes` | string | |
| `hidden` | bool | hidden from the timeline, not deleted |

### Place (`places`)

| Field | Type | Notes |
| --- | --- | --- |
| `id`, `name` | string | |
| `createdAt` | ISO string | |
| `latitude`, `longitude` | double? | optional; a place may be a label only |
| `radiusMeters` | double | schematic proximity hint, default 120 |
| `notes` | string | |
| `colorValue` | int | |

### Visit (`visits`)

| Field | Type | Notes |
| --- | --- | --- |
| `id`, `label` | string | label is stored so a visit survives place deletion |
| `startAt`, `endAt` | ISO string, ISO string? | `endAt` null means ongoing |
| `placeId` | string? | optional link |
| `confidence` | string | `confirmed` or `suggested` |
| `notes` | string | |

### MusicScrobble (`scrobbles`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | deterministic for Last.fm imports |
| `artist`, `title`, `album` | string | |
| `playedAt` | ISO string | |
| `artworkUrl` | string? | remote artwork URL, displayed only if loaded |
| `durationSeconds` | int? | |
| `source` | string | `lastfm` or `manual` |

## Settings (`settings.json`)

Preferences are plaintext because they contain no journal content:

- onboarding completion and theme mode
- week start
- Last.fm username, connection timestamps and sync window
- Last.fm API key **ciphertext** only
- PIN salt and Argon2id hash, auto-lock minutes, lock enabled flag
- last backup timestamp
- hidden insight categories
- custom Today dashboard section order

The API key is encrypted with the archive key and a separate AAD before being
written here. The PIN hash is salted and derived with Argon2id.

## Migration

Both the archive and backup containers carry a `format` and `version`. Unknown
or mismatched versions are rejected rather than guessed at. Adding a field is
backward compatible because every `fromJson` provides a default. Removing or
renaming a field would require a version bump and a migration step.

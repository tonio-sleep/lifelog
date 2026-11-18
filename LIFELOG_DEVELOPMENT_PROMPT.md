# LIFELOG --- Complete Product & Engineering Specification

**Project type:** Production-quality personal life archive\
**Primary platform:** Flutter (Dart), Android and iOS\
**Backend:** Supabase\
**Storage model:** Local-first with encrypted cloud synchronization\
**Music integration:** Last.fm\
**Product vision:** A private, searchable, long-term archive of everyday
life.

------------------------------------------------------------------------

## 1. Product vision

Build **Lifelog**, a polished personal life-logging application that
helps one person remember the details of their life over months and
years.

Lifelog is not merely a diary, habit tracker, fitness app, or location
tracker. It combines these ideas into one coherent personal archive. A
user should be able to open a date from years ago and explore what
happened: journal entries, photos, places visited, routes, activities,
custom tracker records, and music listened to through Last.fm.

The app should support both automatic collection and intentional manual
logging. It should capture useful context with as little friction as
possible, while always making it clear what is being collected and
allowing the user to pause, edit, export, or delete it.

### Core product principles

1.  **Private by design:** Sensitive content is encrypted on the device
    before cloud upload. The backend must not be able to decrypt private
    content.
2.  **Local-first:** Logging must work offline. Cloud sync is a
    secondary replication mechanism, not a prerequisite for using the
    app.
3.  **Automatic, but user-controlled:** Location and other background
    collection are opt-in, transparent, battery-conscious, and easy to
    pause.
4.  **Everything is editable:** Automatically detected events are
    suggestions until confirmed, where appropriate. Users can correct,
    merge, split, rename, or delete records.
5.  **Flexible logging:** Users can create any tracker or event type
    without needing a developer to add a new category.
6.  **Long-term ownership:** Users can export and restore their archive
    in a documented format.
7.  **Calm, minimal interface:** Apple-like clarity, excellent
    typography, considered spacing, subtle motion, and no clutter.

Do not build a generic dashboard full of arbitrary cards. Every screen
should help users capture, understand, or revisit memories.

------------------------------------------------------------------------

## 2. Target platforms and technical direction

Build a cross-platform Flutter application in Dart for:

-   Android phones.
-   iPhones.
-   A responsive tablet layout where practical.
-   A future desktop/web companion only if it can preserve the same
    privacy guarantees.

Use stable, actively maintained packages and pin compatible versions.
Before choosing a package, verify current maintenance status, platform
support, licensing, and compatibility with the current Flutter SDK.

### Recommended architecture

Use a feature-first, clean architecture with clear boundaries:

-   Presentation: screens, widgets, navigation, view models/controllers.
-   Application: use cases and orchestration.
-   Domain: entities, value objects, repository contracts, business
    rules.
-   Data: local persistence, Supabase adapters, API clients, encryption
    adapters, background services.

Recommended technologies (validate choices before implementation):

-   Flutter and Dart.
-   Riverpod for state management and dependency injection.
-   GoRouter for navigation.
-   Drift with SQLite for reliable local relational storage and
    migrations.
-   Supabase Auth for account identity.
-   Supabase PostgreSQL for encrypted cloud records and sync metadata.
-   Supabase Storage for encrypted media blobs.
-   A well-reviewed cryptographic library for client-side encryption.
-   Workmanager / platform-native background task mechanisms where
    appropriate.
-   Geolocator or a carefully selected background location solution,
    subject to current Android/iOS restrictions.
-   A map SDK such as Mapbox or Google Maps, chosen after comparing
    privacy, cost, offline capability, and terms.
-   A charting package for analytics.
-   Secure platform key storage using Android Keystore and Apple
    Keychain/Secure Enclave capabilities where available.

Do not blindly follow this package list. Research current package status
and choose maintainable, secure dependencies. Document each major
dependency and why it was selected.

### Project organization

Use a structure similar to:

``` text
lib/
  app/
    app.dart
    router/
    theme/
    bootstrap/
  core/
    crypto/
    database/
    sync/
    permissions/
    errors/
    logging/
    utilities/
    widgets/
  features/
    today/
    journal/
    timeline/
    locations/
    map/
    trackers/
    calendar/
    memories/
    photos/
    music/
    insights/
    search/
    settings/
    backup/
  integrations/
    lastfm/
    maps/
    weather/
  main.dart

test/
  unit/
  widget/
  integration/
  security/

docs/
  architecture.md
  threat-model.md
  data-model.md
  privacy-model.md
  backup-and-recovery.md
  setup.md
```

Keep platform-specific code behind interfaces. Avoid putting database,
encryption, GPS, or API logic directly inside widgets.

------------------------------------------------------------------------

## 3. Visual design and interaction

### Design direction

Create a minimalist, Apple-like interface:

-   Quiet, clean surfaces.
-   Strong visual hierarchy.
-   Generous but efficient spacing.
-   High-quality typography.
-   Subtle dividers and restrained shadows.
-   Rounded corners used consistently, not excessively.
-   Thoughtful light and dark themes.
-   Smooth, restrained transitions.
-   Clear iconography.
-   Excellent empty, loading, error, and offline states.

Avoid: - Overcrowded dashboards. - Excessive gradients and glass
effects. - Gamification that makes personal logging feel like work. -
Unnecessary badges, streak pressure, or guilt-inducing notifications. -
Fake data presented as real user history.

Create a reusable design system with color tokens, typography scale,
spacing scale, corner radii, elevation, icon sizes, and component
variants. Support dynamic text sizing and accessibility contrast.

### Main navigation

Use five primary destinations:

1.  **Today** --- current day and quick capture.
2.  **Timeline** --- chronological events across days.
3.  **Map** --- visited places and journeys.
4.  **Memories** --- calendar, journal, photos, and historical browsing.
5.  **Insights** --- statistics, patterns, and listening summaries.

Provide a prominent, accessible quick-add action available throughout
the app. Settings and account controls should be easy to reach without
consuming a primary navigation slot.

### Quick-add actions

Allow users to add:

-   Journal entry.
-   Photo or video.
-   Voice note.
-   Timeline event.
-   Location or journey.
-   Tracker record.
-   Meal, drink, or water intake.
-   Mood.
-   Sleep record.
-   Music note or manually logged song.
-   Custom event.

Support quick capture with minimal required fields. Never force a user
to complete a long form to record a small memory.

------------------------------------------------------------------------

## 4. Today dashboard

The Today screen is the daily home base.

Display:

-   Current date and weekday.
-   A welcoming but understated date header.
-   Optional weather, only with permission and a configured weather
    provider.
-   A compact daily photo/memory highlight.
-   Timeline preview.
-   Places visited or location status.
-   Today's tracker summary.
-   Music listening summary from Last.fm, if connected.
-   A small daily recap.
-   Quick-add controls.

Allow users to customize which sections appear and their order. Do not
imply an activity happened if the app has no reliable record of it.

Provide clear status indicators for: - Location tracking on, paused, or
unavailable. - Last.fm connected or disconnected. - Cloud sync complete,
pending, or failed. - Offline mode.

The Today screen must remain useful when no integrations are connected.

------------------------------------------------------------------------

## 5. Journal and free-form memories

Build a flexible journal, not a rigid questionnaire.

### Journal entry features

-   Multiple entries per day.
-   Rich text or a practical structured text editor.
-   Autosave with visible save status.
-   Draft recovery.
-   Photos, videos, and audio attachments.
-   Captions and optional alt text.
-   Tags and user-defined categories.
-   Mood or feeling, optional.
-   Timestamp, optional.
-   Location attachment, optional.
-   Links to related places, tracker events, music, and timeline events.
-   Edit, duplicate, archive, and delete.
-   Search within entry text and captions.

The user must be able to write a short sentence, a long entry, or
nothing at all. Do not require a mood or category.

### Media handling

-   Preserve original media when possible.
-   Generate local thumbnails for fast browsing.
-   Store media metadata separately from encrypted media bytes.
-   Encrypt media before cloud upload.
-   Avoid public media URLs.
-   Support private authenticated downloads.
-   Keep local and cloud copies consistent.
-   Explain how metadata such as EXIF timestamps and GPS coordinates are
    handled.
-   Offer a privacy setting to strip embedded GPS metadata from
    exported/shared copies.

------------------------------------------------------------------------

## 6. Custom tracker system

Trackers are a core feature. Build a flexible schema-driven tracker
system rather than hardcoding every possible habit.

### Built-in example trackers

Personal care: - Showered (yes/no or count). - Brushed teeth. -
Skincare. - Hair wash. - Other routines.

Bathroom: - Restroom visit count. - Optional timestamp for each visit. -
Optional private notes.

Daily life: - Meals and snacks. - Water and other drinks. - Sleep. -
Exercise and walking. - Studying and work. - Entertainment. - Social
activities. - Spending. - Mood. - Custom activities.

These are examples, not mandatory health assessments. Do not diagnose,
infer a medical condition, or label behavior as good or bad.

### Custom tracker builder

Let users create trackers with:

-   Name and icon.
-   Category and color.
-   Data type: boolean, count, number, duration, text, rating, or event.
-   Unit, where applicable.
-   Optional target or goal.
-   Optional reminder.
-   Frequency or schedule.
-   Whether multiple entries per day are allowed.
-   Optional notes.
-   Optional timestamp.
-   Optional location.
-   Custom fields.

Examples: - "Coffee" --- count per day. - "Shower" --- yes/no plus
optional time. - "Reading" --- duration. - "Restroom" --- event count
with timestamps. - "Something interesting" --- free text.

Allow users to edit tracker definitions without corrupting historical
records. Version tracker schemas where needed. Preserve old values if a
tracker is renamed, archived, or its unit changes.

### Tracker presentation

-   Quick one-tap logging.
-   Daily totals.
-   Weekly and monthly summaries.
-   Calendar heatmaps where appropriate.
-   Charts with clear units and date ranges.
-   Optional goals, never forced.
-   Edit and delete individual records.
-   Export tracker data.

------------------------------------------------------------------------

## 7. Automatic location history and journeys

Location tracking is a major capability and must be implemented
responsibly.

### User control and platform constraints

Automatic background GPS tracking must be explicitly enabled by the
user. Explain why each permission is needed before requesting it.
Respect Android and iOS background-location policies and system
indicators.

Provide: - Start, pause, resume, and stop controls. - A visible tracking
status. - A persistent Android notification when required by the
operating system. - Clear iOS permission explanations. -
Battery-conscious sampling. - Configurable tracking sensitivity. - A
manual mode. - A "do not track" schedule or private periods. - A one-tap
pause control. - A way to delete a location history range.

Do not promise continuous tracking if the operating system may suspend
the app. Document platform limitations and design graceful recovery.

### Location features

-   Record location samples with timestamp, accuracy, and relevant
    metadata.
-   Infer likely stops from clusters of samples, but label inferred
    places as suggestions.
-   Let users confirm, reject, merge, split, rename, or delete detected
    stops.
-   Save favorite and named places such as Home, School, Work, or custom
    labels.
-   Record arrival and departure estimates with confidence indicators.
-   Estimate time spent at a place only when data supports it.
-   Build journeys between stops.
-   Display route traces on an interactive map.
-   Allow manual start/end points and manual route entries.
-   Attach journal entries, photos, and events to places.
-   Show locations visited on a selected day.
-   Browse places by day, week, month, or year.
-   Search by place name and date.

### Location data quality

Store accuracy and source information. Distinguish: - GPS-observed
location. - User-entered location. - Geocoded place suggestion. -
Inferred stop or journey.

Never silently convert an uncertain guess into a confirmed visit. Let
the user correct incorrect place names and stop boundaries.

### Map interface

Include: - Daily route map. - Place pins. - Stop clusters. - Journey
lines. - Photo markers. - Timeline/map synchronization. - Date
selector. - Filters for places, photos, and events. - A privacy mode
that hides exact coordinates in screenshots or overview screens.

Use a mapping provider only after evaluating privacy and API terms.
Avoid sending unnecessary precise location history to third-party
services. Where possible, geocode only when needed and explain the data
flow.

------------------------------------------------------------------------

## 8. Automatic daily timeline

Create one chronological timeline combining relevant records from
different features.

Example:

-   7:15 AM --- Woke up (manual tracker).
-   7:30 AM --- Shower (tracker).
-   8:25 AM --- Left Home (location-derived suggestion).
-   8:50 AM --- Arrived at School (location-derived suggestion).
-   12:15 PM --- Lunch (manual entry).
-   3:45 PM --- Left School (location-derived suggestion).
-   4:20 PM --- Arrived Home (location-derived suggestion).
-   8:30 PM --- Listened to an album (Last.fm listening data).
-   10:30 PM --- Journal entry.

### Timeline requirements

-   Merge entries from journal, trackers, locations, media, and music.
-   Preserve original source and timestamp.
-   Allow manual events.
-   Edit, delete, hide, merge, and correct events.
-   Display confidence/source for automatically inferred events.
-   Support multiple events with the same timestamp.
-   Handle time zones and daylight-saving changes correctly.
-   Avoid inventing events to fill gaps.
-   Allow users to filter by event type.
-   Keep a stable chronological ordering.

The timeline should be a view over the underlying records, not a second
source of truth that duplicates data unnecessarily.

------------------------------------------------------------------------

## 9. Last.fm music integration

Integrate **Last.fm** to add music listening history to the user's daily
archive.

### Connection and setup

-   Provide a dedicated Last.fm connection screen.
-   Explain that listening history depends on the user's Last.fm account
    and scrobbling setup.
-   Use Last.fm's documented authentication flow and API requirements.
-   Keep API secrets out of the Flutter client. If a shared secret is
    required for signed requests, perform those operations through a
    secure backend function or another architecture that does not expose
    the secret in the app binary.
-   Store user authorization tokens securely and only as needed.
-   Allow disconnecting Last.fm and deleting imported music history.
-   Respect Last.fm's terms, rate limits, attribution, and branding
    requirements.
-   Do not scrape Last.fm pages.

### Data to import

For each day, retrieve and store as appropriate:

-   Track title.
-   Artist.
-   Album.
-   Album artwork URL or cached artwork where permitted.
-   Scrobble timestamp.
-   Track duration if available.
-   Listening count.
-   Top artists.
-   Top albums.
-   Top tracks.
-   Daily, weekly, monthly, and yearly listening statistics.

Use Last.fm API methods such as the documented user recent tracks and
top tracks/artists/albums endpoints. Verify current API response fields,
pagination, authentication needs, rate limits, and timestamp behavior
against official documentation before implementation.

### Music timeline

-   Add listening events to the daily timeline using their actual
    timestamps.
-   Group repeated plays intelligently without losing individual
    scrobble records.
-   Show what was playing around a particular time.
-   Display daily top artists, tracks, and albums.
-   Show total scrobbles and unique tracks for the day.
-   Support date-based browsing and historical comparisons.
-   Link music to journal entries or locations manually, without
    assuming a song caused a particular mood or event.

### Sync and privacy

Treat imported music history as personal data. Encrypt sensitive music
records before cloud upload if they are part of the private archive.
Store only the minimum data needed. Do not expose Last.fm tokens in
logs, analytics, crash reports, or client-visible configuration.

### Last.fm reliability

-   Handle empty days and missing metadata.
-   Handle pagination and API errors.
-   Avoid duplicate imports.
-   Use stable identifiers where available, with a documented fallback
    matching strategy.
-   Track the last successful synchronization cursor/time.
-   Backfill history within API availability and rate limits.
-   Make it clear that Last.fm cannot provide reliable listening history
    for music that was not scrobbled.

------------------------------------------------------------------------

## 10. Calendar, memory explorer, and "On This Day"

Create a calendar and memory browser for long-term exploration.

### Calendar

-   Month, week, and day navigation.
-   Indicators for journal entries, photos, places, and music.
-   Optional mood indicator.
-   Small photo previews.
-   Daily activity summaries.
-   Navigate directly to any date.
-   Avoid overwhelming the calendar with too many symbols.

### On This Day

Show memories from the same date in previous years:

-   Journal excerpts.
-   Photos.
-   Places visited.
-   Music listened to.
-   Tracker highlights.
-   User-created events.

Example: "One year ago today, you visited a saved place and listened to
18 tracks."

Only display information actually present in the archive. Explain when a
memory is incomplete.

### Memory views

Provide three connected ways to explore: 1. Chronological timeline. 2.
Journal/day page. 3. Interactive map.

Allow users to move between these views while keeping the selected date
and context.

------------------------------------------------------------------------

## 11. Photo and media gallery

Create a dedicated media archive:

-   Photos and videos grouped by date.
-   Timeline gallery.
-   Map-based photo exploration.
-   Captions and tags.
-   Related journal entries.
-   Full-screen viewer.
-   Search by date, caption, tag, or place.
-   Filters by media type.
-   Optional favorites.
-   Duplicate detection suggestions.
-   Upload and sync status.

Do not claim facial recognition or people identification unless
explicitly implemented with clear opt-in, on-device processing, and a
separate privacy review. Do not upload media to an AI service by
default.

------------------------------------------------------------------------

## 12. Insights and personal analytics

Create a thoughtful analytics area that helps users understand their own
records without judging them.

Possible insights: - Shower frequency. - Tracker totals and trends. -
Time spent at saved places. - Number of places visited. - Travel
distance estimates, if sufficiently reliable. - Journal entry
frequency. - Photo counts. - Music listening totals. - Top artists,
albums, and tracks. - Day-of-week comparisons. - Monthly and yearly
summaries.

Allow date-range selection and clear chart labels, units, and data
sources.

Avoid unsupported conclusions. Do not diagnose health conditions or
infer sensitive traits. Users should be able to hide any analytics
category.

------------------------------------------------------------------------

## 13. Global search

Build a fast search system across the user's archive.

Search: - Journal text. - Dates and date ranges. - Tags. - Tracker names
and values. - Place names. - Captions. - Music track, artist, and
album. - Timeline event titles.

Support filters and sorting. Show results grouped by type and date.

Because private content is encrypted, search must be designed carefully.
Prefer a local decrypted search index on the user's device. Do not send
plaintext search queries or private journal text to the backend. For
multiple-device search, design a privacy-preserving encrypted index only
if it can be implemented safely and documented; otherwise rebuild the
local index after authorized sync.

Example searches: - "Where did I go last Friday?" - "What song was I
listening to when I got home?" - "Show photos from November." - "When
did I last visit this place?" - "How many times did I log a shower this
month?"

Natural-language search can be a future feature. Do not send private
archive contents to third-party AI services without explicit opt-in and
clear disclosure.

------------------------------------------------------------------------

## 14. Privacy, encryption, and threat model

This is a critical requirement, not an optional enhancement.

The application stores highly sensitive data: personal writing,
photographs, precise location history, routines, and music history. The
design must assume that cloud infrastructure, database credentials, or a
service provider could be exposed.

### Security objective

Implement genuine client-side end-to-end encryption for private content
so that Supabase and its administrators cannot read the plaintext
journal, precise location history, tracker records, or private media.

Be accurate about the limits: end-to-end encryption reduces provider
access but cannot protect data while the device is unlocked and
compromised, from screenshots, or from a malicious app running on the
device.

### Data classification

Classify data into: - Public application configuration. - Account and
sync metadata. - Private encrypted content. - Secret credentials and
encryption keys.

Minimize plaintext metadata. Even encrypted content can leak information
through record sizes, timestamps, access patterns, object counts, or
unencrypted identifiers. Document these residual risks.

### Encryption design

-   Use a vetted, maintained cryptographic library.
-   Use authenticated encryption such as AES-256-GCM or
    XChaCha20-Poly1305.
-   Use a unique nonce/IV per encryption operation according to the
    algorithm's requirements.
-   Never implement cryptographic primitives yourself.
-   Use a secure password-based key derivation function such as Argon2id
    with documented parameters, or a well-reviewed key hierarchy.
-   Keep root encryption keys on-device using platform secure storage.
-   Never upload plaintext encryption keys.
-   Encrypt journal content, tracker values, exact coordinates, location
    names, sensitive timestamps where feasible, and media before upload.
-   Encrypt attachments locally before they enter cloud storage.
-   Authenticate ciphertext and relevant metadata.
-   Support key rotation with a documented migration procedure.
-   Do not silently downgrade to plaintext.
-   Do not log keys, tokens, plaintext records, or sensitive
    coordinates.

### Multi-device key management

Design a secure process to add a new device: - Authenticate the
account. - Authorize the new device from an existing trusted device or
use a carefully designed recovery-key flow. - Transfer or unwrap
encryption keys securely. - Show active devices and allow revocation. -
Explain that revoking a device cannot erase plaintext it previously
downloaded. - Do not make a server password alone sufficient to decrypt
private data.

### Recovery

Provide a recovery key or recovery phrase that the user can store
offline. Explain clearly that if all trusted devices and recovery
material are lost, encrypted data may be unrecoverable.

Do not create a hidden provider-controlled recovery backdoor.

### Supabase controls

-   Enable Row Level Security on every user-scoped table.
-   Deny access by default.
-   Use private storage buckets.
-   Use short-lived signed access only where needed, and only for
    already-encrypted objects.
-   Never expose the Supabase service-role key in the Flutter app.
-   Use least-privilege database policies.
-   Validate ownership server-side.
-   Rate-limit sensitive endpoints.
-   Keep secrets in server-side secret storage.
-   Separate authentication identity from encryption identity.
-   Test that one account cannot read, modify, or delete another
    account's records.

### App protection

-   Optional biometric or PIN app lock.
-   Secure session handling.
-   Automatic lock after configurable inactivity.
-   Hide sensitive content in app switcher previews where supported.
-   Avoid sensitive notification previews by default.
-   Avoid private content in crash reports and analytics.
-   Provide a panic/quick-hide option only if it can be implemented
    safely and predictably.

### Important security rule

Do not market the application as "unhackable" or "100% secure." Provide
a clear threat model, security limitations, and a plan for independent
review before production release.

------------------------------------------------------------------------

## 15. Supabase cloud sync and local-first storage

Use Supabase for account identity, encrypted record synchronization, and
encrypted media storage.

### Local database

The local database is the primary working copy.

-   All core logging works offline.
-   Writes happen locally first.
-   Sync runs in the background when connectivity is available.
-   Use migrations and schema versioning.
-   Support safe database upgrades.
-   Avoid losing local data if sync fails.
-   Clearly show pending, synced, and failed changes.

### Cloud database

Store encrypted payloads and only the metadata needed for
synchronization.

Suggested record concepts: - User/device identity. - Encrypted record
envelope. - Record ID. - Schema version. - Encryption/key version. -
Revision number. - Sync timestamps. - Tombstone/deletion state. -
Encrypted media object reference.

Avoid exposing sensitive fields in plaintext columns. Design the schema
to minimize metadata leakage.

### Conflict handling

-   Use stable UUIDs.
-   Track revisions and modification times.
-   Detect concurrent edits.
-   Do not silently overwrite a newer record.
-   Provide a conflict-resolution interface when automatic merging is
    unsafe.
-   Merge append-only event records carefully.
-   Preserve deletion tombstones so deleted records do not reappear on
    another device.
-   Make sync idempotent.

### Media synchronization

-   Encrypt media locally before upload.
-   Upload ciphertext only.
-   Verify hashes and upload completion.
-   Support resumable uploads where practical.
-   Handle failed and interrupted uploads.
-   Download only when needed, with local caching.
-   Ensure deleting a media record also handles its cloud object
    according to retention policy.

### Backup and restore

Provide: - Encrypted full archive export. - Encrypted media export. -
Restore from backup. - Backup verification. - Clear explanation of what
is and is not included. - Recovery-key instructions. - Optional
user-controlled backup destination in a future phase.

A backup is not complete until a restore test has succeeded.

------------------------------------------------------------------------

## 16. Notifications and reminders

Optional reminders for: - Daily journaling. - Custom trackers. -
Personal routines. - Daily review. - Incomplete sync or backup. -
Location tracking status where appropriate.

Keep notification content private by default. Allow users to disable
every reminder. Do not use guilt-based streak messages.

------------------------------------------------------------------------

## 17. Data model and domain entities

Design a documented, versioned data model. Suggested domain entities
include:

-   `UserProfile`
-   `Device`
-   `JournalEntry`
-   `MediaAsset`
-   `TimelineEvent`
-   `TrackerDefinition`
-   `TrackerDefinitionVersion`
-   `TrackerRecord`
-   `Place`
-   `LocationSample`
-   `Visit`
-   `Journey`
-   `MusicTrack`
-   `MusicScrobble`
-   `MusicArtist`
-   `MusicAlbum`
-   `Tag`
-   `Reminder`
-   `SyncOperation`
-   `EncryptedRecordEnvelope`
-   `BackupManifest`

Use UUIDs and UTC timestamps internally, while preserving original time
zone context for display. Store time zone identifiers and offsets where
necessary so old events render correctly after travel or daylight-saving
changes.

Separate raw observations from user-confirmed interpretations. For
example, a GPS sample is not the same entity as a confirmed visit to a
named place.

Provide database migrations and tests for every schema change.

------------------------------------------------------------------------

## 18. Permissions and onboarding

Build a thoughtful onboarding flow:

1.  Introduce Lifelog and its purpose.
2.  Explain local-first storage.
3.  Explain encryption and recovery-key responsibility.
4.  Create or sign into an account, if cloud sync is desired.
5.  Set up the encryption key and recovery method.
6.  Offer Last.fm connection.
7.  Explain location tracking and its battery implications.
8.  Request location permissions only when the user enables that
    feature.
9.  Explain photo, camera, microphone, and notification permissions only
    when needed.
10. Let the user begin with manual logging without granting every
    permission.

Never request all permissions immediately on first launch.

------------------------------------------------------------------------

## 19. Accessibility, reliability, and performance

-   Support screen readers and semantic labels.
-   Respect system text scaling.
-   Maintain accessible color contrast.
-   Support reduced motion.
-   Optimize large photo galleries.
-   Paginate historical data.
-   Cache thumbnails.
-   Avoid loading an entire lifetime archive into memory.
-   Use background processing carefully.
-   Handle app termination and restart.
-   Handle time-zone changes.
-   Handle device clock changes.
-   Handle offline and intermittent connectivity.
-   Show recoverable errors with useful actions.
-   Avoid blocking the UI during encryption or sync.

------------------------------------------------------------------------

## 20. Testing requirements

### Unit tests

Test: - Domain rules. - Tracker calculations. - Timeline sorting. -
Time-zone conversion. - Encryption/decryption. - Key derivation and key
rotation. - Sync conflict resolution. - Last.fm parsing and
deduplication. - Location-stop inference.

### Widget tests

Test: - Today screen. - Journal editor. - Quick-add flow. - Tracker
creation and logging. - Timeline. - Calendar. - Map controls. - Last.fm
connection state. - Privacy and settings screens.

### Integration tests

Test: - Create an entry offline and sync later. - Attach and encrypt a
photo. - Restore a backup. - Add a second authorized device. - Revoke a
device. - Disconnect Last.fm. - Delete an account and its cloud data. -
Handle interrupted uploads. - Correct a detected location visit.

### Security tests

Test: - Cross-user access denial. - RLS policy enforcement. - Private
storage access. - No plaintext private content in cloud payloads. - No
secrets in app logs. - Token protection. - Encryption failure
handling. - Recovery flow. - Device revocation behavior.

Use synthetic test data only. Never use the developer's real personal
location or private journal entries in test fixtures.

------------------------------------------------------------------------

## 21. Development phases and deliverables

Build in phases, but keep the architecture production-oriented from the
beginning.

### Phase 0 --- Research and architecture

Deliver: - Architecture decision records. - Threat model. -
Privacy/data-flow diagram. - Package and platform compatibility
review. - Database design. - Encryption/key-management design. -
Background-location feasibility assessment for Android and iOS. -
Last.fm API integration plan. - Cost and provider comparison.

Do not start by generating dozens of screens before these decisions are
made.

### Phase 1 --- App foundation

Implement: - Flutter project setup. - Design system. - Navigation. -
Local database. - Domain entities. - Error handling. - Light/dark
themes. - Basic settings and onboarding.

### Phase 2 --- Core logging

Implement: - Today dashboard. - Journal. - Media attachments. - Custom
tracker builder. - Tracker logging. - Calendar. - Local search.

At the end of this phase, the app must be useful offline.

### Phase 3 --- Timeline and memories

Implement: - Unified timeline. - Daily memory page. - Photo gallery. -
On This Day. - Timeline editing and source indicators.

### Phase 4 --- Location

Implement: - Permission onboarding. - Manual location logging. -
Background tracking. - Stop detection suggestions. - Journeys and route
display. - Daily map. - Location history editing and deletion.

Test on real Android and iOS devices. Clearly document OS-specific
limitations.

### Phase 5 --- Last.fm

Implement: - Account connection. - Recent track import. - Historical
backfill where available. - Daily artist, album, and track statistics. -
Timeline music events. - Duplicate prevention. - Sync cursor and error
handling.

### Phase 6 --- Encryption and cloud synchronization

Implement and verify: - Client-side encryption. - Key management and
recovery. - Supabase Auth. - RLS. - Encrypted record sync. - Encrypted
media storage. - Multi-device authorization. - Conflict resolution. -
Device revocation. - Encrypted backup and restore.

Do not release cloud sync until security tests pass.

### Phase 7 --- Insights and advanced search

Implement: - Charts and summaries. - Historical comparisons. - Music
insights. - Location analytics. - Advanced local search. - Cross-feature
memory connections.

### Phase 8 --- Production hardening

Implement: - Performance improvements. - Accessibility review. -
Security review. - Crash/error handling without leaking private
content. - Backup/restore verification. - App store preparation. -
Privacy policy and data-flow documentation. - Release checklist.

------------------------------------------------------------------------

## 22. Definition of done

The app is not complete merely because screens render.

A feature is complete only when: - It has working UI and business
logic. - Data persists across app restarts. - Offline behavior is
defined and tested. - Sync behavior is defined and tested where
applicable. - Permissions are requested responsibly. - Errors and empty
states are handled. - Sensitive data is protected. - Automated tests
cover important behavior. - Documentation explains setup and
limitations.

Do not leave fake buttons, hardcoded sample timelines, placeholder
statistics, or nonfunctional settings in the production build.

------------------------------------------------------------------------

## 23. Instructions to the coding agent

Act as a senior Flutter engineer, mobile architect, product designer,
and security-conscious technical lead.

Before writing implementation code:

1.  Inspect the repository and identify existing code and constraints.
2.  Produce an implementation plan and architecture documents.
3.  Identify technical risks, especially background location, end-to-end
    encryption, key recovery, and Last.fm API constraints.
4.  Verify current official documentation and package compatibility.
5.  Ask for required credentials only when needed. Never request or
    commit secrets in source control.
6.  Define milestones and acceptance criteria.

Then implement incrementally.

After each phase: - Run formatting and static analysis. - Run relevant
tests. - Fix failures before continuing. - Update documentation. -
Summarize what works and what remains. - Keep the app runnable.

If a feature cannot be implemented reliably due to platform restrictions
or API limitations, explain the limitation and implement the safest
honest alternative. Never simulate a feature and present it as real.

Do not compromise encryption to make synchronization easier. Do not
weaken location permission controls to make tracking appear more
continuous. Do not send private archive content to external AI services.

The final product should be a reliable, elegant, private, long-term
personal archive.

------------------------------------------------------------------------

## 24. Final product vision

Imagine opening Lifelog ten years from now.

You choose a random date. You see the photos you took, what you wrote,
where you went, the route you traveled, the places where you spent time,
the activities you logged, and the songs and artists you listened to
that day.

You can move from a timeline to a map to a journal page. You can search
for a place, song, memory, or random detail and find the day it
happened.

The app should preserve the little details that normally disappear from
memory. It should feel like a private digital record of your life,
controlled by you, stored securely, and usable for years.

**Build Lifelog as a real, production-quality Flutter application---not
a mockup.**

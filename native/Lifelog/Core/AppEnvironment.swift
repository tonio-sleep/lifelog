import Foundation
import SwiftUI

/// Runs CPU-heavy or file-heavy work away from the UI actor. The caller stays
/// responsible for publishing any resulting state changes on the main actor.
private func runOffMain<T>(
    priority: TaskPriority = .userInitiated,
    _ work: @escaping @Sendable () throws -> T
) async throws -> T {
    try await Task.detached(priority: priority, operation: work).value
}

@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let crypto: CryptoService
    let mediaStore: MediaStore
    let lastfm: LastFMService
    let cloudflare: CloudflareService
    let health: HealthService
    let location: LocationService

    @Published var archive: Archive
    @Published var settings: AppSettings
    @Published var isLocked: Bool
    @Published var isWorking: Bool = false
    @Published var syncStatus: String = "On this device"
    @Published var toast: String?
    @Published var usedFallbackKey: Bool = false

    init() {
        do {
            try Paths.prepare()
            let vault = try KeyVault.loadOrCreate(in: Paths.root)
            usedFallbackKey = vault.usedFallback
            crypto = CryptoService(key: vault.key)
            mediaStore = MediaStore(directory: Paths.media, crypto: crypto)
            settings = SettingsStore.load()
            archive = (try ArchiveStore.load(crypto: crypto)) ?? .empty
            isLocked = settings.lockEnabled && settings.pinHash != nil
        } catch {
            fatalError("Lifelog could not open its encrypted store: \(error.localizedDescription)")
        }
        lastfm = LastFMService()
        cloudflare = CloudflareService()
        health = HealthService()
        location = LocationService(trackingEnabled: settings.locationTrackingEnabled)

        location.onSample = { [weak self] sample in
            Task { @MainActor in self?.record(sample) }
        }
        location.onVisit = { [weak self] visit in
            Task { @MainActor in self?.record(visit) }
        }
    }

    // MARK: - Persistence

    func save() {
        do {
            try ArchiveStore.save(archive, crypto: crypto)
            try SettingsStore.save(settings)
        } catch {
            toast = "Could not save your journal. Please try again."
        }
    }

    private func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        do { try SettingsStore.save(settings) } catch { toast = "Could not save settings." }
    }

    func present(_ message: String) { toast = message }

    // MARK: - Lock

    func unlock(with pin: String) async -> Bool {
        guard let salt = settings.pinSalt, let hash = settings.pinHash else {
            isLocked = false
            return true
        }
        let verified: Bool
        do {
            verified = try await runOffMain { PinHasher.verify(pin: pin, salt: salt, hash: hash) }
        } catch {
            return false
        }
        guard verified else { return false }
        isLocked = false
        return true
    }

    func setPin(_ pin: String) async {
        let result: (salt: String, hash: String)
        do {
            result = try await runOffMain { PinHasher.create(pin) }
        } catch {
            present("Could not enable screen lock. Please try again.")
            return
        }
        updateSettings {
            $0.lockEnabled = true
            $0.pinSalt = result.salt
            $0.pinHash = result.hash
        }
        present("Screen lock enabled.")
    }

    func removePin() {
        updateSettings {
            $0.lockEnabled = false
            $0.pinSalt = nil
            $0.pinHash = nil
        }
        isLocked = false
        present("Screen lock disabled.")
    }

    func lock() {
        guard settings.lockEnabled, settings.pinHash != nil else { return }
        isLocked = true
    }

    // MARK: - Records

    func saveEntry(_ entry: JournalEntry) {
        var entry = entry
        entry.updatedAt = Date()
        archive = archive.puttingEntry(entry)
        save()
    }

    func deleteEntry(_ entry: JournalEntry) {
        archive = archive.removingEntry(entry.id, detachMedia: true)
        save()
    }

    func saveEvent(_ event: TimelineEvent) {
        archive = archive.puttingEvent(event)
        save()
    }

    func deleteEvent(_ id: String) {
        archive.events.removeAll { $0.id == id }
        save()
    }

    func saveTracker(_ tracker: TrackerDefinition) {
        archive = archive.puttingTracker(tracker)
        save()
    }

    func deleteTracker(_ id: String) {
        archive.trackers.removeAll { $0.id == id }
        archive.trackerRecords.removeAll { $0.trackerId == id }
        save()
    }

    func saveTrackerRecord(_ record: TrackerRecord) {
        archive = archive.puttingRecord(record)
        save()
    }

    func deleteTrackerRecord(_ id: String) {
        archive.trackerRecords.removeAll { $0.id == id }
        save()
    }

    func savePlace(_ place: Place) {
        archive = archive.puttingPlace(place)
        save()
    }

    func saveVisit(_ visit: Visit) {
        archive = archive.puttingVisit(visit)
        save()
    }

    func record(_ visit: Visit) {
        archive = archive.puttingVisit(visit)
        save()
    }

    func record(_ sample: LocationSample) {
        archive.locationSamples.append(sample)
        if archive.locationSamples.count > 20_000 {
            archive.locationSamples.removeFirst(archive.locationSamples.count - 20_000)
        }
        save()
    }

    @discardableResult
    func importMedia(_ data: Data, fileName: String, caption: String = "", journalEntryId: String? = nil) -> MediaItem? {
        do {
            let item = try mediaStore.importBytes(data, fileName: fileName, caption: caption, journalEntryId: journalEntryId)
            archive = archive.puttingMedia(item)
            save()
            return item
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func deleteMedia(_ item: MediaItem) {
        mediaStore.delete(item)
        archive.media.removeAll { $0.id == item.id }
        save()
    }

    func toggleMediaFavorite(_ item: MediaItem) {
        var item = item
        item.favorite.toggle()
        archive = archive.puttingMedia(item)
        save()
    }

    func importScrobbles(_ incoming: [MusicScrobble]) -> Int {
        guard !incoming.isEmpty else { return 0 }
        var seen = Set(archive.scrobbles.map(\.dedupeKey))
        var fresh: [MusicScrobble] = []
        for scrobble in incoming where seen.insert(scrobble.dedupeKey).inserted {
            fresh.append(scrobble)
        }
        guard !fresh.isEmpty else { return 0 }
        archive.scrobbles.append(contentsOf: fresh)
        save()
        return fresh.count
    }

    func addManualTrack(artist: String, title: String, album: String) {
        let track = MusicScrobble.manual(artist: artist, title: title, album: album)
        _ = importScrobbles([track])
    }

    func deleteScrobble(_ id: String) {
        archive.scrobbles.removeAll { $0.id == id }
        save()
    }

    func removeImportedMusic() {
        archive.scrobbles.removeAll { $0.source != "manual" }
        save()
    }

    // MARK: - Health

    func syncHealth() async {
        guard let summary = try? await health.dailySummary(for: Date()) else { return }
        guard summary.steps != nil || summary.sleepHours != nil else { return }
        let day = Dates.dayStart(Date())
        if let entry = archive.dailyEntryFor(day) {
            var entry = entry
            if let steps = summary.steps { entry.steps = steps }
            if let sleep = summary.sleepHours { entry.sleepHours = sleep }
            saveEntry(entry)
        } else {
            var entry = JournalEntry(
                createdAt: Dates.momentForDay(day),
                title: "Daily metrics",
                kind: .note
            )
            entry.steps = summary.steps
            entry.sleepHours = summary.sleepHours
            saveEntry(entry)
        }
    }

    // MARK: - Last.fm

    func lastfmApiKey() -> String? {
        guard let cipher = settings.lastfmApiKeyCipher else { return nil }
        return try? crypto.decryptString(cipher, aad: AAD.lastfmKey)
    }

    func connectLastfm(username: String, apiKey: String) {
        do {
            let cipher = try crypto.encryptString(apiKey, aad: AAD.lastfmKey)
            updateSettings {
                $0.lastfmUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
                $0.lastfmApiKeyCipher = cipher
                $0.lastfmConnectedAt = Date()
            }
            present("Last.fm connected.")
        } catch {
            present("Could not save your Last.fm API key.")
        }
    }

    func disconnectLastfm() {
        updateSettings {
            $0.lastfmUsername = nil
            $0.lastfmApiKeyCipher = nil
            $0.lastfmConnectedAt = nil
            $0.lastfmLastSync = nil
            $0.lastfmLastSyncFrom = nil
        }
        present("Last.fm disconnected.")
    }

    @discardableResult
    func syncLastfm() async -> Int? {
        guard settings.lastfmConnected,
              let username = settings.lastfmUsername,
              let apiKey = lastfmApiKey() else { return nil }
        let now = Date()
        let from: Date
        if let last = settings.lastfmLastSync {
            from = Dates.addingDays(-1, to: last)
        } else {
            from = Dates.addingDays(-14, to: now)
        }
        do {
            let tracks = try await lastfm.fetchRecentTracks(username: username, apiKey: apiKey, from: from, to: now, maxPages: 12)
            let added = importScrobbles(tracks)
            updateSettings {
                $0.lastfmLastSync = now
                $0.lastfmLastSyncFrom = tracks.first?.playedAt ?? $0.lastfmLastSyncFrom
            }
            return added
        } catch {
            present(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Cloudflare sync

    func cloudflareSession() -> CloudflareSession? {
        guard let cipher = settings.cloudflareSessionCipher,
              let json = try? crypto.decryptString(cipher, aad: AAD.cloudflareSession),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder.lifelog.decode(CloudflareSession.self, from: data)
    }

    func saveCloudflareSession(_ session: CloudflareSession) {
        do {
            let data = try JSONEncoder.lifelog.encode(session)
            let json = String(decoding: data, as: UTF8.self)
            let cipher = try crypto.encryptString(json, aad: AAD.cloudflareSession)
            updateSettings {
                $0.cloudflareWorkerUrl = CloudflareService.normalizeBaseURL($0.cloudflareWorkerUrl ?? AppSettings.defaultCloudflareWorkerUrl)
                $0.cloudflareUsername = session.username
                $0.cloudflareSessionCipher = cipher
                $0.cloudflareConnectedAt = Date()
                $0.cloudflareSetupDone = true
            }
            syncStatus = "Signed in as \(session.username)"
        } catch {
            present("Could not save your sync session.")
        }
    }

    func signOutCloudflare() {
        updateSettings {
            $0.cloudflareUsername = nil
            $0.cloudflareSessionCipher = nil
            $0.cloudflareConnectedAt = nil
        }
        syncStatus = "On this device"
        present("Signed out of Cloudflare sync.")
    }

    func cloudBackupInfo() async -> CloudflareBackupMeta? {
        guard let session = cloudflareSession(),
              let worker = settings.cloudflareWorkerUrl else { return nil }
        return try? await cloudflare.getBackupMeta(baseURL: worker, token: session.token)
    }

    func backupToCloud(passphrase: String) async -> Bool {
        guard let session = cloudflareSession(),
              let worker = settings.cloudflareWorkerUrl else {
            present("Sign in to Cloudflare sync in Settings first.")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let snapshot = archive
            let store = mediaStore
            let bytes = try await runOffMain {
                try BackupService.create(archive: snapshot, passphrase: passphrase, mediaStore: store)
            }
            try await cloudflare.uploadBackup(baseURL: worker, token: session.token, bytes: bytes)
            updateSettings { $0.cloudflareLastSyncAt = Date() }
            syncStatus = "Synced \(Dates.formatTime(Date()))"
            present("Encrypted backup synced to Cloudflare. Keep your backup passphrase safe.")
            return true
        } catch {
            present("Could not sync backup: \(error.localizedDescription)")
            return false
        }
    }

    func restoreFromCloud(passphrase: String) async -> Bool {
        guard let session = cloudflareSession(),
              let worker = settings.cloudflareWorkerUrl else {
            present("Sign in to Cloudflare sync in Settings first.")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let bytes = try await cloudflare.downloadBackup(baseURL: worker, token: session.token)
            try await restoreBackup(bytes, passphrase: passphrase)
            return true
        } catch {
            present("Could not restore cloud backup: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Backup files

    func exportBackup(passphrase: String) async -> URL? {
        let snapshot = archive
        let store = mediaStore
        do {
            let url = try await runOffMain { () -> URL in
                let bytes = try BackupService.create(archive: snapshot, passphrase: passphrase, mediaStore: store)
                try Paths.prepare()
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let target = Paths.backups.appendingPathComponent("lifelog-\(formatter.string(from: Date())).json")
                try bytes.write(to: target, options: [.atomic])
                return target
            }
            updateSettings { $0.lastBackupAt = Date() }
            return url
        } catch {
            present(error.localizedDescription)
            return nil
        }
    }

    func restoreBackup(_ data: Data, passphrase: String) async throws {
        let vaultKey = crypto
        let restored = try await runOffMain { () -> Archive in
            let contents = try BackupService.read(data: data, passphrase: passphrase)

            // Stage every media file first. Existing data stays untouched until
            // the whole backup has been written successfully.
            let fm = FileManager.default
            let suffix = UUID().uuidString.lowercased()
            let stagedDirectory = Paths.root.appendingPathComponent("media-restore-\(suffix)", isDirectory: true)
            let previousDirectory = Paths.root.appendingPathComponent("media-previous-\(suffix)", isDirectory: true)
            try fm.createDirectory(at: stagedDirectory, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stagedDirectory) }

            let stagedStore = MediaStore(directory: stagedDirectory, crypto: vaultKey)
            let byId = Dictionary(
                contents.archive.media.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for file in contents.mediaFiles {
                guard let item = byId[file.id] else { continue }
                try stagedStore.writeRestoredItem(item, original: file.original, thumbnail: file.thumbnail)
            }

            var movedExistingMedia = false
            try? fm.removeItem(at: previousDirectory)
            if fm.fileExists(atPath: Paths.media.path) {
                try fm.moveItem(at: Paths.media, to: previousDirectory)
                movedExistingMedia = true
            }
            do {
                try fm.moveItem(at: stagedDirectory, to: Paths.media)
                try ArchiveStore.save(contents.archive, crypto: vaultKey)
            } catch {
                try? fm.removeItem(at: Paths.media)
                try? fm.createDirectory(at: Paths.media, withIntermediateDirectories: true)
                if movedExistingMedia {
                    try? fm.moveItem(at: previousDirectory, to: Paths.media)
                }
                throw error
            }
            if movedExistingMedia { try? fm.removeItem(at: previousDirectory) }

            MediaStore.clearCache()
            return contents.archive
        }

        archive = restored
        present("Backup restored.")
    }

    func clearAllData() {
        mediaStore.deleteAll()
        archive = .empty
        save()
        present("All local journal data was erased.")
    }

    // MARK: - Settings conveniences

    func setThemeMode(_ mode: AppThemeMode) { updateSettings { $0.themeMode = mode } }
    func setLocationTracking(_ enabled: Bool) {
        updateSettings { $0.locationTrackingEnabled = enabled }
        location.trackingEnabled = enabled
        if enabled {
            location.requestPermission()
            location.start()
        } else {
            location.stop()
        }
    }
    func setShowArtwork(_ enabled: Bool) { updateSettings { $0.showArtwork = enabled } }
    func setWeekStartsMonday(_ enabled: Bool) { updateSettings { $0.weekStartsMonday = enabled } }
    func setAutoLockMinutes(_ minutes: Int) { updateSettings { $0.autoLockMinutes = min(240, max(0, minutes)) } }
}

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette
    @State private var showPin = false
    @State private var showLastfm = false
    @State private var showCloudflare = false
    @State private var showBackupImporter = false
    @State private var importedData: Data?
    @State private var showImportPassphrase = false
    @State private var showCloudPassphrase: CloudPassphraseMode?
    @State private var showCloudInfo = false
    @State private var showClearConfirm = false
    @State private var showReminders = false
    @State private var showHealthAlert = false

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { env.settings.themeMode },
                    set: { env.setThemeMode($0) }
                )) {
                    Text("System").tag(AppThemeMode.system)
                    Text("Light").tag(AppThemeMode.light)
                    Text("Dark").tag(AppThemeMode.dark)
                }
                Toggle("Show album artwork", isOn: Binding(
                    get: { env.settings.showArtwork },
                    set: { env.setShowArtwork($0) }
                ))
                Toggle("Week starts Monday", isOn: Binding(
                    get: { env.settings.weekStartsMonday },
                    set: { env.setWeekStartsMonday($0) }
                ))
            }

            Section("Privacy") {
                Button { showPin = true } label: {
                    Label(env.settings.lockEnabled ? "Change screen lock PIN" : "Set screen lock PIN", systemImage: "lock")
                }
                if env.settings.lockEnabled {
                    Picker("Auto-lock", selection: Binding(
                        get: { env.settings.autoLockMinutes },
                        set: { env.setAutoLockMinutes($0) }
                    )) {
                        Text("Manual only").tag(0)
                        Text("After 1 minute").tag(1)
                        Text("After 5 minutes").tag(5)
                        Text("After 10 minutes").tag(10)
                        Text("After 15 minutes").tag(15)
                        Text("After 30 minutes").tag(30)
                        Text("After 1 hour").tag(60)
                    }
                }
                Text("The PIN is a convenience screen lock. Archive encryption uses the key stored in your device Keychain.")
                    .font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                if env.usedFallbackKey {
                    Text("Keychain was unavailable when this journal was created, so the encryption key is kept in a local fallback file. Keep device backups current.")
                        .font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                }
            }

            Section("Connected services") {
                Button { showLastfm = true } label: {
                    HStack {
                        Label("Last.fm", systemImage: "music.note")
                        Spacer()
                        Text(env.settings.lastfmConnected ? (env.settings.lastfmUsername ?? "Connected") : "Not connected")
                            .font(LifelogTheme.sans(12)).foregroundStyle(palette.secondary)
                    }
                }
                Button { showCloudflare = true } label: {
                    HStack {
                        Label("Cloudflare sync", systemImage: "icloud.and.arrow.up")
                        Spacer()
                        Text(env.settings.cloudflareUsername ?? "Not connected")
                            .font(LifelogTheme.sans(12)).foregroundStyle(palette.secondary)
                    }
                }
                if env.settings.cloudflareConnected {
                    HStack {
                        Label("Status", systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        Text(env.syncStatus).font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                    }
                    Button { showCloudPassphrase = .backup } label: {
                        Label("Back up encrypted archive", systemImage: "arrow.up.arrow.down.circle")
                    }
                    Button { showCloudPassphrase = .restore } label: {
                        Label("Restore from cloud backup", systemImage: "arrow.down.circle")
                    }
                }
                Button {
                    Task { await requestHealthAccess() }
                } label: {
                    Label("Apple Health access", systemImage: "heart")
                }
                Toggle("Location visits", isOn: Binding(
                    get: { env.settings.locationTrackingEnabled },
                    set: { env.setLocationTracking($0) }
                ))
                NavigationLink { RemindersView().environmentObject(env) } label: {
                    Label("Reminders", systemImage: "bell")
                }
            }

            Section("Backup") {
                if let last = env.settings.lastBackupAt {
                    Text("Last local export: \(Dates.formatDayLong(last))")
                        .font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                }
                Button { showBackupImporter = true } label: {
                    Label("Restore from backup file", systemImage: "square.and.arrow.down")
                }
                NavigationLink { BackupGuideView() } label: {
                    Label("How backups work", systemImage: "questionmark.circle")
                }
            }

            Section("Data") {
                NavigationLink { MediaGalleryView().environmentObject(env) } label: {
                    Label("Media vault", systemImage: "photo.stack")
                }
                Button(role: .destructive) { showClearConfirm = true } label: {
                    Label("Erase local data", systemImage: "trash")
                }
            }

            Section {
                HStack {
                    Text("Lifelog").font(LifelogTheme.serif(15))
                    Spacer()
                    Text("Native archive v1").font(LifelogTheme.sans(11)).foregroundStyle(palette.tertiary)
                }
                Text("Your journal is stored locally. Connected services are optional.")
                    .font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showPin) { PinSettingsView().environmentObject(env) }
        .sheet(isPresented: $showLastfm) { LastfmSettingsView().environmentObject(env) }
        .sheet(isPresented: $showCloudflare) { CloudflareConnectView().environmentObject(env) }
        .sheet(item: $showCloudPassphrase) { mode in
            CloudPassphraseView(mode: mode).environmentObject(env)
        }
        .sheet(isPresented: $showImportPassphrase) {
            if let importedData {
                BackupImportView(data: importedData).environmentObject(env)
            }
        }
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                importedData = try? Data(contentsOf: url)
                url.stopAccessingSecurityScopedResource()
                if importedData != nil { showImportPassphrase = true }
            case .failure:
                env.present("Could not open that backup file.")
            }
        }
        .alert("Erase all local data?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Erase", role: .destructive) { env.clearAllData() }
        } message: {
            Text("This removes the local archive and encrypted media from this device. It does not delete an encrypted cloud backup.")
        }
        .alert("Health access requested", isPresented: $showHealthAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Lifelog reads steps and sleep only when you allow it in Apple Health. Nothing is uploaded.")
        }
    }

    @MainActor
    private func requestHealthAccess() async {
        _ = await env.health.requestPermission()
        await env.syncHealth()
        showHealthAlert = true
    }
}

enum CloudPassphraseMode: String, Identifiable {
    case backup, restore
    var id: String { rawValue }
}

// MARK: - PIN

private struct PinSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var pin = ""
    @State private var confirm = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New PIN (4–12 digits)", text: $pin)
                        .keyboardType(.numberPad)
                    SecureField("Repeat PIN", text: $confirm)
                        .keyboardType(.numberPad)
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                    Button("Enable screen lock") {
                        guard pin.count >= 4, pin.count <= 12, pin.allSatisfy(\.isNumber) else {
                            error = "Use 4 to 12 digits."
                            return
                        }
                        guard pin == confirm else {
                            error = "The two PINs do not match."
                            return
                        }
                        let chosen = pin
                        Task {
                            await env.setPin(chosen)
                            await MainActor.run { dismiss() }
                        }
                    }
                    .disabled(pin.isEmpty || confirm.isEmpty)
                }
                if env.settings.lockEnabled {
                    Section {
                        Button(role: .destructive) {
                            env.removePin()
                            dismiss()
                        } label: { Label("Disable screen lock", systemImage: "lock.open") }
                    }
                }
            }
            .navigationTitle("Screen lock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Last.fm

private struct LastfmSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var username: String
    @State private var apiKey = ""

    init() { _username = State(initialValue: "") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Last.fm username", text: $username)
                        .textInputAutocapitalization(.never)
                    SecureField("API key", text: $apiKey)
                    Button("Connect") {
                        env.connectLastfm(username: username, apiKey: apiKey)
                        dismiss()
                    }
                    .disabled(username.isEmpty || apiKey.isEmpty)
                }
                Section {
                    Text("A read-only API key is enough. Lifelog never stores your Last.fm password or shared secret.")
                        .font(LifelogTheme.sans(11)).foregroundStyle(.secondary)
                }
                if env.settings.lastfmConnected {
                    Section {
                        Button("Sync now") {
                            Task { _ = await env.syncLastfm() }
                            dismiss()
                        }
                        Button(role: .destructive) {
                            env.disconnectLastfm()
                            dismiss()
                        } label: { Label("Disconnect Last.fm", systemImage: "link.badge.plus") }
                    }
                }
            }
            .navigationTitle("Last.fm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { username = env.settings.lastfmUsername ?? "" }
        }
    }
}

// MARK: - Cloudflare

private struct CloudflareConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var workerURL: String
    @State private var username = ""
    @State private var password = ""
    @State private var createAccount = false
    @State private var isWorking = false
    @State private var error = ""

    init() { _workerURL = State(initialValue: AppSettings.defaultCloudflareWorkerUrl) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Worker URL", text: $workerURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                    Toggle("Create account", isOn: $createAccount)
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                    Button(isWorking ? "Working…" : (createAccount ? "Create account" : "Sign in")) { signIn() }
                        .disabled(username.isEmpty || password.isEmpty || isWorking)
                }
                Section {
                    Text("Cloudflare sync is optional. Your journal works fully without an account; this only stores encrypted backup files.")
                        .font(LifelogTheme.sans(11)).foregroundStyle(.secondary)
                }
                if env.settings.cloudflareConnected {
                    Section {
                        Button(role: .destructive) {
                            env.signOutCloudflare()
                            dismiss()
                        } label: { Label("Sign out on this device", systemImage: "rectangle.portrait.and.arrow.right") }
                    }
                }
            }
            .navigationTitle("Cloudflare sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                workerURL = env.settings.cloudflareWorkerUrl ?? AppSettings.defaultCloudflareWorkerUrl
                username = env.settings.cloudflareUsername ?? ""
            }
        }
    }

    private func signIn() {
        isWorking = true
        error = ""
        let service = env.cloudflare
        let base = CloudflareService.normalizeBaseURL(workerURL)
        let requestedUsername = username
        let requestedPassword = password
        let shouldCreateAccount = createAccount
        Task {
            do {
                var session: CloudflareSession?
                if shouldCreateAccount {
                    do {
                        session = try await service.register(baseURL: base, username: requestedUsername, password: requestedPassword)
                    } catch {
                        let text = error.localizedDescription.lowercased()
                        if !text.contains("already") && !text.contains("exists") { throw error }
                    }
                }
                if session == nil {
                    session = try await service.login(baseURL: base, username: requestedUsername, password: requestedPassword)
                }
                if let session {
                    await MainActor.run {
                        env.saveCloudflareSession(session)
                        isWorking = false
                        dismiss()
                    }
                } else {
                    await MainActor.run { isWorking = false }
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    self.error = message
                    isWorking = false
                }
            }
        }
    }
}

private struct CloudPassphraseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    let mode: CloudPassphraseMode
    @State private var passphrase = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Backup passphrase", text: $passphrase)
                    Button(mode == .backup ? "Back up now" : "Restore now") {
                        let chosen = passphrase
                        let selectedMode = mode
                        let environment = env
                        isWorking = true
                        Task {
                            let succeeded: Bool
                            if selectedMode == .backup {
                                succeeded = await environment.backupToCloud(passphrase: chosen)
                            } else {
                                succeeded = await environment.restoreFromCloud(passphrase: chosen)
                            }
                            await MainActor.run {
                                isWorking = false
                                if succeeded { dismiss() }
                            }
                        }
                    }
                    .disabled(passphrase.isEmpty || isWorking)
                }
                Section {
                    Text("This is the passphrase used for the encrypted backup file, not your Cloudflare account password.")
                        .font(LifelogTheme.sans(11)).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(mode == .backup ? "Cloud backup" : "Cloud restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Local backup import

private struct BackupImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    let data: Data
    @State private var passphrase = ""
    @State private var error = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Backup passphrase", text: $passphrase)
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                    Button(isWorking ? "Restoring…" : "Restore") {
                        let chosen = passphrase
                        let environment = env
                        isWorking = true
                        Task {
                            do {
                                try await environment.restoreBackup(data, passphrase: chosen)
                                await MainActor.run { dismiss() }
                            } catch {
                                let message = error.localizedDescription
                                await MainActor.run {
                                    self.error = message
                                    isWorking = false
                                }
                            }
                        }
                    }
                    .disabled(passphrase.isEmpty || isWorking)
                }
                Section {
                    Text("Restoring replaces the data on this device with the backup contents.")
                        .font(LifelogTheme.sans(11)).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Restore backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct BackupGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("How backups work")
                    .font(LifelogTheme.serif(26, relativeTo: .title))
                Text("A backup is a JSON file containing an AES-256-GCM encrypted payload. The key is derived from your passphrase with Argon2id.")
                Text("Media files that are still available are decrypted on this device, packed into the encrypted payload, and re-encrypted with the backup key. A restore needs only the backup passphrase.")
                Text("Keep the passphrase separate from the file. Nobody can recover it for you.")
            }
            .font(LifelogTheme.sans(14))
            .padding(20)
        }
        .navigationTitle("Backups")
    }
}

// MARK: - Reminders

struct RemindersView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette

    var body: some View {
        List {
            Section {
                Text("Gentle nudges, never streaks or pressure.")
                    .font(LifelogTheme.sans(12)).foregroundStyle(palette.secondary)
            }
            ForEach(env.settings.reminders) { reminder in
                ReminderRow(reminder: reminder)
            }
            Section {
                Button {
                    let next = ReminderItem(title: "Evening reflection", hour: 20, minute: 0)
                    env.settings.reminders.append(next)
                    env.save()
                    Task { await NotificationService.sync(env.settings.reminders) }
                } label: {
                    Label("Add reminder", systemImage: "plus")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("Reminders")
    }
}

private struct ReminderRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let reminder: ReminderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(reminder.title.isEmpty ? "Reminder" : reminder.title, isOn: Binding(
                get: { reminder.enabled },
                set: { value in
                    guard let index = env.settings.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
                    env.settings.reminders[index].enabled = value
                    env.save()
                    Task { await NotificationService.sync(env.settings.reminders) }
                }
            ))
            DatePicker("", selection: Binding(
                get: { timeDate(reminder) },
                set: { value in
                    guard let index = env.settings.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: value)
                    env.settings.reminders[index].hour = comps.hour ?? 9
                    env.settings.reminders[index].minute = comps.minute ?? 0
                    env.save()
                    Task { await NotificationService.sync(env.settings.reminders) }
                }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
    }

    private func timeDate(_ reminder: ReminderItem) -> Date {
        var comps = DateComponents()
        comps.hour = reminder.hour
        comps.minute = reminder.minute
        return Calendar.current.date(from: comps) ?? Date()
    }
}

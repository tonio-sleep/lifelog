import SwiftUI
import UniformTypeIdentifiers

private extension View {
    func settingsRow() -> some View {
        self.listRowBackground(Palette.surface)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.dismiss) private var dismiss

    @State private var showPin = false
    @State private var showBackupExport = false
    @State private var showFileImporter = false
    @State private var importedData: IdentifiableData?
    @State private var showCloudflare = false
    @State private var cloudMode: CloudPassphraseMode?
    @State private var confirmErase = false
    @State private var cloudInfo: String?

    private let lockOptions: [Int] = [0, 1, 5, 15, 30, 60]

    var body: some View {
        List {
            appearance
            security
            sources
            library
            backup
            about
        }
        .listStyle(.insetGrouped)
        .paperList()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
        }
        .sheet(isPresented: $showPin) { PinSettingsView().environmentObject(env) }
        .sheet(isPresented: $showBackupExport) { BackupExportSheet().environmentObject(env) }
        .sheet(isPresented: $showCloudflare) { CloudflareConnectView().environmentObject(env) }
        .sheet(item: $cloudMode) { mode in CloudPassphraseView(mode: mode).environmentObject(env) }
        .sheet(item: $importedData) { wrapper in BackupImportView(data: wrapper.data).environmentObject(env) }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                importedData = IdentifiableData(data: data)
            } else {
                env.present("That file could not be read.")
            }
        }
        .confirmationDialog("Erase everything on this device?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase all data", role: .destructive) { env.clearAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Entries, media, places, trackers, and settings are deleted. Make a backup first if you might want them back.")
        }
        .task { await loadCloudInfo() }
    }

    // MARK: Appearance

    private var appearance: some View {
        Section("Appearance") {
            Picker("Theme", selection: Binding(
                get: { env.settings.themeMode },
                set: { env.setThemeMode($0) }
            )) {
                Text("System").tag(AppThemeMode.system)
                Text("Light").tag(AppThemeMode.light)
                Text("Dark").tag(AppThemeMode.dark)
            }
            .settingsRow()
            Toggle("Show album artwork", isOn: Binding(
                get: { env.settings.showArtwork },
                set: { env.setShowArtwork($0) }
            ))
            .settingsRow()
            Toggle("Week starts on Monday", isOn: Binding(
                get: { env.settings.weekStartsMonday },
                set: { env.setWeekStartsMonday($0) }
            ))
            .settingsRow()
            NavigationLink("Customize Today") { TodaySettingsView() }
                .settingsRow()
        }
    }

    // MARK: Security

    private var security: some View {
        Section {
            Button {
                showPin = true
            } label: {
                HStack {
                    Text(env.settings.lockEnabled ? "Change or remove screen lock" : "Set a screen lock PIN")
                    Spacer()
                    Text(env.settings.lockEnabled ? "On" : "Off").foregroundStyle(Palette.inkSecondary)
                }
            }
            .settingsRow()

            if env.settings.lockEnabled {
                Picker("Auto-lock", selection: Binding(
                    get: { env.settings.autoLockMinutes },
                    set: { env.setAutoLockMinutes($0) }
                )) {
                    ForEach(lockOptions, id: \.self) { minutes in
                        Text(lockLabel(minutes)).tag(minutes)
                    }
                }
                .settingsRow()

                let bio = Biometrics.availability()
                if bio.available {
                    Toggle(bio.name, isOn: Binding(
                        get: { env.biometricUnlockEnabled },
                        set: { enabled in toggleBiometrics(enabled, name: bio.name) }
                    ))
                    .settingsRow()
                }

                Button("Lock now") { env.lock() }
                    .settingsRow()
            }

            NavigationLink("Permissions") { PermissionsScreen() }
                .settingsRow()
        } header: {
            Text("Privacy and security")
        } footer: {
            Text("The screen lock hides the app. Your archive is always encrypted on this device, with or without it.")
        }
    }

    private func lockLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Only when I lock it"
        case 1: return "After 1 minute away"
        default: return "After \(minutes) minutes away"
        }
    }

    private func toggleBiometrics(_ enabled: Bool, name: String) {
        guard enabled else {
            env.biometricUnlockEnabled = false
            return
        }
        Task {
            let ok = await Biometrics.authenticate(reason: "Turn on \(name) for your Lifelog screen lock.")
            env.biometricUnlockEnabled = ok
            if !ok { env.present("\(name) was not turned on.") }
        }
    }

    // MARK: Data sources

    private var sources: some View {
        Section {
            Toggle("Location visits", isOn: Binding(
                get: { env.settings.locationTrackingEnabled },
                set: { env.setLocationTracking($0) }
            ))
            .settingsRow()
            LocationSettingsNote(location: env.location)
                .settingsRow()

            HealthSettingsRows()
                .settingsRow()

            NavigationLink {
                LastfmSettingsView()
            } label: {
                HStack {
                    Text("Last.fm")
                    Spacer()
                    Text(env.settings.lastfmConnected ? (env.settings.lastfmUsername ?? "Connected") : "Not connected")
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .settingsRow()

            NavigationLink {
                RemindersView()
            } label: {
                HStack {
                    Text("Reminders")
                    Spacer()
                    let active = env.settings.reminders.filter { $0.enabled }.count
                    Text(active == 0 ? "None" : "\(active) on").foregroundStyle(Palette.inkSecondary)
                }
            }
            .settingsRow()
        } header: {
            Text("Sources and reminders")
        } footer: {
            Text("Each source is optional and off until you turn it on.")
        }
    }

    // MARK: Library

    private var library: some View {
        Section("Library") {
            libraryButton("Practices", symbol: "checkmark.circle", route: .trackers)
            libraryButton("Places", symbol: "mappin.and.ellipse", route: .places)
            libraryButton("Photos, video, and voice notes", symbol: "photo.on.rectangle", route: .media)
        }
    }

    private func libraryButton(_ title: String, symbol: String, route: Route) -> some View {
        Button {
            dismiss()
            navigator.push(route)
        } label: {
            Label(title, systemImage: symbol)
        }
        .settingsRow()
    }

    // MARK: Backup

    private var backup: some View {
        Section {
            if let last = env.settings.lastBackupAt {
                LabeledContent("Last backup", value: Dates.formatDayLong(last))
                    .settingsRow()
            } else {
                Text("You have not made a backup yet.")
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .settingsRow()
            }
            Button("Create encrypted backup") { showBackupExport = true }
                .settingsRow()
            Button("Restore from a backup file") { showFileImporter = true }
                .settingsRow()
            NavigationLink("How backups work") { BackupGuideView() }
                .settingsRow()

            if env.settings.cloudflareConnected {
                LabeledContent("Cloud account", value: env.settings.cloudflareUsername ?? "Signed in")
                    .settingsRow()
                if let cloudInfo {
                    Text(cloudInfo).font(Typeface.caption).foregroundStyle(Palette.inkSecondary).settingsRow()
                }
                Button("Back up to Cloudflare") { cloudMode = .backup }
                    .disabled(env.isWorking)
                    .settingsRow()
                Button("Restore from Cloudflare") { cloudMode = .restore }
                    .disabled(env.isWorking)
                    .settingsRow()
                Button("Manage Cloudflare account") { showCloudflare = true }
                    .settingsRow()
            } else {
                Button("Connect Cloudflare sync (optional)") { showCloudflare = true }
                    .settingsRow()
            }
        } header: {
            Text("Backup and sync")
        } footer: {
            Text("Backups are encrypted with a passphrase only you know. Nobody, including Lifelog, can recover it.")
        }
    }

    // MARK: About

    private var about: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                .settingsRow()
            Text("Lifelog is local-first. Your journal lives on this device, encrypted, and nothing is uploaded unless you choose to back up.")
                .font(Typeface.caption)
                .foregroundStyle(Palette.inkSecondary)
                .settingsRow()
            Button("Erase all data on this device", role: .destructive) { confirmErase = true }
                .settingsRow()
        } header: {
            Text("About")
        }
    }

    private func loadCloudInfo() async {
        guard env.settings.cloudflareConnected, let info = await env.cloudBackupInfo() else { return }
        if info.exists, let uploaded = info.uploadedAt ?? info.modifiedAt {
            var text = "Cloud backup from \(Dates.formatShortDate(uploaded)) at \(Dates.formatTime(uploaded))"
            if let size = info.size { text += " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
            cloudInfo = text
        } else {
            cloudInfo = "No cloud backup yet."
        }
    }
}

struct IdentifiableData: Identifiable {
    let data: Data
    let id = UUID()
}

enum CloudPassphraseMode: String, Identifiable {
    case backup, restore
    var id: String { rawValue }
}

// MARK: - Rows with live state

private struct LocationSettingsNote: View {
    @ObservedObject var location: LocationService
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            switch location.authorization {
            case .denied, .restricted:
                InfoLine(text: "Location access is off for Lifelog, so nothing can be recorded.", symbol: "location.slash")
                Button("Open Settings") { PermissionCenter.openSystemSettings() }.buttonStyle(QuietButtonStyle())
            case .authorizedWhenInUse:
                InfoLine(text: "Recording while the app is open. Choose “Always” to notice stops in the background.", symbol: "location")
                Button("Allow Always") { location.requestPermission(always: true) }.buttonStyle(QuietButtonStyle())
            case .authorizedAlways:
                InfoLine(text: "Allowed Always. Stops and routes are stored in your encrypted archive only.", symbol: "location.fill")
            case .notDetermined:
                InfoLine(text: env.settings.locationTrackingEnabled
                         ? "Waiting for your permission."
                         : "Turn this on to be asked for permission.", symbol: "location")
            @unknown default:
                EmptyView()
            }
        }
    }
}

private struct HealthSettingsRows: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        if HealthService.isAvailable {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Text("Apple Health")
                    Spacer()
                    Text(env.healthConnected ? "Connected" : "Not connected").foregroundStyle(Palette.inkSecondary)
                }
                if env.healthConnected {
                    HStack(spacing: Space.lg) {
                        Button(busy ? "Syncing…" : "Sync today") { run { await env.syncHealth() } }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(busy)
                        Button("Disconnect") { env.disconnectHealth(); message = "Health sync is off. Existing numbers stay in your journal." }
                            .buttonStyle(QuietButtonStyle())
                    }
                } else {
                    Button(busy ? "Waiting…" : "Connect Apple Health") { run { await env.connectHealth() } }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(busy)
                }
                if let message {
                    Text(message).font(Typeface.caption).foregroundStyle(Palette.inkSecondary)
                }
                Text("Steps and sleep are saved on a daily metrics entry. iOS doesn't tell apps whether read access was granted, so if nothing appears, check Settings › Health › Data Access.")
                    .font(Typeface.micro)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    private func run(_ work: @escaping () async -> String) {
        busy = true
        message = nil
        Task {
            let result = await work()
            message = result
            busy = false
        }
    }
}

// MARK: - Today layout

private struct TodaySettingsView: View {
    @EnvironmentObject private var env: AppEnvironment

    private let titles: [(key: String, title: String, detail: String)] = [
        ("status", "Day facts", "Entries, mood, sleep, and steps."),
        ("quickAdd", "Quick note", "The writing box at the top."),
        ("highlight", "Writing box", "Shown together with the quick note."),
        ("timeline", "Today's thread", "Recent records from today."),
        ("trackers", "Practices", "Your trackers with quick logging."),
        ("places", "Where you were", "Today's stops."),
        ("music", "Listening", "Tracks you played."),
        ("recap", "Day so far", "A one-sentence summary."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(titles, id: \.key) { item in
                    Toggle(isOn: binding(item.key)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.detail).font(Typeface.caption).foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .settingsRow()
                }
            } footer: {
                Text("Hiding a section only changes what Today shows. Nothing is deleted.")
            }
        }
        .listStyle(.insetGrouped)
        .paperList()
        .navigationTitle("Customize Today")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { env.settings.todaySections.contains(key) },
            set: { enabled in
                env.updateSettings { settings in
                    var set = Set(settings.todaySections)
                    if enabled { set.insert(key) } else { set.remove(key) }
                    settings.todaySections = TodaySection.defaults.filter { set.contains($0) }
                }
            }
        )
    }
}

// MARK: - Screen lock

private struct PinSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var pin = ""
    @State private var confirm = ""
    @State private var error = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New PIN (4–12 digits)", text: $pin).keyboardType(.numberPad)
                    SecureField("Repeat PIN", text: $confirm).keyboardType(.numberPad)
                    if !error.isEmpty { Text(error).font(Typeface.caption).foregroundStyle(Palette.danger) }
                    Button(env.settings.lockEnabled ? "Change PIN" : "Enable screen lock") { submit() }
                        .disabled(pin.isEmpty || confirm.isEmpty || working)
                } footer: {
                    Text("There is no PIN recovery. If you forget it, restore from a backup or reinstall the app.")
                }
                if env.settings.lockEnabled {
                    Section {
                        Button(role: .destructive) {
                            env.removePin()
                            env.biometricUnlockEnabled = false
                            dismiss()
                        } label: { Label("Disable screen lock", systemImage: "lock.open") }
                    }
                }
            }
            .paperList()
            .navigationTitle("Screen lock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func submit() {
        guard pin.count >= 4, pin.count <= 12, pin.allSatisfy(\.isNumber) else {
            error = "Use 4 to 12 digits."
            return
        }
        guard pin == confirm else {
            error = "The two PINs do not match."
            return
        }
        working = true
        let chosen = pin
        Task {
            await env.setPin(chosen)
            working = false
            dismiss()
        }
    }
}

// MARK: - Last.fm

private struct LastfmSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @State private var syncing = false
    @State private var confirmRemove = false
    @State private var message: String?

    var body: some View {
        Form {
            if env.settings.lastfmConnected {
                Section {
                    LabeledContent("Account", value: env.settings.lastfmUsername ?? "")
                    if let last = env.settings.lastfmLastSync {
                        LabeledContent("Last sync", value: Dates.formatShortDate(last) + " " + Dates.formatTime(last))
                    }
                    Button(syncing ? "Syncing…" : "Sync now") { sync() }.disabled(syncing)
                    if let message { Text(message).font(Typeface.caption).foregroundStyle(Palette.inkSecondary) }
                }
                Section {
                    Button("Remove imported listening history", role: .destructive) { confirmRemove = true }
                    Button("Disconnect Last.fm", role: .destructive) { env.disconnectLastfm() }
                } footer: {
                    Text("Disconnecting keeps tracks already imported. Removing history deletes only tracks that came from Last.fm.")
                }
            } else {
                Section {
                    Button("Connect with Last.fm") { navigator.present(.lastfmConnect) }
                } footer: {
                    Text("Last.fm needs a free API key to read scrobbles. The guided setup opens Last.fm for you, then saves your username and key encrypted on this device. No password or shared secret is required.")
                }
            }
        }
        .paperList()
        .navigationTitle("Last.fm")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove imported listening history?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove history", role: .destructive) { env.removeImportedMusic() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func sync() {
        syncing = true
        message = nil
        Task {
            if let added = await env.syncLastfm() {
                message = added == 0 ? "Already up to date." : "Added \(added) \(Dates.plural(added, "track"))."
            } else {
                message = "Sync did not finish. Check your connection and API key."
            }
            syncing = false
        }
    }
}

// MARK: - Reminders

struct RemindersView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var editing: ReminderItem?
    @State private var notice: String?

    var body: some View {
        List {
            if env.permissions.notifications.needsSettings {
                Section {
                    PermissionNotice(message: "Notifications are off for Lifelog, so reminders cannot appear. Allow them in Settings.")
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section {
                if env.settings.reminders.isEmpty {
                    EmptyNote(
                        title: "No reminders",
                        message: "A reminder is a quiet nudge at a time you choose, delivered on this device.",
                        actionTitle: "Add a reminder"
                    ) { editing = ReminderItem() }
                    .listRowBackground(Color.clear)
                }
                ForEach(env.settings.reminders) { reminder in
                    HStack {
                        Button { editing = reminder } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.title.isEmpty ? "Reminder" : reminder.title)
                                    .font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                                Text(reminder.timeLabel + (reminder.repeatMode == .daily ? " · Every day" : " · Once"))
                                    .font(Typeface.caption).foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Toggle("Enabled", isOn: Binding(
                            get: { reminder.enabled },
                            set: { value in
                                var changed = reminder
                                changed.enabled = value
                                Task { await save(changed) }
                            }
                        ))
                        .labelsHidden()
                    }
                    .settingsRow()
                }
                .onDelete { offsets in
                    let ids = offsets.map { env.settings.reminders[$0].id }
                    Task { for id in ids { await env.deleteReminder(id) } }
                }
            } footer: {
                if let notice { Text(notice) }
            }
        }
        .listStyle(.insetGrouped)
        .paperList()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = ReminderItem() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add reminder")
            }
        }
        .sheet(item: $editing) { reminder in
            ReminderEditor(reminder: reminder) { saved in
                await save(saved)
            }
            .environmentObject(env)
        }
        .task { await env.permissions.refresh() }
    }

    private func save(_ reminder: ReminderItem) async {
        let result = await env.saveReminder(reminder)
        if reminder.enabled && !result.authorized {
            notice = "This reminder is saved, but notifications are not allowed yet, so it will not appear."
        } else {
            notice = nil
        }
    }
}

private struct ReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReminderItem
    @State private var time: Date
    let onSave: (ReminderItem) async -> Void

    init(reminder: ReminderItem, onSave: @escaping (ReminderItem) async -> Void) {
        _draft = State(initialValue: reminder)
        var parts = DateComponents()
        parts.hour = reminder.hour
        parts.minute = reminder.minute
        _time = State(initialValue: Dates.calendar.date(from: parts) ?? Date())
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                    TextField("Message (optional)", text: $draft.note, axis: .vertical).lineLimit(1...3)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("Repeat", selection: $draft.repeatMode) {
                        Text("Every day").tag(ReminderRepeat.daily)
                        Text("Once").tag(ReminderRepeat.once)
                    }
                    Toggle("Enabled", isOn: $draft.enabled)
                } footer: {
                    Text("The first time you turn a reminder on, iOS asks whether Lifelog may send notifications.")
                }
            }
            .paperList()
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parts = Dates.calendar.dateComponents([.hour, .minute], from: time)
                        draft.hour = parts.hour ?? 9
                        draft.minute = parts.minute ?? 0
                        let finished = draft
                        Task {
                            await onSave(finished)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Backup

struct BackupExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var error = ""
    @State private var share: IdentifiableURL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Backup passphrase", text: $passphrase)
                    SecureField("Repeat passphrase", text: $confirm)
                    if !error.isEmpty { Text(error).font(Typeface.caption).foregroundStyle(Palette.danger) }
                    Button(working ? "Encrypting…" : "Create backup") { create() }
                        .disabled(passphrase.isEmpty || confirm.isEmpty || working)
                } footer: {
                    Text("Choose a passphrase you will remember. It cannot be recovered. Keep it separate from the backup file.")
                }
            }
            .paperList()
            .navigationTitle("Encrypted backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(item: $share) { item in
                ShareSheet(items: [item.url]) { dismiss() }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func create() {
        guard passphrase == confirm else {
            error = "The two passphrases do not match."
            return
        }
        error = ""
        working = true
        let chosen = passphrase
        Task {
            if let url = await env.exportBackup(passphrase: chosen) {
                share = IdentifiableURL(url: url)
            } else {
                error = "The backup could not be created. Passphrases need at least 8 characters."
            }
            working = false
        }
    }
}

struct BackupImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    let data: Data
    @State private var passphrase = ""
    @State private var error = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Backup passphrase", text: $passphrase)
                    if !error.isEmpty { Text(error).font(Typeface.caption).foregroundStyle(Palette.danger) }
                    Button(working ? "Restoring…" : "Restore") { restore() }
                        .disabled(passphrase.isEmpty || working)
                } footer: {
                    Text("Restoring replaces the data on this device with the backup's contents.")
                }
            }
            .paperList()
            .navigationTitle("Restore backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func restore() {
        working = true
        error = ""
        let chosen = passphrase
        Task {
            do {
                try await env.restoreBackup(data, passphrase: chosen)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                working = false
            }
        }
    }
}

struct BackupGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("How backups work").font(Typeface.display).foregroundStyle(Palette.ink)
                Text("A backup is a file containing an AES-256-GCM encrypted copy of your archive. The key is derived from your passphrase with Argon2id.")
                Text("Media that is still available is decrypted on this device, packed into the encrypted payload, and re-encrypted with the backup key. A restore needs only the file and the passphrase.")
                Text("Keep the passphrase separate from the file. Nobody can recover it for you.")
            }
            .font(Typeface.reading)
            .foregroundStyle(Palette.inkSecondary)
            .padding(Space.page)
        }
        .paperScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Cloudflare

private struct CloudflareConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var workerURL = AppSettings.defaultCloudflareWorkerUrl
    @State private var username = ""
    @State private var password = ""
    @State private var createAccount = false
    @State private var isWorking = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Worker URL", text: $workerURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    Toggle("Create account", isOn: $createAccount)
                    if !error.isEmpty { Text(error).font(Typeface.caption).foregroundStyle(Palette.danger) }
                    Button(isWorking ? "Working…" : (createAccount ? "Create account" : "Sign in")) { signIn() }
                        .disabled(username.isEmpty || password.isEmpty || isWorking)
                } footer: {
                    Text("Cloudflare sync is optional. Your journal works fully without an account; this only stores encrypted backup files.")
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
            .paperList()
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
        let shouldCreate = createAccount
        Task {
            do {
                var session: CloudflareSession?
                if shouldCreate {
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
                    env.saveCloudflareSession(session)
                    isWorking = false
                    dismiss()
                } else {
                    isWorking = false
                }
            } catch {
                self.error = error.localizedDescription
                isWorking = false
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
                    Button(isWorking ? "Working…" : (mode == .backup ? "Back up now" : "Restore now")) { run() }
                        .disabled(passphrase.isEmpty || isWorking)
                } footer: {
                    Text("This is the passphrase for the encrypted backup file, not your Cloudflare account password.")
                }
            }
            .paperList()
            .navigationTitle(mode == .backup ? "Cloud backup" : "Cloud restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func run() {
        isWorking = true
        let chosen = passphrase
        let selected = mode
        Task {
            let succeeded = selected == .backup
                ? await env.backupToCloud(passphrase: chosen)
                : await env.restoreFromCloud(passphrase: chosen)
            isWorking = false
            if succeeded { dismiss() }
        }
    }
}

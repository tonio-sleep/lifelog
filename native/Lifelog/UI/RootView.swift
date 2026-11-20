import SwiftUI
import UIKit

extension AppThemeMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private enum FullCover: String, Identifiable {
    case recovery, onboarding
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var navigator = Navigator()
    @State private var backgroundedAt: Date?

    var body: some View {
        ZStack {
            shell
                .disabled(env.isLocked)
                .accessibilityHidden(env.isLocked)

            if showPrivacyShield && !env.isLocked {
                PrivacyShield()
            }
            if env.isLocked {
                LockView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .environmentObject(navigator)
        .tint(Palette.accent)
        .preferredColorScheme(env.settings.themeMode.colorScheme)
        .sheet(item: $navigator.sheet) { sheet in
            SheetRouter(sheet: sheet)
                .environmentObject(env)
                .environmentObject(navigator)
                .tint(Palette.accent)
                .preferredColorScheme(env.settings.themeMode.colorScheme)
        }
        .fullScreenCover(item: coverBinding) { cover in
            Group {
                switch cover {
                case .recovery: RecoveryView()
                case .onboarding: OnboardingView()
                }
            }
            .environmentObject(env)
            .tint(Palette.accent)
            .preferredColorScheme(env.settings.themeMode.colorScheme)
        }
        .overlay(alignment: .top) { toastOverlay }
        .animation(.easeOut(duration: 0.2), value: env.isLocked)
        .animation(.snappy(duration: 0.25), value: env.toast)
        .onChange(of: scenePhase) { _, phase in handle(phase) }
        .onChange(of: env.isLocked) { _, locked in
            if locked { navigator.sheet = nil }
        }
        .task { await idleLockLoop() }
        .task { await env.permissions.refresh() }
    }

    // MARK: Shell

    @ViewBuilder
    private var shell: some View {
        if sizeClass == .regular {
            SplitShell()
        } else {
            TabShell()
        }
    }

    private var showPrivacyShield: Bool {
        env.settings.lockEnabled && scenePhase != .active
    }

    private var coverBinding: Binding<FullCover?> {
        Binding(
            get: {
                if env.persistenceBlocked { return .recovery }
                #if DEBUG
                let preview = ProcessInfo.processInfo.environment["LIFELOG_PREVIEW"] == "1"
                #else
                let preview = false
                #endif
                if !preview && !env.settings.onboardingComplete { return .onboarding }
                return nil
            },
            set: { _ in }
        )
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = env.toast {
            ToastBanner(message: toast)
                .padding(.top, Space.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    if env.toast == toast { env.toast = nil }
                }
        }
    }

    // MARK: Lifecycle

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Date()
            env.flushForBackground()
        case .inactive:
            env.flushForBackground()
        case .active:
            if let left = backgroundedAt {
                let limit = TimeInterval(env.settings.autoLockMinutes * 60)
                if limit > 0, Date().timeIntervalSince(left) >= limit { env.lock() }
                backgroundedAt = nil
            }
            ActivityClock.shared.reset()
            ActivityClock.shared.installIfNeeded()
            Task {
                await env.permissions.refresh()
                _ = await env.syncReminders()
                await env.autoSyncHealthIfNeeded()
                await env.autoSyncLastfmIfNeeded()
            }
            if env.settings.locationTrackingEnabled { env.location.start() }
        @unknown default:
            break
        }
    }

    private func idleLockLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard env.settings.lockEnabled, !env.isLocked else { continue }
            let limit = TimeInterval(env.settings.autoLockMinutes * 60)
            guard limit > 0, UIApplication.shared.applicationState == .active else { continue }
            if ActivityClock.shared.idleSeconds >= limit { env.lock() }
        }
    }
}

// MARK: - Shells

private struct TabShell: View {
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DestinationStack(destination: navigator.selection)
                .id(navigator.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.16), value: navigator.selection)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LifelogTabBar()
        }
    }
}

private struct SplitShell: View {
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            DestinationStack(destination: navigator.selection)
                .id(navigator.selection)
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        List {
            Section {
                ForEach(Destination.allCases) { destination in
                    Button {
                        navigator.selection = destination
                    } label: {
                        Label(destination.title, systemImage: destination.symbol)
                            .font(navigator.selection == destination ? Typeface.labelStrong : Typeface.label)
                            .foregroundStyle(navigator.selection == destination ? Palette.accent : Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(navigator.selection == destination ? Palette.accentSoft : Color.clear)
                    .accessibilityAddTraits(navigator.selection == destination ? .isSelected : [])
                }
            } header: {
                Text("Lifelog")
                    .font(Typeface.title)
                    .foregroundStyle(Palette.ink)
                    .textCase(nil)
                    .padding(.bottom, Space.sm)
            }
            Section {
                Button { navigator.present(.quickAdd) } label: { Label("Quick add", systemImage: "plus") }
                Button { navigator.present(.search) } label: { Label("Search", systemImage: "magnifyingglass") }
                Button { navigator.present(.settings) } label: { Label("Settings", systemImage: "gearshape") }
            }
            .font(Typeface.label)
            .foregroundStyle(Palette.ink)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
    }
}

/// One navigation stack per destination, so each keeps its own place.
struct DestinationStack: View {
    @EnvironmentObject private var navigator: Navigator
    let destination: Destination

    var body: some View {
        NavigationStack(path: navigator.path(for: destination)) {
            DestinationRoot(destination: destination)
                .primaryToolbar()
                .lifelogDestinations()
        }
    }
}

private struct DestinationRoot: View {
    let destination: Destination

    var body: some View {
        Group {
            switch destination {
            case .today: TodayView()
            case .timeline: TimelineView()
            case .map: MapView()
            case .memories: MemoriesView()
            case .insights: InsightsView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .paperScreen()
    }
}

/// Hides content in the app switcher when a screen lock is set.
private struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            Image(systemName: "lock")
                .font(.system(.largeTitle).weight(.light))
                .foregroundStyle(Palette.inkTertiary)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sheets

private struct SheetRouter: View {
    @EnvironmentObject private var env: AppEnvironment
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .quickAdd:
            QuickAddSheet()
        case .search:
            SearchSheet()
        case .settings:
            NavigationStack { SettingsView() }
        case .newEntry(let date, let voice):
            EntryEditorSheet(entry: JournalEntry(createdAt: date.momentForDay), startWithVoice: voice)
        case .editEntry(let id):
            if let entry = env.archive.entryById(id) {
                EntryEditorSheet(entry: entry, startWithVoice: false)
            } else {
                MissingRecord(title: "Entry not found")
            }
        case .newEvent(let date):
            EventEditorSheet(event: .blank(date.momentForDay))
        case .editEvent(let id):
            if let event = env.archive.events.first(where: { $0.id == id }) {
                EventEditorSheet(event: event)
            } else {
                MissingRecord(title: "Event not found")
            }
        case .logTracker(let id):
            TrackerLogSheet(trackerId: id)
        case .newTracker:
            TrackerEditorSheet(tracker: .blank())
        case .editTracker(let id):
            if let tracker = env.archive.trackerById(id) {
                TrackerEditorSheet(tracker: tracker)
            } else {
                MissingRecord(title: "Tracker not found")
            }
        case .addMedia(let date):
            MediaAddSheet(day: date)
        case .addTrack:
            ManualTrackSheet()
        case .lastfmConnect:
            LastfmConnectView()
        case .newPlace:
            PlaceEditorSheet(place: Place())
        case .editPlace(let id):
            if let place = env.archive.placeById(id) {
                PlaceEditorSheet(place: place)
            } else {
                MissingRecord(title: "Place not found")
            }
        }
    }
}

struct MissingRecord: View {
    @Environment(\.dismiss) private var dismiss
    let title: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "questionmark.folder")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
        }
    }
}

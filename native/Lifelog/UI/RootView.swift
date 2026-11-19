import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var router = Router()
    @State private var selection: Destination = .today
    @State private var showQuickAdd = false
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var wentToBackgroundAt: Date?
    @State private var lastActiveAt = Date()

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    DestinationSidebar(selection: $selection, onQuickAdd: { showQuickAdd = true }, onSettings: { showSettings = true })
                } detail: {
                    NavigationStack(path: $router.path) {
                        destinationContent
                    }
                }
            } else {
                NavigationStack(path: $router.path) {
                    destinationContent
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    DestinationDock(selection: $selection, onQuickAdd: { showQuickAdd = true })
                }
            }
        }
        .environmentObject(router)
        .preferredColorScheme(colorScheme)
        .lifelogPaletteProvider()
        .sheet(isPresented: $showQuickAdd) { QuickAddView().environmentObject(env) }
        .sheet(isPresented: $showSearch) {
            NavigationStack { SearchView().environmentObject(env) }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView().environmentObject(env) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !env.settings.onboardingComplete },
            set: { value in
                if !value {
                    env.settings.onboardingComplete = true
                    env.save()
                }
            }
        )) {
            OnboardingView().environmentObject(env)
        }
        .fullScreenCover(isPresented: Binding(
            get: { env.isLocked },
            set: { value in if !value { env.isLocked = false } }
        )) {
            LockView().environmentObject(env)
        }
        .overlay(alignment: .top) {
            if let toast = env.toast {
                Text(toast)
                    .font(LifelogTheme.sans(13, weight: .medium))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(palette.surfaceRaised))
                    .overlay(Capsule().stroke(palette.border, lineWidth: 0.8))
                    .shadow(color: palette.shadow, radius: 12, y: 5)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_800_000_000)
                            env.toast = nil
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.22), value: env.toast)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                wentToBackgroundAt = Date()
                lastActiveAt = Date()
            case .active:
                if let backgrounded = wentToBackgroundAt {
                    let limit = TimeInterval(env.settings.autoLockMinutes * 60)
                    if limit > 0, Date().timeIntervalSince(backgrounded) >= limit {
                        env.lock()
                    }
                    wentToBackgroundAt = nil
                }
                lastActiveAt = Date()
            default:
                break
            }
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
            guard scenePhase == .active, wentToBackgroundAt == nil, !env.isLocked else { return }
            let limit = TimeInterval(env.settings.autoLockMinutes * 60)
            if limit > 0, Date().timeIntervalSince(lastActiveAt) >= limit {
                env.lock()
            }
        }
        .simultaneousGesture(TapGesture().onEnded { _ in lastActiveAt = Date() })
        .onAppear {
            if env.settings.locationTrackingEnabled { env.location.start() }
        }
    }

    private var palette: LifelogTheme.Palette { LifelogTheme.palette(colorScheme ?? .light) }

    private var colorScheme: ColorScheme? {
        switch env.settings.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        Group {
            switch selection {
            case .today: TodayView()
            case .timeline: TimelineView()
            case .map: MapView()
            case .memories: MemoriesView()
            case .insights: InsightsView()
            }
        }
        .environmentObject(env)
        .environmentObject(router)
        .navigationTitle(selection.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { showQuickAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Quick add")
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .trackers:
                TrackersView().environmentObject(env)
            case .media:
                MediaGalleryView().environmentObject(env)
            case .entry(let id):
                if let entry = env.archive.entryById(id) {
                    EntryEditorView(entry: entry).environmentObject(env)
                } else {
                    ContentUnavailableView("Entry not found", systemImage: "book.closed")
                }
            case .newEntry:
                EntryEditorView(entry: JournalEntry()).environmentObject(env)
            case .event(let id):
                if let event = env.archive.events.first(where: { $0.id == id }) {
                    EventEditorView(event: event).environmentObject(env)
                } else {
                    ContentUnavailableView("Event not found", systemImage: "calendar")
                }
            case .newEvent:
                EventEditorView(event: .blank(Date())).environmentObject(env)
            case .place(let id):
                if let place = env.archive.places.first(where: { $0.id == id }) {
                    PlaceDetailView(place: place).environmentObject(env)
                } else {
                    ContentUnavailableView("Place not found", systemImage: "map")
                }
            case .reminders:
                RemindersView().environmentObject(env)
            case .journal(let day):
                JournalView(day: day).environmentObject(env).environmentObject(router)
            case .timeline(let day):
                TimelineView(day: day).environmentObject(env).environmentObject(router)
            case .map(let day):
                MapView(day: day).environmentObject(env).environmentObject(router)
            }
        }
        .lifelogScreenBackground()
    }
}

import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case today, timeline, map, memories, insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .timeline: return "Timeline"
        case .map: return "Map"
        case .memories: return "Memories"
        case .insights: return "Insights"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .timeline: return "calendar.day.timeline.left"
        case .map: return "map"
        case .memories: return "clock.arrow.circlepath"
        case .insights: return "chart.bar.xaxis"
        }
    }
}

/// Screens that are pushed onto a destination's stack.
enum Route: Hashable {
    case trackers
    case tracker(String)
    case media
    case mediaItem(String)
    case entry(String)
    case place(String)
    case places
    /// Day-based journal page, kept as a pushed route rather than a tab.
    case journal(Date)
    case timeline(Date)
    case map(Date)
}

/// Screens that are presented as sheets. One slot, so sheets never stack by accident.
enum AppSheet: Identifiable {
    case quickAdd
    case search
    case settings
    case newEntry(Date, startWithVoice: Bool)
    case editEntry(String)
    case newEvent(Date)
    case editEvent(String)
    case logTracker(String?)
    case newTracker
    case editTracker(String)
    case addMedia(Date)
    case addTrack
    case newPlace
    case editPlace(String)

    var id: String {
        switch self {
        case .quickAdd: return "quickAdd"
        case .search: return "search"
        case .settings: return "settings"
        case .newEntry(let date, let voice): return "newEntry-\(date.timeIntervalSince1970)-\(voice)"
        case .editEntry(let id): return "editEntry-\(id)"
        case .newEvent(let date): return "newEvent-\(date.timeIntervalSince1970)"
        case .editEvent(let id): return "editEvent-\(id)"
        case .logTracker(let id): return "logTracker-\(id ?? "any")"
        case .newTracker: return "newTracker"
        case .editTracker(let id): return "editTracker-\(id)"
        case .addMedia(let date): return "addMedia-\(date.timeIntervalSince1970)"
        case .addTrack: return "addTrack"
        case .newPlace: return "newPlace"
        case .editPlace(let id): return "editPlace-\(id)"
        }
    }
}

@MainActor
final class Navigator: ObservableObject {
    @Published var selection: Destination = .today
    @Published var sheet: AppSheet?
    @Published private var paths: [Destination: NavigationPath] = [:]

    func path(for destination: Destination) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[destination] ?? NavigationPath() },
            set: { self.paths[destination] = $0 }
        )
    }

    /// Pushes onto the stack of the destination currently on screen.
    func push(_ route: Route) {
        var path = paths[selection] ?? NavigationPath()
        path.append(route)
        paths[selection] = path
    }

    func present(_ sheet: AppSheet) { self.sheet = sheet }
    func dismissSheet() { sheet = nil }

    /// Opens whatever a timeline row points at.
    func open(_ row: DayRow) {
        switch row.source {
        case .journal:
            if let id = row.sourceId { push(.entry(id)) }
        case .manual:
            if let id = row.sourceId { present(.editEvent(id)) }
        case .photo:
            if let id = row.sourceId { push(.mediaItem(id)) }
        case .tracker:
            push(.trackers)
        case .location:
            push(.map(row.at))
        case .music:
            push(.journal(row.at))
        }
    }

    /// Opens a search result. Tracker-record hits carry the tracker id as their source id.
    func open(_ hit: SearchHit) {
        sheet = nil
        switch hit.kind {
        case .journal: push(.entry(hit.sourceId))
        case .photo: push(.mediaItem(hit.sourceId))
        case .tracker: push(.tracker(hit.sourceId))
        case .place: push(.place(hit.sourceId))
        case .visit: push(.map(hit.date))
        case .music: push(.journal(hit.date))
        case .event: present(.editEvent(hit.sourceId))
        }
    }
}

// MARK: - Toolbar shared by the five destinations

struct PrimaryToolbar: ViewModifier {
    @EnvironmentObject private var navigator: Navigator

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { navigator.present(.settings) } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { navigator.present(.search) } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search")
                    Button { navigator.present(.quickAdd) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Quick add")
                }
            }
    }
}

extension View {
    func primaryToolbar() -> some View { modifier(PrimaryToolbar()) }
}

/// Resolves a pushed route to its screen.
struct RouteView: View {
    @EnvironmentObject private var env: AppEnvironment
    let route: Route

    var body: some View {
        switch route {
        case .trackers:
            TrackersView()
        case .tracker(let id):
            TrackerDetailView(trackerId: id)
        case .media:
            MediaGalleryView()
        case .mediaItem(let id):
            MediaDetailView(itemId: id)
        case .entry(let id):
            EntryDetailView(entryId: id)
        case .place(let id):
            PlaceDetailView(placeId: id)
        case .places:
            PlacesListView()
        case .journal(let day):
            JournalDayView(day: day)
        case .timeline(let day):
            TimelineView(day: day)
        case .map(let day):
            MapView(day: day)
        }
    }
}

extension View {
    func lifelogDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            RouteView(route: route)
        }
    }
}

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

enum Route: Hashable {
    case trackers
    case media
    case entry(String)
    case newEntry
    case event(String)
    case newEvent
    case place(String)
    case reminders
    /// Day-based journal editing, kept as a pushed route rather than a tab.
    case journal(Date)
    case timeline(Date)
    case map(Date)
}

final class Router: ObservableObject {
    @Published var path = NavigationPath()

    func push(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func reset() { path = NavigationPath() }
}

struct DestinationSidebar: View {
    @Environment(\.lifelogPalette) private var palette
    @Binding var selection: Destination
    let onQuickAdd: () -> Void
    let onSettings: () -> Void

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 6) {
                Text("Lifelog")
                    .font(LifelogTheme.serif(27, relativeTo: .largeTitle))
                    .foregroundStyle(palette.text)
                Text("A quiet record of your days")
                    .font(LifelogTheme.sans(12))
                    .foregroundStyle(palette.secondary)
            }
            .padding(.vertical, 14)

            Section {
                ForEach(Destination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        Label(destination.title, systemImage: destination.symbol)
                            .font(LifelogTheme.sans(15, weight: selection == destination ? .semibold : .medium))
                            .foregroundStyle(selection == destination ? palette.accent : palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selection == destination ? palette.accentSoft : Color.clear)
                }
            }

            Section {
                Button(action: onQuickAdd) {
                    Label("Quick add", systemImage: "plus.circle")
                }
                Button(action: onSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }
}

struct DestinationDock: View {
    @Environment(\.lifelogPalette) private var palette
    @Binding var selection: Destination
    let onQuickAdd: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Destination.allCases.prefix(2)) { item in button(item) }
            Button(action: onQuickAdd) {
                ZStack {
                    Circle().fill(palette.accent)
                        .frame(width: 48, height: 48)
                        .shadow(color: palette.accent.opacity(0.3), radius: 10, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(palette.background)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 64)
            ForEach(Destination.allCases.dropFirst(2)) { item in button(item) }
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 0.6) }
    }

    private func button(_ item: Destination) -> some View {
        Button {
            selection = item
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: selection == item ? .semibold : .regular))
                Text(item.title)
                    .font(LifelogTheme.sans(9, weight: selection == item ? .semibold : .regular))
            }
            .foregroundStyle(selection == item ? palette.accent : palette.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

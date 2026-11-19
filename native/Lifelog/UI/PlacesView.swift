import SwiftUI
import MapKit

struct PlacesListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: Router
    @Environment(\.lifelogPalette) private var palette
    @State private var showEditor = false
    @State private var camera = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
        span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
    ))

    private var mappedPlaces: [Place] { env.archive.places.filter(\.hasCoordinates) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Your geography")
                    Text("Places and visits")
                        .font(LifelogTheme.serif(27, relativeTo: .title))
                    Text("Coordinates stay local. Only you decide what a place means.")
                        .font(LifelogTheme.sans(13))
                        .foregroundStyle(palette.secondary)
                }

                if mappedPlaces.isEmpty {
                    EmptyState(
                        title: "No saved coordinates",
                        message: "Add a place and attach your current location to see it here.",
                        systemImage: "map",
                        action: { showEditor = true },
                        actionTitle: "Add place"
                    )
                    .lifelogCard()
                } else {
                    Map(position: $camera) {
                        ForEach(mappedPlaces) { place in
                            Marker(place.name, coordinate: CLLocationCoordinate2D(
                                latitude: place.latitude ?? 0,
                                longitude: place.longitude ?? 0
                            ))
                            .tint(palette.accent)
                        }
                    }
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(palette.border, lineWidth: 0.8))
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Saved places",
                        subtitle: "\(env.archive.places.count) total",
                        action: { showEditor = true },
                        actionLabel: "Add"
                    )
                    if env.archive.places.isEmpty {
                        EmptyState(title: "No places yet", message: "A place can be as specific as a room or as broad as a city.", systemImage: "mappin", action: nil)
                            .lifelogCard()
                    } else {
                        ForEach(env.archive.places.sorted { $0.createdAt > $1.createdAt }) { place in
                            Button { router.push(.place(place.id)) } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color(hex: place.colorValue).opacity(0.18)).frame(width: 38, height: 38)
                                        Image(systemName: place.hasCoordinates ? "location.fill" : "mappin")
                                            .foregroundStyle(Color(hex: place.colorValue))
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(place.name).font(LifelogTheme.sans(15, weight: .semibold))
                                        if !place.notes.isEmpty {
                                            Text(place.notes).font(LifelogTheme.sans(12)).foregroundStyle(palette.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(palette.tertiary)
                                }
                                .lifelogCard(padding: 14, radius: 15)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !env.archive.visits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Recent visits", subtitle: "Confirmed and suggested")
                        ForEach(Array(env.archive.visits.sorted { $0.startAt > $1.startAt }.prefix(12))) { visit in
                            HStack {
                                Image(systemName: "clock").foregroundStyle(palette.tertiary)
                                VStack(alignment: .leading) {
                                    Text(visit.label).font(LifelogTheme.sans(14, weight: .medium))
                                    Text(Dates.formatDayLong(visit.startAt) + " · " + Dates.formatTime(visit.startAt))
                                        .font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                                }
                                Spacer()
                                if visit.confidence == .suggested {
                                    Text("Suggested").font(LifelogTheme.sans(9)).foregroundStyle(palette.tertiary)
                                }
                            }
                            .lifelogCard(padding: 13, radius: 14)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $showEditor) {
            PlaceEditorView(place: Place()).environmentObject(env)
        }
    }
}

struct PlaceDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lifelogPalette) private var palette
    let place: Place
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if place.hasCoordinates {
                    Map(position: .constant(MapCameraPosition.region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: place.latitude ?? 0, longitude: place.longitude ?? 0),
                        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                    )))) {
                        Marker(place.name, coordinate: CLLocationCoordinate2D(
                            latitude: place.latitude ?? 0,
                            longitude: place.longitude ?? 0
                        ))
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Saved place")
                    Text(place.name).font(LifelogTheme.serif(28, relativeTo: .title))
                    if !place.notes.isEmpty {
                        Text(place.notes).font(LifelogTheme.sans(14)).foregroundStyle(palette.secondary)
                    }
                }
                .lifelogCard()

                let visits = env.archive.visits.filter { $0.placeId == place.id || $0.label == place.name }
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Visits", subtitle: "\(visits.count) matched")
                    if visits.isEmpty {
                        EmptyState(title: "No matched visits", message: "Visits with this place name or id appear here.", systemImage: "clock", action: nil)
                    } else {
                        ForEach(visits.sorted { $0.startAt > $1.startAt }) { visit in
                            HStack {
                                Text(Dates.formatDayLong(visit.startAt))
                                Spacer()
                                Text(Dates.formatTimeRange(visit.startAt, visit.endAt)).foregroundStyle(palette.secondary)
                            }
                            .font(LifelogTheme.sans(13))
                            .lifelogCard(padding: 13, radius: 14)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(place.name)
        .toolbar {
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $editing) {
            PlaceEditorView(place: place).environmentObject(env)
        }
    }
}

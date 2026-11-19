import SwiftUI
import MapKit

/// Map destination for the selected day. Precise coordinates stay in the local
/// encrypted archive; MapKit receives only the visible region needed to draw tiles.
struct MapView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: Router
    @Environment(\.lifelogPalette) private var palette

    @State private var day: Date
    @State private var camera: MapCameraPosition
    @State private var showRoute = true
    @State private var showVisits = true
    @State private var showPlaces = true
    @State private var privacyMode = false
    @State private var showPlacesList = false

    private struct VisitAnnotation: Identifiable {
        let id: String
        let title: String
        let coordinate: CLLocationCoordinate2D
        let visit: Visit
    }

    init(day: Date? = nil) {
        let initial = day ?? Date()
        _day = State(initialValue: initial)
        _camera = State(initialValue: .region(MapView.defaultRegion))
    }

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
        span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
    )

    private var samples: [LocationSample] { env.archive.locationSamplesOn(day) }
    private var visits: [Visit] { env.archive.visitsOn(day) }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        samples.compactMap { sample in
            guard Self.isValid(sample.latitude, sample.longitude) else { return nil }
            return CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
        }
    }

    private var mappedPlaces: [Place] {
        env.archive.places.filter {
            guard let lat = $0.latitude, let lon = $0.longitude else { return false }
            return Self.isValid(lat, lon)
        }
    }

    private var visitAnnotations: [VisitAnnotation] {
        visits.compactMap { visit in
            let place = env.archive.placeById(visit.placeId)
                ?? env.archive.places.first { $0.name == visit.label }
            guard let lat = place?.latitude, let lon = place?.longitude,
                  Self.isValid(lat, lon) else { return nil }
            return VisitAnnotation(
                id: visit.id,
                title: visit.label,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                visit: visit
            )
        }
    }

    private var region: MKCoordinateRegion {
        var coordinates: [CLLocationCoordinate2D] = []
        if showRoute { coordinates += routeCoordinates }
        if showVisits { coordinates += visitAnnotations.map(\.coordinate) }
        if showPlaces {
            coordinates += mappedPlaces.compactMap { place in
                guard let lat = place.latitude, let lon = place.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
        guard !coordinates.isEmpty else { return Self.defaultRegion }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: min(180, max((maxLat - minLat) * 1.4, 0.02)),
                longitudeDelta: min(360, max((maxLon - minLon) * 1.4, 0.02))
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            dateBar

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    filters

                    if privacyMode {
                        privacyCard
                    } else {
                        preciseMap
                            .privacySensitive()
                    }

                    routeSummary
                    stopsSection
                    placesSection
                    photoNote

                    Text("Your route comes from your encrypted archive. MapKit receives the visible region to draw the map; privacy mode hides exact points.")
                        .font(LifelogTheme.sans(11))
                        .foregroundStyle(palette.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.push(.timeline(day))
                } label: {
                    Image(systemName: "calendar.day.timeline.left")
                }
                .accessibilityLabel("Open timeline for this day")
            }
        }
        .sheet(isPresented: $showPlacesList) {
            NavigationStack {
                PlacesListView()
                    .environmentObject(env)
                    .environmentObject(router)
                    .navigationTitle("Saved places")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear { camera = .region(region) }
        .onChange(of: day) { _, _ in camera = .region(region) }
        .onChange(of: showRoute) { _, _ in camera = .region(region) }
        .onChange(of: showVisits) { _, _ in camera = .region(region) }
        .onChange(of: showPlaces) { _, _ in camera = .region(region) }
        .onChange(of: privacyMode) { _, hidden in if !hidden { camera = .region(region) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Your geography")
            Text(Dates.formatDayLong(day))
                .font(LifelogTheme.serif(26, relativeTo: .title))
                .foregroundStyle(palette.text)
            Text("A route made only from samples you chose to keep.")
                .font(LifelogTheme.sans(13))
                .foregroundStyle(palette.secondary)
        }
    }

    private var dateBar: some View {
        HStack(spacing: 10) {
            Button {
                day = Dates.addingDays(-1, to: day)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")

            DatePicker("", selection: $day, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .colorMultiply(palette.text)

            Button {
                day = Dates.addingDays(1, to: day)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next day")

            Button { day = Date() } label: {
                Text("Today")
                    .font(LifelogTheme.sans(12, weight: .semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(palette.background.opacity(0.92))
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 0.6) }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                mapFilter("Route", systemImage: "road.lanes", isOn: $showRoute)
                mapFilter("Stops", systemImage: "mappin.and.ellipse", isOn: $showVisits)
                mapFilter("Places", systemImage: "star", isOn: $showPlaces)
            }
            Toggle("Hide exact coordinates", isOn: $privacyMode)
                .font(LifelogTheme.sans(12))
                .foregroundStyle(palette.secondary)
                .tint(palette.accent)
        }
        .lifelogCard(padding: 14, radius: 16)
    }

    private func mapFilter(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(LifelogTheme.sans(11, weight: .medium))
            }
            .foregroundStyle(isOn.wrappedValue ? palette.background : palette.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(isOn.wrappedValue ? palette.accent : palette.surfaceRaised))
            .overlay(Capsule().stroke(palette.border, lineWidth: isOn.wrappedValue ? 0 : 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }

    @ViewBuilder
    private var preciseMap: some View {
        Map(position: $camera) {
            if showRoute, routeCoordinates.count > 1 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(palette.accent.opacity(0.8), lineWidth: 3)
            }
            if showPlaces {
                ForEach(mappedPlaces) { place in
                    Marker(place.name, coordinate: CLLocationCoordinate2D(
                        latitude: place.latitude ?? 0,
                        longitude: place.longitude ?? 0
                    ))
                    .tint(Color(hex: place.colorValue))
                }
            }
            if showVisits {
                ForEach(visitAnnotations) { annotation in
                    Marker(annotation.title, coordinate: annotation.coordinate)
                        .tint(annotation.visit.confidence == .suggested ? palette.tertiary : palette.accent)
                }
            }
        }
        .mapStyle(.standard)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(palette.border, lineWidth: 0.8))
    }

    private var privacyCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(palette.accentSoft).frame(width: 56, height: 56)
                Image(systemName: "eye.slash")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(palette.accent)
            }
            Text("Exact locations hidden")
                .font(LifelogTheme.serif(19, relativeTo: .title3))
                .foregroundStyle(palette.text)
            Text("The map, route line, and coordinate pins are hidden. Visit names and times below remain available.")
                .font(LifelogTheme.sans(12))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .lifelogCard()
    }

    private var routeSummary: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(palette.accentSoft).frame(width: 38, height: 38)
                Image(systemName: "location")
                    .foregroundStyle(palette.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(samples.count) \(Dates.plural(samples.count, "location sample"))")
                    .font(LifelogTheme.sans(14, weight: .semibold))
                Text(env.settings.locationTrackingEnabled
                     ? "Location visits are enabled"
                     : "Location visits are off in Settings")
                    .font(LifelogTheme.sans(11))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            if !privacyMode, let first = samples.first, let last = samples.last, first.id != last.id {
                Text(Dates.formatTimeRange(first.recordedAt, last.recordedAt))
                    .font(LifelogTheme.sans(11))
                    .foregroundStyle(palette.tertiary)
            }
        }
        .lifelogCard(padding: 14, radius: 16)
    }

    private var stopsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Stops for this day",
                subtitle: "\(visits.count) \(Dates.plural(visits.count, "visit"))",
                action: { router.push(.timeline(day)) },
                actionLabel: "Timeline"
            )
            if visits.isEmpty {
                EmptyState(
                    title: "No visits recorded",
                    message: "Visits appear here when location tracking is on and a stop is inferred or saved.",
                    systemImage: "mappin",
                    action: nil
                )
                .lifelogCard()
            } else {
                ForEach(visits.sorted { $0.startAt > $1.startAt }) { visit in
                    Button {
                        router.push(.timeline(visit.startAt))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: visit.confidence == .suggested ? "mappin" : "mappin.circle.fill")
                                .foregroundStyle(visit.confidence == .suggested ? palette.tertiary : palette.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(visit.label)
                                    .font(LifelogTheme.sans(14, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Text(Dates.formatTimeRange(visit.startAt, visit.endAt))
                                    .font(LifelogTheme.sans(11))
                                    .foregroundStyle(palette.secondary)
                            }
                            Spacer()
                            if visit.confidence == .suggested {
                                Text("Suggested")
                                    .font(LifelogTheme.sans(9, weight: .bold))
                                    .foregroundStyle(palette.tertiary)
                            }
                        }
                        .lifelogCard(padding: 13, radius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var placesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Saved places",
                subtitle: "\(env.archive.places.count) total",
                action: { showPlacesList = true },
                actionLabel: "Manage"
            )
            if env.archive.places.isEmpty {
                EmptyState(
                    title: "No places yet",
                    message: "A place can be as specific as a room or as broad as a city.",
                    systemImage: "mappin",
                    action: { showPlacesList = true },
                    actionTitle: "Add place"
                )
                .lifelogCard()
            } else {
                ForEach(env.archive.places.sorted { $0.createdAt > $1.createdAt }.prefix(6)) { place in
                    Button { router.push(.place(place.id)) } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: place.colorValue).opacity(0.18))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: place.hasCoordinates ? "location.fill" : "mappin")
                                        .foregroundStyle(Color(hex: place.colorValue))
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(LifelogTheme.sans(14, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Text(place.hasCoordinates ? "Pinned" : "No coordinates")
                                    .font(LifelogTheme.sans(11))
                                    .foregroundStyle(palette.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(palette.tertiary)
                        }
                        .lifelogCard(padding: 13, radius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var photoNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "photo")
                .foregroundStyle(palette.tertiary)
            Text("Photo markers are omitted because the archive does not store photo coordinates. No locations are invented to fill the map.")
                .font(LifelogTheme.sans(11))
                .foregroundStyle(palette.secondary)
        }
        .lifelogCard(padding: 14, radius: 15)
    }

    private static func isValid(_ latitude: Double, _ longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite &&
        abs(latitude) <= 90 && abs(longitude) <= 180 &&
        !(latitude == 0 && longitude == 0)
    }
}

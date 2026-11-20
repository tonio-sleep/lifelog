import SwiftUI
import MapKit

// MARK: - Snapshot

struct MapPoint: Identifiable {
    var id: String
    var title: String
    var coordinate: CLLocationCoordinate2D
    var suggested: Bool = false
    var color: UInt32 = 0xFF9A4733
}

struct StopLine: Identifiable {
    var id: String
    var label: String
    var range: String
    var suggested: Bool
    var coordinate: CLLocationCoordinate2D?
    var startAt: Date
}

struct MapSnapshot {
    var loaded = false
    var route: [CLLocationCoordinate2D] = []
    var stops: [StopLine] = []
    var places: [MapPoint] = []
    var sampleCount = 0
    var firstSample: Date?
    var lastSample: Date?

    var stopPins: [MapPoint] {
        stops.compactMap { stop in
            guard let coordinate = stop.coordinate else { return nil }
            return MapPoint(id: stop.id, title: stop.label, coordinate: coordinate, suggested: stop.suggested)
        }
    }

    static func isValid(_ latitude: Double, _ longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite &&
        abs(latitude) <= 90 && abs(longitude) <= 180 &&
        !(latitude == 0 && longitude == 0)
    }

    static func make(_ archive: Archive, day: Date) -> MapSnapshot {
        var snap = MapSnapshot()
        snap.loaded = true

        let samples = archive.locationSamplesOn(day).filter { isValid($0.latitude, $0.longitude) }
        snap.sampleCount = samples.count
        snap.firstSample = samples.first?.recordedAt
        snap.lastSample = samples.last?.recordedAt

        // Keep the line light: a few hundred points draw the same route.
        let stride = max(1, samples.count / 600)
        snap.route = samples.enumerated().compactMap { index, sample in
            index % stride == 0
                ? CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
                : nil
        }

        snap.places = archive.places.compactMap { place in
            guard let lat = place.latitude, let lon = place.longitude, isValid(lat, lon) else { return nil }
            return MapPoint(
                id: place.id,
                title: place.name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                color: place.colorValue
            )
        }

        // Visits carry no coordinates in the archive. A stop is placed only from a
        // saved place it belongs to, or from a real location sample taken during it.
        snap.stops = archive.visitsOn(day).sorted { $0.startAt > $1.startAt }.map { visit in
            var coordinate: CLLocationCoordinate2D?
            let place = archive.placeById(visit.placeId)
                ?? archive.places.first { $0.name == visit.label }
            if let lat = place?.latitude, let lon = place?.longitude, isValid(lat, lon) {
                coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else {
                let windowStart = visit.startAt.addingTimeInterval(-15 * 60)
                let windowEnd = (visit.endAt ?? visit.startAt).addingTimeInterval(15 * 60)
                let nearby = samples.filter { $0.recordedAt >= windowStart && $0.recordedAt <= windowEnd }
                if let best = nearby.min(by: {
                    abs($0.recordedAt.timeIntervalSince(visit.startAt)) < abs($1.recordedAt.timeIntervalSince(visit.startAt))
                }) {
                    coordinate = CLLocationCoordinate2D(latitude: best.latitude, longitude: best.longitude)
                }
            }
            return StopLine(
                id: visit.id,
                label: visit.label,
                range: Dates.formatTimeRange(visit.startAt, visit.endAt),
                suggested: visit.confidence == .suggested,
                coordinate: coordinate,
                startAt: visit.startAt
            )
        }
        return snap
    }

    func region(route showRoute: Bool, stops showStops: Bool, places showPlaces: Bool) -> MKCoordinateRegion? {
        var coordinates: [CLLocationCoordinate2D] = []
        if showRoute { coordinates += route }
        if showStops { coordinates += stopPins.map(\.coordinate) }
        if showPlaces && coordinates.isEmpty { coordinates += places.map(\.coordinate) }
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: min(180, max((maxLat - minLat) * 1.4, 0.01)),
                longitudeDelta: min(360, max((maxLon - minLon) * 1.4, 0.01))
            )
        )
    }
}

// MARK: - View

/// The map for one day. Precise coordinates stay in the encrypted archive;
/// MapKit receives only the visible region it needs to draw tiles.
struct MapView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator

    @State private var day: Date
    @State private var camera: MapCameraPosition = .automatic
    @State private var snapshot = MapSnapshot()
    @AppStorage("lifelog.map.route") private var showRoute = true
    @AppStorage("lifelog.map.stops") private var showStops = true
    @AppStorage("lifelog.map.places") private var showPlaces = true
    @AppStorage("lifelog.map.privacy") private var privacy = false

    init(day: Date? = nil) {
        _day = State(initialValue: day ?? Date())
    }

    private struct Key: Equatable {
        var revision: Int
        var day: String
    }

    var body: some View {
        VStack(spacing: 0) {
            dateBar
            Hairline()
            mapArea
                .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
            Hairline()
            panel
                .frame(maxHeight: 320)
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Route", isOn: $showRoute)
                    Toggle("Stops", isOn: $showStops)
                    Toggle("Saved places", isOn: $showPlaces)
                    Divider()
                    Toggle("Hide exact locations", isOn: $privacy)
                    Divider()
                    Button { navigator.push(.places) } label: { Label("Saved places", systemImage: "star") }
                    Button { navigator.push(.timeline(day)) } label: { Label("Timeline for this day", systemImage: "calendar.day.timeline.left") }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Map options")
            }
        }
        .task(id: Key(revision: env.revision, day: Dates.dayKey(day))) { await rebuild() }
        .onChange(of: showRoute) { _, _ in fit() }
        .onChange(of: showStops) { _, _ in fit() }
        .onChange(of: showPlaces) { _, _ in fit() }
    }

    // MARK: Date bar

    private var dateBar: some View {
        HStack(spacing: Space.sm) {
            Button { day = Dates.addingDays(-1, to: day) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous day")
            DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
            Button { day = Dates.addingDays(1, to: day) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(Dates.sameDay(day, Date()))
            .accessibilityLabel("Next day")
            Spacer()
            Button("Today") { day = Date() }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(.horizontal, Space.md)
    }

    // MARK: Map

    @ViewBuilder
    private var mapArea: some View {
        if privacy {
            VStack(spacing: Space.sm) {
                Image(systemName: "eye.slash")
                    .font(.system(.title).weight(.light))
                    .foregroundStyle(Palette.inkTertiary)
                Text("Exact locations are hidden")
                    .font(Typeface.heading)
                    .foregroundStyle(Palette.ink)
                Text("The map, route, and pins are not drawn. Stop names and times below remain.")
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                Button("Show map") { privacy = false }
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface)
        } else {
            Map(position: $camera) {
                if showRoute, snapshot.route.count > 1 {
                    MapPolyline(coordinates: snapshot.route)
                        .stroke(Palette.accent, lineWidth: 3)
                }
                if showPlaces {
                    ForEach(snapshot.places) { place in
                        Marker(place.title, systemImage: "star.fill", coordinate: place.coordinate)
                            .tint(Color(hex: place.color))
                    }
                }
                if showStops {
                    ForEach(snapshot.stopPins) { pin in
                        Marker(pin.title, systemImage: "mappin", coordinate: pin.coordinate)
                            .tint(pin.suggested ? Palette.inkTertiary : Palette.accent)
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .privacySensitive()
        }
    }

    // MARK: Panel

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Dates.formatDayLong(day))
                        .font(Typeface.heading)
                        .foregroundStyle(Palette.ink)
                    Text(summaryLine)
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }

                LocationStatusRow(location: env.location, onShowMe: showMyLocation)

                VStack(alignment: .leading, spacing: 0) {
                    if snapshot.stops.isEmpty {
                        EmptyNote(
                            title: "No stops this day",
                            message: "Stops appear when location visits are on and you spend time somewhere, or when you add a place."
                        )
                    } else {
                        ForEach(snapshot.stops) { stop in
                            StopRow(stop: stop) { select(stop) }
                            if stop.id != snapshot.stops.last?.id { Hairline() }
                        }
                    }
                }

                InfoLine(
                    text: "Photo locations are not shown because the archive does not store them. Nothing is guessed to fill the map.",
                    symbol: "photo"
                )
            }
            .padding(Space.page)
        }
        .background(Palette.paper)
    }

    private var summaryLine: String {
        guard snapshot.sampleCount > 0 else { return "No location samples recorded" }
        var text = "\(snapshot.sampleCount) \(Dates.plural(snapshot.sampleCount, "location sample"))"
        if let first = snapshot.firstSample, let last = snapshot.lastSample, first != last {
            text += " · " + Dates.formatTimeRange(first, last)
        }
        return text
    }

    // MARK: Actions

    private func rebuild() async {
        let archive = env.archive
        let target = day
        let result = await offMain { MapSnapshot.make(archive, day: target) }
        guard !Task.isCancelled else { return }
        snapshot = result
        fit()
    }

    private func fit() {
        if let region = snapshot.region(route: showRoute, stops: showStops, places: showPlaces) {
            camera = .region(region)
        } else {
            camera = .automatic
        }
    }

    private func select(_ stop: StopLine) {
        if let coordinate = stop.coordinate, !privacy {
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        } else {
            navigator.push(.timeline(stop.startAt))
        }
    }

    private func showMyLocation() {
        Task {
            if await env.location.requestWhenInUseAndWait() {
                camera = .userLocation(fallback: .automatic)
            }
        }
    }
}

private struct StopRow: View {
    let stop: StopLine
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                SourceGlyph(source: .location, suggested: stop.suggested)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.label).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                    Text(stop.range + (stop.suggested ? " · Suggested" : ""))
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 0)
                if stop.coordinate != nil {
                    Image(systemName: "scope")
                        .foregroundStyle(Palette.inkTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Space.sm)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityHint(stop.coordinate != nil ? "Centers the map on this stop" : "Opens the timeline")
    }
}

/// Explains, and lets the person change, location access and tracking.
struct LocationStatusRow: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var location: LocationService
    var onShowMe: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            switch location.authorization {
            case .denied, .restricted:
                PermissionNotice(message: "Location access is off, so Lifelog cannot record routes or stops. You can allow it in Settings; nothing is recorded without it.")
            case .notDetermined:
                InfoLine(text: env.settings.locationTrackingEnabled
                         ? "Lifelog needs your permission before it can record visits."
                         : "Location visits are off. Nothing is recorded.", symbol: "location")
                HStack(spacing: Space.lg) {
                    Button(env.settings.locationTrackingEnabled ? "Allow location" : "Turn on visits") {
                        env.setLocationTracking(true)
                    }
                    .buttonStyle(QuietButtonStyle())
                    if let onShowMe {
                        Button("Show my location", action: onShowMe).buttonStyle(QuietButtonStyle())
                    }
                }
            case .authorizedWhenInUse:
                InfoLine(text: env.settings.locationTrackingEnabled
                         ? "Recording only while Lifelog is open. Allow “Always” so stops are noticed in the background."
                         : "Location is allowed while using the app. Visits are off.", symbol: "location")
                HStack(spacing: Space.lg) {
                    if !env.settings.locationTrackingEnabled {
                        Button("Turn on visits") { env.setLocationTracking(true) }.buttonStyle(QuietButtonStyle())
                    } else {
                        Button("Allow Always") { location.requestPermission(always: true) }.buttonStyle(QuietButtonStyle())
                    }
                    if let onShowMe {
                        Button("Show my location", action: onShowMe).buttonStyle(QuietButtonStyle())
                    }
                }
            case .authorizedAlways:
                InfoLine(text: env.settings.locationTrackingEnabled
                         ? "Visits are recorded on this device, in your encrypted archive."
                         : "Location is allowed, but visits are off in Settings.", symbol: "location.fill")
                HStack(spacing: Space.lg) {
                    if !env.settings.locationTrackingEnabled {
                        Button("Turn on visits") { env.setLocationTracking(true) }.buttonStyle(QuietButtonStyle())
                    }
                    if let onShowMe {
                        Button("Show my location", action: onShowMe).buttonStyle(QuietButtonStyle())
                    }
                }
            @unknown default:
                EmptyView()
            }
        }
        .surface(padding: Space.md, radius: 14)
    }
}

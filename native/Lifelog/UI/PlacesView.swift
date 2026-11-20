import SwiftUI
import MapKit

private let placeColors: [UInt32] = [
    0xFF9A4733, 0xFF47755E, 0xFF52796F, 0xFF3D6A8F, 0xFF92692A, 0xFF7A4E8F, 0xFF8F4A5C,
]

// MARK: - List

struct PlacesListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator

    private var places: [Place] { env.archive.places.sorted { $0.createdAt > $1.createdAt } }
    private var mapped: [Place] { env.archive.places.filter(\.hasCoordinates) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader(
                    eyebrow: "Your geography",
                    title: "Places",
                    subtitle: "Coordinates stay on this device. You decide what a place means."
                )

                if !mapped.isEmpty {
                    Map(initialPosition: .automatic) {
                        ForEach(mapped) { place in
                            Marker(place.name, systemImage: "star.fill", coordinate: CLLocationCoordinate2D(
                                latitude: place.latitude ?? 0,
                                longitude: place.longitude ?? 0
                            ))
                            .tint(Color(hex: place.colorValue))
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
                    .privacySensitive()
                }

                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(title: "Saved places", detail: "\(places.count)", actionTitle: "Add") {
                        navigator.present(.newPlace)
                    }
                    if places.isEmpty {
                        EmptyNote(
                            title: "No places yet",
                            message: "A place can be as specific as a room or as broad as a city."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(places) { place in
                                Button { navigator.push(.place(place.id)) } label: { PlaceRow(place: place) }
                                    .buttonStyle(RowButtonStyle())
                                if place.id != places.last?.id { Hairline() }
                            }
                        }
                    }
                }

                recentVisits
            }
            .padding(Space.page)
        }
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.inline)
        .paperScreen()
    }

    @ViewBuilder
    private var recentVisits: some View {
        let visits = Array(env.archive.visits.sorted { $0.startAt > $1.startAt }.prefix(12))
        if !visits.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(title: "Recent visits")
                VStack(spacing: 0) {
                    ForEach(visits) { visit in
                        Button { navigator.push(.map(visit.startAt)) } label: {
                            HStack(spacing: Space.md) {
                                SourceGlyph(source: .location, suggested: visit.confidence == .suggested)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(visit.label).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                                    Text(Dates.formatShortDate(visit.startAt) + " · " + Dates.formatTimeRange(visit.startAt, visit.endAt))
                                        .font(Typeface.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, Space.sm)
                        }
                        .buttonStyle(RowButtonStyle())
                        .contextMenu {
                            Button(role: .destructive) { env.deleteVisit(visit.id) } label: {
                                Label("Delete visit", systemImage: "trash")
                            }
                        }
                        if visit.id != visits.last?.id { Hairline() }
                    }
                }
            }
        }
    }
}

private struct PlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: Space.md) {
            Circle()
                .fill(Color(hex: place.colorValue).opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: place.hasCoordinates ? "location.fill" : "mappin")
                        .font(.system(.footnote))
                        .foregroundStyle(Color(hex: place.colorValue))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                Text(place.notes.isEmpty ? (place.hasCoordinates ? "Pinned" : "No coordinates") : place.notes)
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(Typeface.caption)
                .foregroundStyle(Palette.inkTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Space.sm)
    }
}

// MARK: - Detail

struct PlaceDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.dismiss) private var dismiss
    let placeId: String
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let place = env.archive.placeById(placeId) {
                content(place)
            } else {
                ContentUnavailableView("Place not found", systemImage: "mappin.slash")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .paperScreen()
    }

    private func content(_ place: Place) -> some View {
        let visits = env.archive.visits
            .filter { $0.placeId == place.id || $0.label == place.name }
            .sorted { $0.startAt > $1.startAt }
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if let lat = place.latitude, let lon = place.longitude {
                    let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    Map(
                        initialPosition: .region(MKCoordinateRegion(
                            center: center,
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        )),
                        interactionModes: [.zoom, .pan]
                    ) {
                        MapCircle(center: center, radius: place.radiusMeters)
                            .foregroundStyle(Color(hex: place.colorValue).opacity(0.18))
                        Marker(place.name, coordinate: center).tint(Color(hex: place.colorValue))
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .privacySensitive()
                }

                PageHeader(eyebrow: "Saved place", title: place.name, subtitle: place.notes.isEmpty ? nil : place.notes)

                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(title: "Visits", detail: "\(visits.count)")
                    if visits.isEmpty {
                        EmptyNote(title: "No matched visits", message: "Visits with this place's name or id appear here.")
                    } else {
                        ForEach(visits) { visit in
                            Button { navigator.push(.map(visit.startAt)) } label: {
                                HStack {
                                    Text(Dates.formatDayLong(visit.startAt)).font(Typeface.label).foregroundStyle(Palette.ink)
                                    Spacer()
                                    Text(Dates.formatTimeRange(visit.startAt, visit.endAt))
                                        .font(Typeface.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                .padding(.vertical, Space.sm)
                            }
                            .buttonStyle(RowButtonStyle())
                            Hairline()
                        }
                    }
                }

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete place", systemImage: "trash")
                }
                .buttonStyle(QuietButtonStyle())
                .tint(Palette.danger)
            }
            .padding(Space.page)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { navigator.present(.editPlace(place.id)) }
            }
        }
        .confirmationDialog("Delete this place?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete place", role: .destructive) {
                env.deletePlace(place.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Visits and entries keep their names; only the saved place is removed.")
        }
    }
}

// MARK: - Editor

struct PlaceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var draft: Place
    @State private var working = false
    @State private var message: String?

    init(place: Place) {
        var start = place
        if start.name == "Place" && start.latitude == nil { start.name = "" }
        _draft = State(initialValue: start)
    }

    private var isExisting: Bool { env.archive.placeById(draft.id) != nil }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(2...6)
                }
                locationSection
                Section("Color") { swatches }
                if isExisting {
                    Section {
                        Button("Delete place", role: .destructive) {
                            env.deletePlace(draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .paperList()
            .navigationTitle(isExisting ? "Edit place" : "New place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        env.savePlace(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave || working)
                }
            }
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Section("Location") {
            if let lat = draft.latitude, let lon = draft.longitude {
                LabeledContent("Coordinates", value: String(format: "%.4f, %.4f", lat, lon))
                Stepper(
                    "Radius \(Int(draft.radiusMeters)) m",
                    value: $draft.radiusMeters,
                    in: 50...500,
                    step: 25
                )
                Button("Update from current location") { Task { await capture() } }
                    .disabled(working)
                Button("Remove coordinates", role: .destructive) {
                    draft.latitude = nil
                    draft.longitude = nil
                }
            } else {
                Button { Task { await capture() } } label: {
                    Label(working ? "Finding you…" : "Use current location", systemImage: "location")
                }
                .disabled(working)
            }
            if let message {
                Text(message).font(Typeface.caption).foregroundStyle(Palette.inkSecondary)
            }
            if env.location.authorization == .denied || env.location.authorization == .restricted {
                Button("Open Settings to allow location") { PermissionCenter.openSystemSettings() }
            }
        }
    }

    private var swatches: some View {
        HStack(spacing: Space.md) {
            ForEach(placeColors, id: \.self) { value in
                Button { draft.colorValue = value } label: {
                    Circle()
                        .fill(Color(hex: value))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle().strokeBorder(Palette.ink, lineWidth: draft.colorValue == value ? 2 : 0).padding(-3)
                        )
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color")
                .accessibilityAddTraits(draft.colorValue == value ? .isSelected : [])
            }
        }
    }

    private func capture() async {
        working = true
        message = nil
        defer { working = false }
        if let sample = await env.location.captureCurrent() {
            draft.latitude = sample.latitude
            draft.longitude = sample.longitude
            message = "Saved your current coordinates on this device."
        } else if env.location.authorization == .denied || env.location.authorization == .restricted {
            message = "Location access is off for Lifelog."
        } else {
            message = "Could not get a location fix. Try again where the signal is better."
        }
    }
}

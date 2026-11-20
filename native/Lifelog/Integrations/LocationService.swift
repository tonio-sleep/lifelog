import Foundation
import CoreLocation

/// Captures location samples and significant visits. All records remain local;
/// reverse geocoding is used only to give a visit a human-readable label.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate, ObservableObject {
    var onSample: ((LocationSample) -> Void)?
    var onVisit: ((Visit) -> Void)?
    /// Returns a saved place near a coordinate, so visits can reuse its name.
    var placeMatcher: ((Double, Double) -> Place?)?
    var trackingEnabled: Bool

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var oneShotRequests: [UUID: LocationRequest] = [:]
    private var authWaiters: [CheckedContinuation<Void, Never>] = []
    private var wantsAlwaysUpgrade = false
    private var lastSampleAt: Date?
    private var activeVisitArrival: Date?
    private var activeVisitLabel = "Away"
    private var activeVisitPlaceId: String?

    init(trackingEnabled: Bool = false) {
        self.trackingEnabled = trackingEnabled
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
        authorization = manager.authorizationStatus
    }

    // MARK: Permission

    /// Asks for "While Using" first, then (optionally) "Always", which is what
    /// iOS expects. Visit tracking works best with Always.
    func requestPermission(always: Bool = true) {
        switch manager.authorizationStatus {
        case .notDetermined:
            wantsAlwaysUpgrade = always
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            if always { manager.requestAlwaysAuthorization() }
        default:
            break
        }
    }

    /// Prompts for "While Using" if needed and waits for the answer.
    func requestWhenInUseAndWait() async -> Bool {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                authWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        return isAuthorized
    }

    // MARK: Tracking

    func start() {
        guard trackingEnabled, CLLocationManager.locationServicesEnabled() else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways:
            manager.startMonitoringVisits()
            manager.startMonitoringSignificantLocationChanges()
            manager.startUpdatingLocation()
        case .authorizedWhenInUse:
            // Visits and significant changes require Always authorization.
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
    }

    // MARK: One-shot capture

    func captureCurrent() async -> LocationSample? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        guard await requestWhenInUseAndWait() else { return nil }
        guard let location = await requestLocation() else { return nil }
        return sample(from: location)
    }

    private func requestLocation() async -> CLLocation? {
        let id = UUID()
        let request = LocationRequest()
        oneShotRequests[id] = request
        let location: CLLocation? = await withCheckedContinuation { continuation in
            request.completion = { result in continuation.resume(returning: result) }
            request.start()
        }
        oneShotRequests[id] = nil
        return location
    }

    private func sample(from location: CLLocation) -> LocationSample? {
        let accuracy = location.horizontalAccuracy
        if accuracy < 0 { return nil }
        if accuracy.isFinite, accuracy > 1_000 { return nil }
        let speed = location.speed >= 0 ? location.speed : nil
        return LocationSample(
            recordedAt: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyMeters: accuracy.isFinite ? accuracy : nil,
            speedMps: speed
        )
    }

    // MARK: Visits

    private func label(latitude: Double, longitude: Double) async -> String {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            let place = placemarks.first
            return place?.name ?? place?.locality ?? place?.subLocality ?? "Away"
        } catch {
            return "Away"
        }
    }

    private func handleVisit(
        latitude: Double,
        longitude: Double,
        arrival: Date,
        departure: Date,
        accuracy: Double
    ) async {
        let hasArrival = arrival != Date.distantPast
        let hasDeparture = departure != Date.distantFuture
        guard hasArrival || hasDeparture else { return }
        guard latitude.isFinite, longitude.isFinite else { return }

        // Visits carry no coordinates in the archive, so store a real sample at
        // the stop. The map uses it to place the stop; nothing is invented.
        onSample?(LocationSample(
            recordedAt: hasArrival ? arrival : departure,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracy.isFinite && accuracy >= 0 ? accuracy : nil,
            speedMps: nil
        ))

        let match = placeMatcher?(latitude, longitude)

        if !hasDeparture {
            // Arrival: remember the start and resolve a label.
            activeVisitArrival = arrival
            activeVisitPlaceId = match?.id
            if let match {
                activeVisitLabel = match.name
            } else {
                activeVisitLabel = "Away"
                let resolved = await label(latitude: latitude, longitude: longitude)
                if activeVisitArrival == arrival { activeVisitLabel = resolved }
            }
            return
        }

        // Departure: a visit needs a real start time. If the app never saw the
        // arrival and iOS did not report one, there is nothing honest to record.
        let started: Date
        if let known = activeVisitArrival {
            started = known
        } else if hasArrival {
            started = arrival
        } else {
            return
        }
        guard departure > started else { return }

        var visitLabel = activeVisitLabel
        var placeId = activeVisitPlaceId
        if activeVisitArrival == nil {
            if let match {
                visitLabel = match.name
                placeId = match.id
            } else {
                visitLabel = await label(latitude: latitude, longitude: longitude)
                placeId = nil
            }
        }
        activeVisitArrival = nil
        activeVisitLabel = "Away"
        activeVisitPlaceId = nil

        onVisit?(Visit(
            label: visitLabel,
            startAt: started,
            placeId: placeId,
            endAt: departure,
            confidence: .suggested,
            notes: "Auto-tracked from Apple significant visits"
        ))
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let locations = locations
        Task { @MainActor in
            guard let location = locations.last, let item = self.sample(from: location) else { return }
            let now = Date()
            if let lastSampleAt = self.lastSampleAt, now.timeIntervalSince(lastSampleAt) < 10 * 60 { return }
            self.lastSampleAt = now
            self.onSample?(item)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Core Location failures are usually transient (for example a temporary
        // outage). Keeping this witness avoids silent "updates paused" states.
        _ = error
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let latitude = visit.coordinate.latitude
        let longitude = visit.coordinate.longitude
        let arrival = visit.arrivalDate
        let departure = visit.departureDate
        let accuracy = visit.horizontalAccuracy
        Task { @MainActor in
            await self.handleVisit(
                latitude: latitude,
                longitude: longitude,
                arrival: arrival,
                departure: departure,
                accuracy: accuracy
            )
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status != .notDetermined {
                let waiters = self.authWaiters
                self.authWaiters = []
                for waiter in waiters { waiter.resume() }
            }
            switch status {
            case .authorizedWhenInUse:
                if self.wantsAlwaysUpgrade {
                    self.wantsAlwaysUpgrade = false
                    self.manager.requestAlwaysAuthorization()
                }
                self.start()
            case .authorizedAlways:
                self.wantsAlwaysUpgrade = false
                self.start()
            default:
                self.stop()
            }
        }
    }
}

/// One-shot location request helper. Retained until the callback fires or a
/// timeout expires, so a dropped Core Location request cannot hang an editor.
@MainActor
private final class LocationRequest: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var completion: ((CLLocation?) -> Void)?

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestLocation()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            self?.finish(nil)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private func finish(_ location: CLLocation?) {
        guard let completion else { return }
        self.completion = nil
        completion(location)
    }
}

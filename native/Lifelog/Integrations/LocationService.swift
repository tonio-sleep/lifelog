import Foundation
import CoreLocation

/// Captures location samples and significant visits. All records remain local;
/// reverse geocoding is used only to give a visit a human-readable label.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    var onSample: ((LocationSample) -> Void)?
    var onVisit: ((Visit) -> Void)?
    var trackingEnabled: Bool

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var oneShotRequests: [UUID: LocationRequest] = [:]
    private var lastSampleAt: Date?
    private var activeVisitArrival: Date?
    private var activeVisitLabel = "Away"
    private var activeVisitID: UUID?

    init(trackingEnabled: Bool = false) {
        self.trackingEnabled = trackingEnabled
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

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

    func captureCurrent() async -> LocationSample? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: break
        default: return nil
        }
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
        // Core Location failures are usually transient (e.g. temporary outage).
        // Keeping this witness avoids silent "location updates paused" states.
        _ = error
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let coordinate = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        let arrivalDate = visit.arrivalDate
        let departureDate = visit.departureDate
        let isDeparture = departureDate < Date.distantFuture.addingTimeInterval(-1)

        if isDeparture {
            Task { @MainActor in
                let started = self.activeVisitArrival ?? arrivalDate
                let label = self.activeVisitLabel
                self.activeVisitArrival = nil
                self.activeVisitLabel = "Away"
                self.activeVisitID = nil
                self.onVisit?(Visit(
                    label: label,
                    startAt: started,
                    endAt: departureDate,
                    confidence: .suggested,
                    notes: "Auto-tracked from Apple significant visits"
                ))
            }
            return
        }

        let visitID = UUID()
        Task { @MainActor in
            self.activeVisitID = visitID
            self.geocoder.reverseGeocodeLocation(coordinate) { placemarks, _ in
                let place = placemarks?.first
                let label = place?.name ?? place?.locality ?? place?.subLocality ?? "Away"
                Task { @MainActor in
                    // Ignore a stale geocode if this visit already departed.
                    guard self.activeVisitID == visitID else { return }
                    self.activeVisitArrival = arrivalDate
                    self.activeVisitLabel = label
                }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.start()
            default:
                self.stop()
            }
        }
    }
}

/// One-shot location request helper. Retained until the callback fires or a
/// timeout expires, so a dropped Core Location request cannot hang Quick Add.
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

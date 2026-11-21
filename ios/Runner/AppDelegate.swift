import AVFoundation
import CoreLocation
import CoreMedia
import Flutter
import Foundation
import MapKit
import Speech
import UIKit

// MARK: - Detailed interactive map (Apple MapKit)

private final class LifelogMapPointAnnotation: MKPointAnnotation {
  var itemId = ""
  var kind = "place"
  var color: UIColor = .systemBlue
}

private final class LifelogMapCoordinator: NSObject, MKMapViewDelegate {
  private weak var mapView: MKMapView?
  private let channel: FlutterMethodChannel
  private var lastCurrentCoordinate: CLLocationCoordinate2D?

  init(mapView: MKMapView, channel: FlutterMethodChannel) {
    self.mapView = mapView
    self.channel = channel
  }

  private func double(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
  }

  private func coordinate(_ value: Any?) -> CLLocationCoordinate2D? {
    guard let dictionary = value as? [String: Any],
          let latitude = double(dictionary["latitude"]),
          let longitude = double(dictionary["longitude"]),
          latitude >= -90, latitude <= 90, longitude >= -180, longitude <= 180
    else { return nil }
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  func apply(_ arguments: Any?) {
    guard let mapView, let args = arguments as? [String: Any] else { return }

    let privateMode = args["privateMode"] as? Bool ?? false
    mapView.pointOfInterestFilter = .includingAll
    mapView.showsUserLocation = !privateMode && (args["showUser"] as? Bool ?? true)
    mapView.showsCompass = true
    mapView.showsScale = true
    mapView.showsBuildings = true
    setMapType(args["mapType"] as? String)

    mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
    mapView.removeOverlays(mapView.overlays)

    for value in args["places"] as? [[String: Any]] ?? [] {
      guard let point = coordinate(value) else { continue }
      let annotation = LifelogMapPointAnnotation()
      annotation.coordinate = point
      annotation.itemId = value["id"] as? String ?? ""
      annotation.kind = "place"
      let rawColor = double(value["color"]) ?? Double(0xFF52796F)
      annotation.color = UIColor(
        red: CGFloat((Int(rawColor) >> 16) & 0xFF) / 255,
        green: CGFloat((Int(rawColor) >> 8) & 0xFF) / 255,
        blue: CGFloat(Int(rawColor) & 0xFF) / 255,
        alpha: 1
      )
      annotation.title = privateMode ? "Saved place" : (value["name"] as? String ?? "Place")
      annotation.subtitle = privateMode ? nil : (value["notes"] as? String)
      mapView.addAnnotation(annotation)
    }

    for value in args["stops"] as? [[String: Any]] ?? [] {
      guard let point = coordinate(value) else { continue }
      let annotation = LifelogMapPointAnnotation()
      annotation.coordinate = point
      annotation.itemId = value["id"] as? String ?? ""
      annotation.kind = "stop"
      annotation.color = .systemOrange
      annotation.title = privateMode ? "Hidden stop" : (value["name"] as? String ?? "Stop")
      annotation.subtitle = privateMode ? nil : (value["notes"] as? String)
      mapView.addAnnotation(annotation)
    }

    let suppliedCurrent = coordinate(args["current"])
    lastCurrentCoordinate = privateMode ? nil : suppliedCurrent
    if !privateMode, let current = suppliedCurrent {
      // The current fix is data too: plot it and include it when fitting the
      // camera. Without this, a day with no saved pins looked like a blank map.
      let annotation = LifelogMapPointAnnotation()
      annotation.coordinate = current
      annotation.itemId = "current"
      annotation.kind = "current"
      annotation.color = .systemBlue
      annotation.title = "Current location"
      mapView.addAnnotation(annotation)
    }

    var route = (args["route"] as? [[String: Any]] ?? []).compactMap { coordinate($0) }
    if !privateMode && route.count > 1 {
      let polyline = MKPolyline(coordinates: &route, count: route.count)
      mapView.addOverlay(polyline)
    } else if !privateMode, route.count == 1 {
      let annotation = LifelogMapPointAnnotation()
      annotation.coordinate = route[0]
      annotation.kind = "route"
      annotation.color = .systemBlue
      annotation.title = "Recorded location"
      mapView.addAnnotation(annotation)
    }

    let shouldFit = args["fitOnLoad"] as? Bool ?? true
    if shouldFit {
      fitAll()
    } else if let current = suppliedCurrent, !privateMode {
      mapView.setCenter(current, animated: false)
    }
    if args["followUser"] as? Bool ?? false, !privateMode {
      // MapKit starts following as soon as a location becomes available; it
      // must not depend on userLocation already being populated.
      mapView.userTrackingMode = .follow
    }
  }

  func setMapType(_ raw: String?) {
    guard let mapView else { return }
    switch raw {
    case "satellite": mapView.mapType = .satellite
    case "hybrid": mapView.mapType = .hybrid
    default: mapView.mapType = .standard
    }
  }

  func centerOn(_ coordinate: CLLocationCoordinate2D) {
    mapView?.setCenter(coordinate, animated: true)
  }

  func centerOnUser() {
    guard let mapView else { return }
    if let location = mapView.userLocation.location {
      mapView.setCenter(location.coordinate, animated: true)
    } else {
      mapView.userTrackingMode = .follow
    }
  }

  func fitAll() {
    guard let mapView else { return }
    let annotations = mapView.annotations.filter { !($0 is MKUserLocation) }
    if !annotations.isEmpty {
      mapView.showAnnotations(annotations, animated: true)
    } else if let current = lastCurrentCoordinate {
      mapView.setCenter(current, animated: true)
    } else if let location = mapView.userLocation.location {
      mapView.setCenter(location.coordinate, animated: true)
    }
  }

  func emitPin(_ coordinate: CLLocationCoordinate2D) {
    channel.invokeMethod("pinDropped", arguments: [
      "latitude": coordinate.latitude,
      "longitude": coordinate.longitude,
      "id": "",
      "name": "",
      "color": Int(0xFF52796F),
      "radiusMeters": 120,
      "kind": "pin",
      "notes": "",
    ])
  }

  func mapView(
    _ mapView: MKMapView,
    viewFor annotation: MKAnnotation
  ) -> MKAnnotationView? {
    if annotation is MKUserLocation { return nil }
    guard let point = annotation as? LifelogMapPointAnnotation else { return nil }
    let identifier = "lifelog.map.pin"
    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
          annotation: annotation,
          reuseIdentifier: identifier
        )
    view.annotation = annotation
    view.canShowCallout = true
    view.markerTintColor = point.color
    switch point.kind {
    case "stop": view.glyphText = "S"
    case "current": view.glyphText = "●"
    case "route": view.glyphText = "•"
    default: view.glyphText = "P"
    }
    return view
  }

  func mapView(
    _ mapView: MKMapView,
    rendererFor overlay: MKOverlay
  ) -> MKOverlayRenderer {
    if let polyline = overlay as? MKPolyline {
      let renderer = MKPolylineRenderer(polyline: polyline)
      renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.55)
      renderer.lineWidth = 4
      return renderer
    }
    return MKOverlayRenderer(overlay: overlay)
  }
}

private final class LifelogMapPlatformView: NSObject, FlutterPlatformView {
  private let mapView: MKMapView
  private let channel: FlutterMethodChannel
  private let coordinator: LifelogMapCoordinator

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments: Any?
  ) {
    mapView = MKMapView(frame: frame)
    channel = FlutterMethodChannel(
      name: "lifelog/map/\(viewId)",
      binaryMessenger: messenger
    )
    coordinator = LifelogMapCoordinator(mapView: mapView, channel: channel)
    super.init()
    mapView.delegate = coordinator
    coordinator.apply(arguments)

    let longPress = UILongPressGestureRecognizer(
      target: self,
      action: #selector(handleLongPress(_:))
    )
    longPress.minimumPressDuration = 0.35
    mapView.addGestureRecognizer(longPress)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "update":
        self.coordinator.apply(call.arguments)
        result(nil)
      case "setMapType":
        self.coordinator.setMapType(call.arguments as? String)
        result(nil)
      case "centerOn":
        if let point = self.coordinatorCoordinate(call.arguments) {
          self.coordinator.centerOn(point)
        }
        result(nil)
      case "centerOnUser":
        self.coordinator.centerOnUser()
        result(nil)
      case "fitAll":
        self.coordinator.fitAll()
        result(nil)
      case "dropPinAtCenter":
        self.coordinator.emitPin(self.mapView.centerCoordinate)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func coordinatorCoordinate(_ value: Any?) -> CLLocationCoordinate2D? {
    guard let dictionary = value as? [String: Any],
          let latitude = (dictionary["latitude"] as? NSNumber)?.doubleValue,
          let longitude = (dictionary["longitude"] as? NSNumber)?.doubleValue
    else { return nil }
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began else { return }
    let point = recognizer.location(in: mapView)
    coordinator.emitPin(mapView.convert(point, toCoordinateFrom: mapView))
  }

  func view() -> UIView { mapView }
}

private final class LifelogMapViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    LifelogMapPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      arguments: args
    )
  }
}

/// Address / POI search and reverse geocoding. These queries go to Apple;
/// archive coordinates and history are never uploaded by Lifelog.
private final class LifelogMapSearchHandler: NSObject {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "lifelog/map/search",
      binaryMessenger: messenger
    )
    super.init()
    // The channel owns this handler through its closure. A weak capture here
    // let ARC deallocate it immediately, so every search returned nil.
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "search":
        self.search(call.arguments as? String ?? "") { result($0) }
      case "reverse":
        guard let dictionary = call.arguments as? [String: Any],
              let latitude = (dictionary["latitude"] as? NSNumber)?.doubleValue,
              let longitude = (dictionary["longitude"] as? NSNumber)?.doubleValue
        else {
          result(nil)
          return
        }
        self.reverse(latitude: latitude, longitude: longitude) { result($0) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func title(_ placemark: CLPlacemark) -> String {
    placemark.name ?? placemark.thoroughfare ?? placemark.locality ?? "Location"
  }

  private func subtitle(_ placemark: CLPlacemark) -> String {
    var parts: [String] = []
    if let number = placemark.subThoroughfare { parts.append(number) }
    if let street = placemark.thoroughfare { parts.append(street) }
    if let city = placemark.locality ?? placemark.subAdministrativeArea {
      parts.append(city)
    }
    if let region = placemark.administrativeArea { parts.append(region) }
    if parts.isEmpty, let postcode = placemark.postalCode { parts.append(postcode) }
    if parts.isEmpty, let country = placemark.country { parts.append(country) }
    return parts.joined(separator: ", ")
  }

  private func dictionary(_ placemark: CLPlacemark) -> [String: Any] {
    let coordinate = placemark.location?.coordinate ?? CLLocationCoordinate2D()
    return [
      "latitude": coordinate.latitude,
      "longitude": coordinate.longitude,
      "title": title(placemark),
      "subtitle": subtitle(placemark),
    ]
  }

  private func search(
    _ query: String,
    completion: @escaping ([[String: Any]]) -> Void
  ) {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    let localSearch = MKLocalSearch(request: request)
    localSearch.start { response, _ in
      let items = response?.mapItems ?? []
      if !items.isEmpty {
        let results = items.prefix(8).compactMap { $0.placemark }.map { self.dictionary($0) }
        DispatchQueue.main.async { completion(results) }
        return
      }
      CLGeocoder().geocodeAddressString(query) { placemarks, _ in
        let results = (placemarks ?? []).prefix(8).map { self.dictionary($0) }
        DispatchQueue.main.async { completion(results) }
      }
    }
  }

  private func reverse(
    latitude: Double,
    longitude: Double,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    let location = CLLocation(latitude: latitude, longitude: longitude)
    CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
      guard let placemark = placemarks?.first else {
        DispatchQueue.main.async { completion(nil) }
        return
      }
      var result = self.dictionary(placemark)
      result["latitude"] = latitude
      result["longitude"] = longitude
      DispatchQueue.main.async { completion(result) }
    }
  }
}

/// Queues iOS visit / significant-change events while Flutter is not running.
/// Monitoring uses CLLocationManager's battery-friendly APIs (no continuous
/// background GPS), so no UIBackgroundModes capability is required.
private final class LocationVisitManager: NSObject, CLLocationManagerDelegate {
  static let shared = LocationVisitManager()

  private let methodChannelName = "lifelog/location"
  private let eventChannelName = "lifelog/location/events"
  private let enabledKey = "lifelog.backgroundLocation.enabled"
  private let queueKey = "lifelog.backgroundLocation.pending"
  private let maximumQueuedEvents = 200
  // Event ids must not depend on the device locale (decimal commas, etc.).
  private let posixLocale = Locale(identifier: "en_US_POSIX")

  private let locationManager = CLLocationManager()
  private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var enabled = false
  private var monitoringActive = false

  private override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    // Visit and significant-change monitoring do not need continuous updates.
    locationManager.allowsBackgroundLocationUpdates = false
    enabled = UserDefaults.standard.bool(forKey: enabledKey)
  }

  /// Called from `didFinishLaunchingWithOptions` so a terminated app relaunched
  /// by Core Location restores monitoring before Flutter attaches its channels.
  func restoreEnabledState() {
    enabled = UserDefaults.standard.bool(forKey: enabledKey)
    if enabled {
      startMonitoring()
    } else {
      stopMonitoring()
    }
  }

  func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "setEnabled":
        let value = call.arguments as? Bool ?? false
        self.setEnabled(value)
        // Return an effective status object, not just the requested bool.
        result(self.statusDictionary())
      case "takePending", "peekPending":
        // Legacy name kept for compatibility: this is now a non-destructive
        // peek. Dart acks each event with `ackPending` after it is persisted.
        result(self.takePending())
      case "ackPending":
        self.ackPending(self.eventIds(from: call.arguments))
        result(nil)
      case "clearPending":
        self.clearPending()
        result(nil)
      case "authorizationStatus":
        result(self.authorizationStatus())
      case "locationStatus":
        result(self.statusDictionary())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.methodChannel = methodChannel

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)
    self.eventChannel = eventChannel
  }

  private func authorizationStatus() -> String {
    switch locationManager.authorizationStatus {
    case .authorizedAlways: return "always"
    case .authorizedWhenInUse: return "whenInUse"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
  }

  private var canMonitor: Bool {
    enabled &&
      CLLocationManager.locationServicesEnabled() &&
      locationManager.authorizationStatus == .authorizedAlways
  }

  private func statusDictionary() -> [String: Any] {
    let servicesEnabled = CLLocationManager.locationServicesEnabled()
    let always = locationManager.authorizationStatus == .authorizedAlways
    return [
      "enabled": enabled,
      "authorization": authorizationStatus(),
      "monitoringActive": monitoringActive,
      "locationServicesEnabled": servicesEnabled,
      "canMonitorVisits": servicesEnabled && always &&
        CLLocationManager.isMonitoringAvailable(for: CLVisit.self),
      "canMonitorSignificantChanges": servicesEnabled && always &&
        CLLocationManager.significantLocationChangeMonitoringAvailable(),
    ]
  }

  private func setEnabled(_ value: Bool) {
    enabled = value
    UserDefaults.standard.set(value, forKey: enabledKey)
    if value {
      // Always is required for visits while the app is not in the foreground.
      // iOS shows this prompt only once; afterwards the person can upgrade in
      // Settings, which the app explains in its own UI.
      if locationManager.authorizationStatus == .notDetermined {
        locationManager.requestAlwaysAuthorization()
      }
      startMonitoring()
    } else {
      stopMonitoring()
      // Disabled means the person does not want these events at all.
      clearPending()
    }
  }

  private func startMonitoring() {
    guard canMonitor else {
      monitoringActive = false
      return
    }
    var started = false
    if CLLocationManager.isMonitoringAvailable(for: CLVisit.self) {
      locationManager.startMonitoringVisits()
      started = true
    }
    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      locationManager.startMonitoringSignificantLocationChanges()
      started = true
    }
    monitoringActive = started
  }

  private func stopMonitoring() {
    if CLLocationManager.isMonitoringAvailable(for: CLVisit.self) {
      locationManager.stopMonitoringVisits()
    }
    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      locationManager.stopMonitoringSignificantLocationChanges()
    }
    monitoringActive = false
  }

  private var pending: [[String: Any]] {
    get {
      UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]] ?? []
    }
    set {
      UserDefaults.standard.set(newValue, forKey: queueKey)
    }
  }

  private func enqueue(_ event: [String: Any]) {
    guard enabled else { return }
    var queue = pending
    queue.append(event)
    if queue.count > maximumQueuedEvents {
      queue.removeFirst(queue.count - maximumQueuedEvents)
    }
    pending = queue
    eventSink?(event)
  }

  /// Non-destructive read. Events stay queued until Dart calls `ackPending`
  /// with the ids it actually persisted, so a failed write can be retried.
  private func takePending() -> [[String: Any]] {
    pending
  }

  private func eventIds(from arguments: Any?) -> Set<String> {
    if let ids = arguments as? [String] {
      return Set(ids)
    }
    if let events = arguments as? [[String: Any]] {
      return Set(events.compactMap { $0["id"] as? String })
    }
    if let event = arguments as? [String: Any], let id = event["id"] as? String {
      return [id]
    }
    return []
  }

  private func ackPending(_ ids: Set<String>) {
    guard !ids.isEmpty else { return }
    let current = pending
    let remaining = current.filter { event in
      guard let id = event["id"] as? String else { return true }
      return !ids.contains(id)
    }
    if remaining.count != current.count {
      pending = remaining
    }
  }

  private func clearPending() {
    pending = []
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard enabled else { return }
    if manager.authorizationStatus == .authorizedAlways {
      startMonitoring()
    } else {
      // When-In-Use cannot deliver background visits. Never monitor with it.
      stopMonitoring()
    }
  }

  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    let latitude = visit.coordinate.latitude
    let longitude = visit.coordinate.longitude
    let arrival = isoFormatter.string(from: visit.arrivalDate)
    let departure = isoFormatter.string(from: visit.departureDate)
    let millis = Int(visit.arrivalDate.timeIntervalSince1970 * 1000)
    var event: [String: Any] = [
      "id": String(
        format: "visit-%d-%.5f-%.5f",
        locale: posixLocale,
        millis,
        latitude,
        longitude
      ),
      "source": "visit",
      "latitude": latitude,
      "longitude": longitude,
      "accuracy": visit.horizontalAccuracy,
      "startedAt": arrival,
    ]
    // An ongoing visit reports NSDate.distantFuture; leave it open instead of
    // writing a year-9999 departure sample.
    if visit.departureDate.timeIntervalSinceNow < 60 * 60 * 24 * 365 {
      event["endedAt"] = departure
    }
    enqueue(event)
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    let timestamp = isoFormatter.string(from: location.timestamp)
    let millis = Int(location.timestamp.timeIntervalSince1970 * 1000)
    let event: [String: Any] = [
      "id": String(
        format: "significant-%d-%.5f-%.5f",
        locale: posixLocale,
        millis,
        location.coordinate.latitude,
        location.coordinate.longitude
      ),
      "source": "significant",
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "startedAt": timestamp,
    ]
    enqueue(event)
  }
}

extension LocationVisitManager: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    // Replay anything collected before Dart was listening. The queue is not
    // cleared here; `_handleBackgroundEvent` acks it through the same path as
    // the periodic flush.
    for event in pending { events(event) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

/// File-based on-device speech recognition. It runs only on a finished audio
/// file, after the recorder has been stopped, so long recordings never depend
/// on a live recognition session staying alive.
private final class LifelogTranscriptionHandler: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private var lastEvent: [String: Any]?

  private var task: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?
  private var activeId: String?
  private var activeStart: Date?
  private var activeDuration: Double = 0
  private var activeTranscript = ""
  private var activeRecognizedSeconds: Double = 0
  private var activeHasTimedSegments = false
  private var generation = 0

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: "lifelog/transcription",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "lifelog/transcription/events",
      binaryMessenger: messenger
    )
    super.init()
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "prepare":
        let args = call.arguments as? [String: Any]
        self.prepare(localeId: args?["localeId"] as? String) { result($0) }
      case "transcribe":
        self.transcribe(
          call.arguments,
          completion: { result($0) },
          failure: { result($0) }
        )
      case "cancel":
        self.cancelCurrent()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    eventChannel.setStreamHandler(self)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    if let lastEvent = lastEvent {
      events(lastEvent)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func authorizationStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    default: return "unknown"
    }
  }

  private func resolvedLocaleId(_ raw: String?) -> String {
    if let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
       !raw.isEmpty {
      return raw.replacingOccurrences(of: "_", with: "-")
    }
    return Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
  }

  private func supportedLanguages() -> [[String: Any]] {
    let languages: [[String: Any]] = SFSpeechRecognizer.supportedLocales().map { locale in
      let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
      let name = Locale.current.localizedString(forIdentifier: identifier) ?? identifier
      return ["id": identifier, "name": name] as [String: Any]
    }
    return languages.sorted { left, right in
      (left["id"] as? String ?? "") < (right["id"] as? String ?? "")
    }
  }

  private func prepare(
    localeId: String?,
    completion: @escaping ([String: Any]) -> Void
  ) {
    let finish: (SFSpeechRecognizerAuthorizationStatus) -> Void = { status in
      DispatchQueue.main.async {
        let resolved = self.resolvedLocaleId(localeId)
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: resolved))
        completion([
          "status": self.authorizationStatus(status),
          "localeId": resolved,
          "onDeviceAvailable": recognizer?.supportsOnDeviceRecognition ?? false,
          "languages": self.supportedLanguages(),
        ])
      }
    }

    let status = SFSpeechRecognizer.authorizationStatus()
    if status == .notDetermined {
      SFSpeechRecognizer.requestAuthorization { finish($0) }
    } else {
      finish(status)
    }
  }

  private func audioDuration(
    _ url: URL,
    completion: @escaping (Double?) -> Void
  ) {
    let asset = AVURLAsset(url: url)
    asset.loadValuesAsynchronously(forKeys: ["duration"]) { [asset] in
      var error: NSError?
      let status = asset.statusOfValue(forKey: "duration", error: &error)
      var seconds: Double?
      if status == .loaded {
        let value = CMTimeGetSeconds(asset.duration)
        if value.isFinite && value > 0 {
          seconds = value
        }
      }
      DispatchQueue.main.async { completion(seconds) }
    }
  }

  private func errorDetails(message: String) -> [String: Any] {
    return [
      "transcript": activeTranscript,
      "recognizedSeconds": activeRecognizedSeconds,
      "durationSeconds": activeDuration,
      "elapsedSeconds": activeStart.map { Date().timeIntervalSince($0) } ?? 0,
      "hasTimedSegments": activeHasTimedSegments,
      "message": message,
    ]
  }

  private func flutterError(_ code: String, _ message: String) -> FlutterError {
    FlutterError(
      code: code,
      message: message,
      details: errorDetails(message: message)
    )
  }

  private func progressEvent(final: Bool) -> [String: Any] {
    return [
      "transcriptionId": activeId ?? "",
      "transcript": activeTranscript,
      "recognizedSeconds": activeRecognizedSeconds,
      "durationSeconds": activeDuration,
      "elapsedSeconds": activeStart.map { Date().timeIntervalSince($0) } ?? 0,
      "hasTimedSegments": activeHasTimedSegments,
      "isFinal": final,
    ]
  }

  private func emitProgress(final: Bool) {
    guard activeId != nil else { return }
    let event = progressEvent(final: final)
    lastEvent = event
    eventSink?(event)
  }

  private func resultPayload(onDevice: Bool) -> [String: Any] {
    var payload = progressEvent(final: true)
    payload["transcript"] = activeTranscript
    payload["onDevice"] = onDevice
    return payload
  }

  private func invalidateActive(cancelTask: Bool) {
    if cancelTask {
      task?.cancel()
    }
    task = nil
    recognizer = nil
    activeId = nil
    activeStart = nil
    activeDuration = 0
    activeTranscript = ""
    activeRecognizedSeconds = 0
    activeHasTimedSegments = false
    lastEvent = nil
  }

  /// Always advances the generation so a cancel that arrives while the audio
  /// duration is still loading also stops that recognition from starting.
  private func cancelCurrent() {
    generation += 1
    guard activeId != nil || task != nil || recognizer != nil else { return }
    invalidateActive(cancelTask: true)
  }

  private func transcribe(
    _ arguments: Any?,
    completion: @escaping ([String: Any]) -> Void,
    failure: @escaping (FlutterError) -> Void
  ) {
    guard let args = arguments as? [String: Any],
          let path = args["path"] as? String,
          !path.isEmpty else {
      failure(flutterError("INVALID_ARGUMENTS", "No audio file was supplied."))
      return
    }
    let id = args["transcriptionId"] as? String ?? UUID().uuidString
    let localeId = resolvedLocaleId(args["localeId"] as? String)
    guard FileManager.default.fileExists(atPath: path) else {
      failure(flutterError("FILE_NOT_FOUND", "The recorded audio file was not found."))
      return
    }

    var completed = false
    let finishSuccess: ([String: Any]) -> Void = { payload in
      guard !completed else { return }
      completed = true
      completion(payload)
    }
    let finishError: (FlutterError) -> Void = { error in
      guard !completed else { return }
      completed = true
      failure(error)
    }

    cancelCurrent()
    let requestGeneration = generation
    let url = URL(fileURLWithPath: path)
    audioDuration(url) { [weak self] duration in
      guard let self else { return }
      guard requestGeneration == self.generation else { return }
      guard let duration = duration else {
        finishError(self.flutterError("INVALID_AUDIO", "The audio file has no readable duration."))
        return
      }
      guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
        finishError(self.flutterError("NOT_AUTHORIZED", "Speech recognition is not authorized."))
        return
      }
      guard let recognizer = SFSpeechRecognizer(
        locale: Locale(identifier: localeId)
      ) else {
        finishError(self.flutterError("UNSUPPORTED_LOCALE", "This language is not supported by speech recognition."))
        return
      }
      // On-device only: Lifelog never uploads the recording to a speech server.
      guard recognizer.supportsOnDeviceRecognition else {
        finishError(self.flutterError(
          "ON_DEVICE_UNAVAILABLE",
          "On-device transcription is not available for this language."
        ))
        return
      }
      guard recognizer.isAvailable else {
        finishError(self.flutterError(
          "RECOGNIZER_UNAVAILABLE",
          "Speech recognition is temporarily unavailable."
        ))
        return
      }

      let request = SFSpeechURLRecognitionRequest(url: url)
      request.requiresOnDeviceRecognition = true
      request.shouldReportPartialResults = true
      if #available(iOS 16.0, *) {
        request.addsPunctuation = true
      }
      request.taskHint = .dictation

      let generation = requestGeneration
      self.recognizer = recognizer
      self.activeId = id
      self.activeStart = Date()
      self.activeDuration = duration
      self.activeTranscript = ""
      self.activeRecognizedSeconds = 0
      self.activeHasTimedSegments = false
      self.emitProgress(final: false)

      self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
        guard let self else { return }
        DispatchQueue.main.async {
          guard generation == self.generation,
                self.activeId == id,
                !completed else { return }
          if let result = result {
            let transcription = result.bestTranscription
            self.activeTranscript = transcription.formattedString
            var furthest = 0.0
            var hasTimedSegments = false
            for segment in transcription.segments {
              let end = segment.timestamp + segment.duration
              hasTimedSegments = true
              if end.isFinite && end > furthest {
                furthest = end
              }
            }
            if hasTimedSegments {
              self.activeRecognizedSeconds = furthest
              self.activeHasTimedSegments = true
            }
            self.emitProgress(final: result.isFinal)
            if result.isFinal {
              finishSuccess(self.resultPayload(onDevice: true))
              self.generation += 1
              self.invalidateActive(cancelTask: false)
              return
            }
          }
          if let error = error {
            let message = error.localizedDescription
              .trimmingCharacters(in: .whitespacesAndNewlines)
            finishError(self.flutterError(
              "RECOGNITION_FAILED",
              message.isEmpty ? "Speech recognition failed." : message
            ))
            self.generation += 1
            self.invalidateActive(cancelTask: true)
          }
        }
      }
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var transcriptionHandler: LifelogTranscriptionHandler?
  private var mapSearchHandler: LifelogMapSearchHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Force-create before Flutter registers plugins. A background visit can
    // relaunch the app directly into this path; monitoring must already be on.
    _ = LocationVisitManager.shared
    LocationVisitManager.shared.restoreEnabledState()
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LifelogLocation") {
      LocationVisitManager.shared.register(with: registrar)
    }
    if let mapRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "LifelogMap") {
      mapRegistrar.register(
        LifelogMapViewFactory(messenger: mapRegistrar.messenger()),
        withId: "lifelog/map"
      )
      mapSearchHandler = LifelogMapSearchHandler(
        messenger: mapRegistrar.messenger()
      )
    }
    if let transcriptionRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "LifelogTranscription"
    ) {
      transcriptionHandler = LifelogTranscriptionHandler(
        messenger: transcriptionRegistrar.messenger()
      )
    }
  }
}

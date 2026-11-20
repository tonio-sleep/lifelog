import CoreLocation
import Flutter
import UIKit

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

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
  }
}

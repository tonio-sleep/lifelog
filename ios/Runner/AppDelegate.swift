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

  private override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    // Visit and significant-change monitoring do not need continuous updates.
    locationManager.allowsBackgroundLocationUpdates = false
    enabled = UserDefaults.standard.bool(forKey: enabledKey)
    if enabled { startMonitoring() }
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
        result(self.enabled)
      case "takePending":
        result(self.takePending())
      case "authorizationStatus":
        result(self.authorizationStatus())
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
    }
  }

  private func startMonitoring() {
    guard CLLocationManager.locationServicesEnabled() else { return }
    if CLLocationManager.isMonitoringAvailable(for: CLVisit.self) {
      locationManager.startMonitoringVisits()
    }
    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      locationManager.startMonitoringSignificantLocationChanges()
    }
  }

  private func stopMonitoring() {
    if CLLocationManager.isMonitoringAvailable(for: CLVisit.self) {
      locationManager.stopMonitoringVisits()
    }
    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      locationManager.stopMonitoringSignificantLocationChanges()
    }
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

  /// Hands queued events to Dart and clears them. Dart writes them into the
  /// encrypted archive immediately and de-duplicates by event id.
  private func takePending() -> [[String: Any]] {
    let events = pending
    if !events.isEmpty { pending = [] }
    return events
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard enabled else { return }
    if manager.authorizationStatus == .authorizedAlways ||
        manager.authorizationStatus == .authorizedWhenInUse {
      startMonitoring()
    }
  }

  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    let latitude = visit.coordinate.latitude
    let longitude = visit.coordinate.longitude
    let arrival = isoFormatter.string(from: visit.arrivalDate)
    let departure = isoFormatter.string(from: visit.departureDate)
    let millis = Int(visit.arrivalDate.timeIntervalSince1970 * 1000)
    var event: [String: Any] = [
      "id": String(format: "visit-%d-%.5f-%.5f", millis, latitude, longitude),
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
      "id": String(format: "significant-%d-%.5f-%.5f",
                   millis, location.coordinate.latitude, location.coordinate.longitude),
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
    // Send anything collected before the Dart listener was ready.
    for event in takePending() { events(event) }
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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LifelogLocation") {
      LocationVisitManager.shared.register(with: registrar)
    }
  }
}

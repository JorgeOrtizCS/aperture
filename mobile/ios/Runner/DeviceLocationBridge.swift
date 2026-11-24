import CoreLocation
import Flutter
import UIKit

/// Foreground-only, bounded OS measurements. No coordinate storage or logging.
@MainActor
final class DeviceLocationBridge: NSObject, CLLocationManagerDelegate {
  static let shared = DeviceLocationBridge()
  private let manager = CLLocationManager()
  private var channel: FlutterMethodChannel?
  private var observers: [NSObjectProtocol] = []
  private var permissionOwner: Int64?
  private var permissionResult: FlutterResult?
  private var pending: Request?

  private final class Request {
    let owner: Int64
    let id: Int64
    let started = Date()
    let result: FlutterResult
    var timeout: DispatchWorkItem?
    init(owner: Int64, id: Int64, result: @escaping FlutterResult) {
      self.owner = owner; self.id = id; self.result = result
    }
  }

  func register(with messenger: FlutterBinaryMessenger) {
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest // Desired quality, not an accepted policy limit.
    manager.distanceFilter = kCLDistanceFilterNone
    manager.allowsBackgroundLocationUpdates = false
    let channel = FlutterMethodChannel(name: "aperture/device_location", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in self?.handle(call, result: result) }
    }
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers = [
      NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
        object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.inactive() }
        },
      NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
        object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.backgrounded() }
        },
    ]
  }

  private var foreground: Bool { UIApplication.shared.applicationState == .active }
  private func permission() -> String {
    guard CLLocationManager.locationServicesEnabled() else { return "unavailable" }
    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      return manager.accuracyAuthorization == .fullAccuracy ? "granted" : "approximate"
    case .notDetermined: return "notDetermined"
    case .denied: return "permanentlyDenied"
    case .restricted: return "unavailable"
    @unknown default: return "unavailable"
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let owner = (args?["owner_id"] as? NSNumber)?.int64Value
    switch call.method {
    case "permission": result(permission())
    case "requestPermission":
      guard let owner, owner > 0, foreground else { result("unavailable"); return }
      guard permissionResult == nil else { result("unavailable"); return }
      let state = permission()
      guard state == "notDetermined" else { result(state); return }
      permissionOwner = owner; permissionResult = result
      manager.requestWhenInUseAuthorization()
    case "locate":
      guard let owner, owner > 0,
        let id = (args?["request_id"] as? NSNumber)?.int64Value, id > 0,
        let timeout = (args?["timeout_ms"] as? NSNumber)?.intValue,
        (1...4000).contains(timeout), foreground else {
        result(["status": "unavailable"]); return
      }
      let state = permission()
      guard state == "granted" else {
        result(["status": state == "notDetermined" ? "permissionRequired" : state]); return
      }
      if let previous = pending { finish(previous, value: ["status": "cancelled"]) }
      let request = Request(owner: owner, id: id, result: result)
      pending = request
      let timer = DispatchWorkItem { [weak self, weak request] in
        MainActor.assumeIsolated {
          if let request { self?.finish(request, value: ["status": "unavailable"]) }
        }
      }
      request.timeout = timer
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeout), execute: timer)
      // Updates are requested only until a new valid fix or the bounded timeout.
      // requestLocation() can finish with an old cached fix without another update.
      manager.startUpdatingLocation()
    case "cancelAcquisition":
      if let request = pending, request.owner == owner { finish(request, value: ["status": "cancelled"]) }
      result(nil)
    case "close":
      if let request = pending, request.owner == owner { finish(request, value: ["status": "cancelled"]) }
      if permissionOwner == owner { finishPermission("cancelled") }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let state = permission()
    if state != "notDetermined" { finishPermission(state) }
    if state != "granted", let request = pending { finish(request, value: ["status": state]) }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard foreground, let request = pending else { return }
    let state = permission()
    guard state == "granted" else { finish(request, value: ["status": state]); return }
    let now = Date()
    guard let fix = locations.last(where: {
      CLLocationCoordinate2DIsValid($0.coordinate) &&
      $0.coordinate.latitude.isFinite && $0.coordinate.longitude.isFinite &&
      $0.horizontalAccuracy.isFinite && $0.horizontalAccuracy >= 0 &&
      $0.timestamp >= request.started && $0.timestamp <= now
    }) else { return }
    finish(request, value: ["status": "granted", "latitude": fix.coordinate.latitude,
      "longitude": fix.coordinate.longitude, "accuracy_m": fix.horizontalAccuracy,
      "timestamp_ms": Int64(fix.timestamp.timeIntervalSince1970 * 1000)])
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if let error = error as? CLError, error.code == .locationUnknown { return }
    if let request = pending { finish(request, value: ["status": "unavailable"]) }
  }

  private func finish(_ request: Request, value: [String: Any]) {
    guard pending === request else { return }
    pending = nil
    request.timeout?.cancel(); request.timeout = nil
    manager.stopUpdatingLocation()
    request.result(value)
  }
  private func finishPermission(_ state: String) {
    let result = permissionResult
    permissionOwner = nil; permissionResult = nil
    result?(state) // Permission never starts a fix or returns viewing approval.
  }
  private func inactive() {
    if let request = pending { finish(request, value: ["status": "cancelled"]) }
  }
  private func backgrounded() { inactive(); finishPermission("cancelled") }
}

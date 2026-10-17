import Flutter
import UIKit

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
    Task { @MainActor in
      ScreenCaptureProtectionBridge.shared.register(
        with: engineBridge.applicationRegistrar.messenger()
      )
    }
  }
}

private final class ScreenCaptureProtectionBridge: NSObject, FlutterStreamHandler {
  static let shared = ScreenCaptureProtectionBridge()

  private let methodChannelName = "aperture/screen_capture_protection"
  private let eventChannelName = "aperture/screen_capture_protection/events"

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private weak var flutterViewController: UIViewController?
  private weak var flutterWindowScene: UIWindowScene?
  private weak var observedCaptureScene: UIWindowScene?
  private var captureStateTraitRegistration: Any?
  private var protectionEnabled = false
  private var legacyObserverRegistered = false
  private var screenshotObserverRegistered = false

  @MainActor
  func register(with messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: messenger
    )

    methodChannel?.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        guard let self else {
          result(FlutterError(
            code: "unavailable",
            message: "Screen capture protection bridge is unavailable.",
            details: nil
          ))
          return
        }

        switch call.method {
        case "enableProtection":
          result(self.enableProtection())
        case "disableProtection":
          self.disableProtection()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    eventChannel?.setStreamHandler(self)
  }

  @MainActor
  private func enableProtection() -> Any {
    protectionEnabled = true
    debugLog("protection enabled")
    registerScreenshotObserverIfNeeded()
    attachFlutterViewControllerIfAvailable()
    guard let captureActive = currentCaptureState() else {
      return FlutterError(
        code: "capture_state_unavailable",
        message: "The Flutter scene capture state could not be confirmed.",
        details: nil
      )
    }
    publishCaptureState(captureActive)
    return captureActive
  }

  @MainActor
  private func disableProtection() {
    protectionEnabled = false
    removeScreenshotObserverIfNeeded()
    publishCaptureState(false)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    Task { @MainActor in
      self.eventSink = events
      self.attachFlutterViewControllerIfAvailable()
      self.publishCaptureState(
        self.protectionEnabled ? self.currentCaptureState() : false
      )
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    Task { @MainActor in
      self.eventSink = nil
    }
    return nil
  }

  @MainActor
  private func attachFlutterViewControllerIfAvailable() {
    if let controller = flutterViewController,
       let windowScene = controller.view.window?.windowScene ?? flutterWindowScene {
      flutterWindowScene = windowScene
      registerCaptureStateObserver(for: windowScene)
      return
    }

    let windowScenes = UIApplication.shared.connectedScenes.compactMap {
      $0 as? UIWindowScene
    }.sorted { lhs, rhs in
      activationPriority(lhs.activationState) < activationPriority(rhs.activationState)
    }

    for windowScene in windowScenes {
      let windows = windowScene.windows.sorted { lhs, rhs in
        lhs.isKeyWindow && !rhs.isKeyWindow
      }

      for window in windows where window.rootViewController != nil {
        if let controller = findFlutterViewController(
          from: window.rootViewController
        ) {
          flutterViewController = controller
          flutterWindowScene = controller.view.window?.windowScene ?? windowScene
          if let flutterWindowScene {
            debugLog(
              "capture monitoring found Flutter scene state=\(captureStateDescription(flutterWindowScene))"
            )
            registerCaptureStateObserver(for: flutterWindowScene)
          }
          return
        }
      }
    }

    registerLegacyCaptureStateObserverIfNeeded()
  }

  private func activationPriority(_ activationState: UIScene.ActivationState)
    -> Int {
    switch activationState {
    case .foregroundActive:
      return 0
    case .foregroundInactive:
      return 1
    case .background:
      return 2
    case .unattached:
      return 3
    @unknown default:
      return 4
    }
  }

  @MainActor
  private func findFlutterViewController(
    from controller: UIViewController?
  ) -> UIViewController? {
    guard let controller else {
      return nil
    }

    if controller is FlutterViewController {
      return controller
    }

    if let navigationController = controller as? UINavigationController {
      return findFlutterViewController(
        from: navigationController.visibleViewController
      )
    }

    if let tabBarController = controller as? UITabBarController {
      return findFlutterViewController(
        from: tabBarController.selectedViewController
      )
    }

    if let presentedController = controller.presentedViewController,
       let flutterController = findFlutterViewController(
         from: presentedController
       ) {
      return flutterController
    }

    for child in controller.children {
      if let flutterController = findFlutterViewController(from: child) {
        return flutterController
      }
    }

    return nil
  }

  @MainActor
  private func registerCaptureStateObserver(for windowScene: UIWindowScene) {
    if #available(iOS 17.0, *) {
      guard observedCaptureScene !== windowScene else {
        return
      }

      observedCaptureScene = windowScene
      captureStateTraitRegistration = windowScene.registerForTraitChanges(
        [UITraitSceneCaptureState.self]
      ) {
        [weak self] (scene: UIWindowScene, _: UITraitCollection) in
        Task { @MainActor in
          self?.debugLog(
            "scene capture state changed to \(self?.captureStateDescription(scene) ?? "unknown")"
          )
          self?.publishCurrentCaptureState()
        }
      }
      debugLog(
        "capture monitoring registered for Flutter UIWindowScene state=\(captureStateDescription(windowScene))"
      )
    } else {
      registerLegacyCaptureStateObserverIfNeeded()
    }
  }

  @MainActor
  private func registerLegacyCaptureStateObserverIfNeeded() {
    if #available(iOS 17.0, *) {
      return
    }

    guard !legacyObserverRegistered else {
      return
    }

    legacyObserverRegistered = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(legacyCaptureStateChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    debugLog("legacy UIScreen.isCaptured monitoring registered")
  }

  @objc private func legacyCaptureStateChanged() {
    Task { @MainActor in
      self.debugLog("legacy screen capture state changed")
      self.publishCurrentCaptureState()
    }
  }

  @MainActor
  private func registerScreenshotObserverIfNeeded() {
    guard !screenshotObserverRegistered else {
      return
    }

    screenshotObserverRegistered = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(userDidTakeScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    debugLog("screenshot monitoring registered")
  }

  @MainActor
  private func removeScreenshotObserverIfNeeded() {
    guard screenshotObserverRegistered else {
      return
    }

    screenshotObserverRegistered = false
    NotificationCenter.default.removeObserver(
      self,
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
  }

  @objc private func userDidTakeScreenshot() {
    Task { @MainActor in
      guard self.protectionEnabled else {
        return
      }

      self.debugLog("screenshot detected while protection active")
      self.publishScreenshotViolation()
    }
  }

  @MainActor
  private func publishCurrentCaptureState() {
    guard protectionEnabled else {
      return
    }

    publishCaptureState(currentCaptureState())
  }

  @MainActor
  private func publishCaptureState(_ captureActive: Bool?) {
    guard let captureActive else {
      eventSink?(FlutterError(
        code: "capture_state_unavailable",
        message: "The Flutter scene capture state could not be confirmed.",
        details: nil
      ))
      return
    }
    debugLog("event sent to Flutter captureActive=\(captureActive)")
    eventSink?([
      "type": "capture",
      "active": captureActive,
    ])
  }

  @MainActor
  private func publishScreenshotViolation() {
    debugLog("event sent to Flutter screenshot violation")
    eventSink?([
      "type": "screenshot",
    ])
  }

  @MainActor
  private func currentCaptureState() -> Bool? {
    attachFlutterViewControllerIfAvailable()

    if #available(iOS 17.0, *),
       let flutterWindowScene {
      let captureState = flutterWindowScene.traitCollection.sceneCaptureState
      guard captureState == .active || captureState == .inactive else {
        return nil
      }
      let captureActive = captureState == .active
      debugLog(
        "evaluated scene capture state=\(captureStateDescription(flutterWindowScene))"
      )
      return captureActive
    }

    if #unavailable(iOS 17.0) {
      let captureActive = UIScreen.main.isCaptured
      debugLog("evaluated UIScreen.isCaptured=\(captureActive)")
      return captureActive
    }

    return nil
  }

  @MainActor
  private func captureStateDescription(_ windowScene: UIWindowScene) -> String {
    if #available(iOS 17.0, *) {
      switch windowScene.traitCollection.sceneCaptureState {
      case .active:
        return "active"
      case .inactive:
        return "inactive"
      case .unspecified:
        return "unspecified"
      @unknown default:
        return "unknown"
      }
    }

    return "legacy"
  }

  private func debugLog(_ message: String) {
    #if DEBUG
      NSLog("[ApertureCapture] \(message)")
    #endif
  }
}

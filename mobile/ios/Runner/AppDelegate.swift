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
  private var protectionEnabled = false
  private var traitObserverRegistered = false
  private var legacyObserverRegistered = false

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
  private func enableProtection() -> Bool {
    protectionEnabled = true
    attachFlutterViewControllerIfAvailable()
    let captureActive = currentCaptureState()
    publish(captureActive)
    return captureActive
  }

  @MainActor
  private func disableProtection() {
    protectionEnabled = false
    publish(false)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    Task { @MainActor in
      self.eventSink = events
      self.attachFlutterViewControllerIfAvailable()
      events(self.protectionEnabled ? self.currentCaptureState() : false)
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
    guard flutterViewController == nil else {
      return
    }

    let windowScenes = UIApplication.shared.connectedScenes.compactMap {
      $0 as? UIWindowScene
    }

    for windowScene in windowScenes {
      for window in windowScene.windows where window.rootViewController != nil {
        if let controller = findFlutterViewController(
          from: window.rootViewController
        ) {
          flutterViewController = controller
          registerCaptureStateObserver(for: controller)
          return
        }
      }
    }

    registerLegacyCaptureStateObserverIfNeeded()
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
  private func registerCaptureStateObserver(for controller: UIViewController) {
    if #available(iOS 17.0, *) {
      guard !traitObserverRegistered else {
        return
      }

      traitObserverRegistered = true
      controller.registerForTraitChanges([UITraitSceneCaptureState.self]) {
        [weak self] (_: UIViewController, _: UITraitCollection) in
        Task { @MainActor in
          self?.publishCurrentCaptureState()
        }
      }
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
  }

  @objc private func legacyCaptureStateChanged() {
    Task { @MainActor in
      self.publishCurrentCaptureState()
    }
  }

  @MainActor
  private func publishCurrentCaptureState() {
    guard protectionEnabled else {
      return
    }

    publish(currentCaptureState())
  }

  @MainActor
  private func publish(_ captureActive: Bool) {
    eventSink?(captureActive)
  }

  @MainActor
  private func currentCaptureState() -> Bool {
    attachFlutterViewControllerIfAvailable()

    if #available(iOS 17.0, *),
       let flutterViewController {
      return flutterViewController.traitCollection.sceneCaptureState == .active
    }

    if #unavailable(iOS 17.0) {
      return UIScreen.main.isCaptured
    }

    return false
  }
}

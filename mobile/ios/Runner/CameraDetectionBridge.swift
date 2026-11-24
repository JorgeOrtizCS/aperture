import AVFoundation
import Flutter
import MediaPipeTasksVision
import UIKit

/// No preview layer, frame storage, network calls or image logging.
final class CameraDetectionBridge: NSObject, FlutterStreamHandler,
  AVCaptureVideoDataOutputSampleBufferDelegate {
  static let shared = CameraDetectionBridge()
  private let queue = DispatchQueue(label: "aperture.camera.inference")
  // Main-thread bridge state. Capture and inference resources belong to queue.
  private var sink: FlutterEventSink?
  private var token: Int?
  private var pendingStart: FlutterResult?
  private var methods: FlutterMethodChannel?
  private var events: FlutterEventChannel?
  private var capture: AVCaptureSession?
  private var detector: ObjectDetector?
  private var runToken: Int?
  private var lastFrameTime = -Double.infinity

  func register(with messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "aperture/camera_detection", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "aperture/camera_detection/events", binaryMessenger: messenger)
    events?.setStreamHandler(self)
    methods?.setMethodCallHandler { [weak self] call, result in
      guard let self,
        let args = call.arguments as? [String: Any], let id = args["session_id"] as? Int else {
        result(FlutterError(code: "invalid_arguments", message: "Missing camera run ID.", details: nil))
        return
      }
      switch call.method {
      case "start": self.start(id: id, result: result)
      case "stop": self.stop(id: id, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(self, selector: #selector(inactive),
      name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
      name: AVCaptureSession.wasInterruptedNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
      name: AVCaptureSession.runtimeErrorNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged),
      name: UIDevice.orientationDidChangeNotification, object: nil)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    if let id = token { stop(id: id, result: nil) }
    return nil
  }

  private func start(id: Int, result: @escaping FlutterResult) {
    guard sink != nil, token == nil,
      UIApplication.shared.applicationState == .active else {
      result(FlutterError(code: "camera_unavailable", message: "Camera requires an active viewer.", details: nil))
      return
    }
    token = id
    pendingStart = result
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: configure(id: id)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self, self.token == id else { return }
          if granted { self.configure(id: id) }
          else { self.fail(id: id, code: "permission_denied") }
        }
      }
    default: fail(id: id, code: "permission_denied")
    }
  }

  private func configure(id: Int) {
    guard token == id, UIApplication.shared.applicationState == .active else {
      fail(id: id, code: "app_inactive")
      return
    }
    let orientation = currentVideoOrientation()
    queue.async {
      do {
        guard let path = Bundle.main.path(forResource: "efficientdet_lite0", ofType: "tflite"),
          let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
          throw CameraFailure.unavailable
        }
        let options = ObjectDetectorOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .image
        options.scoreThreshold = 0.15
        options.categoryAllowlist = ["cell phone", "person"]
        options.maxResults = -1
        self.detector = try ObjectDetector(options: options)
        let capture = AVCaptureSession()
        self.capture = capture
        capture.sessionPreset = .vga640x480
        let input = try AVCaptureDeviceInput(device: device)
        guard capture.canAddInput(input) else { throw CameraFailure.unavailable }
        capture.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: self.queue)
        guard capture.canAddOutput(output) else { throw CameraFailure.unavailable }
        capture.addOutput(output)
        output.connection(with: .video)?.videoOrientation = orientation
        self.runToken = id
        self.lastFrameTime = -Double.infinity
        capture.startRunning()
        guard capture.isRunning else { throw CameraFailure.unavailable }
        DispatchQueue.main.async {
          guard self.token == id else { return }
          self.pendingStart?(true)
          self.pendingStart = nil
        }
      } catch {
        self.releaseResources()
        DispatchQueue.main.async { self.fail(id: id, code: "detector_start_failed") }
      }
    }
  }

  private func stop(id: Int, result: FlutterResult?) {
    if token == id {
      token = nil
      pendingStart?(FlutterError(code: "cancelled", message: "Camera startup cancelled.", details: nil))
      pendingStart = nil
    }
    queue.async {
      if self.runToken == id || self.runToken == nil { self.releaseResources() }
      DispatchQueue.main.async { result?(nil) }
    }
  }

  private func releaseResources() {
    // Called only on the capture queue, after any current inference finishes.
    capture?.stopRunning()
    for output in capture?.outputs ?? [] {
      (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
      capture?.removeOutput(output)
    }
    for input in capture?.inputs ?? [] { capture?.removeInput(input) }
    capture = nil
    detector = nil
    runToken = nil
  }

  private func fail(id: Int, code: String) {
    guard token == id else { return }
    let error = FlutterError(code: code, message: "Camera protection unavailable. Content stays hidden.", details: nil)
    pendingStart?(error)
    pendingStart = nil
    sink?(error)
    stop(id: id, result: nil)
  }

  @objc private func inactive() {
    if let id = token { fail(id: id, code: "app_inactive") }
  }

  @objc private func interrupted() {
    DispatchQueue.main.async {
      if let id = self.token { self.fail(id: id, code: "camera_interrupted") }
    }
  }

  @objc private func orientationChanged() {
    let orientation = currentVideoOrientation()
    queue.async {
      for output in self.capture?.outputs ?? [] {
        output.connection(with: .video)?.videoOrientation = orientation
      }
    }
  }

  private func currentVideoOrientation() -> AVCaptureVideoOrientation {
    switch UIDevice.current.orientation {
    case .portraitUpsideDown: return .portraitUpsideDown
    case .landscapeLeft: return .landscapeRight
    case .landscapeRight: return .landscapeLeft
    default: return .portrait
    }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection) {
    guard let detector, let id = runToken else { return }
    // Bound power use without retaining a queue of old camera frames.
    let now = CACurrentMediaTime()
    guard now - lastFrameTime >= 0.2 else { return }
    lastFrameTime = now
    do {
      // The output connection rotates buffers to the current device orientation.
      let image = try MPImage(sampleBuffer: sampleBuffer, orientation: .up)
      let start = CACurrentMediaTime()
      let result = try detector.detect(image: image)
      let latency = (CACurrentMediaTime() - start) * 1000
      var confidence: Float = 0
      var persons = 0
      for detection in result.detections {
        guard let category = detection.categories.first else { continue }
        if category.categoryName == "cell phone", category.score >= 0.15 {
          confidence = max(confidence, category.score)
        } else if category.categoryName == "person", category.score >= 0.5 {
          persons += 1
        }
      }
      let payload: [String: Any] = [
        "session_id": id, "phone_detected": confidence >= 0.15,
        "phone_confidence": Double(confidence), "person_count": persons,
        "latency_ms": latency,
        "timestamp": ISO8601DateFormatter().string(from: Date()),
      ]
      #if DEBUG
      NSLog("[ApertureCamera] inference latency_ms=%.2f", latency)
      #endif
      DispatchQueue.main.async {
        guard self.token == id else { return }
        self.sink?(payload)
      }
    } catch {
      DispatchQueue.main.async { self.fail(id: id, code: "inference_failed") }
    }
  }

  private enum CameraFailure: Error { case unavailable }
}

import Flutter
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareFilePickerBridge: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  static let shared = ShareFilePickerBridge()
  private static let maximumBytes = 5 * 1024 * 1024
  private var channel: FlutterMethodChannel?
  private var picker: UIDocumentPickerViewController?
  private var picking: (id: Int, reply: FlutterResult)?
  private var selected: (id: Int, url: URL)?
  private var reading: (id: Int, reply: FlutterResult)?
  private var workerId: Int?
  private var readTask: Task<Void, Never>?

  private enum ReadOutcome: Sendable {
    case file(String, String?, Data)
    case error(String)
  }

  func register(with messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "aperture/share_file_picker", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, reply in
      Task { @MainActor in
        guard let self, let args = call.arguments as? [String: Any],
              let id = args["id"] as? Int, id > 0 else {
          reply(FlutterError(code: "unreadable", message: nil, details: nil))
          return
        }
        switch call.method {
        case "pick": self.open(id, reply: reply)
        case "read": self.read(id, limit: args["maxBytes"] as? Int, reply: reply)
        case "discard":
          self.discard(id)
          reply(nil)
        default: reply(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private func open(_ id: Int, reply: @escaping FlutterResult) {
    guard picker == nil, selected == nil, workerId == nil else {
      reply(FlutterError(code: "busy", message: nil, details: nil))
      return
    }
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    guard var presenter = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      reply(FlutterError(code: "unavailable", message: nil, details: nil))
      return
    }
    while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
      presenter = presented
    }
    guard presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else {
      reply(FlutterError(code: "busy", message: nil, details: nil))
      return
    }

    // Open in place. Aperture does not import a plaintext copy into its sandbox.
    let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.png], asCopy: false)
    controller.allowsMultipleSelection = false
    controller.delegate = self
    controller.presentationController?.delegate = self
    picker = controller
    picking = (id, reply)
    presenter.present(controller, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard controller === picker, let pending = picking else { return }
    picker = nil
    picking = nil
    guard urls.count == 1, let url = urls.first, url.isFileURL else {
      pending.reply(FlutterError(code: "unreadable", message: nil, details: nil))
      return
    }
    selected = (pending.id, url)
    pending.reply(true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishCancellation(controller)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finishCancellation(presentationController.presentedViewController)
  }

  private func finishCancellation(_ controller: UIViewController) {
    guard controller === picker else { return }
    let pending = picking
    picker = nil
    picking = nil
    pending?.reply(false)
  }

  private func discard(_ id: Int) {
    if let pending = picking, pending.id == id, let controller = picker {
      picking = nil
      pending.reply(false)
      controller.dismiss(animated: true) { [weak self] in
        self?.finishCancellation(controller)
      }
    }
    if selected?.id == id { selected = nil }
    if let pending = reading, pending.id == id {
      reading = nil
      readTask?.cancel()
      pending.reply(FlutterError(code: "unreadable", message: nil, details: nil))
    }
  }

  private func read(_ id: Int, limit: Int?, reply: @escaping FlutterResult) {
    guard let document = selected, document.id == id, workerId == nil,
          let limit, (1...Self.maximumBytes).contains(limit) else {
      reply(FlutterError(code: "unreadable", message: nil, details: nil))
      return
    }
    selected = nil
    reading = (id, reply)
    workerId = id
    readTask = Task.detached(priority: .userInitiated) { [weak self] in
      let outcome = Self.load(document.url, limit: limit)
      await self?.finishRead(id, outcome: outcome)
    }
  }

  private func finishRead(_ id: Int, outcome: ReadOutcome) {
    if workerId == id {
      workerId = nil
      readTask = nil
    }
    let reply: FlutterResult?
    if let pending = reading, pending.id == id {
      reading = nil
      reply = pending.reply
    } else {
      reply = nil
    }
    switch outcome {
    case .file(let name, let mime, var bytes):
      defer { bytes.resetBytes(in: 0..<bytes.count) }
      if let reply {
        var envelope: [String: Any] = ["name": name, "bytes": FlutterStandardTypedData(bytes: bytes)]
        if let mime { envelope["mimeType"] = mime }
        reply(envelope)
      }
    case .error(let code):
      reply?(FlutterError(code: code, message: nil, details: nil))
    }
  }

  nonisolated private static func load(_ url: URL, limit: Int) -> ReadOutcome {
    guard !Task.isCancelled else { return .error("unreadable") }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    var outcome = ReadOutcome.error("unreadable")
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(
      readingItemAt: url, options: .withoutChanges, error: &coordinationError
    ) { coordinated in
      guard !Task.isCancelled else { return }
      let metadata = try? coordinated.resourceValues(forKeys: [.fileSizeKey, .nameKey, .contentTypeKey])
      let name = metadata?.name ?? url.lastPathComponent
      let mime = metadata?.contentType?.preferredMIMEType
      let permitted = ["image/png", "image/x-png", "application/octet-stream"]
      guard name.lowercased().hasSuffix(".png"), mime.map({ permitted.contains($0) }) ?? true else {
        outcome = .error("unsupported")
        return
      }
      if let size = metadata?.fileSize, size > limit {
        outcome = .error("too_large")
        return
      }
      guard let stream = InputStream(url: coordinated) else { return }
      stream.open()
      defer { stream.close() }
      var staging = [UInt8](repeating: 0, count: limit + 1)
      defer {
        staging.withUnsafeMutableBufferPointer { buffer in
          buffer.baseAddress?.update(repeating: 0, count: buffer.count)
        }
      }
      let count = staging.withUnsafeMutableBufferPointer { buffer -> Int? in
        guard let start = buffer.baseAddress else { return nil }
        var used = 0
        while used < buffer.count {
          if Task.isCancelled { return nil }
          let n = stream.read(start.advanced(by: used), maxLength: min(65536, buffer.count - used))
          if n < 0 { return nil }
          if n == 0 { break }
          used += n
        }
        return used
      }
      guard let count, !Task.isCancelled else { return }
      if count == 0 {
        outcome = .error("empty")
      } else if count > limit {
        outcome = .error("too_large")
      } else {
        outcome = .file(name, mime, Data(staging.prefix(count)))
      }
    }
    return coordinationError == nil ? outcome : .error("unreadable")
  }
}

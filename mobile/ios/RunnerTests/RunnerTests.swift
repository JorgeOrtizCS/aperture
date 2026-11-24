import Flutter
import MediaPipeTasksVision
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testBundledModelRunsNativeInference() throws {
    let path = try XCTUnwrap(Bundle.main.path(forResource: "efficientdet_lite0", ofType: "tflite"))
    let options = ObjectDetectorOptions()
    options.baseOptions.modelAssetPath = path
    options.categoryAllowlist = ["cell phone", "person"]
    options.scoreThreshold = 0.15
    options.maxResults = -1
    let detector = try ObjectDetector(options: options)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 320)).image { context in
      UIColor.gray.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
    }
    let start = CACurrentMediaTime()
    let result = try detector.detect(image: MPImage(uiImage: image))
    let latency = (CACurrentMediaTime() - start) * 1000
    XCTAssertTrue(latency.isFinite && latency >= 0)
    for detection in result.detections {
      for category in detection.categories {
        XCTAssertTrue(["cell phone", "person"].contains(category.categoryName ?? ""))
        XCTAssertTrue(category.score.isFinite && category.score >= 0.15 && category.score <= 1)
      }
    }
    print("[ApertureCameraTest] native inference latency_ms=\(latency)")
  }

}

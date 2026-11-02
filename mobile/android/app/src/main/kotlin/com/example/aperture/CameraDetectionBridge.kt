package com.example.aperture

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.OrientationEventListener
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.CameraInfo
import androidx.camera.core.CameraState
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.Observer
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

/** The analysis use case has no preview and never persists or logs frames. */
class CameraDetectionBridge(private val activity: FlutterActivity, messenger: BinaryMessenger) :
    EventChannel.StreamHandler {
    companion object { const val PERMISSION_REQUEST = 7407 }
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var sink: EventChannel.EventSink? = null
    private var token: Int? = null // Main thread only.
    private var pending: MethodChannel.Result? = null
    private var permissionPending = false
    private var provider: ProcessCameraProvider? = null
    private var analysis: ImageAnalysis? = null
    private var cameraInfo: CameraInfo? = null
    private var cameraObserver: Observer<CameraState>? = null
    // Accessed only by worker, including initialization and destruction.
    private var detector: ObjectDetector? = null
    private var lastFrameNs = 0L
    private var destroyed = false
    @Volatile private var cleanupFailed = false
    private val orientationListener = object : OrientationEventListener(activity) {
        override fun onOrientationChanged(orientation: Int) {
            if (orientation == ORIENTATION_UNKNOWN) return
            analysis?.targetRotation = when (orientation) {
                in 45..134 -> Surface.ROTATION_270
                in 135..224 -> Surface.ROTATION_180
                in 225..314 -> Surface.ROTATION_90
                else -> Surface.ROTATION_0
            }
        }
    }

    init {
        EventChannel(messenger, "aperture/camera_detection/events").setStreamHandler(this)
        MethodChannel(messenger, "aperture/camera_detection").setMethodCallHandler { call, result ->
            val id = call.argument<Int>("session_id")
            if (id == null) result.error("invalid_arguments", "Missing camera run ID.", null)
            else when (call.method) {
                "start" -> start(id, result)
                "stop" -> stop(id) { clean ->
                    if (clean) result.success(null)
                    else result.error("cleanup_failed", "Camera cleanup could not be confirmed.", null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
    override fun onCancel(arguments: Any?) {
        sink = null
        token?.let { stop(it) {} }
    }

    private fun start(id: Int, result: MethodChannel.Result) {
        if (destroyed || cleanupFailed || token != null || sink == null ||
            !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            result.error("camera_unavailable", "Camera requires an active viewer.", null)
            return
        }
        token = id
        pending = result
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            configure(id)
        } else if (!permissionPending) {
            permissionPending = true
            activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST)
        }
    }

    fun permissionResult() {
        permissionPending = false
        val id = token ?: return
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            configure(id)
        } else fail(id, "permission_denied")
    }

    private fun configure(id: Int) {
        val future = ProcessCameraProvider.getInstance(activity)
        future.addListener({
            if (token != id || destroyed) return@addListener
            try {
                val cameraProvider = future.get()
                if (!cameraProvider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)) {
                    fail(id, "camera_unavailable")
                    return@addListener
                }
                provider = cameraProvider
                worker.execute {
                    try {
                        check(!cleanupFailed) { "Previous camera cleanup failed" }
                        val options = ObjectDetector.ObjectDetectorOptions.builder()
                            .setBaseOptions(BaseOptions.builder().setModelAssetPath("efficientdet_lite0.tflite").build())
                            .setRunningMode(RunningMode.IMAGE)
                            .setScoreThreshold(0.15f)
                            .setCategoryAllowlist(listOf("cell phone", "person"))
                            .setMaxResults(-1).build()
                        detector = ObjectDetector.createFromOptions(activity, options)
                        lastFrameNs = 0
                        main.post {
                            if (token != id || destroyed) return@post
                            try {
                                val useCase = ImageAnalysis.Builder()
                                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                                    .build()
                                analysis = useCase
                                orientationListener.enable()
                                useCase.setAnalyzer(worker) { image -> infer(id, image) }
                                val camera = cameraProvider.bindToLifecycle(activity, CameraSelector.DEFAULT_FRONT_CAMERA, useCase)
                                val observer = Observer<CameraState> { state ->
                                    if (state.error != null) fail(id, "camera_interrupted")
                                }
                                cameraInfo = camera.cameraInfo
                                cameraObserver = observer
                                camera.cameraInfo.cameraState.observe(activity, observer)
                                pending?.success(true)
                                pending = null
                            } catch (_: Exception) { fail(id, "camera_unavailable") }
                        }
                    } catch (_: Exception) { main.post { fail(id, "detector_start_failed") } }
                }
            } catch (_: Exception) { fail(id, "camera_unavailable") }
        }, ContextCompat.getMainExecutor(activity))
    }

    private fun infer(id: Int, image: ImageProxy) {
        try {
            val activeDetector = detector ?: return
            val now = System.nanoTime()
            if (now - lastFrameNs < 200_000_000) return
            lastFrameNs = now
            val plane = image.planes[0]
            // RGBA planes may include row padding; never interpret padding as pixels.
            val packed = java.nio.ByteBuffer.allocate(image.width * image.height * 4)
            val source = plane.buffer.duplicate()
            for (row in 0 until image.height) {
                source.position(row * plane.rowStride)
                val bytes = ByteArray(image.width * 4)
                source.get(bytes)
                packed.put(bytes)
            }
            packed.rewind()
            val raw = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
            raw.copyPixelsFromBuffer(packed)
            val matrix = Matrix().apply { postRotate(image.imageInfo.rotationDegrees.toFloat()) }
            val bitmap = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, matrix, false)
            val mpImage = BitmapImageBuilder(bitmap).build()
            try {
                val start = System.nanoTime()
                val detections = activeDetector.detect(mpImage)
                val latency = (System.nanoTime() - start) / 1_000_000.0
                var confidence = 0f
                var persons = 0
                for (detection in detections.detections()) {
                    val category = detection.categories().firstOrNull() ?: continue
                    if (category.categoryName() == "cell phone" && category.score() >= 0.15f) {
                        confidence = maxOf(confidence, category.score())
                    } else if (category.categoryName() == "person" && category.score() >= 0.5f) persons++
                }
                val payload = mapOf(
                    "session_id" to id, "phone_detected" to (confidence >= 0.15f),
                    "phone_confidence" to confidence.toDouble(), "person_count" to persons,
                    "latency_ms" to latency, "timestamp" to SimpleDateFormat(
                        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US,
                    ).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date()),
                )
                if (activity.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                    Log.d("ApertureCamera", "inference latency_ms=$latency")
                }
                main.post { if (token == id) sink?.success(payload) }
            } finally {
                mpImage.close()
                if (bitmap !== raw) bitmap.recycle()
                raw.recycle()
            }
        } catch (_: Exception) { main.post { fail(id, "inference_failed") } }
        finally { image.close() }
    }

    private fun fail(id: Int, code: String) {
        if (token != id) return
        pending?.error(code, "Camera protection unavailable. Content stays hidden.", null)
        pending = null
        sink?.error(code, "Camera protection unavailable. Content stays hidden.", null)
        stop(id) {}
    }

    private fun stop(id: Int, complete: (Boolean) -> Unit) {
        if (token != id) { complete(!cleanupFailed); return }
        token = null
        pending?.error("cancelled", "Camera startup cancelled.", null)
        pending = null
        var clean = true
        try {
            orientationListener.disable()
            cameraObserver?.let { cameraInfo?.cameraState?.removeObserver(it) }
            analysis?.clearAnalyzer()
            analysis?.let { provider?.unbind(it) }
        } catch (_: Exception) { clean = false; cleanupFailed = true }
        cameraInfo = null
        cameraObserver = null
        analysis = null
        worker.execute {
            try { detector?.close() } catch (_: Exception) { clean = false; cleanupFailed = true } finally {
                detector = null
                main.post { complete(clean) }
            }
        }
    }

    fun inactive() { token?.let { fail(it, "app_inactive") } }
    fun destroy() {
        inactive()
        destroyed = true
        worker.shutdown() // Queued destruction runs after any in-flight inference.
    }
}

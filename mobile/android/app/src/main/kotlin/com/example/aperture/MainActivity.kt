package com.example.aperture

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager

class MainActivity : FlutterFragmentActivity() {
    private var cameraDetection: CameraDetectionBridge? = null
    private var deviceLocation: DeviceLocationBridge? = null
    private var shareFilePicker: ShareFilePickerBridge? = null
    private val methodChannelName = "aperture/screen_capture_protection"
    private val eventChannelName = "aperture/screen_capture_protection/events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cameraDetection = CameraDetectionBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        deviceLocation = DeviceLocationBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        shareFilePicker = ShareFilePickerBridge(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableProtection" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(false)
                    }
                    "disableProtection" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        events?.success(false)
                    }

                    override fun onCancel(arguments: Any?) = Unit
                },
            )
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CameraDetectionBridge.PERMISSION_REQUEST) cameraDetection?.permissionResult()
        if (requestCode == DeviceLocationBridge.PERMISSION_REQUEST) deviceLocation?.permissionReturned()
    }

    override fun onPause() {
        shareFilePicker?.cancelRead()
        cameraDetection?.inactive()
        deviceLocation?.inactive()
        super.onPause()
    }

    override fun onDestroy() {
        shareFilePicker?.destroy()
        shareFilePicker = null
        deviceLocation?.destroy()
        deviceLocation = null
        cameraDetection?.destroy()
        cameraDetection = null
        super.onDestroy()
    }

    override fun onStop() {
        deviceLocation?.backgrounded()
        super.onStop()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ShareFilePickerBridge.REQUEST) shareFilePicker?.onResult(resultCode, data)
    }
}

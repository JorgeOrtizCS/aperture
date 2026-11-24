package com.example.aperture

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Foreground, bounded measurement only. No coordinates are persisted or logged. */
class DeviceLocationBridge(private val activity: ComponentActivity, messenger: BinaryMessenger) {
    companion object { const val PERMISSION_REQUEST = 7411 }
    private val channel = MethodChannel(messenger, "aperture/device_location")
    private val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val handler = Handler(Looper.getMainLooper())
    private var asked = false
    private var dialogOpen = false
    private var permissionOwner: Long? = null
    private var permissionResult: MethodChannel.Result? = null
    private var pending: Request? = null

    private class Request(val owner: Long, val id: Long, val result: MethodChannel.Result) {
        val startedWall = System.currentTimeMillis()
        val startedElapsed = SystemClock.elapsedRealtimeNanos()
        var listener: LocationListener? = null
        var timeout: Runnable? = null
    }

    init {
        channel.setMethodCallHandler { call, result ->
            val owner = call.argument<Number>("owner_id")?.toLong()
            when (call.method) {
                "permission" -> result.success(permission())
                "requestPermission" -> {
                    if (owner == null || owner <= 0 || !foreground()) result.success("unavailable")
                    else if (dialogOpen) result.success("unavailable")
                    else if (permission() == "granted") result.success("granted")
                    else {
                        permissionOwner = owner; permissionResult = result; dialogOpen = true
                        try {
                            activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION,
                                Manifest.permission.ACCESS_FINE_LOCATION), PERMISSION_REQUEST)
                        } catch (_: RuntimeException) { finishPermission("unavailable"); dialogOpen = false }
                    }
                }
                "locate" -> {
                    val id = call.argument<Number>("request_id")?.toLong()
                    val timeout = call.argument<Number>("timeout_ms")?.toLong()
                    if (owner == null || owner <= 0 || id == null || id <= 0 ||
                        timeout == null || timeout !in 1L..4000L) {
                        result.success(mapOf("status" to "unavailable"))
                    } else locate(owner, id, timeout, result)
                }
                "cancelAcquisition" -> { cancelAcquisition(owner); result.success(null) }
                "close" -> { cancelAcquisition(owner); cancelPermission(owner); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun foreground() = activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
    private fun permission(): String {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) return "granted"
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) return "approximate"
        if (!asked) return "notDetermined"
        return if (activity.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION)) "denied" else "permanentlyDenied"
    }

    fun permissionReturned() {
        asked = true; dialogOpen = false
        finishPermission(permission()) // May be a cancelled wait; never starts acquisition.
    }

    private fun finishPermission(status: String) {
        val result = permissionResult
        permissionResult = null; permissionOwner = null
        result?.success(status)
    }

    private fun cancelPermission(owner: Long?) {
        if (owner != null && owner == permissionOwner) finishPermission("cancelled")
        // Keep dialogOpen until the OS callback, preventing overlapping prompts.
    }

    private fun locate(owner: Long, id: Long, timeout: Long, result: MethodChannel.Result) {
        if (!foreground()) { result.success(mapOf("status" to "unavailable")); return }
        val permission = permission()
        if (permission != "granted") {
            result.success(mapOf("status" to if (permission == "notDetermined") "permissionRequired" else permission)); return
        }
        // Replace the old native operation, never its owner's permission state.
        pending?.let { finish(it, mapOf("status" to "cancelled")) }
        val request = Request(owner, id, result)
        pending = request
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (pending !== request || !foreground()) return
                val currentPermission = permission()
                if (currentPermission != "granted") {
                    finish(request, mapOf("status" to currentPermission)); return
                }
                val now = System.currentTimeMillis()
                if (!location.latitude.isFinite() || !location.longitude.isFinite() ||
                    location.latitude !in -90.0..90.0 || location.longitude !in -180.0..180.0 ||
                    !location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy < 0 ||
                    location.elapsedRealtimeNanos < request.startedElapsed ||
                    location.time < request.startedWall || location.time > now) return
                finish(request, mapOf("status" to "granted", "latitude" to location.latitude,
                    "longitude" to location.longitude, "accuracy_m" to location.accuracy.toDouble(),
                    "timestamp_ms" to location.time))
            }
            override fun onProviderDisabled(provider: String) {
                if (!manager.isProviderEnabled(LocationManager.GPS_PROVIDER) &&
                    !manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    finish(request, mapOf("status" to "unavailable"))
                }
            }
            override fun onProviderEnabled(provider: String) = Unit
            @Deprecated("Required on older supported Android versions")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
        }
        request.listener = listener
        request.timeout = Runnable { finish(request, mapOf("status" to "unavailable")) }
        handler.postDelayed(request.timeout!!, timeout)
        try {
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
                .filter { manager.isProviderEnabled(it) }
            if (providers.isEmpty()) { finish(request, mapOf("status" to "unavailable")); return }
            for (provider in providers) {
                manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
            }
        } catch (_: SecurityException) { finish(request, mapOf("status" to "denied")) }
        catch (_: RuntimeException) { finish(request, mapOf("status" to "unavailable")) }
    }

    private fun finish(request: Request, value: Map<String, Any>) {
        if (pending !== request) return
        pending = null
        request.timeout?.let { handler.removeCallbacks(it) }
        request.listener?.let { try { manager.removeUpdates(it) } catch (_: RuntimeException) {} }
        request.listener = null; request.timeout = null
        request.result.success(value)
    }

    private fun cancelAcquisition(owner: Long?) {
        pending?.let { if (owner != null && it.owner == owner) finish(it, mapOf("status" to "cancelled")) }
    }
    fun inactive() { pending?.let { finish(it, mapOf("status" to "cancelled")) } }
    fun backgrounded() { inactive(); permissionOwner?.let { cancelPermission(it) } }
    fun destroy() { backgrounded(); channel.setMethodCallHandler(null) }
}

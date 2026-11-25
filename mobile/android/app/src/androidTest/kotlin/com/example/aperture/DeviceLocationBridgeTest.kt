package com.example.aperture

import android.Manifest
import android.app.Instrumentation
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager.GPS_PROVIDER
import android.location.LocationManager.NETWORK_PROVIDER
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import java.util.concurrent.FutureTask
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Deterministic measurements through the real MethodChannel bridge, without touching OS providers. */
@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = 28)
class DeviceLocationBridgeTest {
    @Test
    fun inaccurateNetworkFixKeepsWaitingForFreshAccurateGps() = withBridge {
        onMain {
            val reply = messenger.locate()
            val listener = updates.activeListener()
            listener.onLocationChanged(fix(NETWORK_PROVIDER, 800f))
            listener.onLocationChanged(fix(GPS_PROVIDER, 5f, ageMs = 1_000L))
            assertNull(reply.poll())
            assertEquals(setOf(GPS_PROVIDER, NETWORK_PROVIDER), updates.active.keys)

            listener.onLocationChanged(fix(GPS_PROVIDER, 8f))
            assertEquals("granted", reply.poll()?.get("status"))
            assertTrue(updates.active.isEmpty())
            assertEquals(1, updates.removals)
            listener.onLocationChanged(fix(GPS_PROVIDER, 5f))
            assertNull(reply.poll())
        }
    }

    @Test
    fun multipleInaccurateFixesExpireSingleDeadlineWithoutCoordinates() = withBridge {
        lateinit var reply: LinkedBlockingQueue<Map<*, *>>
        lateinit var listener: LocationListener
        onMain {
            reply = messenger.locate(timeoutMs = 250)
            listener = updates.activeListener()
            listener.onLocationChanged(fix(NETWORK_PROVIDER, 800f))
            listener.onLocationChanged(fix(GPS_PROVIDER, 101f))
            assertNull(reply.poll())
            assertEquals(0, updates.removals)
        }
        assertEquals(mapOf("status" to "insufficientAccuracy"), reply.poll(2, TimeUnit.SECONDS))
        onMain {
            assertTrue(updates.active.isEmpty())
            assertEquals(1, updates.removals)
            listener.onLocationChanged(fix(GPS_PROVIDER, 1f))
            assertNull(reply.poll())
        }
    }

    @Test
    fun deadlineWithoutAnyFixReturnsUnavailableAndUnsubscribes() = withBridge {
        lateinit var reply: LinkedBlockingQueue<Map<*, *>>
        onMain { reply = messenger.locate(timeoutMs = 150) }
        assertEquals(mapOf("status" to "unavailable"), reply.poll(2, TimeUnit.SECONDS))
        onMain {
            assertTrue(updates.active.isEmpty())
            assertEquals(1, updates.removals)
        }
    }

    @Test
    fun callbackAfterDeadlineCannotWinAheadOfTimeoutOrAffectNextRequest() = withBridge {
        lateinit var oldReply: LinkedBlockingQueue<Map<*, *>>
        lateinit var oldListener: LocationListener
        onMain {
            oldReply = messenger.locate(timeoutMs = 100)
            oldListener = updates.activeListener()
            SystemClock.sleep(55)
            oldListener.onLocationChanged(fix(NETWORK_PROVIDER, 800f))
            // Hold the main loop so the callback deliberately runs before the scheduled timeout.
            SystemClock.sleep(70)
            oldListener.onLocationChanged(fix(GPS_PROVIDER, 1f))
            assertNull(oldReply.poll())
        }
        assertEquals(mapOf("status" to "insufficientAccuracy"), oldReply.poll(2, TimeUnit.SECONDS))
        onMain {
            val newReply = messenger.locate(request = 2)
            oldListener.onLocationChanged(fix(GPS_PROVIDER, 1f))
            assertNull(newReply.poll())
            assertNull(oldReply.poll())
            updates.activeListener().onLocationChanged(fix(GPS_PROVIDER, 100f))
            assertEquals("granted", newReply.poll()?.get("status"))
            assertTrue(updates.active.isEmpty())
            assertEquals(2, updates.removals)
        }
    }

    @Test
    fun inactiveRequestRemovesBothSubscriptionsAndIgnoresLateAccurateFix() = withBridge {
        onMain {
            val reply = messenger.locate()
            val listener = updates.activeListener()
            listener.onLocationChanged(fix(NETWORK_PROVIDER, 800f))
            bridge.inactive()
            assertEquals(mapOf("status" to "cancelled"), reply.poll())
            assertTrue(updates.active.isEmpty())
            assertEquals(1, updates.removals)
            listener.onLocationChanged(fix(GPS_PROVIDER, 1f))
            assertNull(reply.poll())
        }
    }

    @Test
    fun invalidMaximumAccuracyFailsBeforeCollecting() = withBridge {
        onMain {
            for (limit in listOf(0.0, -1.0, Double.POSITIVE_INFINITY, Double.NaN, "100")) {
                assertEquals(mapOf("status" to "unavailable"), messenger.locate(limit = limit).poll())
                assertTrue(updates.active.isEmpty())
            }
        }
    }

    private fun withBridge(test: Fixture.() -> Unit) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val packageName = instrumentation.targetContext.packageName
        for (permission in listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)) {
            instrumentation.uiAutomation.grantRuntimePermission(packageName, permission)
        }
        val intent = Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val activity = instrumentation.startActivitySync(intent) as MainActivity
        instrumentation.waitForIdleSync()
        val fixture = Fixture(instrumentation)
        fixture.onMain { fixture.bridge = DeviceLocationBridge(activity, fixture.messenger, fixture.updates) }
        try {
            fixture.test()
        } finally {
            fixture.onMain {
                fixture.bridge.destroy()
                activity.finish()
            }
            instrumentation.waitForIdleSync()
        }
    }

    private class Fixture(private val instrumentation: Instrumentation) {
        val messenger = TestMessenger()
        val updates = TestUpdates()
        lateinit var bridge: DeviceLocationBridge
        fun onMain(action: () -> Unit) {
            val task = FutureTask(Runnable(action), Unit)
            instrumentation.runOnMainSync(task)
            task.get()
        }
    }

    private class TestUpdates : LocationUpdates {
        val active = mutableMapOf<String, LocationListener>()
        var removals = 0
        override fun isEnabled(provider: String) = true
        override fun subscribe(provider: String, listener: LocationListener) { active[provider] = listener }
        override fun unsubscribe(listener: LocationListener) {
            removals++
            active.entries.removeAll { it.value === listener }
        }
        fun activeListener(): LocationListener = active.values.toSet().single()
    }

    private class TestMessenger : BinaryMessenger {
        private val codec = StandardMethodCodec.INSTANCE
        private var handler: BinaryMessenger.BinaryMessageHandler? = null

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            this.handler = handler
        }
        override fun send(channel: String, message: ByteBuffer?) = error("Unexpected outbound message")
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) =
            error("Unexpected outbound message")

        fun locate(request: Long = 1, timeoutMs: Long = 4_000, limit: Any = 100.0): LinkedBlockingQueue<Map<*, *>> {
            val replies = LinkedBlockingQueue<Map<*, *>>()
            val args = mapOf("owner_id" to 1L, "request_id" to request, "timeout_ms" to timeoutMs, "max_accuracy_m" to limit)
            val message = codec.encodeMethodCall(MethodCall("locate", args)).apply { flip() }
            checkNotNull(handler).onMessage(message) { response ->
                replies.add(codec.decodeEnvelope(checkNotNull(response).apply { flip() }) as Map<*, *>)
            }
            return replies
        }
    }

    private fun fix(provider: String, accuracyMeters: Float, ageMs: Long = 0): Location =
        Location(provider).apply {
            latitude = 26.37
            longitude = -80.1
            accuracy = accuracyMeters
            time = System.currentTimeMillis() - ageMs
            elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos() - ageMs * 1_000_000L
        }
}

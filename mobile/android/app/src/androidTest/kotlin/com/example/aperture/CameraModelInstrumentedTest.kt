package com.example.aperture

import android.graphics.Bitmap
import android.graphics.Color
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetector
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real bundled model and native runtime; synthetic input, no camera or saved frames. */
@RunWith(AndroidJUnit4::class)
class CameraModelInstrumentedTest {
    @Test
    fun bundledModelRunsNativeInference() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val options = ObjectDetector.ObjectDetectorOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath("efficientdet_lite0.tflite").build())
            .setScoreThreshold(0.15f)
            .setCategoryAllowlist(listOf("cell phone", "person"))
            .setMaxResults(-1).build()
        val bitmap = Bitmap.createBitmap(320, 320, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.GRAY)
        val image = BitmapImageBuilder(bitmap).build()
        val detector = ObjectDetector.createFromOptions(context, options)
        try {
            repeat(5) {
                val start = System.nanoTime()
                val result = detector.detect(image)
                val latency = (System.nanoTime() - start) / 1_000_000.0
                assertTrue(latency.isFinite() && latency >= 0)
                for (detection in result.detections()) {
                    for (category in detection.categories()) {
                        assertTrue(category.categoryName() in listOf("cell phone", "person"))
                        assertTrue(category.score().isFinite() && category.score() in 0.15f..1.0f)
                    }
                }
                Log.i("ApertureCameraTest", "synthetic_image latency_ms=$latency")
            }
        } finally {
            detector.close()
            image.close()
            bitmap.recycle()
        }
    }
}

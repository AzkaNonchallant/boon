package com.example.boon

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import android.util.Base64

/** User-approved Android screen capture, streamed as low-rate JPEG previews. */
class BoonScreenCaptureService : Service() {
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var lastFrameAt = 0L
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, 0) ?: 0
        val data = if (Build.VERSION.SDK_INT >= 33) {
            intent?.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(EXTRA_RESULT_DATA)
        }
        if (resultCode == 0 || data == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        createNotificationChannel()
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("Boon screen sharing")
            .setContentText("Your screen is being shared with a paired Boon device")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        try {
            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projection = manager.getMediaProjection(resultCode, data)
            projection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() = stopSelf()
            }, Handler(mainLooper))
            startCapture()
        } catch (error: Exception) {
            Log.e(TAG, "Unable to start screen capture", error)
            BoonNotificationListener.eventSink?.invoke(
                mapOf("kind" to "screen_error", "message" to (error.message ?: error.javaClass.simpleName)),
            )
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun startCapture() {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        val scale = minOf(1f, 720f / metrics.widthPixels)
        val width = (metrics.widthPixels * scale).toInt().coerceAtLeast(1)
        val height = (metrics.heightPixels * scale).toInt().coerceAtLeast(1)
        val density = (metrics.densityDpi * scale).toInt().coerceAtLeast(1)

        thread = HandlerThread("boon-screen-capture").apply { start() }
        val handler = Handler(thread!!.looper)
        reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        reader!!.setOnImageAvailableListener({ source ->
            val now = android.os.SystemClock.elapsedRealtime()
            if (now - lastFrameAt < FRAME_INTERVAL_MS) {
                source.acquireLatestImage()?.close()
                return@setOnImageAvailableListener
            }
            val image = source.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val plane = image.planes[0]
                val paddedWidth = plane.rowStride / plane.pixelStride
                val bitmap = Bitmap.createBitmap(paddedWidth, image.height, Bitmap.Config.ARGB_8888)
                bitmap.copyPixelsFromBuffer(plane.buffer)
                val cropped = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                val bytes = ByteArrayOutputStream().use { output ->
                    cropped.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, output)
                    output.toByteArray()
                }
                if (lastFrameAt == 0L) Log.d(TAG, "First frame encoded (${bytes.size} bytes)")
                emit(
                    mapOf(
                        "kind" to "screen_frame",
                        "data" to Base64.encodeToString(bytes, Base64.NO_WRAP),
                        "width" to width,
                        "height" to height,
                    ),
                )
                bitmap.recycle()
                if (cropped !== bitmap) cropped.recycle()
                lastFrameAt = now
            } catch (error: Exception) {
                Log.e(TAG, "Unable to encode screen frame", error)
                emit(
                    mapOf("kind" to "screen_error", "message" to (error.message ?: error.javaClass.simpleName)),
                )
                // A frame can be invalidated by rotation while the reader updates.
            } finally {
                image.close()
            }
        }, handler)
        display = projection?.createVirtualDisplay(
            "BoonScreen",
            width,
            height,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader!!.surface,
            null,
            handler,
        )
        check(display != null) { "Android did not create the screen display" }
        emit(mapOf("kind" to "screen_started"))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Screen sharing", NotificationManager.IMPORTANCE_LOW),
            )
        }
    }

    override fun onDestroy() {
        display?.release()
        reader?.close()
        projection?.stop()
        thread?.quitSafely()
        emit(mapOf("kind" to "screen_stopped"))
        super.onDestroy()
    }

    private fun emit(event: Map<String, Any>) {
        // EventChannel sends must run on Flutter's platform (main) thread.
        mainHandler.post {
            val sink = BoonNotificationListener.eventSink
            if (event["kind"] == "screen_frame") {
                Log.d(TAG, "Emitting screen frame to Flutter (event sink=${sink != null})")
            }
            sink?.invoke(event)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "BoonScreenCapture"
        const val ACTION_STOP = "com.example.boon.STOP_SCREEN_SHARE"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        private const val CHANNEL_ID = "boon_screen_share"
        private const val NOTIFICATION_ID = 7152
        private const val FRAME_INTERVAL_MS = 300L // ~3 FPS: preview/control, not video playback.
        private const val JPEG_QUALITY = 42
    }
}

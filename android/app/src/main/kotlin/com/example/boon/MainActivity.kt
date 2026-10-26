package com.example.boon

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ContentValues
import android.net.Uri
import android.net.wifi.WifiManager
import android.media.projection.MediaProjectionManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.service.notification.NotificationListenerService
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Native bridges for the Android companion app.
///
/// - "boon/status": real device status (battery level + charging) via
///   ACTION_BATTERY_CHANGED, plus the device model for identity naming.
/// - "boon/discovery": WifiManager.MulticastLock so the Dart UDP
///   discovery service can receive multicast/broadcast packets on Wi-Fi.
/// - "boon/companion": notification access state, opening the system
///   notification-access screen, and applying media button actions.
/// - "boon/companion/events": stream of mirrored notifications + media
///   snapshots from BoonNotificationListener.
class MainActivity : FlutterActivity() {

    private val screenCaptureRequestCode = 7151

    private var multicastLock: WifiManager.MulticastLock? = null

    private var batteryReceiver: BroadcastReceiver? = null
    private var batteryLevel: Int = -1
    private var batteryCharging: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "boon/status")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        registerBatteryReceiver()
                        result.success(true)
                    }
                    "stop" -> {
                        unregisterBatteryReceiver()
                        result.success(true)
                    }
                    "battery" -> result.success(batterySnapshot())
                    "deviceName" -> result.success(deviceModelName())
                    else -> result.notImplemented()
                }
            }

        // Foreground-service control from Dart (keep-link-alive toggle).
        // The service itself lives in BoonForegroundService.kt.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "boon/service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startForegroundService(
                            Intent(this, BoonForegroundService::class.java)
                                .setAction(BoonForegroundService.ACTION_START),
                        )
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(Intent(this, BoonForegroundService::class.java))
                        result.success(true)
                    }
                    "requestNotificationPermission" -> result.success(
                        requestNotificationPermissionIfNeeded(),
                    )
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "boon/discovery")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquireMulticastLock()
                        result.success(true)
                    }
                    "release" -> {
                        releaseMulticastLock()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Phone Buddy: notification mirroring + media control. The capture
        // side lives in BoonNotificationListener (same process); this channel
        // only reports state, opens the permission screen and forwards media
        // button presses from the desktop.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "boon/companion")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isListening" -> result.success(isNotificationListenerEnabled())
                    "openListenerSettings" -> {
                        openNotificationListenerSettings()
                        result.success(true)
                    }
                    "requestRebind" -> {
                        requestNotificationListenerRebind()
                        result.success(true)
                    }
                    "applyMediaAction" -> {
                        val action = call.argument<String>("action") ?: ""
                        result.success(BoonNotificationListener.applyMediaAction(action))
                    }
                    "requestScreenShare" -> {
                        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        startActivityForResult(manager.createScreenCaptureIntent(), screenCaptureRequestCode)
                        result.success(true)
                    }
                    "stopScreenShare" -> {
                        stopService(Intent(this, BoonScreenCaptureService::class.java))
                        result.success(true)
                    }
                    "isAccessibilityEnabled" -> result.success(BoonControlAccessibilityService.isEnabled())
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    "screenTap" -> {
                        val x = call.argument<Double>("x")?.toFloat() ?: -1f
                        val y = call.argument<Double>("y")?.toFloat() ?: -1f
                        result.success(BoonControlAccessibilityService.tap(x, y))
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "boon/companion/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    BoonNotificationListener.eventSink = { payload -> events?.success(payload) }
                    BoonNotificationListener.emitCurrentMedia()
                }

                override fun onCancel(arguments: Any?) {
                    BoonNotificationListener.eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "boon/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToGallery" -> {
                        val path = call.argument<String>("path") ?: ""
                        val name = call.argument<String>("name") ?: "file"
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        result.success(saveToGallery(path, name, mimeType))
                    }
                    "openFile" -> {
                        val path = call.argument<String>("path") ?: ""
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        result.success(openFile(path, mimeType))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        unregisterBatteryReceiver()
        releaseMulticastLock()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Deprecated("Deprecated in Android, retained for MediaProjection consent result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != screenCaptureRequestCode) return
        if (resultCode != RESULT_OK || data == null) {
            BoonNotificationListener.eventSink?.invoke(
                mapOf("kind" to "screen_error", "message" to "Screen sharing was cancelled on the phone."),
            )
            return
        }
        val intent = Intent(this, BoonScreenCaptureService::class.java)
            .putExtra(BoonScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
            .putExtra(BoonScreenCaptureService.EXTRA_RESULT_DATA, data)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
        } catch (error: Exception) {
            BoonNotificationListener.eventSink?.invoke(
                mapOf("kind" to "screen_error", "message" to (error.message ?: "Android blocked screen sharing.")),
            )
        }
    }

    // ---- Battery ------------------------------------------------------

    private fun registerBatteryReceiver() {
        if (batteryReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                updateBattery(intent)
            }
        }
        registerReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        batteryReceiver = receiver
    }

    private fun unregisterBatteryReceiver() {
        batteryReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already unregistered — nothing to clean up.
            }
        }
        batteryReceiver = null
    }

    private fun updateBattery(intent: Intent) {
        batteryLevel = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        batteryCharging = charging && plugged != 0
    }

    private fun batterySnapshot(): Map<String, Any> {
        if (batteryLevel < 0) {
            // No update seen yet — read the current sticky broadcast once.
            updateBattery(
                registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                    ?: return mapOf("level" to -1, "charging" to false),
            )
        }
        val scale = batteryLevel.coerceIn(0, 100)
        return mapOf("level" to scale, "charging" to batteryCharging)
    }

    private fun deviceModelName(): String {
        val manufacturer = Build.MANUFACTURER
        val model = Build.MODEL
        return if (model.startsWith(manufacturer, ignoreCase = true)) {
            model
        } else {
            "$manufacturer $model"
        }
    }

    // ---- Notification permission ----------------------------------------

    /// API 33+: run-time gate for the persistent FGS tray notification.
    /// The service runs regardless; without the grant the notification
    /// (and thus the FGS entry) may simply be invisible to the user.
    private fun requestNotificationPermissionIfNeeded(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED) {
            return true
        }
        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4545)
        return false
    }

    // ---- Received files -------------------------------------------------

    private fun saveToGallery(path: String, name: String, mimeType: String): Boolean {
        val source = File(path)
        if (!source.exists() || (!mimeType.startsWith("image/") && !mimeType.startsWith("video/"))) {
            return false
        }

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val video = mimeType.startsWith("video/")
                val collection = if (video) {
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                } else {
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                }
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        if (video) Environment.DIRECTORY_MOVIES + "/Boon"
                        else Environment.DIRECTORY_PICTURES + "/Boon",
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(collection, values) ?: return false
                try {
                    contentResolver.openOutputStream(uri)?.use { output ->
                        source.inputStream().use { input -> input.copyTo(output) }
                    } ?: throw IllegalStateException("Unable to open gallery output")
                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    true
                } catch (error: Exception) {
                    contentResolver.delete(uri, null, null)
                    false
                }
            } else {
                if (checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                    android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE), 4546)
                    return false
                }
                val directory = Environment.getExternalStoragePublicDirectory(
                    if (mimeType.startsWith("video/")) Environment.DIRECTORY_MOVIES
                    else Environment.DIRECTORY_PICTURES,
                ).resolve("Boon")
                directory.mkdirs()
                val target = directory.resolve(name)
                source.inputStream().use { input -> target.outputStream().use { output -> input.copyTo(output) } }
                sendBroadcast(Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.fromFile(target)))
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun openFile(path: String, mimeType: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Open with"))
            true
        } catch (_: Exception) {
            false
        }
    }

    // ---- Notification access (Phone Buddy) -----------------------------

    private fun isNotificationListenerEnabled(): Boolean {
        // BoonNotificationListener being connected is the strongest signal;
        // fall back to parsing the secure setting for the pre-connect case.
        if (BoonNotificationListener.isConnected()) return true
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return flat.split(':').any { entry ->
            ComponentName.unflattenFromString(entry)?.packageName == packageName
        }
    }

    private fun openNotificationListenerSettings() {
        try {
            startActivity(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
            // Some OEM firmwares hide the direct screen; open app settings.
            startActivity(
                Intent(Settings.ACTION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    /// Nudges the system to rebind the listener after the user grants access
    /// while Boon is already running.
    private fun requestNotificationListenerRebind() {
        try {
            NotificationListenerService.requestRebind(
                ComponentName(this, BoonNotificationListener::class.java),
            )
        } catch (_: Exception) {
            // Not granted yet — the next app resume re-checks the setting.
        }
    }

    // ---- Multicast lock ------------------------------------------------

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifi.createMulticastLock("boon-discovery")
        lock.setReferenceCounted(false)
        lock.acquire()
        multicastLock = lock
    }

    private fun releaseMulticastLock() {
        val lock = multicastLock ?: return
        if (lock.isHeld) {
            try {
                lock.release()
            } catch (_: RuntimeException) {
                // Lock already released under us.
            }
        }
        multicastLock = null
    }
}

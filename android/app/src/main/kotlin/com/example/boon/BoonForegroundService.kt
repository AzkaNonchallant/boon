package com.example.boon

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/// Foreground service that keeps the Boon process (and with it the running
/// Dart engine, sockets and timers) alive while the activity is backgrounded.
///
/// Why this exists: without a foreground service Android treats the app as
/// cacheable once the activity is stopped — timers throttle/stop and the
/// Wi-Fi multicast lock is dropped, so discovery, tDeviceStatus and
/// desktop→phone clipboard all go dead. Android requires a persistent
/// notification for this state; that is also how the user can tell the link
/// is still on.
///
/// The Dart side talks to MainActivity over the "boon/service" channel;
/// this service only reacts to the ACTION_START/ACTION_STOP intents it
/// sends. It must never be stopped when the user backgrounds the app —
/// only when they toggle the setting off.
class BoonForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        startAsForeground()
        return START_STICKY
    }

    private fun startAsForeground() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                // The manifest declares foregroundServiceType="connectedDevice";
                // the type must be repeated in startForeground on API 29+.
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // MissingForegroundServiceTypeException / ServiceStartNotAllowed /
            // SecurityException land here. The link simply degrades to
            // background behavior rather than crashing the app; the phase
            // doc records whether this ever fired on real hardware.
            Log.w(TAG, "startForeground failed: $e")
        }
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Boon link",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Persistent notice that the Boon link stays active"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)

        // Tapping opens the main app in place (Same MainActivity instance
        // thanks to singleTop).
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Boon")
            .setContentText("Boon link aktif")
            .setOngoing(true)
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    companion object {
        private const val TAG = "BoonForegroundService"
        const val CHANNEL_ID = "boon_link"
        const val NOTIFICATION_ID = 4545
        const val ACTION_START = "com.example.boon.service.START"
        const val ACTION_STOP = "com.example.boon.service.STOP"
    }
}

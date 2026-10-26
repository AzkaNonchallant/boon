package com.example.boon

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/// Native Phone Buddy half: mirrors other apps' notifications to the Dart
/// layer and exposes the active media session for playback control.
///
/// Requires the user to grant Notification Access (Special App Access).
/// The same grant also unlocks MediaSessionManager, which is why media
/// control lives here instead of a second permission.
///
/// Everything is emitted through [eventSink], which MainActivity wires to
/// the "boon/companion/events" EventChannel. The static [instance] is safe
/// because the service and the Flutter engine live in the same process.
class BoonNotificationListener : NotificationListenerService() {

    private var sessionManager: MediaSessionManager? = null
    private var activeController: MediaController? = null
    private var mediaCallback: MediaController.Callback? = null
    private var lastMediaSnapshot = ""

    /// Last few notification signatures, so apps that republish the same
    /// content on every tick don't flood the desktop feed.
    private val recentSignatures = LinkedHashSet<String>()

    private val sessionsChangedListener =
        MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
            attachController(chooseController(controllers))
        }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        startMediaWatch()
        emit(mapOf("kind" to "listener", "connected" to true))
    }

    override fun onListenerDisconnected() {
        stopMediaWatch()
        if (instance === this) instance = null
        emit(mapOf("kind" to "listener", "connected" to false))
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        stopMediaWatch()
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        // Never mirror Boon's own foreground-service notice.
        if (n.packageName == packageName) return
        // Ongoing/ticker notifications (downloads, foreground services,
        // group summaries) are noise for a desktop feed.
        if (n.isOngoing) return
        if (n.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val extras = n.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)
            ?.toString()?.trim().orEmpty()
        var body = extras.getCharSequence(Notification.EXTRA_TEXT)
            ?.toString()?.trim().orEmpty()
        if (body.isEmpty()) {
            body = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?.toString()?.trim().orEmpty()
        }
        if (title.isEmpty() && body.isEmpty()) return

        if (!remember("${n.key}|$title|$body")) return

        emit(
            mapOf(
                "kind" to "notification",
                "appId" to n.packageName,
                "appName" to appLabel(n.packageName),
                "title" to title,
                "body" to body,
                "time" to n.postTime,
            ),
        )
    }

    private fun remember(signature: String): Boolean {
        if (recentSignatures.contains(signature)) return false
        recentSignatures.add(signature)
        if (recentSignatures.size > 80) {
            val it = recentSignatures.iterator()
            if (it.hasNext()) {
                it.next()
                it.remove()
            }
        }
        return true
    }

    private fun appLabel(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) {
        pkg
    }

    // ------------------------------------------------------------------
    // Media session tracking
    // ------------------------------------------------------------------

    private fun startMediaWatch() {
        val manager = getSystemService(Context.MEDIA_SESSION_SERVICE)
            as? MediaSessionManager ?: return
        sessionManager = manager
        val component = ComponentName(this, BoonNotificationListener::class.java)
        try {
            manager.addOnActiveSessionsChangedListener(sessionsChangedListener, component)
            attachController(chooseController(manager.getActiveSessions(component)))
        } catch (e: SecurityException) {
            // Notification access not actually granted (or revoked mid-run).
            Log.w(TAG, "media sessions unavailable: $e")
        }
    }

    private fun stopMediaWatch() {
        try {
            sessionManager?.removeOnActiveSessionsChangedListener(sessionsChangedListener)
        } catch (_: Exception) {
            // Nothing registered.
        }
        sessionManager = null
        attachController(null)
    }

    private fun chooseController(controllers: List<MediaController>?): MediaController? {
        if (controllers.isNullOrEmpty()) return null
        return controllers.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING
        } ?: controllers.firstOrNull()
    }

    private fun attachController(controller: MediaController?) {
        if (controller === activeController) {
            emitMedia(controller, force = true)
            return
        }
        mediaCallback?.let { cb ->
            try {
                activeController?.unregisterCallback(cb)
            } catch (_: Exception) {
                // Session already gone.
            }
        }
        mediaCallback = null
        activeController = controller

        if (controller == null) {
            lastMediaSnapshot = ""
            emit(mapOf("kind" to "media", "available" to false, "playing" to false))
            return
        }

        val callback = object : MediaController.Callback() {
            override fun onPlaybackStateChanged(state: PlaybackState?) {
                emitMedia(controller, force = true)
            }

            override fun onMetadataChanged(metadata: MediaMetadata?) {
                emitMedia(controller, force = true)
            }

            override fun onSessionDestroyed() {
                attachController(null)
            }
        }
        try {
            controller.registerCallback(callback)
            mediaCallback = callback
        } catch (e: Exception) {
            Log.w(TAG, "media callback registration failed: $e")
        }
        emitMedia(controller, force = true)
    }

    private fun emitMedia(controller: MediaController?, force: Boolean = false) {
        if (controller == null) {
            emit(mapOf("kind" to "media", "available" to false, "playing" to false))
            return
        }
        val metadata = controller.metadata
        val playback = controller.playbackState
        val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
        val available = title != null || playback != null

        val payload: Map<String, Any?> = if (!available) {
            mapOf("kind" to "media", "available" to false, "playing" to false)
        } else {
            mapOf(
                "kind" to "media",
                "available" to true,
                "playing" to (playback?.state == PlaybackState.STATE_PLAYING),
                "title" to title,
                "artist" to (metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    ?: metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)),
                "album" to metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM),
                "positionMs" to (playback?.position ?: 0L).toInt(),
                "durationMs" to (metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L).toInt(),
            )
        }

        val snapshot = payload.toString()
        if (!force && snapshot == lastMediaSnapshot) return
        lastMediaSnapshot = snapshot
        emit(payload)
    }

    private fun emit(payload: Map<String, Any?>) {
        eventSink?.invoke(payload)
    }

    companion object {
        private const val TAG = "BoonNotifListener"

        /// Wired to the EventChannel by MainActivity. Null while no Flutter
        /// engine is listening; events are simply dropped then.
        @Volatile
        var eventSink: ((Map<String, Any?>) -> Unit)? = null

        @Volatile
        private var instance: BoonNotificationListener? = null

        fun isConnected(): Boolean = instance != null

        /// Applies a desktop media button press to the active session.
        /// Returns false when there is no session to control.
        fun applyMediaAction(action: String): Boolean {
            val controller = instance?.activeController ?: return false
            val controls = controller.transportControls ?: return false
            return try {
                when (action) {
                    "play" -> { controls.play(); true }
                    "pause" -> { controls.pause(); true }
                    "prev" -> { controls.skipToPrevious(); true }
                    "next" -> { controls.skipToNext(); true }
                    else -> false
                }
            } catch (e: Exception) {
                Log.w(TAG, "media action '$action' failed: $e")
                false
            }
        }

        /// Replays the current media snapshot to a freshly attached sink.
        fun emitCurrentMedia() {
            instance?.let { it.emitMedia(it.activeController, force = true) }
        }
    }
}

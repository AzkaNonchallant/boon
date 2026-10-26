package com.example.boon

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.view.accessibility.AccessibilityEvent

/** Explicitly user-enabled service for tap control from a trusted Boon peer. */
class BoonControlAccessibilityService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit

    override fun onServiceConnected() {
        instance = this
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    fun tap(x: Float, y: Float): Boolean {
        if (x !in 0f..1f || y !in 0f..1f) return false
        val metrics = resources.displayMetrics
        val path = Path().apply { moveTo(x * metrics.widthPixels, y * metrics.heightPixels) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 90))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    companion object {
        @Volatile private var instance: BoonControlAccessibilityService? = null

        fun tap(x: Float, y: Float): Boolean = instance?.tap(x, y) ?: false
        fun isEnabled(): Boolean = instance != null
    }
}

package com.nexaryo.buzz

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createBuzzChannel()
    }

    /**
     * Create (or update) the "buzz_notifications" channel with HIGH
     * importance so incoming buzz / chat / voice push notifications drop
     * down as heads-up banners and use the Buzz Bee lavender accent.
     */
    private fun createBuzzChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Android channel importance is IMMUTABLE after the first creation.
        // Bump the channel ID whenever you need to change importance / sound /
        // vibration — the old channel can be safely deleted.
        manager.deleteNotificationChannel("buzz_notifications")

        val channel = NotificationChannel(
            "buzz_messages_v1",
            "Messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Chats, buzzes and voice messages"
            enableLights(true)
            lightColor = 0xFF6C63FF.toInt()
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 200, 120, 200)
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }
}

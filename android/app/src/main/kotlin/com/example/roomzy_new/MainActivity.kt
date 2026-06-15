package com.example.roomzy_new

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel("chat_messages") != null) return

            val channel = NotificationChannel(
                "chat_messages",
                "Bookings & Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "RoomzyFind booking confirmations, payments, and chat messages"
                enableVibration(true)
                enableLights(true)
            }

            manager.createNotificationChannel(channel)
        }
    }
}
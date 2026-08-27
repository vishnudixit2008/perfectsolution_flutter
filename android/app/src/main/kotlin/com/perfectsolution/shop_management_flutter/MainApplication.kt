package com.perfectsolution.shop_management_flutter

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createCallAlertChannel()
        }
    }

    private fun createCallAlertChannel() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val soundUri = Uri.parse("android.resource://$packageName/raw/soothing_alert")
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_ALARM)
            .build()

        val callChannel = NotificationChannel(
            "call_alerts_v2",
            "Call Assignment Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "High-priority full screen call alerts with soothing sound"
            setSound(soundUri, audioAttributes)
            enableVibration(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        notificationManager.createNotificationChannel(callChannel)

        val fallbackChannel = NotificationChannel(
            "call_alerts_fallback",
            "Call Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Call alert notifications"
            enableVibration(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        notificationManager.createNotificationChannel(fallbackChannel)

        val kioskChannel = NotificationChannel(
            "kiosk_qr_channel",
            "Payment QR Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Pops up incoming customer payment QR codes on kiosk"
            enableVibration(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        notificationManager.createNotificationChannel(kioskChannel)
    }
}

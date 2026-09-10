package com.perfectsolution.shop_management_flutter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

class CallFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        val data = remoteMessage.data
        Log.d("CallFcmService", "Received push message: $data")

        val type = data["type"] ?: ""
        if (type == "call_assignment") {
            handleCallAssignmentPush(data)
        } else if (type == "kiosk_qr") {
            handleKioskQrPush(data)
        }
    }

    companion object {
        private var activeMediaPlayer: android.media.MediaPlayer? = null
        private var autoStopHandler: android.os.Handler? = null

        fun stopNativeAlert() {
            try {
                autoStopHandler?.removeCallbacksAndMessages(null)
                autoStopHandler = null
                activeMediaPlayer?.apply {
                    if (isPlaying) stop()
                    release()
                }
                activeMediaPlayer = null
            } catch (e: Exception) {
                Log.e("CallFcmService", "Error stopping native MediaPlayer: ${e.message}")
            }
        }
    }

    private fun handleCallAssignmentPush(data: Map<String, String>) {
        val payloadJson = JSONObject(data as Map<*, *>).toString()
        val callNo = data["call_no"] ?: data["call_id"] ?: ""
        val name = data["name"] ?: "Customer"
        val devices = data["devices"] ?: "Incoming Call"
        val notifId = callNo.toIntOrNull() ?: 999

        // 1. Wake up the screen immediately
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager != null) {
                @Suppress("DEPRECATION")
                val wakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                            PowerManager.ACQUIRE_CAUSES_WAKEUP or
                            PowerManager.ON_AFTER_RELEASE,
                    "PerfectSolution:CallAlertWakeLock"
                )
                wakeLock.acquire(30000)
            }
        } catch (e: Exception) {
            Log.e("CallFcmService", "WakeLock error: ${e.message}")
        }

        // 2. Prepare Intent to launch/bring MainActivity to the front
        val notifyIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("call_data", payloadJson)
            putExtra("notification_payload", payloadJson)
        }

        // Support Android 14/15 Background Activity Launch mode
        val activityOptions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            android.app.ActivityOptions.makeBasic().apply {
                setPendingIntentBackgroundActivityStartMode(
                    android.app.ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                )
            }.toBundle()
        } else null

        val pendingIntent = PendingIntent.getActivity(
            this,
            notifId,
            notifyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0),
            activityOptions
        )

        // 3. Post High-Priority Notification with FullScreenIntent
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "call_alerts_v4"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Call Assignment Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Full-screen popups and alerts for incoming calls"
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 300, 150, 300)
                    setBypassDnd(true)
                }
                notificationManager.createNotificationChannel(channel)
            }

            val notification = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("New Call Assigned: $name")
                .setContentText("Open app • Job #$callNo • $devices")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setFullScreenIntent(pendingIntent, true)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setOngoing(false)
                .addAction(
                    android.R.drawable.ic_menu_call,
                    "View Call",
                    pendingIntent
                )
                .build()

            notificationManager.notify(notifId, notification)
        } catch (e: Exception) {
            Log.e("CallFcmService", "Notification error: ${e.message}")
        }

        // 4. Directly launch MainActivity to bring full-screen modal up immediately
        try {
            startActivity(notifyIntent)
        } catch (e: Exception) {
            Log.e("CallFcmService", "StartActivity error: ${e.message}")
        }
    }

    private fun handleKioskQrPush(data: Map<String, String>) {
        val payloadJson = JSONObject(data as Map<*, *>).toString()
        val amount = data["amount"] ?: "0.00"
        val customerName = data["customer_name"] ?: ""
        val notifId = 1002

        // 1. Wake up the screen
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager != null) {
                @Suppress("DEPRECATION")
                val wakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                            PowerManager.ACQUIRE_CAUSES_WAKEUP or
                            PowerManager.ON_AFTER_RELEASE,
                    "PerfectSolution:KioskQrWakeLock"
                )
                wakeLock.acquire(30000)
            }
        } catch (e: Exception) {
            Log.e("CallFcmService", "Kiosk WakeLock error: ${e.message}")
        }

        // 2. Prepare Intent to launch/bring MainActivity directly to front
        val notifyIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("kiosk_qr_data", payloadJson)
            putExtra("notification_payload", payloadJson)
        }

        // Support Android 14/15 Background Activity Launch mode
        val activityOptions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            android.app.ActivityOptions.makeBasic().apply {
                setPendingIntentBackgroundActivityStartMode(
                    android.app.ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                )
            }.toBundle()
        } else null

        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val pendingIntent = PendingIntent.getActivity(this, notifId, notifyIntent, pendingFlags, activityOptions)

        // 3. Post FullScreenIntent Notification for Kiosk QR (Guarantees screen wake & immediate display from lockscreen/background)
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "kiosk_qr_v4"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Kiosk Payment QR",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "High priority full-screen payment QR display for counter tablet"
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 250, 100, 250)
                    setBypassDnd(true)
                }
                notificationManager.createNotificationChannel(channel)
            }

            val notification = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Payment QR Display: ₹$amount")
                .setContentText(if (customerName.isNotEmpty()) "Customer: $customerName" else "Scan to Pay")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setFullScreenIntent(pendingIntent, true)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .build()

            notificationManager.notify(notifId, notification)
        } catch (e: Exception) {
            Log.e("CallFcmService", "Kiosk Notification error: ${e.message}")
        }

        // 4. If overlay permission is granted or system allows, also launch activity directly
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || android.provider.Settings.canDrawOverlays(this)) {
            try {
                startActivity(notifyIntent)
            } catch (e: Exception) {
                Log.e("CallFcmService", "Kiosk StartActivity error: ${e.message}")
            }
        }
    }
}

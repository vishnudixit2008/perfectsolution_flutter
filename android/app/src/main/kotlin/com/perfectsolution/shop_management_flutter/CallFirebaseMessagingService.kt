package com.perfectsolution.shop_management_flutter

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

        // 2. Play native soothing alert chime in background for guaranteed 10 seconds
        try {
            stopNativeAlert()
            val soundResId = resources.getIdentifier("soothing_alert", "raw", packageName)
            if (soundResId != 0) {
                activeMediaPlayer = android.media.MediaPlayer.create(this, soundResId)?.apply {
                    isLooping = true
                    setAudioAttributes(
                        android.media.AudioAttributes.Builder()
                            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                            .setFlags(android.media.AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                            .build()
                    )
                    setVolume(1.0f, 1.0f)
                    start()
                }

                autoStopHandler = android.os.Handler(android.os.Looper.getMainLooper()).apply {
                    postDelayed({
                        stopNativeAlert()
                    }, 10000) // Auto-stop after 10 seconds
                }
            }
        } catch (e: Exception) {
            Log.e("CallFcmService", "Native MediaPlayer error: ${e.message}")
        }

        // 3. Prepare Intent to launch/bring MainActivity to the front
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

        // 4. Post High-Priority Notification with FullScreenIntent
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val notification = NotificationCompat.Builder(this, "call_alerts_v3")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("📞 Call Assignment: Job #$callNo")
                .setContentText("$name • $devices")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setFullScreenIntent(pendingIntent, true)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .addAction(
                    android.R.drawable.ic_menu_call,
                    "Open Call",
                    pendingIntent
                )
                .build()

            notificationManager.notify(notifId, notification)
        } catch (e: Exception) {
            Log.e("CallFcmService", "Notification error: ${e.message}")
        }

        // 5. Directly launch MainActivity to bring full-screen modal up if permissions allow
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
            val notification = NotificationCompat.Builder(this, "kiosk_qr_channel")
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

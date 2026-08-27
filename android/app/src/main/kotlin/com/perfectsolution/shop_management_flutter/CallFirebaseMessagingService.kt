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

        val pendingIntent = PendingIntent.getActivity(
            this,
            notifId,
            notifyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        // 3. Post High-Priority Notification with FullScreenIntent
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val soundUri = Uri.parse("android.resource://$packageName/raw/soothing_alert")

            val notification = NotificationCompat.Builder(this, "call_alerts_v2")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("📞 Call Assignment: Job #$callNo")
                .setContentText("$name • $devices")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setSound(soundUri)
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

        // 4. Directly launch MainActivity to force the full-screen modal onto the screen
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
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("kiosk_qr_data", payloadJson)
            putExtra("notification_payload", payloadJson)
        }

        // 3. Directly launch MainActivity to show the QR display immediately (no notification in shade)
        try {
            startActivity(notifyIntent)
        } catch (e: Exception) {
            Log.e("CallFcmService", "Kiosk StartActivity error: ${e.message}")
        }
    }
}

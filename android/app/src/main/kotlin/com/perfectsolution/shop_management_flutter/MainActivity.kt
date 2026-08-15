package com.perfectsolution.shop_management_flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.perfectsolution.kiosk/overlay"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(Settings.canDrawOverlays(this))
                    } else {
                        result.success(true)
                    }
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "checkBatteryOptimization" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        val isIgnored = powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true
                        result.success(isIgnored)
                    } else {
                        result.success(true)
                    }
                }
                "requestIgnoreBatteryOptimization" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")
                            ).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        } catch (e: Exception) {
                            // Fallback to general battery settings page if direct prompt fails
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        }
                    }
                    result.success(null)
                }
                "openAppDetailsSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    result.success(null)
                }
                "startForegroundService" -> {
                    try {
                        val serviceIntent = Intent(this, KioskForegroundService::class.java).apply {
                            action = KioskForegroundService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        val serviceIntent = Intent(this, KioskForegroundService::class.java).apply {
                            action = KioskForegroundService.ACTION_STOP
                        }
                        startService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "bringAppToFront" -> {
                    try {
                        // 1. Wake up the screen if it is turned off / black
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        if (powerManager != null) {
                            @Suppress("DEPRECATION")
                            val wakeLock = powerManager.newWakeLock(
                                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                                        PowerManager.ON_AFTER_RELEASE,
                                "PerfectSolution:KioskQrWakeLock"
                            )
                            wakeLock.acquire(15000) // Keep screen awake for 15s
                        }

                        // 2. Allow showing over lockscreen & turn screen on
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                            setShowWhenLocked(true)
                            setTurnScreenOn(true)
                        } else {
                            @Suppress("DEPRECATION")
                            window.addFlags(
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                            )
                        }

                        // 3. Post High-Priority FullScreenIntent Notification (guaranteed bypass for Android 10+ Background Start restrictions)
                        val alertChannelId = "kiosk_qr_alert_channel"
                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
                        if (notificationManager != null) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val alertChannel = android.app.NotificationChannel(
                                    alertChannelId,
                                    "Payment QR Alerts",
                                    android.app.NotificationManager.IMPORTANCE_HIGH
                                ).apply {
                                    description = "Pops up incoming customer payment QR codes"
                                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                                    enableVibration(true)
                                }
                                notificationManager.createNotificationChannel(alertChannel)
                            }

                            val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                            }
                            val pendingIntent = android.app.PendingIntent.getActivity(
                                this,
                                1001,
                                fullScreenIntent,
                                android.app.PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) android.app.PendingIntent.FLAG_IMMUTABLE else 0)
                            )

                            val notification = androidx.core.app.NotificationCompat.Builder(this, alertChannelId)
                                .setSmallIcon(android.R.drawable.ic_dialog_info)
                                .setContentTitle("Payment QR Ready")
                                .setContentText("Customer payment QR code is displayed")
                                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_MAX)
                                .setCategory(androidx.core.app.NotificationCompat.CATEGORY_CALL)
                                .setVisibility(androidx.core.app.NotificationCompat.VISIBILITY_PUBLIC)
                                .setFullScreenIntent(pendingIntent, true)
                                .setAutoCancel(true)
                                .build()

                            notificationManager.notify(1001, notification)
                        }

                        // 4. Direct Activity start
                        val intent = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}


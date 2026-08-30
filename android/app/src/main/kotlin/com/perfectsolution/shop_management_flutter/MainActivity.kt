package com.perfectsolution.shop_management_flutter

import android.app.NotificationManager
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
                "checkNotificationPermission" -> {
                    val areEnabled = androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled()
                    result.success(areEnabled)
                }
                "openNotificationSettings" -> {
                    try {
                        val intent = Intent().apply {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            } else {
                                action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                                data = Uri.parse("package:$packageName")
                            }
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                    } catch (e: Exception) {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                    }
                    result.success(null)
                }
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

                        // 3. Direct Activity start (no notification posted)
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
                "checkFullScreenIntentPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        try {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                            val method = nm?.javaClass?.getMethod("canUseFullScreenIntent")
                            val canUse = method?.invoke(nm) as? Boolean ?: true
                            result.success(canUse)
                        } catch (e: Exception) {
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "requestFullScreenIntentPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                data = Uri.parse("package:$packageName")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        } catch (e: Exception) {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        }
                    }
                    result.success(null)
                }
                "stopNativeAlert" -> {
                    CallFirebaseMessagingService.stopNativeAlert()
                    result.success(true)
                }
                "getInitialCallPayload" -> {
                    val payload = pendingCallPayload
                    pendingCallPayload = null
                    result.success(payload)
                }
                "getInitialKioskPayload" -> {
                    val payload = pendingKioskPayload
                    pendingKioskPayload = null
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }

        // Check if there is an initial payload to dispatch
        val initialKiosk = intent?.getStringExtra("kiosk_qr_data")
        val initialCall = intent?.getStringExtra("call_data") ?: intent?.getStringExtra("notification_payload")

        if (!initialKiosk.isNullOrEmpty()) {
            pendingKioskPayload = initialKiosk
            flutterEngine.dartExecutor.binaryMessenger.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("onKioskQrPayload", initialKiosk)
            }
        } else if (!initialCall.isNullOrEmpty()) {
            pendingCallPayload = initialCall
            flutterEngine.dartExecutor.binaryMessenger.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("onCallAlertPayload", initialCall)
            }
        }
    }

    private var pendingCallPayload: String? = null
    private var pendingKioskPayload: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        applyWakeScreenFlags()
        extractPayloads(intent)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        applyWakeScreenFlags()
    }

    override fun onResume() {
        super.onResume()
        applyWakeScreenFlags()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyWakeScreenFlags()
        extractPayloads(intent)
    }

    private fun extractPayloads(intent: Intent?) {
        val kioskPayload = intent?.getStringExtra("kiosk_qr_data")
        val callPayload = intent?.getStringExtra("call_data")
            ?: intent?.getStringExtra("notification_payload")
            ?: intent?.getStringExtra("payload")

        if (!kioskPayload.isNullOrEmpty()) {
            pendingKioskPayload = kioskPayload
            flutterEngine?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onKioskQrPayload", kioskPayload)
            }
        } else if (!callPayload.isNullOrEmpty()) {
            pendingCallPayload = callPayload
            flutterEngine?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onCallAlertPayload", callPayload)
            }
        }
    }

    private fun applyWakeScreenFlags() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager != null) {
                @Suppress("DEPRECATION")
                val wakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                            PowerManager.ACQUIRE_CAUSES_WAKEUP or
                            PowerManager.ON_AFTER_RELEASE,
                    "PerfectSolution:MainActivityWakeLock"
                )
                wakeLock.acquire(15000)
            }
        } catch (e: Exception) {}

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
            keyguardManager?.requestDismissKeyguard(this, null)
        }
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
        )
    }
}


package com.perfectsolution.shop_management_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log

class UpdateReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_INSTALL_STATUS = "com.perfectsolution.shop_management_flutter.INSTALL_STATUS"
        private const val TAG = "UpdateReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)

        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                Log.i(TAG, "User action required for installation confirmation (Android < 12 or device policy fallback).")
                val confirmationIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirmationIntent != null) {
                    confirmationIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirmationIntent)
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                Log.i(TAG, "APK Update installed successfully! Relaunching app.")
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    context.startActivity(launchIntent)
                }
            }
            PackageInstaller.STATUS_FAILURE,
            PackageInstaller.STATUS_FAILURE_ABORTED,
            PackageInstaller.STATUS_FAILURE_BLOCKED,
            PackageInstaller.STATUS_FAILURE_CONFLICT,
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE,
            PackageInstaller.STATUS_FAILURE_INVALID,
            PackageInstaller.STATUS_FAILURE_STORAGE -> {
                val errText = message ?: "Package installer returned error code $status"
                Log.e(TAG, "APK installation failed: status=$status, message=$errText")
                MainActivity.channelInstance?.invokeMethod("onInstallError", errText)
            }
            else -> {
                Log.d(TAG, "Unknown installation status received: $status, message=$message")
            }
        }
    }
}

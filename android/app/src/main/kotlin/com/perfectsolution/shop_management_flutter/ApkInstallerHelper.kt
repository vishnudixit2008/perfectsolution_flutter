package com.perfectsolution.shop_management_flutter

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.io.OutputStream

object ApkInstallerHelper {
    private const val TAG = "ApkInstallerHelper"

    fun canRequestPackageInstalls(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    fun openInstallPermissionSettings(context: Context) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:${context.packageName}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
            } else {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open unknown app sources settings: ${e.message}")
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        }
    }

    fun installApk(context: Context, apkPath: String): Boolean {
        val apkFile = File(apkPath)
        if (!apkFile.exists() || apkFile.length() == 0L) {
            Log.e(TAG, "APK file does not exist or is empty: $apkPath")
            return false
        }

        // 1. Verify that new APK is valid and not a downgrade
        try {
            val pkgInfo = context.packageManager.getPackageArchiveInfo(apkPath, 0)
            if (pkgInfo != null) {
                val newVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    pkgInfo.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    pkgInfo.versionCode.toLong()
                }

                val currentPkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    context.packageManager.getPackageInfo(
                        context.packageName,
                        android.content.pm.PackageManager.PackageInfoFlags.of(0)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    context.packageManager.getPackageInfo(context.packageName, 0)
                }

                val currentVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    currentPkgInfo.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    currentPkgInfo.versionCode.toLong()
                }

                if (newVersionCode < currentVersionCode) {
                    val msg = "Cannot install: Downloaded APK (build $newVersionCode) is older than currently installed (build $currentVersionCode)."
                    Log.e(TAG, msg)
                    MainActivity.channelInstance?.invokeMethod("onInstallError", msg)
                    return false
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not verify archive package info: ${e.message}")
        }

        val packageInstaller = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(context.packageName)
        params.setSize(apkFile.length())

        // For Android 12+ (API 31+): Enable silent unattended update without user prompt
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }

        var sessionId = -1
        try {
            sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            val inStream: InputStream = FileInputStream(apkFile)
            val outStream: OutputStream = session.openWrite("package", 0, apkFile.length())

            val buffer = ByteArray(65536)
            var bytesRead: Int
            while (inStream.read(buffer).also { bytesRead = it } != -1) {
                outStream.write(buffer, 0, bytesRead)
            }
            session.fsync(outStream)
            inStream.close()
            outStream.close()

            // Prepare receiver intent for installation status callback
            val intent = Intent(context, UpdateReceiver::class.java).apply {
                action = UpdateReceiver.ACTION_INSTALL_STATUS
            }

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                sessionId,
                intent,
                flags
            )

            session.commit(pendingIntent.intentSender)
            session.close()
            Log.i(TAG, "PackageInstaller session #$sessionId committed successfully for: $apkPath")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error installing APK via PackageInstaller: ${e.message}", e)
            if (sessionId != -1) {
                try {
                    packageInstaller.abandonSession(sessionId)
                } catch (_: Exception) {}
            }
            return false
        }
    }
}

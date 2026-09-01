import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionStatusModel {
  final bool notificationsGranted;
  final bool overlayGranted;
  final bool batteryOptimizationIgnored;
  final bool installPackagesGranted;
  final bool cameraGranted;
  final bool storageGranted;

  PermissionStatusModel({
    required this.notificationsGranted,
    required this.overlayGranted,
    required this.batteryOptimizationIgnored,
    required this.installPackagesGranted,
    required this.cameraGranted,
    required this.storageGranted,
  });

  bool get isAllEssentialGranted {
    if (kIsWeb || !Platform.isAndroid) return true;
    return notificationsGranted &&
        overlayGranted &&
        batteryOptimizationIgnored &&
        installPackagesGranted;
  }
}

class AppPermissionsService {
  static final AppPermissionsService instance = AppPermissionsService._internal();
  AppPermissionsService._internal();

  static const MethodChannel _nativeChannel = MethodChannel('com.perfectsolution.kiosk/overlay');

  /// Check all permission statuses
  Future<PermissionStatusModel> checkPermissions() async {
    if (kIsWeb || !Platform.isAndroid) {
      return PermissionStatusModel(
        notificationsGranted: true,
        overlayGranted: true,
        batteryOptimizationIgnored: true,
        installPackagesGranted: true,
        cameraGranted: true,
        storageGranted: true,
      );
    }

    bool notif = false;
    bool overlay = false;
    bool battery = false;
    bool installPackages = false;
    bool camera = false;
    bool storage = false;

    try {
      final results = await Future.wait([
        // 1. Notification Check
        (() async {
          try {
            final res = await _nativeChannel.invokeMethod<bool>('checkNotificationPermission');
            return res ?? false;
          } catch (_) {
            return await Permission.notification.isGranted;
          }
        })(),
        // 2. Overlay Check
        (() async {
          try {
            final res = await _nativeChannel.invokeMethod<bool>('checkOverlayPermission');
            return res ?? false;
          } catch (_) {
            return await Permission.systemAlertWindow.isGranted;
          }
        })(),
        // 3. Battery Optimization Check
        (() async {
          try {
            final res = await _nativeChannel.invokeMethod<bool>('checkBatteryOptimization');
            return res ?? false;
          } catch (_) {
            return await Permission.ignoreBatteryOptimizations.isGranted;
          }
        })(),
        // 4. Install Unknown Apps / Package Installer Check
        (() async {
          try {
            final res = await _nativeChannel.invokeMethod<bool>('checkInstallPermission');
            return res ?? false;
          } catch (_) {
            return await Permission.requestInstallPackages.isGranted;
          }
        })(),
        // 5. Camera Check
        Permission.camera.isGranted,
        // 6. Storage / Photos Check
        (() async {
          return (await Permission.photos.isGranted) || (await Permission.storage.isGranted);
        })(),
      ]);

      notif = results[0];
      overlay = results[1];
      battery = results[2];
      installPackages = results[3];
      camera = results[4];
      storage = results[5];
    } catch (e) {
      debugPrint('AppPermissionsService: Error checking permissions: $e');
    }

    return PermissionStatusModel(
      notificationsGranted: notif,
      overlayGranted: overlay,
      batteryOptimizationIgnored: battery,
      installPackagesGranted: installPackages,
      cameraGranted: camera,
      storageGranted: storage,
    );
  }

  /// Request Notification Permission
  Future<bool> requestNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final status = await Permission.notification.request();
      if (status.isGranted) return true;

      // If denied or restricted, open native notification settings directly
      await _nativeChannel.invokeMethod('openNotificationSettings');
      return false;
    } catch (_) {
      try {
        await _nativeChannel.invokeMethod('openNotificationSettings');
      } catch (_) {
        await openAppSettings();
      }
      return false;
    }
  }

  /// Request Overlay (Display over other apps) Permission
  Future<void> requestOverlayPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod('requestOverlayPermission');
    } catch (_) {
      await Permission.systemAlertWindow.request();
    }
  }

  /// Request Ignore Battery Optimization Permission
  Future<void> requestBatteryOptimization() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod('requestIgnoreBatteryOptimization');
    } catch (_) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  /// Request Camera Permission
  Future<bool> requestCameraPermission() async {
    if (kIsWeb) return true;
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Request Storage / Photos Permission
  Future<bool> requestStoragePermission() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      final pStatus = await Permission.photos.request();
      if (pStatus.isGranted) return true;
      final sStatus = await Permission.storage.request();
      return sStatus.isGranted;
    }
    return true;
  }

  /// Request Full Screen Intent Permission (Android 14+)
  Future<void> requestFullScreenIntentPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod('requestFullScreenIntentPermission');
    } catch (_) {}
  }

  /// Request Install Unknown Apps (Auto-Update) Permission
  Future<void> requestInstallPackagesPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod('requestInstallPermission');
    } catch (_) {
      try {
        await Permission.requestInstallPackages.request();
      } catch (_) {
        await openAppSettings();
      }
    }
  }

  /// Open App System Settings
  Future<void> openAppSystemSettings() async {
    try {
      await _nativeChannel.invokeMethod('openAppDetailsSettings');
    } catch (_) {
      await openAppSettings();
    }
  }
}

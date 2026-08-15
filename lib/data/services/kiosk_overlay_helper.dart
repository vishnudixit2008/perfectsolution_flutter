import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class KioskOverlayHelper {
  static const MethodChannel _channel =
      MethodChannel('com.perfectsolution.kiosk/overlay');

  /// Checks if "Display over other apps" (SYSTEM_ALERT_WINDOW) is granted on Android
  static Future<bool> isOverlayPermissionGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? granted = await _channel.invokeMethod<bool>('checkOverlayPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('KioskOverlayHelper check error: $e');
      return true; // Fallback to avoid blocking non-supported platforms
    }
  }

  /// Opens the system Settings page for "Display over other apps" for this app
  static Future<void> requestOverlayPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('KioskOverlayHelper request error: $e');
    }
  }

  /// Checks if battery optimization is disabled / unrestricted for 24/7 background operation
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? ignored = await _channel.invokeMethod<bool>('checkBatteryOptimization');
      return ignored ?? true;
    } catch (e) {
      debugPrint('KioskOverlayHelper battery check error: $e');
      return true;
    }
  }

  /// Opens the system prompt / settings to disable battery optimization (set Unrestricted)
  static Future<void> requestIgnoreBatteryOptimization() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimization');
    } catch (e) {
      debugPrint('KioskOverlayHelper battery request error: $e');
    }
  }

  /// Opens the App Info settings page (for Xiaomi / Vivo / Oppo / Samsung autostart & popup settings)
  static Future<void> openAppDetailsSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openAppDetailsSettings');
    } catch (e) {
      debugPrint('KioskOverlayHelper openAppDetailsSettings error: $e');
    }
  }

  /// Starts the persistent foreground service so Android keeps the WebSocket alive 24/7
  static Future<void> startKioskForegroundService() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (e) {
      debugPrint('KioskOverlayHelper startForegroundService error: $e');
    }
  }

  /// Stops the foreground service when Kiosk mode is disabled
  static Future<void> stopKioskForegroundService() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (e) {
      debugPrint('KioskOverlayHelper stopForegroundService error: $e');
    }
  }

  /// Brings the app / activity to the front over other apps if running in background
  static Future<void> bringAppToFront() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('bringAppToFront');
    } catch (e) {
      debugPrint('KioskOverlayHelper bringAppToFront error: $e');
    }
  }
}

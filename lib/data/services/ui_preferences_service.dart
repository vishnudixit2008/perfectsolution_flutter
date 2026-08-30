import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'fcm_service.dart';

class UiPreferencesService {
  static const String _boxName = 'ui_preferences';
  static const String _columnWidthsKey = 'column_widths';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      try {
        await Hive.openBox(_boxName);
      } catch (_) {
        try {
          await Hive.openBox('${_boxName}_fallback');
        } catch (_) {
          await Hive.openBox('${_boxName}_${DateTime.now().millisecondsSinceEpoch}');
        }
      }
    }
  }

  static Box _getBox() {
    return Hive.box(_boxName);
  }

  static double? getColumnWidth(String pageKey, String columnKey) {
    final box = _getBox();
    final Map? widths = box.get(_columnWidthsKey);
    if (widths != null && widths.containsKey(pageKey)) {
      final Map pageMap = widths[pageKey];
      if (pageMap.containsKey(columnKey)) {
        return (pageMap[columnKey] as num).toDouble();
      }
    }
    return null;
  }

  static Future<void> setColumnWidth(
    String pageKey,
    String columnKey,
    double width,
  ) async {
    final box = _getBox();
    final Map widths = Map.from(
      box.get(_columnWidthsKey, defaultValue: {}) as Map,
    );
    final Map pageMap = Map.from(widths[pageKey] as Map? ?? {});
    pageMap[columnKey] = width;
    widths[pageKey] = pageMap;
    await box.put(_columnWidthsKey, widths);
  }

  static const String _isKioskModeKey = 'is_kiosk_mode';
  static const String _kioskTimeoutSecondsKey = 'kiosk_timeout_seconds';

  static bool isKioskMode() {
    return _getBox().get(_isKioskModeKey, defaultValue: false) as bool;
  }

  static Future<void> setKioskMode(bool enabled) async {
    await _getBox().put(_isKioskModeKey, enabled);
    if (enabled) {
      unawaited(FcmService.instance.syncUserToken('kiosk'));
    }
  }

  static int getKioskTimeoutSeconds() {
    return _getBox().get(_kioskTimeoutSecondsKey, defaultValue: 180) as int;
  }

  static Future<void> setKioskTimeoutSeconds(int seconds) async {
    await _getBox().put(_kioskTimeoutSecondsKey, seconds);
  }

  static dynamic getValue(String key) {
    return _getBox().get(key);
  }

  static Future<void> setValue(String key, dynamic value) async {
    await _getBox().put(key, value);
  }
}

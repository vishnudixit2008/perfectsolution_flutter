import 'package:hive_flutter/hive_flutter.dart';

class UiPreferencesService {
  static const String _boxName = 'ui_preferences';
  static const String _columnWidthsKey = 'column_widths';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
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
}

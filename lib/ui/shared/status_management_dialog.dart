import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../ui/core/app_theme.dart';
import '../../data/services/user_permission_service.dart';
import '../../data/repositories/shop_repository.dart';
import '../../data/services/supabase_sync_service.dart';

class StatusManagementService {
  static const String _boxName = 'status_management_box';
  static const String _statusListKeyPrefix = 'status_list_';
  static const String _defaultStatusPrefix = 'default_form_status_';
  static const String _statusColorsPrefix = 'status_colors_';

  // In-memory cache so compareStatuses() and getStatusColor() never hit disk on every sort/render
  static final Map<String, List<String>> _cache = {};
  static final Map<String, Map<String, int>> _colorCache = {};

  // Default statuses based on actual data per module
  static const Map<String, List<String>> _defaultStatuses = {
    'inward': [
      'Repairing',
      'Ready',
      'Ready return',
      'Pre-complete',
      'Hold',
      'Laptop',
      'Desktop',
      'Printer',
      'Complete',
    ],
    'calls': ['Pending', 'Pending payment', 'Pre-complete', 'Complete'],
    'replacements': ['Pre-Complete', 'Pending', 'Recieved', 'Complete'],
    'requests': ['Pending', 'Received', 'Complete'],
    'purchases': ['PENDING', 'Confirmed'],
    'sales': ['Pending', 'Complete'],
  };

  static String _getUserPrefix([String? email]) {
    final userEmail = (email ?? UserPermissionService.getCurrentUserEmail()).toLowerCase().trim();
    return userEmail.isNotEmpty ? '${userEmail}_' : 'default_';
  }

  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    final box = Hive.box(_boxName);
    final prefix = _getUserPrefix();
    final List? inwardStored = box.get('$prefix${_statusListKeyPrefix}inward') ?? box.get('${_statusListKeyPrefix}inward');
    if (inwardStored != null) {
      final List<String> list = List<String>.from(inwardStored);
      final int origLen = list.length;
      list.removeWhere((s) => s.trim().toLowerCase() == 'test');
      if (list.length != origLen) {
        await box.put('$prefix${_statusListKeyPrefix}inward', list);
        _cache.remove('inward');
      }
    }

    final List? salesStored = box.get('$prefix${_statusListKeyPrefix}sales') ?? box.get('${_statusListKeyPrefix}sales');
    if (salesStored != null) {
      final List<String> list = List<String>.from(salesStored);
      final int origLen = list.length;
      final bool hasComplete = list.any((s) => s.trim().toLowerCase() == 'complete' || s.trim().toLowerCase() == 'completed');
      if (hasComplete) {
        list.removeWhere((s) => s.trim().toLowerCase() == 'confirmed');
      } else {
        for (int i = 0; i < list.length; i++) {
          if (list[i].trim().toLowerCase() == 'confirmed') {
            list[i] = 'Complete';
          }
        }
      }
      if (list.length != origLen) {
        await box.put('$prefix${_statusListKeyPrefix}sales', list);
        _cache.remove('sales');
      }
    }
  }

  static Box? _getBoxSafe() {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }
    return null;
  }

  static Future<Box> _ensureBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  /// Invalidate/clear in-memory cache on user switch
  static void clearCache() {
    _cache.clear();
    _colorCache.clear();
  }

  /// Hydrate local storage and cache from an AppUser record (e.g. from cloud sync)
  static Future<void> loadFromUser(dynamic user) async {
    if (user == null) return;
    final box = await _ensureBox();
    final prefix = _getUserPrefix(user.email);

    // Wipe stale in-memory cache so any updated status lists are applied immediately
    clearCache();

    if (user.customStatusLists != null && user.customStatusLists is Map) {
      final Map customLists = user.customStatusLists as Map;
      for (final entry in customLists.entries) {
        final modKey = entry.key.toString();
        if (entry.value is List) {
          final list = (entry.value as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
          if (list.isNotEmpty) {
            await box.put('$prefix$_statusListKeyPrefix$modKey', list);
            await box.put('$_statusListKeyPrefix$modKey', list);
            _cache[modKey] = List<String>.from(list);
          }
        }
      }
    }

    if (user.defaultStatuses != null && user.defaultStatuses is Map) {
      final Map defStatuses = user.defaultStatuses as Map;
      for (final entry in defStatuses.entries) {
        final modKey = entry.key.toString();
        final defVal = entry.value?.toString().trim();
        if (defVal != null && defVal.isNotEmpty) {
          await box.put('$prefix$_defaultStatusPrefix$modKey', defVal);
          await box.put('$_defaultStatusPrefix$modKey', defVal);
        }
      }
    }
  }

  /// Hydrate directly from shop_settings table
  static Future<void> loadFromCustomStatusesMap(Map rawMap) async {
    final box = await _ensureBox();
    final prefix = _getUserPrefix();
    for (final entry in rawMap.entries) {
      final modKey = entry.key.toString();
      if (entry.value is List) {
        final list = (entry.value as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        if (list.isNotEmpty) {
          await box.put('$prefix$_statusListKeyPrefix$modKey', list);
          await box.put('$_statusListKeyPrefix$modKey', list);
          _cache[modKey] = List<String>.from(list);
        }
      }
    }
  }

  /// Hydrate default statuses directly from shop_settings table
  static Future<void> loadFromDefaultStatusesMap(Map rawMap) async {
    final box = await _ensureBox();
    final prefix = _getUserPrefix();
    for (final entry in rawMap.entries) {
      final modKey = entry.key.toString();
      final defVal = entry.value?.toString().trim();
      if (defVal != null && defVal.isNotEmpty) {
        await box.put('$prefix$_defaultStatusPrefix$modKey', defVal);
        await box.put('$_defaultStatusPrefix$modKey', defVal);
      }
    }
  }

  /// Hydrate custom status colors directly from shop_settings table
  static Future<void> loadFromStatusColorsMap(Map rawMap) async {
    final box = await _ensureBox();
    final prefix = _getUserPrefix();
    for (final entry in rawMap.entries) {
      final modKey = entry.key.toString();
      if (entry.value is Map) {
        final Map<String, int> colorMap = {};
        for (final cEntry in (entry.value as Map).entries) {
          final sName = cEntry.key.toString().toLowerCase().trim();
          final val = cEntry.value;
          if (val is int) {
            colorMap[sName] = val;
          } else if (val is num) {
            colorMap[sName] = val.toInt();
          } else if (val is String) {
            final parsed = int.tryParse(val);
            if (parsed != null) colorMap[sName] = parsed;
          }
        }
        if (colorMap.isNotEmpty) {
          await box.put('$prefix$_statusColorsPrefix$modKey', colorMap);
          await box.put('$_statusColorsPrefix$modKey', colorMap);
          _colorCache[modKey] = Map<String, int>.from(colorMap);
        }
      }
    }
  }

  /// Returns all custom status lists for shop
  static Map<String, List<String>> getAllCustomStatusLists() {
    final Map<String, List<String>> res = {};
    for (final mod in ['inward', 'calls', 'replacements', 'requests', 'purchases', 'sales']) {
      res[mod] = getStatuses(mod);
    }
    return res;
  }

  /// Returns all default statuses for shop
  static Map<String, String> getAllDefaultStatuses() {
    final Map<String, String> res = {};
    for (final mod in ['inward', 'calls', 'replacements', 'requests', 'purchases', 'sales']) {
      res[mod] = getDefaultStatus(mod);
    }
    return res;
  }

  /// Returns all custom status colors for shop
  static Map<String, Map<String, int>> getAllStatusColors() {
    final Map<String, Map<String, int>> res = {};
    for (final mod in ['inward', 'calls', 'replacements', 'requests', 'purchases', 'sales']) {
      final colors = _loadColors(mod);
      if (colors.isNotEmpty) {
        res[mod] = colors;
      }
    }
    return res;
  }

  // -------------------------------------------------------------
  // STATUS COLORS SYSTEM
  // -------------------------------------------------------------

  static Map<String, int> _loadColors(String moduleKey) {
    if (_colorCache.containsKey(moduleKey)) {
      return Map<String, int>.from(_colorCache[moduleKey]!);
    }
    final box = _getBoxSafe();
    final prefix = _getUserPrefix();
    final raw = box != null
        ? (box.get('$prefix$_statusColorsPrefix$moduleKey') ??
            box.get('$_statusColorsPrefix$moduleKey'))
        : null;

    final Map<String, int> colorMap = {};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key.toString().toLowerCase().trim();
        final val = entry.value;
        if (val is int) {
          colorMap[key] = val;
        } else if (val is num) {
          colorMap[key] = val.toInt();
        }
      }
    }
    _colorCache[moduleKey] = colorMap;
    return colorMap;
  }

  /// Gets the theme color for a status in a module.
  /// If admin set a custom color, returns that. Otherwise returns default aesthetic palette color.
  static Color getStatusColor(String moduleKey, String status) {
    final cleanStatus = status.toLowerCase().trim();
    final colors = _loadColors(moduleKey);
    if (colors.containsKey(cleanStatus)) {
      return Color(colors[cleanStatus]!);
    }
    return _getDefaultStatusColor(status);
  }

  /// Sets custom color for a status in a module (Admins only) and syncs across devices.
  static Future<void> setStatusColor(String moduleKey, String status, Color color) async {
    final cleanStatus = status.toLowerCase().trim();
    final colors = _loadColors(moduleKey);
    colors[cleanStatus] = color.toARGB32();

    final box = await _ensureBox();
    final prefix = _getUserPrefix();
    await box.put('$prefix$_statusColorsPrefix$moduleKey', colors);
    await box.put('$_statusColorsPrefix$moduleKey', colors);
    _colorCache[moduleKey] = Map<String, int>.from(colors);

    // Sync to shop_settings so all shop devices receive color updates immediately
    try {
      final allColors = getAllStatusColors();
      unawaited(SupabaseSyncService.instance.pushRecordToCloud(
        'shop_settings',
        {
          'key': 'shop_status_colors',
          'value': allColors,
          'updated_at': DateTime.now().toIso8601String(),
        },
      ));
    } catch (_) {}

    ShopRepository.notifyTableChanged('shop_settings');
    ShopRepository.notifyTableChanged('all');
  }

  /// Removes custom color for a status in a module
  static Future<void> removeStatusColor(String moduleKey, String status) async {
    final cleanStatus = status.toLowerCase().trim();
    final colors = _loadColors(moduleKey);
    if (colors.containsKey(cleanStatus)) {
      colors.remove(cleanStatus);
      final box = await _ensureBox();
      final prefix = _getUserPrefix();
      await box.put('$prefix$_statusColorsPrefix$moduleKey', colors);
      await box.put('$_statusColorsPrefix$moduleKey', colors);
      _colorCache[moduleKey] = Map<String, int>.from(colors);

      try {
        final allColors = getAllStatusColors();
        unawaited(SupabaseSyncService.instance.pushRecordToCloud(
          'shop_settings',
          {
            'key': 'shop_status_colors',
            'value': allColors,
            'updated_at': DateTime.now().toIso8601String(),
          },
        ));
      } catch (_) {}

      ShopRepository.notifyTableChanged('shop_settings');
      ShopRepository.notifyTableChanged('all');
    }
  }

  /// Built-in fallback colors for standard status patterns
  static Color _getDefaultStatusColor(String status) {
    final s = status.toLowerCase().trim();
    if (s == 'laptop' || s == 'desktop') return const Color(0xFFEF4444); // Red
    if (s == 'ready return' || s == 'ready-return') return const Color(0xFFCA8A04); // Dull Yellow
    if (s == 'ready') return const Color(0xFFEAB308); // Yellow
    if (s.contains('hold')) return const Color(0xFF06B6D4); // Cyan
    if (s.contains('complete') || s.contains('pre complete') || s.contains('pre-complete') || s == 'confirmed') {
      return const Color(0xFF10B981); // Green
    }
    if (s.contains('cancel') || s.contains('reject')) return const Color(0xFFEF4444);
    if (s.contains('pending')) return const Color(0xFFF97316); // Orange
    if (s.contains('received') || s.contains('recieved')) return const Color(0xFF38BDF8); // Sky blue
    return const Color(0xFF6366F1); // Indigo
  }

  // -------------------------------------------------------------
  // STATUS LIST & DEFAULT STATUS SYSTEM
  // -------------------------------------------------------------

  /// Get default status for new forms in a module.
  static String getDefaultStatus(String moduleKey) {
    final box = _getBoxSafe();
    final prefix = _getUserPrefix();
    final String? stored = box != null
        ? ((box.get('$prefix$_defaultStatusPrefix$moduleKey') ??
            box.get('$_defaultStatusPrefix$moduleKey')) as String?)
        : null;

    final available = getStatuses(moduleKey);
    if (stored != null &&
        available.any((s) => s.toLowerCase() == stored.toLowerCase())) {
      final match = available.firstWhere((s) => s.toLowerCase() == stored.toLowerCase());
      return match;
    }

    // Check user record default if present
    final currentUser = UserPermissionService.getCurrentUser();
    final userDef = currentUser.defaultStatuses[moduleKey];
    if (userDef != null &&
        available.any((s) => s.toLowerCase() == userDef.toLowerCase())) {
      final match = available.firstWhere((s) => s.toLowerCase() == userDef.toLowerCase());
      return match;
    }

    return available.isNotEmpty ? available.first : 'Pending';
  }

  /// Set default status for new forms in a module and sync to cloud.
  static Future<void> setDefaultStatus(String moduleKey, String status) async {
    final box = await _ensureBox();
    final prefix = _getUserPrefix();
    await box.put('$prefix$_defaultStatusPrefix$moduleKey', status);
    await box.put('$_defaultStatusPrefix$moduleKey', status);

    // 1. Sync to user profile in cloud
    try {
      final currentUser = UserPermissionService.getCurrentUser();
      final updatedDefaults = Map<String, String>.from(currentUser.defaultStatuses);
      updatedDefaults[moduleKey] = status;
      final updatedUser = currentUser.copyWith(defaultStatuses: updatedDefaults);
      unawaited(UserPermissionService.saveUser(updatedUser));
    } catch (_) {}

    // 2. Sync to shop_settings so all shop devices receive the status update immediately
    try {
      final allDefs = getAllDefaultStatuses();
      unawaited(SupabaseSyncService.instance.pushRecordToCloud(
        'shop_settings',
        {
          'key': 'shop_default_statuses',
          'value': allDefs,
          'updated_at': DateTime.now().toIso8601String(),
        },
      ));
    } catch (_) {}

    ShopRepository.notifyTableChanged('app_users');
    ShopRepository.notifyTableChanged('all');
  }

  /// Get statuses — uses cache to avoid hitting Hive on every call.
  static List<String> getStatuses(String moduleKey) {
    if (_cache.containsKey(moduleKey)) {
      return List<String>.from(_cache[moduleKey]!);
    }
    return _loadAndCache(moduleKey);
  }

  static List<String> _loadAndCache(String moduleKey) {
    final box = _getBoxSafe();
    final prefix = _getUserPrefix();
    final List? stored = box != null
        ? (box.get('$prefix$_statusListKeyPrefix$moduleKey') ??
            box.get('$_statusListKeyPrefix$moduleKey'))
        : null;
    List<String> list;
    if (stored != null && stored.isNotEmpty) {
      list = List<String>.from(stored);
    } else {
      // Check current user profile
      final currentUser = UserPermissionService.getCurrentUser();
      final userList = currentUser.customStatusLists[moduleKey];
      if (userList != null && userList.isNotEmpty) {
        list = List<String>.from(userList);
      } else {
        list = List<String>.from(
          _defaultStatuses[moduleKey] ?? ['Pending', 'Complete'],
        );
      }
    }

    if (moduleKey == 'requests') {
      final int initialLen = list.length;
      list.removeWhere((s) => s.trim().toLowerCase() == 'office');
      if (list.length != initialLen && box != null) {
        box.put('$prefix$_statusListKeyPrefix$moduleKey', list);
      }
    }

    if (moduleKey == 'inward') {
      final int initialLen = list.length;
      list.removeWhere((s) => s.trim().toLowerCase() == 'test');
      if (list.length != initialLen && box != null) {
        box.put('$prefix$_statusListKeyPrefix$moduleKey', list);
      }
    }

    if (moduleKey == 'sales') {
      final int initialLen = list.length;
      final bool hasComplete = list.any((s) => s.trim().toLowerCase() == 'complete' || s.trim().toLowerCase() == 'completed');
      if (hasComplete) {
        list.removeWhere((s) => s.trim().toLowerCase() == 'confirmed');
      } else {
        for (int i = 0; i < list.length; i++) {
          if (list[i].trim().toLowerCase() == 'confirmed') {
            list[i] = 'Complete';
          }
        }
      }
      if (list.length != initialLen && box != null) {
        box.put('$prefix$_statusListKeyPrefix$moduleKey', list);
      }
    }

    _cache[moduleKey] = list;
    return List<String>.from(list);
  }

  static int _normalizeStatusIndex(String moduleKey, List<String> orderList, String status) {
    final clean = status.toLowerCase().trim();
    int idx = orderList.indexWhere((s) => s.toLowerCase() == clean);
    if (idx != -1) return idx;
    if (clean == 'confirmed') {
      idx = orderList.indexWhere((s) => s.toLowerCase() == 'complete' || s.toLowerCase() == 'completed');
      if (idx != -1) return idx;
    }
    return 9999;
  }

  /// Fast comparison using the cache — never scans the database.
  static int compareStatuses(String moduleKey, String statusA, String statusB) {
    final orderList = getStatuses(moduleKey);
    final posA = _normalizeStatusIndex(moduleKey, orderList, statusA);
    final posB = _normalizeStatusIndex(moduleKey, orderList, statusB);
    return posA.compareTo(posB);
  }

  static Future<void> saveStatuses(
    String moduleKey,
    List<String> statuses,
  ) async {
    final box = await _ensureBox();
    final prefix = _getUserPrefix();
    await box.put('$prefix$_statusListKeyPrefix$moduleKey', statuses);
    await box.put('$_statusListKeyPrefix$moduleKey', statuses);
    _cache[moduleKey] = List<String>.from(statuses);

    // 1. Sync to user profile in cloud
    try {
      final currentUser = UserPermissionService.getCurrentUser();
      final updatedLists = Map<String, List<String>>.from(currentUser.customStatusLists);
      updatedLists[moduleKey] = List<String>.from(statuses);
      final updatedUser = currentUser.copyWith(customStatusLists: updatedLists);
      unawaited(UserPermissionService.saveUser(updatedUser));
    } catch (_) {}

    // 2. Sync to shop_settings so all shop devices receive the status update immediately
    try {
      final allLists = getAllCustomStatusLists();
      unawaited(SupabaseSyncService.instance.pushRecordToCloud(
        'shop_settings',
        {
          'key': 'shop_custom_statuses',
          'value': allLists,
          'updated_at': DateTime.now().toIso8601String(),
        },
      ));
    } catch (_) {}

    ShopRepository.notifyTableChanged('app_users');
    ShopRepository.notifyTableChanged('all');
  }

  /// Invalidate the cache for a module
  static void invalidateCache(String moduleKey) {
    _cache.remove(moduleKey);
    _colorCache.remove(moduleKey);
  }

  static Future<void> addStatus(String moduleKey, String newStatus) async {
    final current = getStatuses(moduleKey);
    final trimmed = newStatus.trim();
    if (trimmed.isNotEmpty &&
        !current.any((s) => s.toLowerCase() == trimmed.toLowerCase())) {
      current.add(trimmed);
      await saveStatuses(moduleKey, current);
    }
  }

  static Future<void> reorderStatuses(
    String moduleKey,
    int oldIndex,
    int newIndex,
  ) async {
    final current = getStatuses(moduleKey);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final String item = current.removeAt(oldIndex);
    current.insert(newIndex, item);
    await saveStatuses(moduleKey, current);
  }

  // -------------------------------------------------------------
  // ACTIVE ENTRY CHECKING & MIGRATION SYSTEM
  // -------------------------------------------------------------

  static String _getBoxNameForModule(String moduleKey) {
    switch (moduleKey) {
      case 'inward':
        return 'inward_box';
      case 'calls':
        return 'calls_box';
      case 'replacements':
        return 'replacement_box';
      case 'requests':
        return 'request_box';
      case 'purchases':
        return 'purchase_box';
      case 'sales':
        return 'sales_box';
      default:
        return '';
    }
  }

  static String _getTableNameForModule(String moduleKey) {
    switch (moduleKey) {
      case 'inward':
        return 'inward_repairs';
      case 'calls':
        return 'calls';
      case 'replacements':
        return 'replacements';
      case 'requests':
        return 'requests';
      case 'purchases':
        return 'purchases';
      case 'sales':
        return 'sales';
      default:
        return '';
    }
  }

  /// Counts how many entries currently exist in the database using this status
  static int getStatusEntryCount(String moduleKey, String status) {
    final boxName = _getBoxNameForModule(moduleKey);
    if (boxName.isEmpty) return 0;

    try {
      if (!Hive.isBoxOpen(boxName)) return 0;
      final box = Hive.box(boxName);
      final target = status.trim().toLowerCase();
      int count = 0;

      for (var value in box.values) {
        if (value is Map) {
          final s = (value['status'] ?? value['order_status'] ?? value['orderStatus'])?.toString().trim().toLowerCase();
          if (s == target) {
            count++;
          }
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Migrates all entries currently assigned to [fromStatus] to [toStatus]
  static Future<int> migrateStatusEntries(
    String moduleKey,
    String fromStatus,
    String toStatus,
  ) async {
    final boxName = _getBoxNameForModule(moduleKey);
    final tableName = _getTableNameForModule(moduleKey);
    if (boxName.isEmpty) return 0;

    try {
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);
      final target = fromStatus.trim().toLowerCase();
      final Map<dynamic, dynamic> updates = {};
      final List<Map<String, dynamic>> recordsToPush = [];
      int migratedCount = 0;
      final nowUtcIso = DateTime.now().toUtc().toIso8601String();

      for (var key in box.keys) {
        final value = box.get(key);
        if (value is Map) {
          final currentStatus = (value['status'] ?? value['order_status'] ?? value['orderStatus'])?.toString().trim().toLowerCase();
          if (currentStatus == target) {
            final updatedMap = Map<String, dynamic>.from(value);
            updatedMap['updated_at'] = nowUtcIso;
            if (updatedMap.containsKey('status') || moduleKey != 'sales') {
              updatedMap['status'] = toStatus;
            }
            if (updatedMap.containsKey('orderStatus')) {
              updatedMap['orderStatus'] = toStatus;
            }
            if (updatedMap.containsKey('order_status') || moduleKey == 'sales') {
              updatedMap['order_status'] = toStatus;
            }
            updates[key] = updatedMap;
            recordsToPush.add(updatedMap);
            migratedCount++;
          }
        }
      }

      if (updates.isNotEmpty) {
        await box.putAll(updates);
      }

      // 1. Push all updated records to Supabase & local offline sync queue
      if (tableName.isNotEmpty) {
        for (final rec in recordsToPush) {
          try {
            await SupabaseSyncService.instance.pushRecordToCloud(
              tableName,
              rec,
            );
          } catch (_) {}
        }

        // 2. Execute direct remote table batch update on Supabase when online
        try {
          final client = Supabase.instance.client;
          if (moduleKey == 'sales') {
            await client
                .from('sales')
                .update({'order_status': toStatus, 'updated_at': nowUtcIso})
                .ilike('order_status', fromStatus.trim())
                .timeout(const Duration(seconds: 4));
          } else {
            await client
                .from(tableName)
                .update({'status': toStatus, 'updated_at': nowUtcIso})
                .ilike('status', fromStatus.trim())
                .timeout(const Duration(seconds: 4));
          }
        } catch (e) {
          if (kDebugMode) print('Bulk remote status migration: $e');
        }
      }

      ShopRepository.notifyTableChanged(tableName.isNotEmpty ? tableName : boxName);
      ShopRepository.notifyTableChanged('all');
      return migratedCount;
    } catch (e) {
      if (kDebugMode) print('Error during status migration: $e');
      return 0;
    }
  }

  /// Deletes a status from a module. If [migrateToStatus] is supplied, migrates active entries first.
  static Future<void> deleteStatus(
    String moduleKey,
    String statusToDelete, {
    String? migrateToStatus,
  }) async {
    final current = getStatuses(moduleKey);
    current.removeWhere(
      (s) => s.toLowerCase() == statusToDelete.trim().toLowerCase(),
    );

    // 1. If migration target is supplied, migrate active records
    if (migrateToStatus != null && migrateToStatus.trim().isNotEmpty) {
      await migrateStatusEntries(moduleKey, statusToDelete, migrateToStatus.trim());
    } else {
      // Fallback migration to first available status if entries existed without explicit target
      final fallback = current.isNotEmpty ? current.first : 'Pending';
      await migrateStatusEntries(moduleKey, statusToDelete, fallback);
    }

    // 2. Save status list
    await saveStatuses(moduleKey, current);

    // 3. Remove custom color for deleted status
    await removeStatusColor(moduleKey, statusToDelete);

    // 4. Update default status if deleted status was default
    final currentDefault = getDefaultStatus(moduleKey);
    if (currentDefault.toLowerCase() == statusToDelete.toLowerCase()) {
      final newDefault = migrateToStatus ?? (current.isNotEmpty ? current.first : 'Pending');
      await setDefaultStatus(moduleKey, newDefault);
    }
  }
}

// ============================================================================
// STATUS MANAGEMENT DIALOG
// ============================================================================

class StatusManagementDialog extends StatefulWidget {
  final String moduleKey;
  final String moduleTitle;
  final VoidCallback onStatusesUpdated;

  const StatusManagementDialog({
    super.key,
    required this.moduleKey,
    required this.moduleTitle,
    required this.onStatusesUpdated,
  });

  static void show(
    BuildContext context, {
    required String moduleKey,
    required String moduleTitle,
    required VoidCallback onStatusesUpdated,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatusManagementDialog(
        moduleKey: moduleKey,
        moduleTitle: moduleTitle,
        onStatusesUpdated: onStatusesUpdated,
      ),
    );
  }

  @override
  State<StatusManagementDialog> createState() => _StatusManagementDialogState();
}

class _StatusManagementDialogState extends State<StatusManagementDialog> {
  late List<String> _statuses;
  final TextEditingController _addController = TextEditingController();
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  void _loadStatuses() {
    setState(() {
      _statuses = StatusManagementService.getStatuses(widget.moduleKey);
    });
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _handleAddStatus() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    await StatusManagementService.addStatus(widget.moduleKey, text);
    _addController.clear();
    setState(() {
      _isAdding = false;
      _loadStatuses();
    });
    widget.onStatusesUpdated();
  }

  // --- Admin-Only Color Picker ---
  Future<void> _openColorPicker(String status) async {
    final currentColor = StatusManagementService.getStatusColor(widget.moduleKey, status);
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (ctx) => _StatusColorPickerDialog(
        statusName: status,
        currentColor: currentColor,
      ),
    );

    if (selectedColor != null) {
      await StatusManagementService.setStatusColor(widget.moduleKey, status, selectedColor);
      setState(() {});
      widget.onStatusesUpdated();
    }
  }

  // --- Admin-Only Delete Flow with Active Entry Check & Migration ---
  Future<void> _handleDeleteStatus(String status) async {
    if (_statuses.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least one status is required.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final int entryCount = StatusManagementService.getStatusEntryCount(widget.moduleKey, status);

    if (entryCount > 0) {
      // Prompt admin with active entries and migration target dropdown
      final otherStatuses = _statuses.where((s) => s.toLowerCase() != status.toLowerCase()).toList();
      final String? targetStatus = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _StatusMigrationDialog(
          statusToDelete: status,
          activeCount: entryCount,
          moduleTitle: widget.moduleTitle,
          availableTargets: otherStatuses,
        ),
      );

      if (targetStatus != null && mounted) {
        await StatusManagementService.deleteStatus(
          widget.moduleKey,
          status,
          migrateToStatus: targetStatus,
        );
        _loadStatuses();
        widget.onStatusesUpdated();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Migrated $entryCount ${entryCount == 1 ? 'record' : 'records'} to "$targetStatus" and removed status "$status".',
              ),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
    } else {
      // Simple confirmation for empty status
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161A23),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: Row(
            children: [
              const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 22),
              const SizedBox(width: 10),
              const Text(
                'Delete Status',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete "$status"?\nThis status has 0 active entries.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        await StatusManagementService.deleteStatus(widget.moduleKey, status);
        _loadStatuses();
        widget.onStatusesUpdated();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Status "$status" removed.'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final bool isAdmin = UserPermissionService.isAdmin();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 24,
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        decoration: BoxDecoration(
          color: const Color(0xFF161A23).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 28,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.low_priority_rounded,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Manage ${widget.moduleTitle} Statuses',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isAdmin
                                    ? 'Drag to reorder, set default, change color, or delete'
                                    : 'Drag to reorder or set default status',
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppTheme.textMuted,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content body
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    if (_isAdding)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _addController,
                                autofocus: true,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Enter new status name...',
                                  hintStyle: TextStyle(
                                    color: AppTheme.textMuted.withValues(alpha: 0.6),
                                    fontSize: 13,
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: AppTheme.primary.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) => _handleAddStatus(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.success,
                                size: 24,
                              ),
                              onPressed: _handleAddStatus,
                              tooltip: 'Save',
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.cancel_rounded,
                                color: AppTheme.textMuted,
                                size: 24,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isAdding = false;
                                  _addController.clear();
                                });
                              },
                              tooltip: 'Cancel',
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isAdding = true;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: BorderSide(
                                color: AppTheme.primary.withValues(alpha: 0.4),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text(
                              'Add New Status',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Reorderable list
                    Expanded(
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          canvasColor: Colors.transparent,
                          shadowColor: Colors.black26,
                        ),
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: _statuses.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (oldIndex < newIndex) {
                                newIndex -= 1;
                              }
                              final item = _statuses.removeAt(oldIndex);
                              _statuses.insert(newIndex, item);
                            });
                            StatusManagementService.saveStatuses(
                              widget.moduleKey,
                              _statuses,
                            ).then((_) {
                              widget.onStatusesUpdated();
                            });
                          },
                          itemBuilder: (context, index) {
                            final status = _statuses[index];
                            final defaultStatus = StatusManagementService.getDefaultStatus(widget.moduleKey);
                            final isDefault = defaultStatus.toLowerCase() == status.toLowerCase();
                            final statusColor = StatusManagementService.getStatusColor(widget.moduleKey, status);

                            return Container(
                              key: ValueKey(status),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDefault
                                    ? AppTheme.primary.withValues(alpha: 0.12)
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDefault
                                      ? AppTheme.primaryLight.withValues(alpha: 0.3)
                                      : Colors.white.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Row(
                                children: [
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Icon(
                                      Icons.drag_handle_rounded,
                                      color: AppTheme.textMuted,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Color circle button (Admin clickable to change color, non-admin indicator)
                                  Tooltip(
                                    message: isAdmin ? 'Change Status Color' : 'Status Color',
                                    child: InkWell(
                                      onTap: isAdmin ? () => _openColorPicker(status) : null,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.35),
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: statusColor.withValues(alpha: 0.4),
                                              blurRadius: 4,
                                              spreadRadius: 0.5,
                                            ),
                                          ],
                                        ),
                                        child: isAdmin
                                            ? const Icon(Icons.palette_rounded, color: Colors.white, size: 12)
                                            : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Status title and Default label
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              color: isDefault
                                                  ? AppTheme.primaryLight
                                                  : AppTheme.textPrimary,
                                              fontSize: 13,
                                              fontWeight: isDefault
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isDefault) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary.withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'DEFAULT',
                                              style: TextStyle(
                                                color: AppTheme.primaryLight,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  // Default Star button
                                  IconButton(
                                    icon: Icon(
                                      isDefault ? Icons.star_rounded : Icons.star_outline_rounded,
                                      color: isDefault ? Colors.amber : AppTheme.textMuted,
                                      size: 20,
                                    ),
                                    tooltip: isDefault
                                        ? 'Default Form Status'
                                        : 'Set as Default Form Status',
                                    onPressed: () async {
                                      await StatusManagementService.setDefaultStatus(
                                        widget.moduleKey,
                                        status,
                                      );
                                      setState(() {});
                                      widget.onStatusesUpdated();
                                    },
                                  ),

                                  // Delete button (Admins Only)
                                  if (isAdmin)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: AppTheme.danger,
                                        size: 19,
                                      ),
                                      tooltip: 'Delete Status',
                                      onPressed: () => _handleDeleteStatus(status),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// STATUS COLOR PICKER DIALOG (ADMIN ONLY)
// ============================================================================

class _StatusColorPickerDialog extends StatefulWidget {
  final String statusName;
  final Color currentColor;

  const _StatusColorPickerDialog({
    required this.statusName,
    required this.currentColor,
  });

  @override
  State<_StatusColorPickerDialog> createState() => _StatusColorPickerDialogState();
}

class _StatusColorPickerDialogState extends State<_StatusColorPickerDialog> {
  late Color _selectedColor;

  static const List<Map<String, dynamic>> _palette = [
    // Vibrant Greens & Limes
    {'color': Color(0xFF10B981), 'name': 'Emerald Green'},
    {'color': Color(0xFF059669), 'name': 'Deep Emerald'},
    {'color': Color(0xFF22C55E), 'name': 'Electric Green'},
    {'color': Color(0xFF16A34A), 'name': 'Vivid Leaf'},
    {'color': Color(0xFF84CC16), 'name': 'Lime Pop'},
    {'color': Color(0xFFA3E635), 'name': 'Neon Lime'},

    // Vibrant Cyans & Teals
    {'color': Color(0xFF06B6D4), 'name': 'Cyan Glow'},
    {'color': Color(0xFF0891B2), 'name': 'Deep Teal'},
    {'color': Color(0xFF14B8A6), 'name': 'Turquoise Aqua'},
    {'color': Color(0xFF2DD4BF), 'name': 'Bright Aqua'},
    {'color': Color(0xFF0EA5E9), 'name': 'Sky Blue'},
    {'color': Color(0xFF0284C7), 'name': 'Ocean Vivid'},

    // Vibrant Blues & Indigos
    {'color': Color(0xFF3B82F6), 'name': 'Royal Blue'},
    {'color': Color(0xFF2563EB), 'name': 'Cobalt Electric'},
    {'color': Color(0xFF1D4ED8), 'name': 'Deep Sapphire'},
    {'color': Color(0xFF6366F1), 'name': 'Indigo Burst'},
    {'color': Color(0xFF4F46E5), 'name': 'Deep Indigo'},
    {'color': Color(0xFF4338CA), 'name': 'Midnight Indigo'},

    // Vibrant Violets & Purples
    {'color': Color(0xFF8B5CF6), 'name': 'Violet Neon'},
    {'color': Color(0xFF7C3AED), 'name': 'Electric Purple'},
    {'color': Color(0xFFA855F7), 'name': 'Purple Flame'},
    {'color': Color(0xFF9333EA), 'name': 'Royal Purple'},
    {'color': Color(0xFFC026D3), 'name': 'Vivid Fuchsia'},
    {'color': Color(0xFFD946EF), 'name': 'Neon Magenta'},

    // Vibrant Pinks, Roses & Corals
    {'color': Color(0xFFE879F9), 'name': 'Bright Orchid'},
    {'color': Color(0xFFEC4899), 'name': 'Hot Pink'},
    {'color': Color(0xFFDB2777), 'name': 'Deep Pink'},
    {'color': Color(0xFFFB7185), 'name': 'Coral Neon'},
    {'color': Color(0xFFF43F5E), 'name': 'Neon Rose'},
    {'color': Color(0xFFE11D48), 'name': 'Ruby Crimson'},

    // Vibrant Reds, Oranges & Golds
    {'color': Color(0xFFEF4444), 'name': 'Crimson Red'},
    {'color': Color(0xFFDC2626), 'name': 'Flame Red'},
    {'color': Color(0xFFEA580C), 'name': 'Fire Orange'},
    {'color': Color(0xFFF97316), 'name': 'Electric Orange'},
    {'color': Color(0xFFF59E0B), 'name': 'Amber Gold'},
    {'color': Color(0xFFEAB308), 'name': 'Sunshine Yellow'},
    {'color': Color(0xFFFACC15), 'name': 'Lemon Neon'},
    {'color': Color(0xFF64748B), 'name': 'Slate Steel'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.currentColor;
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 500;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: 20),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 580),
        decoration: BoxDecoration(
          color: const Color(0xFF161A23),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pick Color for "${widget.statusName}"',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Used for section headers, cards & badges',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Live Preview Box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'LIVE PREVIEW',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              // Section Header Preview
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _selectedColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: _selectedColor.withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.statusName.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: _selectedColor,
                                      ),
                                    ),
                                    if (widget.statusName.trim().toLowerCase() != 'complete' &&
                                        widget.statusName.trim().toLowerCase() != 'completed' &&
                                        widget.statusName.trim().toLowerCase() != 'confirmed') ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '· 3 Jobs',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: _selectedColor,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Chip Badge Preview
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _selectedColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _selectedColor.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  widget.statusName,
                                  style: TextStyle(
                                    color: _selectedColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SELECT VIBRANT PALETTE COLOR',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          '${_palette.length} Colors',
                          style: TextStyle(
                            color: AppTheme.primaryLight.withValues(alpha: 0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Swatch Grid
                    Center(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.start,
                        children: _palette.map((item) {
                          final color = item['color'] as Color;
                          final name = item['name'] as String;
                          final isSelected = _selectedColor.toARGB32() == color.toARGB32();
                          return Tooltip(
                            message: name,
                            child: InkWell(
                              onTap: () => setState(() => _selectedColor = color),
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.2),
                                    width: isSelected ? 3 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withValues(alpha: isSelected ? 0.7 : 0.25),
                                      blurRadius: isSelected ? 10 : 4,
                                      spreadRadius: isSelected ? 1.5 : 0,
                                    ),
                                  ],
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_selectedColor),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    child: const Text('Apply Color'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// STATUS MIGRATION DIALOG (ADMIN ONLY WHEN STATUS HAS ACTIVE ENTRIES)
// ============================================================================

class _StatusMigrationDialog extends StatefulWidget {
  final String statusToDelete;
  final int activeCount;
  final String moduleTitle;
  final List<String> availableTargets;

  const _StatusMigrationDialog({
    required this.statusToDelete,
    required this.activeCount,
    required this.moduleTitle,
    required this.availableTargets,
  });

  @override
  State<_StatusMigrationDialog> createState() => _StatusMigrationDialogState();
}

class _StatusMigrationDialogState extends State<_StatusMigrationDialog> {
  late String _selectedTarget;

  @override
  void initState() {
    super.initState();
    _selectedTarget = widget.availableTargets.isNotEmpty
        ? widget.availableTargets.first
        : 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 550;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 24),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: const Color(0xFF161A23),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Warning Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(color: AppTheme.warning.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.warning,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status Has Active Entries',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Action required before deleting',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
                      children: [
                        const TextSpan(text: 'There are currently '),
                        TextSpan(
                          text: '${widget.activeCount} active ${widget.moduleTitle} record(s)',
                          style: const TextStyle(
                            color: AppTheme.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const TextSpan(text: ' marked with status '),
                        TextSpan(
                          text: '"${widget.statusToDelete}"',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const TextSpan(
                          text: '.\n\nTo preserve data integrity, please select which status all these records should be moved to before deleting:',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Target Status Selection Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedTarget,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1B243B),
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                        items: widget.availableTargets.map((target) {
                          return DropdownMenuItem<String>(
                            value: target,
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_forward_rounded, color: AppTheme.primaryLight, size: 16),
                                const SizedBox(width: 8),
                                Text('Move to: $target'),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedTarget = val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(_selectedTarget),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.sync_alt_rounded, size: 17),
                    label: const Text('Migrate & Delete'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

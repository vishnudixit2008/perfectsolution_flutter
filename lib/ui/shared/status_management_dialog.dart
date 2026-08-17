import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../ui/core/app_theme.dart';
import '../../data/services/user_permission_service.dart';
import '../../data/repositories/shop_repository.dart';
import '../../data/services/supabase_sync_service.dart';

class StatusManagementService {
  static const String _boxName = 'status_management_box';
  static const String _statusListKeyPrefix = 'status_list_';
  static const String _defaultStatusPrefix = 'default_form_status_';

  // In-memory cache so compareStatuses() never hits the disk on every sort
  static final Map<String, List<String>> _cache = {};

  // Default statuses based on actual Excel data per module
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
  }

  static Box _getBox() {
    return Hive.box(_boxName);
  }

  /// Hydrate local storage and cache from an AppUser record (e.g. from cloud sync)
  static Future<void> loadFromUser(dynamic user) async {
    if (user == null) return;
    final box = _getBox();
    final prefix = _getUserPrefix(user.email);

    // Wipe stale in-memory cache so any updated status lists are applied immediately
    _cache.clear();

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
    final box = _getBox();
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
    final box = _getBox();
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

  /// Invalidate/clear in-memory cache on user switch
  static void clearCache() {
    _cache.clear();
  }

  /// Get default status for new forms in a module.
  static String getDefaultStatus(String moduleKey) {
    final box = _getBox();
    final prefix = _getUserPrefix();
    final String? stored = (box.get('$prefix$_defaultStatusPrefix$moduleKey') ??
        box.get('$_defaultStatusPrefix$moduleKey')) as String?;

    final available = getStatuses(moduleKey);
    if (stored != null &&
        available.any((s) => s.toLowerCase() == stored.toLowerCase())) {
      return stored;
    }

    // Check user record default if present
    final currentUser = UserPermissionService.getCurrentUser();
    final userDef = currentUser.defaultStatuses[moduleKey];
    if (userDef != null &&
        available.any((s) => s.toLowerCase() == userDef.toLowerCase())) {
      return userDef;
    }

    return available.isNotEmpty ? available.first : 'Pending';
  }

  /// Set default status for new forms in a module and sync to cloud.
  static Future<void> setDefaultStatus(String moduleKey, String status) async {
    final box = _getBox();
    final prefix = _getUserPrefix();
    await box.put('$prefix$_defaultStatusPrefix$moduleKey', status);
    await box.put('$_defaultStatusPrefix$moduleKey', status);

    // 1. Sync to user profile in cloud
    try {
      final currentUser = UserPermissionService.getCurrentUser();
      final updatedDefaults = Map<String, String>.from(currentUser.defaultStatuses);
      updatedDefaults[moduleKey] = status;
      final updatedUser = currentUser.copyWith(defaultStatuses: updatedDefaults);
      await UserPermissionService.saveUser(updatedUser);
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

  /// Scan the database once and return unique statuses found in it.
  /// This is ONLY called when explicitly loading, not on every sort.
  static List<String> getDatabaseStatuses(String moduleKey) {
    String boxName;
    switch (moduleKey) {
      case 'inward':
        boxName = 'inward_box';
        break;
      case 'calls':
        boxName = 'calls_box';
        break;
      case 'replacements':
        boxName = 'replacement_box';
        break;
      case 'requests':
        boxName = 'request_box';
        break;
      case 'purchases':
        boxName = 'purchase_box';
        break;
      case 'sales':
        boxName = 'sales_box';
        break;
      default:
        return [];
    }

    try {
      if (!Hive.isBoxOpen(boxName)) {
        return [];
      }
      final box = Hive.box(boxName);
      final Set<String> dbStatuses = {};
      for (var value in box.values) {
        if (value is Map) {
          final statusVal = value['status'];
          if (statusVal is String && statusVal.trim().isNotEmpty) {
            dbStatuses.add(statusVal.trim());
          }
        }
      }
      return dbStatuses.toList();
    } catch (_) {
      return [];
    }
  }

  /// Get statuses — uses cache to avoid hitting Hive on every call.
  static List<String> getStatuses(String moduleKey) {
    // Return from cache if available
    if (_cache.containsKey(moduleKey)) {
      return List<String>.from(_cache[moduleKey]!);
    }
    return _loadAndCache(moduleKey);
  }

  static List<String> _loadAndCache(String moduleKey) {
    final box = _getBox();
    final prefix = _getUserPrefix();
    final List? stored = box.get('$prefix$_statusListKeyPrefix$moduleKey') ??
        box.get('$_statusListKeyPrefix$moduleKey');
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
      if (list.length != initialLen) {
        box.put('$prefix$_statusListKeyPrefix$moduleKey', list);
      }
    }

    if (moduleKey == 'inward') {
      final int initialLen = list.length;
      list.removeWhere((s) => s.trim().toLowerCase() == 'test');
      if (list.length != initialLen) {
        box.put('$prefix$_statusListKeyPrefix$moduleKey', list);
      }
    }

    _cache[moduleKey] = list;
    return List<String>.from(list);
  }

  /// Fast comparison using the cache — never scans the database.
  static int compareStatuses(String moduleKey, String statusA, String statusB) {
    final orderList = getStatuses(moduleKey); // hits cache, no Hive I/O
    final indexA = orderList.indexWhere(
      (s) => s.toLowerCase() == statusA.toLowerCase().trim(),
    );
    final indexB = orderList.indexWhere(
      (s) => s.toLowerCase() == statusB.toLowerCase().trim(),
    );
    final posA = indexA == -1 ? 9999 : indexA;
    final posB = indexB == -1 ? 9999 : indexB;
    return posA.compareTo(posB);
  }

  static Future<void> saveStatuses(
    String moduleKey,
    List<String> statuses,
  ) async {
    final box = _getBox();
    final prefix = _getUserPrefix();
    await box.put('$prefix$_statusListKeyPrefix$moduleKey', statuses);
    await box.put('$_statusListKeyPrefix$moduleKey', statuses);
    // Update cache immediately
    _cache[moduleKey] = List<String>.from(statuses);

    // 1. Sync to user profile in cloud
    try {
      final currentUser = UserPermissionService.getCurrentUser();
      final updatedLists = Map<String, List<String>>.from(currentUser.customStatusLists);
      updatedLists[moduleKey] = List<String>.from(statuses);
      final updatedUser = currentUser.copyWith(customStatusLists: updatedLists);
      await UserPermissionService.saveUser(updatedUser);
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

  /// Invalidate the cache for a module (call after external data changes)
  static void invalidateCache(String moduleKey) {
    _cache.remove(moduleKey);
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

  static Future<void> deleteStatus(
    String moduleKey,
    String statusToDelete,
  ) async {
    final current = getStatuses(moduleKey);
    current.removeWhere(
      (s) => s.toLowerCase() == statusToDelete.trim().toLowerCase(),
    );
    await saveStatuses(moduleKey, current);

    // Update database entries that were using this status to a fallback status
    final String fallbackStatus = current.isNotEmpty
        ? current.first
        : 'Pending';
    String boxName;
    switch (moduleKey) {
      case 'inward':
        boxName = 'inward_box';
        break;
      case 'calls':
        boxName = 'calls_box';
        break;
      case 'replacements':
        boxName = 'replacement_box';
        break;
      case 'requests':
        boxName = 'request_box';
        break;
      case 'purchases':
        boxName = 'purchase_box';
        break;
      case 'sales':
        boxName = 'sales_box';
        break;
      default:
        return;
    }

    try {
      if (Hive.isBoxOpen(boxName)) {
        final box = Hive.box(boxName);
        final Map<dynamic, dynamic> updates = {};
        for (var key in box.keys) {
          final value = box.get(key);
          if (value is Map) {
            final statusVal = value['status'] ?? value['orderStatus'];
            if (statusVal is String &&
                statusVal.toLowerCase() ==
                    statusToDelete.trim().toLowerCase()) {
              final updatedMap = Map<String, dynamic>.from(value);
              if (updatedMap.containsKey('status')) {
                updatedMap['status'] = fallbackStatus;
              }
              if (updatedMap.containsKey('orderStatus')) {
                updatedMap['orderStatus'] = fallbackStatus;
              }
              updates[key] = updatedMap;
            }
          }
        }
        if (updates.isNotEmpty) {
          await box.putAll(updates);
        }
      }
    } catch (_) {}
  }
}

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

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 24,
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        decoration: BoxDecoration(
          color: const Color(0xFF161A23).withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 24,
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
                  bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
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
                            color: AppTheme.primary.withOpacity(0.15),
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
                              const Text(
                                'Drag to reorder or add custom status',
                                style: TextStyle(
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
                                    color: AppTheme.textMuted.withOpacity(0.6),
                                    fontSize: 13,
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: AppTheme.primary.withOpacity(0.4),
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
                                color: AppTheme.primary.withOpacity(0.4),
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

                            return Container(
                              key: ValueKey(status),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDefault
                                    ? AppTheme.primary.withOpacity(0.12)
                                    : Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDefault
                                      ? AppTheme.primaryLight.withOpacity(0.3)
                                      : Colors.white.withOpacity(0.06),
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
                                              color: AppTheme.primary.withOpacity(0.3),
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
                  top: BorderSide(color: Colors.white.withOpacity(0.08)),
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

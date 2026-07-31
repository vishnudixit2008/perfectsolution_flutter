import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../ui/core/app_theme.dart';

class StatusManagementService {
  static const String _boxName = 'status_management_box';
  static const String _statusListKeyPrefix = 'status_list_';

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
    'requests': ['Pending', 'Office', 'Received', 'Complete'],
    'purchases': ['PENDING', 'Confirmed'],
    'sales': ['Pending', 'Complete'],
  };

  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  static Box _getBox() {
    return Hive.box(_boxName);
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
    final List? stored = box.get('$_statusListKeyPrefix$moduleKey');
    List<String> list;
    if (stored != null && stored.isNotEmpty) {
      list = List<String>.from(stored);
    } else {
      list = List<String>.from(
        _defaultStatuses[moduleKey] ?? ['Pending', 'Complete'],
      );
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
    await box.put('$_statusListKeyPrefix$moduleKey', statuses);
    // Update cache immediately
    _cache[moduleKey] = List<String>.from(statuses);
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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
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
                  Row(
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
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Manage ${widget.moduleTitle} Statuses',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Drag to reorder or add custom status',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                            return Container(
                              key: ValueKey(status),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.06),
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
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      status,
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
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

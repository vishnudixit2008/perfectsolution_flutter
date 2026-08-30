import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../ui/shared/status_management_dialog.dart';
import '../repositories/shop_repository.dart';
import 'local_database_service.dart';

class MultiWindowSyncService {
  static final MultiWindowSyncService instance = MultiWindowSyncService._internal();
  MultiWindowSyncService._internal();

  static const String _nativeChannelName = 'com.perfectsolution/desktop_window_manager';
  static const MethodChannel _nativeChannel = MethodChannel(_nativeChannelName);

  bool _isInitialized = false;
  int? _currentWindowId;
  Map<String, dynamic> _windowArgs = {};
  final Set<int> _knownSubWindowIds = {};
  LocalDatabaseService? _localDb;

  bool get isSubWindow => _currentWindowId != null && _currentWindowId != 0;
  int? get currentWindowId => _currentWindowId;
  Map<String, dynamic> get windowArgs => _windowArgs;

  /// Initialize multi-window service for main or sub window
  Future<void> init({
    int? windowId,
    Map<String, dynamic>? windowArgs,
    LocalDatabaseService? localDb,
  }) async {
    if (_isInitialized) return;
    if (kIsWeb || (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)) return;

    _currentWindowId = windowId;
    _windowArgs = windowArgs ?? {};
    _localDb = localDb;

    // Listen for messages from other windows
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      debugPrint('MultiWindowSyncService [Window $_currentWindowId]: Received method "${call.method}" from Window $fromWindowId');

      switch (call.method) {
        case 'get_db_snapshot':
          if (_localDb != null) {
            final snapshot = _localDb!.exportDbSnapshot();
            return jsonEncode(snapshot);
          }
          return '{}';

        case 'sync_table_snapshot':
          final payload = call.arguments;
          if (payload is String && _localDb != null) {
            Future.microtask(() async {
              try {
                final map = jsonDecode(payload);
                if (map is Map && map.containsKey('table') && map.containsKey('data')) {
                  final tableName = map['table']?.toString() ?? '';
                  final data = map['data'];
                  await _localDb!.importTableData(tableName, data);
                  ShopRepository.notifyTableChanged(tableName, broadcastToOtherWindows: false);
                }
              } catch (e) {
                debugPrint('sync_table_snapshot error: $e');
              }
            });
          }
          return true;

        case 'table_changed':
          final tableName = call.arguments?.toString() ?? 'all';
          Future.microtask(() {
            ShopRepository.notifyTableChanged(tableName, broadcastToOtherWindows: false);
          });
          return true;

        case 'register_sub_window':
          final newId = int.tryParse(call.arguments?.toString() ?? '');
          if (newId != null && newId != _currentWindowId) {
            _knownSubWindowIds.add(newId);
            debugPrint('MultiWindowSyncService: Registered sub-window #$newId (Total: ${_knownSubWindowIds.length})');
          }
          return true;

        case 'unregister_sub_window':
          final closedId = int.tryParse(call.arguments?.toString() ?? '');
          if (closedId != null) {
            _knownSubWindowIds.remove(closedId);
            debugPrint('MultiWindowSyncService: Unregistered sub-window #$closedId');
          }
          return true;

        case 'new_window':
          await createNewWindow();
          return true;

        default:
          return null;
      }
    });

    // Main window listens to native OS requests (macOS Dock menu / Windows taskbar)
    if (!isSubWindow) {
      _nativeChannel.setMethodCallHandler((call) async {
        if (call.method == 'new_window') {
          debugPrint('MultiWindowSyncService: Native OS requested New Window');
          await createNewWindow();
          return true;
        }
        return null;
      });
    } else {
      // Register sub-window with main window and request initial DB snapshot
      try {
        await DesktopMultiWindow.invokeMethod(0, 'register_sub_window', _currentWindowId.toString());
        final snapshotJson = await DesktopMultiWindow.invokeMethod(0, 'get_db_snapshot');
        if (snapshotJson is String && snapshotJson.isNotEmpty && _localDb != null) {
          final snapshot = jsonDecode(snapshotJson);
          if (snapshot is Map<String, dynamic>) {
            await _localDb!.importDbSnapshot(snapshot);
            await StatusManagementService.init();
            ShopRepository.notifyTableChanged('all', broadcastToOtherWindows: false);
            debugPrint('MultiWindowSyncService: Sub-window #$_currentWindowId loaded DB snapshot & status order successfully');
          }
        }
      } catch (e) {
        debugPrint('MultiWindowSyncService: Sub-window snapshot fetch error: $e');
      }
    }

    _isInitialized = true;
    debugPrint('MultiWindowSyncService: Initialized for Window ID: ${_currentWindowId ?? 0}');
  }

  /// Creates and presents a new native desktop window
  Future<WindowController?> createNewWindow({Map<String, dynamic>? args}) async {
    if (kIsWeb || (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)) return null;

    try {
      final payload = args ?? <String, dynamic>{};
      payload['timestamp'] = DateTime.now().millisecondsSinceEpoch;

      final window = await DesktopMultiWindow.createWindow(jsonEncode(payload));
      _knownSubWindowIds.add(window.windowId);

      // Configure window size and position
      await window.setFrame(const Offset(80, 80) & const Size(1280, 820));
      await window.center();
      await window.setTitle('Perfect Solution');
      await window.show();

      debugPrint('MultiWindowSyncService: Successfully spawned New Window #${window.windowId}');
      return window;
    } catch (e) {
      debugPrint('MultiWindowSyncService: Failed to create new window: $e');
      return null;
    }
  }

  /// Broadcasts a table change event and table data to all other open desktop windows
  Future<void> broadcastTableChange(String tableName) async {
    if (kIsWeb || (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)) return;

    try {
      final allWindows = await DesktopMultiWindow.getAllSubWindowIds();
      final targetWindows = <int>{...allWindows, ..._knownSubWindowIds};

      // Prepare payload if we have localDb
      String? syncPayload;
      if (_localDb != null) {
        final tableData = _localDb!.exportTableData(tableName);
        if (tableData != null) {
          syncPayload = jsonEncode({
            'table': tableName,
            'data': tableData,
          });
        }
      }

      // If we are in a sub-window, notify Window 0
      if (isSubWindow) {
        try {
          if (syncPayload != null) {
            await DesktopMultiWindow.invokeMethod(0, 'sync_table_snapshot', syncPayload);
          } else {
            await DesktopMultiWindow.invokeMethod(0, 'table_changed', tableName);
          }
        } catch (e) {
          debugPrint('MultiWindowSyncService: Error notifying Window 0: $e');
        }
      }

      // Notify other sub-windows
      for (final windowId in targetWindows) {
        if (windowId == _currentWindowId || windowId == 0) continue;
        try {
          if (syncPayload != null) {
            await DesktopMultiWindow.invokeMethod(windowId, 'sync_table_snapshot', syncPayload);
          } else {
            await DesktopMultiWindow.invokeMethod(windowId, 'table_changed', tableName);
          }
        } catch (e) {
          _knownSubWindowIds.remove(windowId);
          debugPrint('MultiWindowSyncService: Window #$windowId closed or unreachable. Removed from registry.');
        }
      }
    } catch (e) {
      debugPrint('MultiWindowSyncService: broadcastTableChange error: $e');
    }
  }
}


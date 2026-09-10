import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../repositories/shop_repository.dart';
import '../services/user_permission_service.dart';
import 'local_database_service.dart';
import 'supabase_sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Initialize multi-window service for main or sub window.
  ///
  /// Architecture:
  /// - Main window (ID 0): owns Supabase Realtime + heartbeat. Responds to IPC
  ///   requests for auth state, data snapshots, and table-specific data.
  /// - Sub-windows (ID > 0): NO competing Realtime/heartbeat. Get initial data
  ///   via IPC snapshot from main window. Receive lightweight [table_changed] IPC
  ///   and perform targeted delta syncs from Supabase for that table only.
  Future<void> init({
    int? windowId,
    Map<String, dynamic>? windowArgs,
    LocalDatabaseService? localDb,
  }) async {
    if (kIsWeb || (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)) return;

    // Always update refs so re-invocations (e.g. after hot-reload) see latest values.
    _currentWindowId = windowId ?? _currentWindowId;
    _windowArgs = windowArgs ?? _windowArgs;
    _localDb = localDb ?? _localDb;

    // ── IPC handler ───────────────────────────────────────────────────────────
    // ALWAYS re-register even if _isInitialized == true.
    // Flutter hot-reload clears all method-channel handlers, so without this
    // any sub-window IPC would throw MissingPluginException after a hot-reload.

    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      debugPrint(
        'MultiWindowSyncService [Window $_currentWindowId]: '
        'Received "${call.method}" from Window $fromWindowId',
      );

      switch (call.method) {
        // ── table_changed ────────────────────────────────────────────────────
        // Sent by any window when local data changes. Sub-windows perform a
        // targeted delta sync from Supabase then refresh their UI.
        // Main window refreshes immediately from its already-updated Hive.
        case 'table_changed':
          final tableName = call.arguments?.toString() ?? 'all';
          if (!isSubWindow) {
            // Main window: Hive was already updated via Realtime — just notify UI
            Future.microtask(() {
              ShopRepository.notifyTableChanged(tableName, broadcastToOtherWindows: false);
            });
          } else {
            // Sub-window: sync that table from Supabase so local Hive gets fresh data
            Future.microtask(() async {
              if (_localDb != null && SupabaseSyncService.instance.isInitialized) {
                try {
                  await SupabaseSyncService.instance.syncTableFromCloud(
                    tableName,
                    _localDb!,
                  );
                } catch (e) {
                  debugPrint('MultiWindowSyncService [SubWin $_currentWindowId]: '
                      'delta sync error for $tableName: $e');
                }
              }
              ShopRepository.notifyTableChanged(tableName, broadcastToOtherWindows: false);
            });
          }
          return true;

        // ── register_sub_window ──────────────────────────────────────────────
        case 'register_sub_window':
          final newId = int.tryParse(call.arguments?.toString() ?? '');
          if (newId != null && newId != _currentWindowId) {
            _knownSubWindowIds.add(newId);
            debugPrint(
              'MultiWindowSyncService: Registered sub-window #$newId '
              '(Total: ${_knownSubWindowIds.length})',
            );
          }
          return true;

        // ── unregister_sub_window ────────────────────────────────────────────
        case 'unregister_sub_window':
          final closedId = int.tryParse(call.arguments?.toString() ?? '');
          if (closedId != null) {
            _knownSubWindowIds.remove(closedId);
            debugPrint('MultiWindowSyncService: Unregistered sub-window #$closedId');
          }
          return true;

        // ── new_window ───────────────────────────────────────────────────────
        case 'new_window':
          await createNewWindow();
          return true;

        // ── get_auth_state ───────────────────────────────────────────────────
        // Sub-windows call this to get the current user's auth info + Supabase
        // session JSON so they can seed their local Hive and recover the session.
        case 'get_auth_state':
          try {
            final email = UserPermissionService.getCurrentUserEmail();
            final user = UserPermissionService.getCurrentUser();
            Session? session;
            try {
              session = Supabase.instance.client.auth.currentSession;
            } catch (_) {}
            return jsonEncode({
              'email': email,
              'is_authenticated': email.isNotEmpty,
              'user_data': user.toJson(),
              'session_json': session != null ? jsonEncode(session.toJson()) : null,
            });
          } catch (e) {
            debugPrint('MultiWindowSyncService: get_auth_state error: $e');
            return null;
          }

        // ── get_table_snapshot ───────────────────────────────────────────────
        // Sub-windows can request the data for a single table from the main
        // window's already-populated Hive.
        case 'get_table_snapshot':
          final tableName = call.arguments?.toString() ?? '';
          if (_localDb != null && tableName.isNotEmpty) {
            try {
              final data = _localDb!.exportTableData(tableName);
              if (data != null) {
                return jsonEncode(data);
              }
            } catch (e) {
              debugPrint(
                  'MultiWindowSyncService: get_table_snapshot error for $tableName: $e');
            }
          }
          return null;

        // ── get_full_snapshot ────────────────────────────────────────────────
        // Returns a complete JSON snapshot of all data tables in the main
        // window's Hive. Used by sub-windows on startup to populate themselves.
        case 'get_full_snapshot':
          if (_localDb != null) {
            try {
              final snapshot = _localDb!.exportDbSnapshot();
              return jsonEncode(snapshot);
            } catch (e) {
              debugPrint('MultiWindowSyncService: get_full_snapshot error: $e');
            }
          }
          return null;

        default:
          return null;
      }
    });

    // ── Main window: always re-register native OS "new window" handler ────────
    if (!isSubWindow) {
      _nativeChannel.setMethodCallHandler((call) async {
        // Called by: (a) native OS Dock / taskbar via flutter_window.cpp
        //            (b) cross-process --new-window arg via flutter_window.cpp WM message
        if (call.method == 'new_window' || call.method == 'new_window_request') {
          debugPrint('MultiWindowSyncService: Native OS requested New Window');
          await createNewWindow();
          return true;
        }
        return null;
      });
    }

    // ── Skip one-time startup sequence if already initialized ─────────────────
    // Handler re-registration above always runs; the block below only runs once.
    if (_isInitialized) return;

    if (isSubWindow) {
      // ── Sub-window startup sequence (non-blocking for instant UI appearance) ───
      // Register with main window and pull snapshot asynchronously in the background.
      // The local database boxes and auth state are already open, so runApp()
      // executes and renders the UI immediately. When the snapshot completes,
      // notifyTableChanged('all') fires to populate all view models.
      unawaited(() async {
        try {
          await DesktopMultiWindow.invokeMethod(
            0,
            'register_sub_window',
            _currentWindowId.toString(),
          );
          debugPrint(
            'MultiWindowSyncService: Sub-window #$_currentWindowId registered with main window.',
          );
        } catch (e) {
          debugPrint('MultiWindowSyncService: register_sub_window IPC error: $e');
        }

        // Pull full snapshot from main window into local Hive
        if (_localDb != null) {
          bool snapshotLoaded = false;
          try {
            final snapshotJson = await DesktopMultiWindow.invokeMethod(
              0,
              'get_full_snapshot',
              null,
            ).timeout(const Duration(seconds: 5));

            if (snapshotJson != null) {
              final snapshot = jsonDecode(snapshotJson.toString()) as Map<String, dynamic>;
              await _localDb!.importDbSnapshot(snapshot);

              snapshotLoaded = true;
              debugPrint(
                'MultiWindowSyncService: Sub-window #$_currentWindowId '
                'populated from main window snapshot.',
              );
            }
          } catch (e) {
            debugPrint(
              'MultiWindowSyncService: Sub-window #$_currentWindowId snapshot error: $e',
            );
          }

          // Fallback: if IPC snapshot failed, do a one-time full sync from Supabase
          if (!snapshotLoaded && SupabaseSyncService.instance.isInitialized) {
            try {
              debugPrint(
                'MultiWindowSyncService: Sub-window #$_currentWindowId '
                'falling back to direct Supabase sync.',
              );
              await SupabaseSyncService.instance.syncAllTablesFromCloud(_localDb!, force: true);
            } catch (syncErr) {
              debugPrint('MultiWindowSyncService: Fallback Supabase sync error: $syncErr');
            }
          }

          // Flush any offline queue accumulated before we had a session
          if (SupabaseSyncService.instance.isInitialized) {
            try {
              await SupabaseSyncService.instance.flushOfflineQueue(_localDb!);
            } catch (_) {}
          }
        }

        // Notify all ViewModels to reload from the now-populated local Hive
        ShopRepository.notifyTableChanged('all', broadcastToOtherWindows: false);
        debugPrint(
          'MultiWindowSyncService: Sub-window #$_currentWindowId ready — '
          'UI notified to reload.',
        );
      }());
    }


    _isInitialized = true;
    debugPrint(
      'MultiWindowSyncService: Initialized for Window ID: ${_currentWindowId ?? 0}',
    );
  }

  /// Creates and presents a new native desktop window.
  Future<WindowController?> createNewWindow({Map<String, dynamic>? args}) async {
    if (kIsWeb || (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)) return null;

    try {
      final payload = args ?? <String, dynamic>{};
      payload['timestamp'] = DateTime.now().millisecondsSinceEpoch;

      // Package current auth session and user into payload for instant synchronous
      // sub-window auth without waiting for network or IPC roundtrips
      try {
        final email = UserPermissionService.getCurrentUserEmail();
        final userData = UserPermissionService.getCurrentUser();
        final session = Supabase.instance.client.auth.currentSession;
        if (email.isNotEmpty) {
          payload['auth_email'] = email;
          payload['auth_user_data'] = userData;
          if (session != null) {
            payload['auth_session_json'] = jsonEncode(session.toJson());
          }
        }

      } catch (e) {
        debugPrint('MultiWindowSyncService: error packaging auth payload: $e');
      }

      final window = await DesktopMultiWindow.createWindow(jsonEncode(payload));
      _knownSubWindowIds.add(window.windowId);

      await Future.wait([
        window.setFrame(const Offset(80, 80) & const Size(1366, 850)),
        window.center(),
        window.setTitle('Perfect Solution'),
      ]);
      await window.show();



      debugPrint('MultiWindowSyncService: Successfully spawned New Window #${window.windowId}');
      return window;
    } catch (e) {
      debugPrint('MultiWindowSyncService: Failed to create new window: $e');
      return null;
    }
  }

  /// Broadcasts a lightweight table-changed event to all other open desktop windows.
  ///
  /// Main window → broadcasts to all sub-windows.
  /// Sub-window  → broadcasts to main window (0) AND all other sub-windows.
  Future<void> broadcastTableChange(String tableName) async {
    if (kIsWeb || (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)) return;

    try {
      final allWindows = await DesktopMultiWindow.getAllSubWindowIds();
      final targetWindows = <int>{...allWindows, ..._knownSubWindowIds};

      // Sub-window: also notify Window 0 (main)
      if (isSubWindow) {
        try {
          await DesktopMultiWindow.invokeMethod(0, 'table_changed', tableName);
        } catch (e) {
          debugPrint('MultiWindowSyncService: Error notifying Window 0: $e');
        }
      }

      // Notify all other sub-windows
      for (final windowId in targetWindows) {
        if (windowId == _currentWindowId || windowId == 0) continue;
        try {
          await DesktopMultiWindow.invokeMethod(windowId, 'table_changed', tableName);
        } catch (e) {
          _knownSubWindowIds.remove(windowId);
          debugPrint(
            'MultiWindowSyncService: Window #$windowId closed or unreachable. '
            'Removed from registry.',
          );
        }
      }
    } catch (e) {
      debugPrint('MultiWindowSyncService: broadcastTableChange error: $e');
    }
  }
}


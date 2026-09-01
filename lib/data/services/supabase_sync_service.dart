import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/call_model.dart';
import '../models/inward_repair.dart';
import '../models/inward_estimate_item.dart';
import '../models/sale_item.dart';
import '../models/purchase_order_item.dart';
import '../models/pricelist_item.dart';
import '../models/purchase_order.dart';
import '../models/replacement.dart';
import '../models/request_order.dart';
import '../models/sale.dart';
import '../services/local_database_service.dart';
import '../services/user_permission_service.dart';
import '../repositories/shop_repository.dart';
import '../../ui/shared/status_management_dialog.dart';
import 'ui_preferences_service.dart';
import 'auto_update_service.dart';
import 'fcm_service.dart';
import '../../ui/shared/dialogs/call_alert_dialog.dart';

enum SyncStatus { offline, syncing, synced, error }

/// ============================================================================
/// CRITICAL ARCHITECTURE NOTICE FOR ALL DEVELOPERS & AI MODELS:
/// ----------------------------------------------------------------------------
/// This service is the core synchronization engine between local Hive storage
/// and the self-hosted Supabase backend (running on Linux over direct IPv6).
///
/// KEY RULES & INVARIANTS:
/// 1. DO NOT MODIFY SYNC OR MERGE LOGIC WITHOUT EXPLICIT PERMISSION FROM USER.
/// 2. BATCHED QUERIES: syncAllTablesFromCloud() MUST run in 3 batched groups
///    (max 4 concurrent requests). DO NOT revert to an unconstrained Future.wait
///    of all 12 tables, as mobile network socket limits (max 6 connections)
///    will starve the Realtime WebSocket channel and trigger timeouts.
/// 3. DELTA SYNC: Every table query MUST include `updated_at >= lastSyncIso`
///    to avoid re-downloading entire tables.
/// 4. MERGE IN PLACE: Always save with `clearOthers: false` to preserve local
///    offline edits and avoid wiping records.
/// 5. TOMBSTONES: Deletions use the `deleted_records` table to ensure atomic
///    and precise item removal across all devices without blind wipes.
/// 6. ENDPOINT: The primary backend is `http://psflutter.duckdns.org:8000`
///    (Direct native IPv6 with DuckDNS). Do not change without user approval.
/// ============================================================================
class SupabaseSyncService extends ChangeNotifier {
  static const String _boxName = 'ui_preferences';
  static const String _urlKey = 'supabase_project_url';
  static const String _keyKey = 'supabase_anon_key';
  static const String _defaultUrl = 'http://psflutter.duckdns.org:8000';
  static const String _defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg4MDE5NTIzLCJleHAiOjIxMDMzNzk1MjN9.eGJCMvVSVQe3lezs_UfCv5TeYRsoB9beJtlZuALKZ28';

  static final SupabaseSyncService instance = SupabaseSyncService._internal();
  SupabaseSyncService._internal();

  static String get defaultUrl => _defaultUrl;
  static String get defaultAnonKey => _defaultAnonKey;

  String? _supabaseUrl;
  String? _supabaseAnonKey;
  bool _isInitialized = false;
  SyncStatus _status = SyncStatus.offline;
  String _statusMessage = 'Not Connected';
  RealtimeChannel? _realtimeChannel;

  // Debounce timer to prevent realtime event flood
  Timer? _debounceTimer;
  Timer? _heartbeatTimer;
  Timer? _offlineDebounceTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isReconnecting = false;
  bool _isRealtimeSubscribed = false;

  SyncStatus get status => _status;
  String get statusMessage => _statusMessage;
  bool get isInitialized => _isInitialized;
  String? get supabaseUrl => _supabaseUrl ?? _defaultUrl;
  String? get supabaseAnonKey => _supabaseAnonKey ?? _defaultAnonKey;

  /// Load credentials from local storage and initialize Supabase
  Future<void> init(LocalDatabaseService localDb) async {
    try {
      final box = await Hive.openBox(_boxName);
      // Force local settings box to use local Cloudflare Tunnel endpoint
      _supabaseUrl = _defaultUrl;
      _supabaseAnonKey = _defaultAnonKey;

      await box.put(_urlKey, _defaultUrl);
      await box.put(_keyKey, _defaultAnonKey);

      await connectAndSubscribe(localDb);
    } catch (e) {
      if (kDebugMode) print('SupabaseSyncService init error: $e');
      _setStatus(SyncStatus.error, 'Init Error: $e');
    }
  }

  /// Saves credentials to local storage and connects to Supabase
  Future<bool> saveCredentials({
    required String url,
    required String anonKey,
    required LocalDatabaseService localDb,
  }) async {
    try {
      final box = await Hive.openBox(_boxName);
      _supabaseUrl = url.trim();
      _supabaseAnonKey = anonKey.trim();

      await box.put(_urlKey, _supabaseUrl!);
      await box.put(_keyKey, _supabaseAnonKey!);

      return await connectAndSubscribe(localDb);
    } catch (e) {
      _setStatus(SyncStatus.error, 'Save Error: $e');
      return false;
    }
  }

  /// Connects to Supabase and listens to realtime database events
  Future<bool> connectAndSubscribe(LocalDatabaseService localDb) async {
    if (_supabaseUrl == null || _supabaseAnonKey == null) return false;

    try {
      _setStatus(SyncStatus.syncing, 'Connecting to Supabase...');

      // Initialize Supabase client if not already done
      try {
        await Supabase.initialize(
          url: _supabaseUrl!,
          publishableKey: _supabaseAnonKey!,
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.pkce,
          ),
          realtimeClientOptions: const RealtimeClientOptions(
            timeout: Duration(seconds: 30),
          ),
        );
      } catch (_) {
        // Already initialized
      }

      _isInitialized = true;
      _setStatus(SyncStatus.synced, 'Connected to Cloud');

      // Subscribe to real-time WebSocket changes (debounced)
      _subscribeRealtime(localDb);

      // Start continuous background connection health check
      _startHeartbeat(localDb);

      // On startup: pull from cloud only.
      unawaited(_performBackgroundSync(localDb));

      return true;
    } catch (e) {
      if (kDebugMode) print('Supabase connect error: $e');
      _setStatus(SyncStatus.error, 'Cloud Connection Failed: $e');
      return false;
    }
  }

  /// Background passive health monitor every 2 minutes.
  /// Reconnects dropped WebSockets and performs an ultra-fast Delta Catch-up Sync (0 egress if no changes).
  void _startHeartbeat(LocalDatabaseService localDb) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!_isInitialized) return;

      try {
        ensureRealtimeConnected(localDb);
        // Fast delta catchup query: takes ~50ms and fetches 0 rows if nothing changed
        await syncAllTablesFromCloud(localDb, forceDelta: true);
        await flushOfflineQueue(localDb);
        if (_status != SyncStatus.synced) {
          _setStatus(SyncStatus.synced, 'Live Synced');
        }
      } catch (e) {
        if (kDebugMode) print('[SupabaseSync] Heartbeat delta sync check: $e');
      }
    });
  }

  /// Triggered on app resume from sleep / background.
  /// Immediately verifies WebSocket connection and executes an instant catch-up delta sync.
  Future<void> onAppResume(LocalDatabaseService localDb) async {
    if (!_isInitialized) {
      ShopRepository.notifyTableChanged('all');
      return;
    }

    if (kDebugMode) print('[SupabaseSync] App resumed — running quick catch-up delta sync');
    ensureRealtimeConnected(localDb);
    try {
      await syncAllTablesFromCloud(localDb, forceDelta: true);
      await flushOfflineQueue(localDb);
      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('[SupabaseSync] onAppResume sync error: $e');
    } finally {
      ShopRepository.notifyTableChanged('all');
    }
  }

  /// Verifies Realtime WebSocket subscription is active, recreating channel if missing or closed.
  void ensureRealtimeConnected(LocalDatabaseService localDb) {
    if (!_isInitialized) return;
    if (!_isRealtimeSubscribed && !_isReconnecting) {
      _subscribeRealtime(localDb);
    }
  }

  /// On startup: pull from cloud, then flush any offline-queued operations.
  /// We do NOT push all local data — cloud is the single source of truth.
  Future<void> _performBackgroundSync(LocalDatabaseService localDb) async {
    try {
      // 1.5s delay to allow initial dashboard UI and animations to render smoothly
      await Future.delayed(const Duration(milliseconds: 1500));
      // 1. Flush any operations queued while the device was offline FIRST
      await flushOfflineQueue(localDb);
      // 2. Small gap so Supabase can propagate records that were just pushed.
      //    Without this, a full sync immediately after flush may not yet see
      //    the newly-pushed rows and will delete them locally (clearOthers:true).
      await Future.delayed(const Duration(milliseconds: 500));
      // 3. Pull authoritative data from cloud into local.
      //    If a fallback Hive box was opened (possibly empty), force a full
      //    re-download to restore any data that may be missing locally.
      final forceFullSync = localDb.hadFallbackBoxOpen;
      await syncAllTablesFromCloud(localDb, force: forceFullSync);
    } catch (e) {
      if (kDebugMode) print('Background sync error: $e');
      _setStatus(SyncStatus.error, 'Background Sync Error: $e');
    }
  }

  DateTime? _lastManualTapTime;

  /// Public method for manual sync triggered by user (pull only).
  /// By default, manual sync performs a Fast Delta Catchup (isDelta: true) to save 99% data.
  /// If [forceFullDownload] is true, it performs a 100% full table re-download.
  /// Regardless, it always broadcasts a Full Screen UI Refresh (0 cloud usage, pure local device RAM).
  Future<void> manualSync(LocalDatabaseService localDb, {bool forceFullDownload = false}) async {
    final now = DateTime.now();
    // Anti-spam debounce: If clicked rapidly within 2 seconds, do instant local UI refresh
    if (!forceFullDownload && _lastManualTapTime != null && now.difference(_lastManualTapTime!).inSeconds < 2) {
      ShopRepository.notifyTableChanged('all');
      _setStatus(SyncStatus.synced, 'Live Synced');
      return;
    }
    _lastManualTapTime = now;

    if (!_isInitialized) {
      try {
        final connected = await connectAndSubscribe(localDb);
        if (!connected) {
          ShopRepository.notifyTableChanged('all');
          return;
        }
      } catch (e) {
        _setStatus(SyncStatus.error, 'Connection Error: $e');
        ShopRepository.notifyTableChanged('all');
        return;
      }
    }

    _setStatus(SyncStatus.syncing, 'Syncing...');

    try {
      await syncAllTablesFromCloud(localDb, force: forceFullDownload, forceDelta: !forceFullDownload);
      await flushOfflineQueue(localDb);
      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Manual sync error: $e');
      _setStatus(SyncStatus.offline, 'Server Offline');
    } finally {
      // Always broadcast full UI refresh using local device resources (0 cloud egress)
      ShopRepository.notifyTableChanged('all');
    }
  }

  void _setStatus(SyncStatus status, String message) {
    _status = status;
    _statusMessage = message;
    notifyListeners();
  }

  /// Subscribes to real-time table mutations broadcast by Supabase.
  /// Uses native WebSocket status & debounced targeted delta sync to fetch only new/modified rows per table.
  /// Auto-reconnects with exponential backoff and jitter on channel drop to prevent connection storms.
  void _subscribeRealtime(LocalDatabaseService localDb) {
    if (!_isInitialized) return;
    try {
      final client = Supabase.instance.client;
      _reconnectTimer?.cancel();
      _offlineDebounceTimer?.cancel();

      if (_realtimeChannel != null) {
        final oldChannel = _realtimeChannel;
        _realtimeChannel = null;
        _isRealtimeSubscribed = false;
        try {
          oldChannel?.unsubscribe();
          if (oldChannel != null) {
            client.removeChannel(oldChannel);
          }
        } catch (_) {}
      }

      final pendingTables = <String>{};

      final newChannel = client.channel('public-db-changes');
      _realtimeChannel = newChannel;

      newChannel
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          callback: (payload) async {
            if (_realtimeChannel != newChannel) return;
            final table = payload.table;
            final eventType = payload.eventType;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (kDebugMode) print('Realtime event on table: $table ($eventType)');

            if (table == 'app_versions') {
              AutoUpdateService.instance.checkForUpdates(force: true);
              return;
            }

            // Direct in-memory fast path for immediate 0ms UI reflection
            try {
              if (eventType == PostgresChangeEvent.delete) {
                // Use each table's specific PK column. Supabase may return an
                // empty oldRecord if RLS doesn't allow returning old values —
                // in that case fall back to newRecord (available on some configs).
                final record = oldRecord.isNotEmpty ? oldRecord : newRecord;
                String? rid;
                switch (table) {
                  case 'inward_repairs':
                    rid = record['job_no']?.toString();
                  case 'calls':
                    rid = record['id']?.toString();
                  case 'sales':
                    rid = record['invoice_no']?.toString();
                  case 'replacements':
                    rid = record['job_no']?.toString();
                  case 'requests':
                    rid = record['id']?.toString();
                  case 'purchases':
                    rid = record['id']?.toString();
                  case 'pricelist':
                    rid = record['id']?.toString();
                }
                if (rid != null && rid.isNotEmpty) {
                  switch (table) {
                    case 'inward_repairs':
                      await localDb.deleteInwardRepair(int.tryParse(rid) ?? -1);
                    case 'calls':
                      await localDb.deleteCall(int.tryParse(rid) ?? -1);
                    case 'sales':
                      await localDb.deleteSale(int.tryParse(rid) ?? -1);
                    case 'replacements':
                      await localDb.deleteReplacement(rid);
                    case 'requests':
                      await localDb.deleteRequestOrder(rid);
                    case 'purchases':
                      await localDb.deletePurchaseOrder(rid);
                    case 'pricelist':
                      await localDb.deletePricelistItem(int.tryParse(rid) ?? -1);
                  }
                  ShopRepository.notifyTableChanged(table);
                  ShopRepository.notifyTableChanged('all');
                } else {
                  if (kDebugMode) print('[Realtime] DELETE on $table — could not determine PK from record; skipping local delete. Will catch on next delta sync.');
                }
              } else if (newRecord.isNotEmpty) {
                // If direct payload contains full record, save immediately into Hive
                switch (table) {
                  case 'inward_repairs':
                    final repair = InwardRepair.fromJson(Map<String, dynamic>.from(newRecord));
                    await localDb.saveInwardRepairHeaderOnly(repair);
                    ShopRepository.notifyTableChanged('inward_repairs');
                    ShopRepository.notifyTableChanged('all');
                  case 'inward_estimate_items':
                    final item = InwardEstimateItem.fromJson(Map<String, dynamic>.from(newRecord));
                    await localDb.saveInwardEstimateItemOnly(item);
                    ShopRepository.notifyTableChanged('inward_repairs');
                    ShopRepository.notifyTableChanged('all');
                  case 'calls':
                    final call = CallModel.fromJson(Map<String, dynamic>.from(newRecord));
                    await localDb.saveCall(call);
                    ShopRepository.notifyTableChanged('calls');
                    ShopRepository.notifyTableChanged('all');
                    if (UserPermissionService.shouldReceiveCallAlertPopup() &&
                        UserPermissionService.isEntryDirectlyAssignedToUser(call.assignedTo)) {
                      final context = FcmService.navigatorKey?.currentContext;
                      if (context != null && context.mounted) {
                        CallAlertDialog.show(context, call);
                      }
                    }
                  case 'sales':
                    final sale = Sale.fromJson(Map<String, dynamic>.from(newRecord));
                    await localDb.saveSaleHeaderOnly(sale);
                    ShopRepository.notifyTableChanged('sales');
                    ShopRepository.notifyTableChanged('all');
                  case 'sale_items':
                    final item = SaleItem.fromJson(Map<String, dynamic>.from(newRecord));
                    await localDb.saveSaleItemOnly(item);
                    ShopRepository.notifyTableChanged('sales');
                    ShopRepository.notifyTableChanged('all');
                  case 'replacements':
                    final rep = Replacement.fromJson(Map<String, dynamic>.from(newRecord));
                    await localDb.saveReplacement(rep);
                    ShopRepository.notifyTableChanged('replacements');
                    ShopRepository.notifyTableChanged('all');
                  case 'requests':
                    final req = RequestOrder.fromJson(Map<String, dynamic>.from(newRecord));
                    await localDb.saveRequestOrder(req);
                    ShopRepository.notifyTableChanged('requests');
                    ShopRepository.notifyTableChanged('all');
                  case 'purchases':
                    final pur = PurchaseOrder.fromJson(Map<String, dynamic>.from(newRecord));
                    await localDb.savePurchaseOrderHeaderOnly(pur);
                    ShopRepository.notifyTableChanged('purchases');
                    ShopRepository.notifyTableChanged('all');
                  case 'purchase_order_items':
                    final item = PurchaseOrderItem.fromJson(Map<String, dynamic>.from(newRecord));
                    await localDb.savePurchaseOrderItemOnly(item);
                    ShopRepository.notifyTableChanged('purchases');
                    ShopRepository.notifyTableChanged('all');
                  case 'pricelist':
                    final item = PricelistItem.fromJson(Map<String, dynamic>.from(newRecord));
                    await localDb.savePricelistItem(item);
                    ShopRepository.notifyTableChanged('pricelist_items');
                    ShopRepository.notifyTableChanged('all');
                  case 'app_users':
                    await UserPermissionService.syncUsersFromCloud(force: true);
                    ShopRepository.notifyTableChanged('app_users');
                    ShopRepository.notifyTableChanged('all');
                  case 'shop_settings':
                    final key = newRecord['key']?.toString();
                    var value = newRecord['value'];
                    if (value is String) {
                      final trimmed = value.trim();
                      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
                        try {
                          value = jsonDecode(trimmed);
                        } catch (_) {}
                      }
                    }
                    if (key == 'shop_status_colors' && value != null) {
                      await StatusManagementService.loadFromStatusColorsMap(value);
                    } else if (key == 'shop_custom_statuses' && value != null) {
                      await StatusManagementService.loadFromCustomStatusesMap(value);
                    } else if (key == 'shop_default_statuses' && value != null) {
                      await StatusManagementService.loadFromDefaultStatusesMap(value);
                    } else if (key == 'upi_ids_list' && value is List) {
                      await localDb.saveUpiIdsList(List<String>.from(value.map((e) => e.toString())), syncToCloud: false);
                    } else if (key == 'active_upi_id' && value != null) {
                      await localDb.setActiveUpiId(value.toString(), syncToCloud: false);
                    } else if (key == 'google_review_listing' && value != null) {
                      await localDb.setGoogleReviewListing(value.toString(), syncToCloud: false);
                    } else if (key == 'upi_names_map' && value is Map) {
                      final map = Map<String, String>.from(value.map((k, v) => MapEntry(k.toString(), v.toString())));
                      await localDb.saveUpiNamesMap(map, syncToCloud: false);
                    } else if (key == 'custom_services_list' && value is List) {
                      final cloudList = List<String>.from(value.map((e) => e.toString()));
                      await localDb.setCustomServicesList(cloudList, syncToCloud: false);
                      ShopRepository.notifyTableChanged('custom_services');
                    }
                    ShopRepository.notifyTableChanged('shop_settings');
                    ShopRepository.notifyTableChanged('all');
                  case 'deleted_records':
                    final targetTable = newRecord['table_name']?.toString();
                    final rid = newRecord['record_id']?.toString();
                    if (targetTable != null && rid != null) {
                      switch (targetTable) {
                        case 'inward_repairs':
                          await localDb.deleteInwardRepair(int.tryParse(rid) ?? -1);
                        case 'calls':
                          await localDb.deleteCall(int.tryParse(rid) ?? -1);
                        case 'sales':
                          await localDb.deleteSale(int.tryParse(rid) ?? -1);
                        case 'replacements':
                          await localDb.deleteReplacement(rid);
                        case 'requests':
                          await localDb.deleteRequestOrder(rid);
                        case 'purchases':
                          await localDb.deletePurchaseOrder(rid);
                        case 'pricelist':
                          await localDb.deletePricelistItem(int.tryParse(rid) ?? -1);
                      }
                      ShopRepository.notifyTableChanged(targetTable);
                      ShopRepository.notifyTableChanged('all');
                    }
                }
              }
            } catch (e) {
              if (kDebugMode) print('Error applying realtime in-memory change: $e');
            }

            // Also schedule background delta fetch for child relations (estimate items, sale items, etc.)
            pendingTables.add(table);
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
              final tablesToSync = Set<String>.from(pendingTables);
              pendingTables.clear();
              for (final t in tablesToSync) {
                await syncTableFromCloud(t, localDb);
              }
            });
          },
        )
        ..subscribe((status, [error]) {
          if (_realtimeChannel != newChannel) return; // Ignore teardown callbacks from stale channels

          if (status == RealtimeSubscribeStatus.subscribed) {
            _isRealtimeSubscribed = true;
            _reconnectAttempts = 0;
            _isReconnecting = false;
            _offlineDebounceTimer?.cancel();
            _reconnectTimer?.cancel();
            if (kDebugMode) print('Supabase Realtime subscribed successfully');
            if (_status != SyncStatus.syncing) {
              _setStatus(SyncStatus.synced, 'Live Synced');
            }
            unawaited(flushOfflineQueue(localDb));
            unawaited(syncAllTablesFromCloud(localDb, forceDelta: true));
          } else if (status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            _isRealtimeSubscribed = false;
            if (kDebugMode) {
              print('Supabase Realtime connection dropped: $status (error: $error). Reconnecting with backoff...');
            }

            _setStatus(SyncStatus.offline, 'Server Offline');

            if (_isReconnecting) return;
            _isReconnecting = true;

            // Exponential backoff with jitter: 2s -> 4s -> 8s -> 16s -> 30s max
            _reconnectAttempts++;
            final backoffSec = min(30, pow(2, min(_reconnectAttempts, 5)).toInt());
            final jitterMs = Random().nextInt(1000);
            final reconnectDelay = Duration(seconds: backoffSec, milliseconds: jitterMs);

            _reconnectTimer?.cancel();
            _reconnectTimer = Timer(reconnectDelay, () {
              _isReconnecting = false;
              if (_isInitialized) {
                if (kDebugMode) {
                  print('Supabase Realtime: attempting reconnect (attempt #$_reconnectAttempts, delay: ${reconnectDelay.inSeconds}s)...');
                }
                _subscribeRealtime(localDb);
              }
            });
          }
        });
    } catch (e) {
      _isReconnecting = false;
      if (kDebugMode) print('Realtime subscribe error: $e');
    }
  }

  // ─── Offline Queue Flush ───────────────────────────────────────────────────
  /// Processes all operations that were queued while the device was offline.
  /// Called on startup and manual sync. Each queued op is retried and removed
  /// on success. If it fails again, it stays in the queue for next attempt.
  Future<void> flushOfflineQueue(LocalDatabaseService localDb) async {
    if (!_isInitialized) return;

    final keys = localDb.getPendingSyncKeys();
    final ops = localDb.getPendingSyncQueue();
    if (ops.isEmpty) return;

    if (kDebugMode) print('Flushing ${ops.length} offline queued operations...');
    final client = Supabase.instance.client;

    for (int i = 0; i < ops.length; i++) {
      final op = ops[i];
      final hiveKey = keys[i];
      final operation = op['operation'] as String? ?? 'upsert';
      final tableName = op['table'] as String? ?? '';
      final rawData = op['data'];
      final Map<String, dynamic>? data = rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : null;
      final pkColumn = op['primary_key_column'] as String?;
      final pkValue = op['primary_key_value'];

      try {
        if (operation == 'upsert' && data != null) {
          await client.from(tableName).upsert(data);
        } else if (operation == 'upsert_items') {
          // Child items queued offline (estimate items, purchase items).
          // Replay as a safe upsert — never delete-then-insert.
          final rawItems = op['items'];
          if (rawItems is List && rawItems.isNotEmpty) {
            final itemsPayload = rawItems
                .map((i) => Map<String, dynamic>.from(i as Map))
                .toList();
            // Determine conflict column from table name
            final conflictCol = tableName == 'inward_estimate_items' ? 'line_id' : 'line_id';
            await client.from(tableName).upsert(itemsPayload, onConflict: conflictCol);
          }
        } else if (operation == 'delete' && pkColumn != null) {
          await client.from(tableName).delete().eq(pkColumn, pkValue);
          // Also write tombstone for delete operations
          try {
            await client.from('deleted_records').upsert({
              'id': _generateUuid(),
              'table_name': tableName,
              'record_id': pkValue.toString(),
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
            }, onConflict: 'table_name,record_id');
          } catch (_) {}
        }
        // Success: remove from queue
        await localDb.removePendingSyncEntry(hiveKey);
        if (kDebugMode) print('Flushed offline op: $operation on $tableName');
      } catch (e) {
        final errStr = e.toString();
        if (kDebugMode) print('Offline flush failed for $tableName: $e');
        // If error is unrecoverable schema mismatch or duplicate key, purge from local pending queue
        if (errStr.contains('PGRST204') || errStr.contains('23505') || errStr.contains('schema cache')) {
          await localDb.removePendingSyncEntry(hiveKey);
        }
      }
    }
  }

  // ─── Offline-Aware Push ────────────────────────────────────────────────────
  /// Pushes all pre-existing local Hive records to Supabase Cloud.
  /// NOTE: This is intentionally NOT called on startup to prevent ghost
  /// resurrection. It is kept as an admin-only "Force Re-sync" function.
  Future<void> pushAllLocalRecordsToCloud(LocalDatabaseService localDb) async {
    if (!_isInitialized) return;

    try {
      final client = Supabase.instance.client;

      // Inward Repairs & items
      final repairs = localDb.getInwardRepairs();
      if (repairs.isNotEmpty) {
        await client
            .from('inward_repairs')
            .upsert(repairs.map((e) => e.toJson()).toList());
        final allItems = <Map<String, dynamic>>[];
        for (final r in repairs) {
          allItems.addAll(
            localDb.getInwardEstimateItems(r.jobNo).map((i) => i.toJson()),
          );
        }
        if (allItems.isNotEmpty) {
          await client.from('inward_estimate_items').upsert(allItems);
        }
      }

      // Replacements
      final replacements = localDb.getReplacements();
      if (replacements.isNotEmpty) {
        await client
            .from('replacements')
            .upsert(replacements.map((e) => e.toJson()).toList());
      }

      // Requests
      final requests = localDb.getRequestOrders();
      if (requests.isNotEmpty) {
        await client
            .from('requests')
            .upsert(requests.map((e) => e.toJson()).toList());
      }

      // Calls
      final calls = localDb.getCalls();
      if (calls.isNotEmpty) {
        await client
            .from('calls')
            .upsert(calls.map((e) => e.toJson()).toList());
      }

      // Sales & items
      final sales = localDb.getSales();
      if (sales.isNotEmpty) {
        await client
            .from('sales')
            .upsert(sales.map((e) => e.toJson()).toList());
        final allSaleItems = <Map<String, dynamic>>[];
        for (final s in sales) {
          allSaleItems.addAll(
            localDb.getSaleItems(s.invoiceNo).map((i) => i.toJson()),
          );
        }
        if (allSaleItems.isNotEmpty) {
          await client.from('sale_items').upsert(allSaleItems);
        }
      }

      // Purchases & items
      final purchases = localDb.getPurchaseOrders();
      if (purchases.isNotEmpty) {
        await client
            .from('purchases')
            .upsert(purchases.map((e) => e.toJson()).toList());
        final allPurchaseItems = <Map<String, dynamic>>[];
        for (final p in purchases) {
          allPurchaseItems.addAll(
            localDb.getPurchaseOrderItems(p.id).map((i) => i.toSupabaseJson()),
          );
        }
        if (allPurchaseItems.isNotEmpty) {
          await client.from('purchase_order_items').upsert(allPurchaseItems);
        }
      }

      // Pricelist
      final pricelist = localDb.getPricelist();
      if (pricelist.isNotEmpty) {
        await client
            .from('pricelist')
            .upsert(pricelist.map((e) => e.toJson()).toList());
      }

      // Users & Permissions
      final users = UserPermissionService.getAllUsers();
      for (final u in users) {
        await UserPermissionService.saveUser(u);
      }

      // Shop Settings (Active UPI, UPI list, UPI reference names)
      final activeUpi = localDb.getActiveUpiId();
      if (activeUpi != null) {
        await client.from('shop_settings').upsert({
          'key': 'active_upi_id',
          'value': activeUpi,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
      final upiList = localDb.getUpiIdsList();
      await client.from('shop_settings').upsert({
        'key': 'upi_ids_list',
        'value': upiList,
        'updated_at': DateTime.now().toIso8601String(),
      });
      final upiNames = localDb.getUpiNamesMap();
      await client.from('shop_settings').upsert({
        'key': 'upi_names_map',
        'value': upiNames,
        'updated_at': DateTime.now().toIso8601String(),
      });
      final statusColors = StatusManagementService.getAllStatusColors();
      if (statusColors.isNotEmpty) {
        await client.from('shop_settings').upsert({
          'key': 'shop_status_colors',
          'value': statusColors,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
      final customStatuses = StatusManagementService.getAllCustomStatusLists();
      if (customStatuses.isNotEmpty) {
        await client.from('shop_settings').upsert({
          'key': 'shop_custom_statuses',
          'value': customStatuses,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
      final defaultStatuses = StatusManagementService.getAllDefaultStatuses();
      if (defaultStatuses.isNotEmpty) {
        await client.from('shop_settings').upsert({
          'key': 'shop_default_statuses',
          'value': defaultStatuses,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      if (kDebugMode) print('Push all local error: $e');
    }
  }

  DateTime? _lastFullSyncTime;

  // ─── Cloud → Local Sync ────────────────────────────────────────────────────
  /// Fetches authoritative data from Supabase and mirrors into local Hive.
  /// Uses Delta Sync (updated_at filter) to download only changed rows,
  /// preserving 0ms local reads while reducing Egress by >90%.
  Future<void> syncAllTablesFromCloud(LocalDatabaseService localDb, {bool force = false, bool forceDelta = false}) async {
    if (!_isInitialized) return;

    // Throttling: If synced less than 15s ago and neither force nor forceDelta, skip to save egress
    final now = DateTime.now();
    if (!force && !forceDelta && _lastFullSyncTime != null && now.difference(_lastFullSyncTime!).inSeconds < 15) {
      if (kDebugMode) print('Sync skipped: synced recently (${now.difference(_lastFullSyncTime!).inSeconds}s ago)');
      return;
    }

    try {
      _setStatus(SyncStatus.syncing, 'Syncing changes from cloud...');
      final client = Supabase.instance.client;

      final lastSyncMillis = (UiPreferencesService.getValue('last_full_sync_timestamp') as num?)?.toInt() ?? 0;
      final String? lastSyncIso = (!force && lastSyncMillis > 0)
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncMillis - 1800000, isUtc: true).toIso8601String()
          : null;
      final bool isDelta = lastSyncIso != null;

      if (kDebugMode) {
        print(isDelta
            ? '[SupabaseSync] Performing Delta Sync for changes after $lastSyncIso'
            : '[SupabaseSync] Performing Full Sync');
      }

      // ── Parallel Cloud Fetch: Run all independent table queries concurrently ──
      var tombstoneQuery = client.from('deleted_records').select();
      if (isDelta) tombstoneQuery = tombstoneQuery.gte('deleted_at', lastSyncIso);

      // Lightweight column select includes photo storage URLs while accelerating sync
      var inwardQuery = client.from('inward_repairs').select('job_no,date,name,mobile_no,devices,query,purchased_from,notes,status,completion_date,updated_at,discount,photo');
      var inwardItemsQuery = client.from('inward_estimate_items').select();
      if (isDelta) {
        inwardQuery = inwardQuery.gte('updated_at', lastSyncIso);
        inwardItemsQuery = inwardItemsQuery.gte('updated_at', lastSyncIso);
      }

      var replacementQuery = client.from('replacements').select();
      if (isDelta) replacementQuery = replacementQuery.gte('updated_at', lastSyncIso);

      var requestQuery = client.from('requests').select();
      if (isDelta) requestQuery = requestQuery.gte('updated_at', lastSyncIso);

      var callQuery = client.from('calls').select();
      if (isDelta) callQuery = callQuery.gte('updated_at', lastSyncIso);

      var salesQuery = client.from('sales').select();
      var salesItemsQuery = client.from('sale_items').select();
      if (isDelta) {
        salesQuery = salesQuery.gte('updated_at', lastSyncIso);
        salesItemsQuery = salesItemsQuery.gte('updated_at', lastSyncIso);
      }

      var purchaseQuery = client.from('purchases').select();
      var purchaseItemsQuery = client.from('purchase_order_items').select();
      if (isDelta) {
        purchaseQuery = purchaseQuery.gte('updated_at', lastSyncIso);
        purchaseItemsQuery = purchaseItemsQuery.gte('updated_at', lastSyncIso);
      }

      var pricelistQuery = client.from('pricelist').select();
      if (isDelta) pricelistQuery = pricelistQuery.gte('updated_at', lastSyncIso);

      var settingsQuery = client.from('shop_settings').select();
      if (isDelta) settingsQuery = settingsQuery.gte('updated_at', lastSyncIso);

      int queryErrors = 0;

      // Batch 1: Deletions, Inward Repairs, Estimate Items, Calls (max 4 concurrent connections)
      final batch1 = await Future.wait([
        tombstoneQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Tombstone query skipped: $e');
          return <Map<String, dynamic>>[];
        }),
        inwardQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Inward query error: $e');
          return <Map<String, dynamic>>[];
        }),
        inwardItemsQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Inward items query error: $e');
          return <Map<String, dynamic>>[];
        }),
        callQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Calls query error: $e');
          return <Map<String, dynamic>>[];
        }),
      ]);

      // Batch 2: Sales, Sale Items, Replacements, Requests
      final batch2 = await Future.wait([
        salesQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Sales query error: $e');
          return <Map<String, dynamic>>[];
        }),
        salesItemsQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Sale items query error: $e');
          return <Map<String, dynamic>>[];
        }),
        replacementQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Replacements query error: $e');
          return <Map<String, dynamic>>[];
        }),
        requestQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Requests query error: $e');
          return <Map<String, dynamic>>[];
        }),
      ]);

      // Batch 3: Purchases, Purchase Order Items, Pricelist, Settings
      final batch3 = await Future.wait([
        purchaseQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Purchases query error: $e');
          return <Map<String, dynamic>>[];
        }),
        purchaseItemsQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Purchase items query error: $e');
          return <Map<String, dynamic>>[];
        }),
        pricelistQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Pricelist query error: $e');
          return <Map<String, dynamic>>[];
        }),
        settingsQuery.limit(50000).timeout(const Duration(seconds: 20)).catchError((e) {
          queryErrors++;
          if (kDebugMode) print('Shop settings query error: $e');
          return <Map<String, dynamic>>[];
        }),
      ]);

      if (queryErrors >= 10) {
        throw TimeoutException('Server Offline / Unreachable');
      }

      final deletions = (batch1[0] as List).cast<Map<String, dynamic>>();
      final inwardData = (batch1[1] as List).cast<Map<String, dynamic>>();
      final inwardItemsData = (batch1[2] as List).cast<Map<String, dynamic>>();
      final callData = (batch1[3] as List).cast<Map<String, dynamic>>();

      final salesData = (batch2[0] as List).cast<Map<String, dynamic>>();
      final salesItemsData = (batch2[1] as List).cast<Map<String, dynamic>>();
      final replacementData = (batch2[2] as List).cast<Map<String, dynamic>>();
      final requestData = (batch2[3] as List).cast<Map<String, dynamic>>();

      final purchaseData = (batch3[0] as List).cast<Map<String, dynamic>>();
      final purchaseItemsData = (batch3[1] as List).cast<Map<String, dynamic>>();
      final pricelistData = (batch3[2] as List).cast<Map<String, dynamic>>();
      final settingsData = (batch3[3] as List).cast<Map<String, dynamic>>();

      // ── Step 0: Apply remote deletions (tombstones with freshness guard) ───
      for (final d in deletions) {
        final tbl = d['table_name']?.toString() ?? '';
        final rid = d['record_id']?.toString();
        if (rid == null || rid.isEmpty) continue;
        final deletedAtStr = d['deleted_at']?.toString();
        final deletedAt = deletedAtStr != null ? DateTime.tryParse(deletedAtStr) : null;

        switch (tbl) {
          case 'inward_repairs':
            final id = int.tryParse(rid) ?? -1;
            final local = localDb.getInwardRepairByJobNo(id);
            if (local != null && deletedAt != null && local.updatedAt.isAfter(deletedAt)) continue;
            await localDb.deleteInwardRepair(id);
          case 'calls':
            final id = int.tryParse(rid) ?? -1;
            final local = localDb.getCallById(id);
            if (local != null && deletedAt != null) {
              final upStr = local['updated_at']?.toString();
              final up = upStr != null ? DateTime.tryParse(upStr) : null;
              if (up != null && up.isAfter(deletedAt)) continue;
            }
            await localDb.deleteCall(id);
          case 'sales':
            final id = int.tryParse(rid) ?? -1;
            final sales = localDb.getSales();
            final local = sales.where((s) => s.invoiceNo == id).firstOrNull;
            if (local != null && deletedAt != null && local.updatedAt.isAfter(deletedAt)) continue;
            await localDb.deleteSale(id);
          case 'replacements':
            final repls = localDb.getReplacements();
            final local = repls.where((r) => r.jobNo == rid).firstOrNull;
            if (local != null && deletedAt != null && local.updatedAt.isAfter(deletedAt)) continue;
            await localDb.deleteReplacement(rid);
          case 'requests':
            final reqs = localDb.getRequestOrders();
            final local = reqs.where((r) => r.id == rid).firstOrNull;
            if (local != null && deletedAt != null && local.updatedAt.isAfter(deletedAt)) continue;
            await localDb.deleteRequestOrder(rid);
          case 'purchases':
            final purs = localDb.getPurchaseOrders();
            final local = purs.where((p) => p.id == rid).firstOrNull;
            if (local != null && deletedAt != null && local.updatedAt.isAfter(deletedAt)) continue;
            await localDb.deletePurchaseOrder(rid);
          case 'pricelist':
            final id = int.tryParse(rid) ?? -1;
            await localDb.deletePricelistItem(id);
        }
      }

      // ── Step 1: Inward Repairs ─────────────────────────────────────────────
      final repairsMap = <int, Map<String, dynamic>>{};
      final inwardItemsMap = <int, List<Map<String, dynamic>>>{};

      for (final json in inwardData) {
        final cloudRepair = InwardRepair.fromJson(Map<String, dynamic>.from(json));
        Map<String, dynamic> repairJson = cloudRepair.toJson();
        if (cloudRepair.photo == null || cloudRepair.photo!.isEmpty) {
          final hasPhotoKey = json.containsKey('photo');
          if (!hasPhotoKey) {
            final existingLocalRepair = localDb.getInwardRepairByJobNo(cloudRepair.jobNo);
            if (existingLocalRepair != null && existingLocalRepair.photo != null && existingLocalRepair.photo!.isNotEmpty) {
              repairJson['photo'] = existingLocalRepair.photo;
            }
          }
        }
        repairsMap[cloudRepair.jobNo] = repairJson;
      }
      for (final json in inwardItemsData) {
        final jno = int.tryParse(json['job_no']?.toString() ?? '');
        if (jno != null) {
          final item = InwardEstimateItem.fromJson(Map<String, dynamic>.from(json));
          inwardItemsMap.putIfAbsent(jno, () => []).add(item.toJson());
        }
      }
      if (repairsMap.isNotEmpty || inwardItemsMap.isNotEmpty || !isDelta) {
        await localDb.saveAllInwardRepairs(repairsMap, inwardItemsMap, clearOthers: !isDelta);
      }

      // ── Step 2: Replacements ───────────────────────────────────────────────
      final replacementMap = <String, Map<String, dynamic>>{};
      for (final json in replacementData) {
        final repl = Replacement.fromJson(Map<String, dynamic>.from(json));
        replacementMap[repl.jobNo] = repl.toJson();
      }
      if (replacementMap.isNotEmpty || !isDelta) {
        await localDb.saveAllReplacements(replacementMap, clearOthers: !isDelta);
      }

      // ── Step 3: Requests ───────────────────────────────────────────────────
      final requestMap = <String, Map<String, dynamic>>{};
      for (final json in requestData) {
        final req = RequestOrder.fromJson(Map<String, dynamic>.from(json));
        requestMap[req.id] = req.toJson();
      }
      if (requestMap.isNotEmpty || !isDelta) {
        await localDb.saveAllRequests(requestMap, clearOthers: !isDelta);
      }

      // ── Step 4: Calls ──────────────────────────────────────────────────────
      final callMap = <int, Map<String, dynamic>>{};
      for (final json in callData) {
        final cloudCall = CallModel.fromJson(Map<String, dynamic>.from(json));
        Map<String, dynamic> callJson = cloudCall.toJson();

        if ((cloudCall.photo == null || cloudCall.photo!.isEmpty)) {
          final hasPhotoKey = json.containsKey('photo');
          if (!hasPhotoKey) {
            final localRaw = localDb.getCallById(cloudCall.id);
            if (localRaw != null) {
              final localPhoto = localRaw['photo']?.toString();
              if (localPhoto != null && localPhoto.isNotEmpty) {
                callJson['photo'] = localPhoto;
              }
            }
          }
        }

        callMap[cloudCall.id] = callJson;
      }
      if (callMap.isNotEmpty || !isDelta) {
        await localDb.saveAllCalls(callMap, clearOthers: !isDelta);
      }

      // ── Step 5: Sales ──────────────────────────────────────────────────────
      final salesMap = <int, Map<String, dynamic>>{};
      final salesItemsMap = <int, List<Map<String, dynamic>>>{};

      for (final json in salesData) {
        final sale = Sale.fromJson(Map<String, dynamic>.from(json));
        salesMap[sale.invoiceNo] = sale.toJson();
      }
      for (final json in salesItemsData) {
        final inv = int.tryParse(json['invoice_no']?.toString() ?? '');
        if (inv != null) {
          final item = SaleItem.fromJson(Map<String, dynamic>.from(json));
          salesItemsMap.putIfAbsent(inv, () => []).add(item.toJson());
        }
      }
      if (salesMap.isNotEmpty || salesItemsMap.isNotEmpty || !isDelta) {
        await localDb.saveAllSales(salesMap, salesItemsMap, clearOthers: !isDelta);
      }

      // ── Step 6: Purchases ──────────────────────────────────────────────────
      final purchasesMap = <String, Map<String, dynamic>>{};
      final purchaseItemsMap = <String, List<Map<String, dynamic>>>{};

      for (final json in purchaseData) {
        final pur = PurchaseOrder.fromJson(Map<String, dynamic>.from(json));
        purchasesMap[pur.id] = pur.toJson();
      }
      for (final json in purchaseItemsData) {
        final pid = json['purchase_id']?.toString();
        if (pid != null && pid.isNotEmpty) {
          final item = PurchaseOrderItem.fromJson(Map<String, dynamic>.from(json));
          purchaseItemsMap.putIfAbsent(pid, () => []).add(item.toJson());
        }
      }
      if (purchasesMap.isNotEmpty || purchaseItemsMap.isNotEmpty || !isDelta) {
        await localDb.saveAllPurchases(purchasesMap, purchaseItemsMap, clearOthers: !isDelta);
      }

      // ── Step 7: Pricelist ──────────────────────────────────────────────────
      final pricelistMap = <int, Map<String, dynamic>>{};
      for (final json in pricelistData) {
        final item = PricelistItem.fromJson(Map<String, dynamic>.from(json));
        pricelistMap[item.id] = item.toJson();
      }
      if (pricelistMap.isNotEmpty || !isDelta) {
        await localDb.saveAllPricelistItems(pricelistMap, clearOthers: !isDelta);
        ShopRepository.notifyTableChanged('pricelist_items');
      }

      // ── Step 8: Users & Permissions ────────────────────────────────────────
      await UserPermissionService.syncUsersFromCloud(force: force);

      // ── Step 10: Shop Settings (UPI IDs, Active UPI ID, UPI Names, Status Colors) ──
      try {
        final settingsMap = <String, dynamic>{};
        for (final item in settingsData) {
          final key = item['key']?.toString();
          if (key != null) {
            var val = item['value'];
            if (val is String) {
              final trimmed = val.trim();
              if ((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
                try {
                  val = jsonDecode(trimmed);
                } catch (_) {}
              }
            }
            settingsMap[key] = val;
          }
        }

        if (settingsMap.containsKey('active_upi_id') && settingsMap['active_upi_id'] != null) {
          await localDb.setActiveUpiId(settingsMap['active_upi_id'].toString(), syncToCloud: false);
        } else if (!isDelta) {
          final localActive = localDb.getActiveUpiId();
          if (localActive != null && localActive.isNotEmpty) {
            await client.from('shop_settings').upsert({
              'key': 'active_upi_id',
              'value': localActive,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        }

        if (settingsMap.containsKey('google_review_listing') && settingsMap['google_review_listing'] != null) {
          await localDb.setGoogleReviewListing(settingsMap['google_review_listing'].toString(), syncToCloud: false);
        } else if (!isDelta) {
          final localReview = localDb.getGoogleReviewListing();
          if (localReview.isNotEmpty) {
            await client.from('shop_settings').upsert({
              'key': 'google_review_listing',
              'value': localReview,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        }

        if (settingsMap.containsKey('upi_ids_list') && settingsMap['upi_ids_list'] is List) {
          final list = (settingsMap['upi_ids_list'] as List).map((e) => e.toString()).toList();
          await localDb.saveUpiIdsList(list, syncToCloud: false);
        } else if (!isDelta) {
          final localList = localDb.getUpiIdsList();
          if (localList.isNotEmpty) {
            await client.from('shop_settings').upsert({
              'key': 'upi_ids_list',
              'value': localList,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        }

        if (settingsMap.containsKey('upi_names_map') && settingsMap['upi_names_map'] is Map) {
          final map = Map<String, String>.from(
            (settingsMap['upi_names_map'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
          );
          await localDb.saveUpiNamesMap(map, syncToCloud: false);
        } else if (!isDelta) {
          final localNames = localDb.getUpiNamesMap();
          if (localNames.isNotEmpty) {
            await client.from('shop_settings').upsert({
              'key': 'upi_names_map',
              'value': localNames,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        }

        if (settingsMap.containsKey('shop_custom_statuses') && settingsMap['shop_custom_statuses'] != null) {
          await StatusManagementService.loadFromCustomStatusesMap(settingsMap['shop_custom_statuses']);
        }
        if (settingsMap.containsKey('shop_default_statuses') && settingsMap['shop_default_statuses'] != null) {
          await StatusManagementService.loadFromDefaultStatusesMap(settingsMap['shop_default_statuses']);
        }
        if (settingsMap.containsKey('shop_status_colors') && settingsMap['shop_status_colors'] != null) {
          await StatusManagementService.loadFromStatusColorsMap(settingsMap['shop_status_colors']);
        }

        if (settingsMap.containsKey('custom_services_list') && settingsMap['custom_services_list'] is List) {
          final cloudList = (settingsMap['custom_services_list'] as List).map((e) => e.toString()).toList();
          await localDb.setCustomServicesList(cloudList, syncToCloud: false);
        } else if (!isDelta) {
          final localList = localDb.getCustomServiceNames();
          if (localList.isNotEmpty) {
            await client.from('shop_settings').upsert({
              'key': 'custom_services_list',
              'value': localList,
              'updated_at': DateTime.now().toIso8601String(),
            });
          }
        }
      } catch (e) {
        if (kDebugMode) print('Shop settings sync error: $e');
      }

      _lastFullSyncTime = DateTime.now();
      await UiPreferencesService.setValue('last_full_sync_timestamp', _lastFullSyncTime!.millisecondsSinceEpoch);
      _setStatus(SyncStatus.synced, 'All tables synchronized');
      ShopRepository.notifyTableChanged('all');
    } catch (e) {
      if (kDebugMode) print('Sync from cloud error: $e');
      _setStatus(SyncStatus.error, 'Sync Error: $e');
    }
  }

  /// Real-time targeted delta sync for a single table that changed
  Future<void> syncTableFromCloud(String tableName, LocalDatabaseService localDb) async {
    if (!_isInitialized) return;

    try {
      final client = Supabase.instance.client;
      final lastSyncMillis = (UiPreferencesService.getValue('last_full_sync_timestamp') as num?)?.toInt() ?? 0;
      final String? lastSyncIso = lastSyncMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncMillis - 1800000, isUtc: true).toIso8601String()
          : null;

      // Handle table deletion tombstones
      try {
        var tombstoneQuery = client.from('deleted_records').select();
        if (tableName != 'deleted_records') {
          tombstoneQuery = tombstoneQuery.eq('table_name', tableName);
        }
        if (lastSyncIso != null) {
          tombstoneQuery = tombstoneQuery.gte('deleted_at', lastSyncIso);
        }
        final deletions = await tombstoneQuery.timeout(const Duration(seconds: 25));
        for (final d in deletions) {
          final tbl = d['table_name']?.toString() ?? tableName;
          final rid = d['record_id']?.toString();
          if (rid == null || rid.isEmpty) continue;
          final deletedAtStr = d['deleted_at']?.toString();
          final deletedAt = deletedAtStr != null ? DateTime.tryParse(deletedAtStr) : null;

          switch (tbl) {
            case 'inward_repairs':
              final id = int.tryParse(rid) ?? -1;
              final local = localDb.getInwardRepairByJobNo(id);
              if (local != null && deletedAt != null && local.updatedAt.isAfter(deletedAt)) continue;
              await localDb.deleteInwardRepair(id);
            case 'calls':
              final id = int.tryParse(rid) ?? -1;
              final local = localDb.getCallById(id);
              if (local != null && deletedAt != null) {
                final upStr = local['updated_at']?.toString();
                final up = upStr != null ? DateTime.tryParse(upStr) : null;
                if (up != null && up.isAfter(deletedAt)) continue;
              }
              await localDb.deleteCall(id);
            case 'sales':
              final id = int.tryParse(rid) ?? -1;
              final sales = localDb.getSales();
              final local = sales.where((s) => s.invoiceNo == id).firstOrNull;
              if (local != null && deletedAt != null && local.updatedAt.isAfter(deletedAt)) continue;
              await localDb.deleteSale(id);
            case 'replacements':
              final repls = localDb.getReplacements();
              final local = repls.where((r) => r.jobNo == rid).firstOrNull;
              if (local != null && deletedAt != null && local.updatedAt.isAfter(deletedAt)) continue;
              await localDb.deleteReplacement(rid);
            case 'requests':
              final reqs = localDb.getRequestOrders();
              final local = reqs.where((r) => r.id == rid).firstOrNull;
              if (local != null && deletedAt != null && local.updatedAt.isAfter(deletedAt)) continue;
              await localDb.deleteRequestOrder(rid);
            case 'purchases':
              final purs = localDb.getPurchaseOrders();
              final local = purs.where((p) => p.id == rid).firstOrNull;
              if (local != null && deletedAt != null && local.updatedAt.isAfter(deletedAt)) continue;
              await localDb.deletePurchaseOrder(rid);
            case 'pricelist':
              final id = int.tryParse(rid) ?? -1;
              await localDb.deletePricelistItem(id);
          }
        }
        if (tableName == 'deleted_records') {
          ShopRepository.notifyTableChanged('all');
        }
      } catch (_) {}

      switch (tableName) {
        case 'inward_repairs':
        case 'inward_estimate_items':
          var q = client.from('inward_repairs').select();
          var iq = client.from('inward_estimate_items').select();
          if (lastSyncIso != null) {
            q = q.gte('updated_at', lastSyncIso);
            iq = iq.gte('updated_at', lastSyncIso);
          }
          final inwardData = await q.limit(50000).timeout(const Duration(seconds: 25));
          final inwardItemsData = await iq.limit(50000).timeout(const Duration(seconds: 25));

          final affectedJobs = <int>{};
          for (final json in inwardData) {
            final jno = int.tryParse(json['job_no']?.toString() ?? '');
            if (jno != null) affectedJobs.add(jno);
          }
          for (final json in inwardItemsData) {
            final jno = int.tryParse(json['job_no']?.toString() ?? '');
            if (jno != null) affectedJobs.add(jno);
          }

          if (affectedJobs.isNotEmpty) {
            final fullInwardData = await client
                .from('inward_repairs')
                .select()
                .inFilter('job_no', affectedJobs.toList())
                .limit(50000)
                .timeout(const Duration(seconds: 25));
            final fullItemsData = await client
                .from('inward_estimate_items')
                .select()
                .inFilter('job_no', affectedJobs.toList())
                .limit(50000)
                .timeout(const Duration(seconds: 25));

            final repairsMap = <int, Map<String, dynamic>>{};
            final inwardItemsMap = <int, List<Map<String, dynamic>>>{};

            for (final json in fullInwardData) {
              final cloudRepair = InwardRepair.fromJson(Map<String, dynamic>.from(json));
              Map<String, dynamic> repairJson = cloudRepair.toJson();
              if (cloudRepair.photo == null || cloudRepair.photo!.isEmpty) {
                final hasPhotoKey = json.containsKey('photo');
                if (!hasPhotoKey) {
                  final existingLocalRepair = localDb.getInwardRepairByJobNo(cloudRepair.jobNo);
                  if (existingLocalRepair != null && existingLocalRepair.photo != null && existingLocalRepair.photo!.isNotEmpty) {
                    repairJson['photo'] = existingLocalRepair.photo;
                  }
                }
              }
              repairsMap[cloudRepair.jobNo] = repairJson;
            }

            for (final jno in affectedJobs) {
              final itemsJson = fullItemsData
                  .where((i) => i['job_no']?.toString() == jno.toString())
                  .map((i) => InwardEstimateItem.fromJson(Map<String, dynamic>.from(i)).toJson())
                  .toList();
              inwardItemsMap[jno] = itemsJson;
            }

            await localDb.saveAllInwardRepairs(repairsMap, inwardItemsMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('inward_repairs');
          ShopRepository.notifyTableChanged('all');

        case 'calls':
          var q = client.from('calls').select();
          if (lastSyncIso != null) q = q.gte('updated_at', lastSyncIso);
          final callsData = await q.limit(50000).timeout(const Duration(seconds: 25));
          final callsMap = <int, Map<String, dynamic>>{};
          final List<CallModel> newlyAssignedCalls = [];

          for (final json in callsData) {
            final cloudCall = CallModel.fromJson(Map<String, dynamic>.from(json));
            final localRaw = localDb.getCallById(cloudCall.id);
            final wasAlreadyHere = localRaw != null;
            final prevAssigned = localRaw?['assigned_to']?.toString();

            // If newly assigned to current user (excluding admins / sale user), queue full screen alert popup
            if (UserPermissionService.shouldReceiveCallAlertPopup() &&
                UserPermissionService.isEntryDirectlyAssignedToUser(cloudCall.assignedTo)) {
              if (!wasAlreadyHere || (prevAssigned != cloudCall.assignedTo)) {
                newlyAssignedCalls.add(cloudCall);
              }
            }

            Map<String, dynamic> callJson = cloudCall.toJson();
            if ((cloudCall.photo == null || cloudCall.photo!.isEmpty)) {
              final hasPhotoKey = json.containsKey('photo');
              if (!hasPhotoKey) {
                final localRaw = localDb.getCallById(cloudCall.id);
                if (localRaw != null) {
                  final localPhoto = localRaw['photo']?.toString();
                  if (localPhoto != null && localPhoto.isNotEmpty) {
                    callJson['photo'] = localPhoto;
                  }
                }
              }
            }
            callsMap[cloudCall.id] = callJson;
          }
          if (callsMap.isNotEmpty) {
            await localDb.saveAllCalls(callsMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('calls');
          ShopRepository.notifyTableChanged('all');

          // Trigger full screen alert dialog with soothing chime for newly assigned calls
          if (newlyAssignedCalls.isNotEmpty) {
            for (final call in newlyAssignedCalls) {
              final context = FcmService.navigatorKey?.currentContext;
              if (context != null && context.mounted) {
                CallAlertDialog.show(context, call);
              }
            }
          }

        case 'sales':
        case 'sale_items':
          var q = client.from('sales').select();
          var sq = client.from('sale_items').select();
          if (lastSyncIso != null) {
            q = q.gte('updated_at', lastSyncIso);
            sq = sq.gte('updated_at', lastSyncIso);
          }
          final salesData = await q.limit(50000).timeout(const Duration(seconds: 25));
          final saleItemsData = await sq.limit(50000).timeout(const Duration(seconds: 25));

          final affectedInvoices = <int>{};
          for (final json in salesData) {
            final inv = int.tryParse(json['invoice_no']?.toString() ?? '');
            if (inv != null) affectedInvoices.add(inv);
          }
          for (final json in saleItemsData) {
            final inv = int.tryParse(json['invoice_no']?.toString() ?? '');
            if (inv != null) affectedInvoices.add(inv);
          }

          if (affectedInvoices.isNotEmpty) {
            final fullSalesData = await client
                .from('sales')
                .select()
                .inFilter('invoice_no', affectedInvoices.toList())
                .limit(50000)
                .timeout(const Duration(seconds: 25));
            final fullSaleItemsData = await client
                .from('sale_items')
                .select()
                .inFilter('invoice_no', affectedInvoices.toList())
                .limit(50000)
                .timeout(const Duration(seconds: 25));

            final salesMap = <int, Map<String, dynamic>>{};
            final saleItemsMap = <int, List<Map<String, dynamic>>>{};

            for (final json in fullSalesData) {
              final sale = Sale.fromJson(Map<String, dynamic>.from(json));
              salesMap[sale.invoiceNo] = sale.toJson();
            }

            for (final inv in affectedInvoices) {
              final itemsJson = fullSaleItemsData
                  .where((i) => i['invoice_no']?.toString() == inv.toString())
                  .map((i) => SaleItem.fromJson(Map<String, dynamic>.from(i)).toJson())
                  .toList();
              saleItemsMap[inv] = itemsJson;
            }

            await localDb.saveAllSales(salesMap, saleItemsMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('sales');
          ShopRepository.notifyTableChanged('all');

        case 'replacements':
          var q = client.from('replacements').select();
          if (lastSyncIso != null) q = q.gte('updated_at', lastSyncIso);
          final replData = await q.limit(50000).timeout(const Duration(seconds: 25));
          final replMap = <String, Map<String, dynamic>>{};
          for (final json in replData) {
            final repl = Replacement.fromJson(Map<String, dynamic>.from(json));
            replMap[repl.jobNo] = repl.toJson();
          }
          if (replMap.isNotEmpty) {
            await localDb.saveAllReplacements(replMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('replacements');
          ShopRepository.notifyTableChanged('all');

        case 'requests':
          var q = client.from('requests').select();
          if (lastSyncIso != null) q = q.gte('updated_at', lastSyncIso);
          final reqData = await q.limit(50000).timeout(const Duration(seconds: 25));
          final reqMap = <String, Map<String, dynamic>>{};
          for (final json in reqData) {
            final req = RequestOrder.fromJson(Map<String, dynamic>.from(json));
            reqMap[req.id] = req.toJson();
          }
          if (reqMap.isNotEmpty) {
            await localDb.saveAllRequests(reqMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('requests');
          ShopRepository.notifyTableChanged('all');

        case 'purchases':
        case 'purchase_items':
        case 'purchase_order_items':
          var q = client.from('purchases').select();
          var pq = client.from('purchase_order_items').select();
          if (lastSyncIso != null) {
            q = q.gte('updated_at', lastSyncIso);
            pq = pq.gte('updated_at', lastSyncIso);
          }
          final purchData = await q.limit(50000).timeout(const Duration(seconds: 25));
          final purchItemsData = await pq.limit(50000).timeout(const Duration(seconds: 25));

          final affectedPurchases = <String>{};
          for (final json in purchData) {
            final pid = json['id']?.toString();
            if (pid != null && pid.isNotEmpty) affectedPurchases.add(pid);
          }
          for (final json in purchItemsData) {
            final pid = json['purchase_id']?.toString();
            if (pid != null && pid.isNotEmpty) affectedPurchases.add(pid);
          }

          if (affectedPurchases.isNotEmpty) {
            final fullPurchData = await client
                .from('purchases')
                .select()
                .inFilter('id', affectedPurchases.toList())
                .limit(50000)
                .timeout(const Duration(seconds: 25));
            final fullItemsData = await client
                .from('purchase_order_items')
                .select()
                .inFilter('purchase_id', affectedPurchases.toList())
                .limit(50000)
                .timeout(const Duration(seconds: 25));

            final purchMap = <String, Map<String, dynamic>>{};
            final purchItemsMap = <String, List<Map<String, dynamic>>>{};

            for (final json in fullPurchData) {
              final pur = PurchaseOrder.fromJson(Map<String, dynamic>.from(json));
              purchMap[pur.id] = pur.toJson();
            }

            for (final pid in affectedPurchases) {
              final itemsJson = fullItemsData
                  .where((i) => i['purchase_id']?.toString() == pid)
                  .map((i) => PurchaseOrderItem.fromJson(Map<String, dynamic>.from(i)).toJson())
                  .toList();
              purchItemsMap[pid] = itemsJson;
            }

            await localDb.saveAllPurchases(purchMap, purchItemsMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('purchases');
          ShopRepository.notifyTableChanged('all');

        case 'pricelist':
        case 'pricelist_items':
          var q = client.from('pricelist').select();
          if (lastSyncIso != null) q = q.gte('updated_at', lastSyncIso);
          final priceData = await q.limit(50000).timeout(const Duration(seconds: 25));
          final priceMap = <int, Map<String, dynamic>>{};
          for (final json in priceData) {
            final item = PricelistItem.fromJson(Map<String, dynamic>.from(json));
            priceMap[item.id] = item.toJson();
          }
          if (priceMap.isNotEmpty) {
            await localDb.saveAllPricelistItems(priceMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('pricelist_items');
          ShopRepository.notifyTableChanged('all');

        case 'app_users':
          await UserPermissionService.syncUsersFromCloud(force: true);
          // Broadcast 'all' so every view model re-reads fresh permission/status data
          ShopRepository.notifyTableChanged('app_users');
          ShopRepository.notifyTableChanged('all');


        case 'shop_settings':
          final settingsData = await client.from('shop_settings').select().timeout(const Duration(seconds: 25));
          for (final row in settingsData) {
            final key = row['key']?.toString();
            var value = row['value'];
            if (value is String) {
              final trimmed = value.trim();
              if ((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
                try {
                  value = jsonDecode(trimmed);
                } catch (_) {}
              }
            }
            if (key == 'upi_ids_list' && value is List) {
              await localDb.saveUpiIdsList(List<String>.from(value.map((e) => e.toString())), syncToCloud: false);
            } else if (key == 'active_upi_id' && value != null) {
              await localDb.setActiveUpiId(value.toString(), syncToCloud: false);
            } else if (key == 'google_review_listing' && value != null) {
              await localDb.setGoogleReviewListing(value.toString(), syncToCloud: false);
            } else if (key == 'upi_names_map' && value is Map) {
              final map = Map<String, String>.from(value.map((k, v) => MapEntry(k.toString(), v.toString())));
              await localDb.saveUpiNamesMap(map, syncToCloud: false);
            } else if (key == 'shop_custom_statuses' && value != null) {
              await StatusManagementService.loadFromCustomStatusesMap(value);
            } else if (key == 'shop_default_statuses' && value != null) {
              await StatusManagementService.loadFromDefaultStatusesMap(value);
            } else if (key == 'shop_status_colors' && value != null) {
              await StatusManagementService.loadFromStatusColorsMap(value);
            } else if (key == 'custom_services_list' && value is List) {
              final cloudList = List<String>.from(value.map((e) => e.toString()));
              await localDb.setCustomServicesList(cloudList, syncToCloud: false);
              ShopRepository.notifyTableChanged('custom_services');
            }
          }
          ShopRepository.notifyTableChanged('shop_settings');
          ShopRepository.notifyTableChanged('all');
      }

      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Delta sync error ($tableName): $e');
    }
  }

  // ─── Offline-Aware Push ────────────────────────────────────────────────────
  /// Uploads a single record to Supabase table when created/edited locally.
  /// If the device is offline (push fails), the operation is saved to the
  /// offline queue and will be retried on next sync / app open.
  Future<void> pushRecordToCloud(
    String tableName,
    Map<String, dynamic> data, {
    LocalDatabaseService? localDb,
  }) async {
    final payload = Map<String, dynamic>.from(data);
    payload['updated_at'] = DateTime.now().toUtc().toIso8601String();

    if (!_isInitialized) {
      if (localDb != null) {
        await localDb.enqueuePendingSync({
          'operation': 'upsert',
          'table': tableName,
          'data': payload,
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      _setStatus(SyncStatus.error, 'Offline: Not connected to cloud ($tableName queued)');
      return;
    }

    try {
      _setStatus(SyncStatus.syncing, 'Syncing change...');
      final client = Supabase.instance.client;
      try {
        await client.from(tableName).upsert(payload);
      } catch (e) {
        // If cloud table doesn't have discount column yet, fallback without discount field
        if (payload.containsKey('discount')) {
          final fallbackData = Map<String, dynamic>.from(payload)
            ..remove('discount');
          await client.from(tableName).upsert(fallbackData);
        } else {
          rethrow;
        }
      }

      // Purge any existing tombstone for this record so old deletions never kill this live record
      final pkVal = payload['invoice_no'] ?? payload['job_no'] ?? payload['id'];
      if (pkVal != null) {
        try {
          await client
              .from('deleted_records')
              .delete()
              .eq('table_name', tableName)
              .eq('record_id', pkVal.toString());
        } catch (_) {}
      }

      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Push to cloud error ($tableName): $e — queuing for offline retry');
      // Queue for retry when device comes back online
      if (localDb != null) {
        await localDb.enqueuePendingSync({
          'operation': 'upsert',
          'table': tableName,
          'data': payload,
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        });
        _setStatus(SyncStatus.error, 'Push failed for $tableName: $e (Queued offline)');
      } else {
        _setStatus(SyncStatus.error, 'Sync Error ($tableName): $e');
      }
    }
  }

  /// Deletes all inward estimate items for a given job_no
  Future<void> deleteEstimateItemsForJob(int jobNo) async {
    if (!_isInitialized) return;

    try {
      final client = Supabase.instance.client;
      await client.from('inward_estimate_items').delete().eq('job_no', jobNo);
    } catch (e) {
      if (kDebugMode) print('Delete estimate items error ($jobNo): $e');
    }
  }

  /// Deletes all sale items for a given invoice_no before updating
  Future<void> deleteSaleItemsForInvoice(int invoiceNo) async {
    if (!_isInitialized) return;

    try {
      final client = Supabase.instance.client;
      await client.from('sale_items').delete().eq('invoice_no', invoiceNo);
    } catch (e) {
      if (kDebugMode) print('Delete sale items error ($invoiceNo): $e');
    }
  }

  /// Batch saves estimate items for a job after parent inward repair is saved.
  /// OFFLINE-SAFE: queues the full item list when offline so items are never lost.
  /// RACE-SAFE: uses upsert + targeted delete instead of delete-then-insert so
  /// a network blip between the two operations can never destroy cloud items.
  Future<void> saveEstimateItemsForJob(
    int jobNo,
    List<InwardEstimateItem> items, {
    LocalDatabaseService? localDb,
  }) async {
    if (!_isInitialized) {
      // Offline: queue items so they sync when connectivity is restored.
      if (localDb != null) {
        final payload = items.map((e) {
          final m = e.toJson();
          m['updated_at'] = DateTime.now().toUtc().toIso8601String();
          return m;
        }).toList();
        await localDb.enqueuePendingSync({
          'operation': 'upsert_items',
          'table': 'inward_estimate_items',
          'parent_key_column': 'job_no',
          'parent_key_value': jobNo,
          'items': payload,
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        });
        _setStatus(SyncStatus.error, 'Offline: estimate items queued for job $jobNo');
      }
      return;
    }

    try {
      _setStatus(SyncStatus.syncing, 'Syncing estimate items...');
      final client = Supabase.instance.client;
      final now = DateTime.now().toUtc().toIso8601String();

      // Step 1: Upsert all current items (safe — idempotent on line_id)
      if (items.isNotEmpty) {
        final payload = items.map((e) {
          final m = e.toJson();
          m['updated_at'] = now;
          return m;
        }).toList();
        await client.from('inward_estimate_items').upsert(payload, onConflict: 'line_id');
      }

      // Step 2: Delete only removed items by comparing with the incoming list.
      // This is safer than DELETE-all-then-insert because if the upsert above
      // succeeds but the delete fails, no data is lost (just orphaned rows).
      final incomingLineIds = items.map((e) => e.lineId).toSet();
      final cloudItems = await client
          .from('inward_estimate_items')
          .select('line_id')
          .eq('job_no', jobNo);
      final cloudLineIds = (cloudItems as List)
          .map((r) => r['line_id']?.toString())
          .whereType<String>()
          .toSet();
      final toDelete = cloudLineIds.difference(incomingLineIds);
      if (toDelete.isNotEmpty) {
        await client
            .from('inward_estimate_items')
            .delete()
            .inFilter('line_id', toDelete.toList());
      }

      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Save estimate items cloud error ($jobNo): $e');
      // Queue for retry on next flush
      if (localDb != null) {
        final payload = items.map((e) {
          final m = e.toJson();
          m['updated_at'] = DateTime.now().toUtc().toIso8601String();
          return m;
        }).toList();
        await localDb.enqueuePendingSync({
          'operation': 'upsert_items',
          'table': 'inward_estimate_items',
          'parent_key_column': 'job_no',
          'parent_key_value': jobNo,
          'items': payload,
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      _setStatus(SyncStatus.error, 'Sync Error (Estimate Items): $e');
    }
  }

  /// Batch saves purchase order items after parent purchase order is saved.
  /// OFFLINE-SAFE: queues the full item list when offline so items are never lost.
  /// RACE-SAFE: uses upsert + targeted delete instead of delete-then-insert.
  Future<void> savePurchaseItemsForPurchase(
    String purchaseId,
    List<PurchaseOrderItem> items, {
    LocalDatabaseService? localDb,
  }) async {
    if (!_isInitialized) {
      // Offline: queue items so they sync when connectivity is restored.
      if (localDb != null) {
        final payload = items.map((e) {
          final m = e.toSupabaseJson();
          m['updated_at'] = DateTime.now().toUtc().toIso8601String();
          return m;
        }).toList();
        await localDb.enqueuePendingSync({
          'operation': 'upsert_items',
          'table': 'purchase_order_items',
          'parent_key_column': 'purchase_id',
          'parent_key_value': purchaseId,
          'items': payload,
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        });
        _setStatus(SyncStatus.error, 'Offline: purchase items queued for $purchaseId');
      }
      return;
    }

    try {
      _setStatus(SyncStatus.syncing, 'Syncing purchase items...');
      final client = Supabase.instance.client;
      final now = DateTime.now().toUtc().toIso8601String();

      // Step 1: Upsert all current items (safe — idempotent on line_id)
      if (items.isNotEmpty) {
        final payload = items.map((e) {
          final m = e.toSupabaseJson();
          m['updated_at'] = now;
          return m;
        }).toList();
        await client.from('purchase_order_items').upsert(payload, onConflict: 'line_id');
      }

      // Step 2: Delete only removed items by comparing with the incoming list.
      final incomingLineIds = items.map((e) => e.lineId).toSet();
      final cloudItems = await client
          .from('purchase_order_items')
          .select('line_id')
          .eq('purchase_id', purchaseId);
      final cloudLineIds = (cloudItems as List)
          .map((r) => r['line_id']?.toString())
          .whereType<String>()
          .toSet();
      final toDelete = cloudLineIds.difference(incomingLineIds);
      if (toDelete.isNotEmpty) {
        await client
            .from('purchase_order_items')
            .delete()
            .inFilter('line_id', toDelete.toList());
      }

      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Save purchase items cloud error ($purchaseId): $e');
      // Queue for retry on next flush
      if (localDb != null) {
        final payload = items.map((e) {
          final m = e.toSupabaseJson();
          m['updated_at'] = DateTime.now().toUtc().toIso8601String();
          return m;
        }).toList();
        await localDb.enqueuePendingSync({
          'operation': 'upsert_items',
          'table': 'purchase_order_items',
          'parent_key_column': 'purchase_id',
          'parent_key_value': purchaseId,
          'items': payload,
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      _setStatus(SyncStatus.error, 'Sync Error (Purchase Items): $e');
    }
  }

  // ─── Delete with Tombstone ────────────────────────────────────────────────
  /// Deletes a record from Supabase AND writes a tombstone so that all other
  /// devices will also delete this record on their next sync.
  Future<void> deleteRecordFromCloud(
    String tableName,
    String primaryKeyColumn,
    dynamic idValue, {
    LocalDatabaseService? localDb,
  }) async {
    if (!_isInitialized) {
      // Offline: queue the delete
      if (localDb != null) {
        await localDb.enqueuePendingSync({
          'operation': 'delete',
          'table': tableName,
          'primary_key_column': primaryKeyColumn,
          'primary_key_value': idValue.toString(),
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      _setStatus(SyncStatus.error, 'Offline: Delete queued for $tableName');
      return;
    }

    try {
      _setStatus(SyncStatus.syncing, 'Deleting from cloud...');
      final client = Supabase.instance.client;

      // 1. Delete the actual record
      await client.from(tableName).delete().eq(primaryKeyColumn, idValue);

      // 2. Write tombstone so all other devices delete it on their next sync
      try {
        await client.from('deleted_records').upsert({
          'id': _generateUuid(),
          'table_name': tableName,
          'record_id': idValue.toString(),
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'table_name,record_id');
      } catch (e) {
        if (kDebugMode) print('Tombstone write failed (non-critical): $e');
      }

      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Delete from cloud error ($tableName): $e');
      // Queue for offline retry
      if (localDb != null) {
        await localDb.enqueuePendingSync({
          'operation': 'delete',
          'table': tableName,
          'primary_key_column': primaryKeyColumn,
          'primary_key_value': idValue.toString(),
          'queued_at': DateTime.now().toIso8601String(),
        });
        _setStatus(SyncStatus.offline, 'Saved Offline — will sync when connected');
      } else {
        _setStatus(SyncStatus.error, 'Delete Error: $e');
      }
    }
  }

  static String _generateUuid() {
    final rnd = Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
import 'ui_preferences_service.dart';

enum SyncStatus { offline, syncing, synced, error }

class SupabaseSyncService extends ChangeNotifier {
  static const String _boxName = 'ui_preferences';
  static const String _urlKey = 'supabase_project_url';
  static const String _keyKey = 'supabase_anon_key';
  static const String _defaultUrl =
      'https://seminar-antidote-abrasion.ngrok-free.dev';
  static const String _defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

  static final SupabaseSyncService instance = SupabaseSyncService._internal();
  SupabaseSyncService._internal();

  String? _supabaseUrl;
  String? _supabaseAnonKey;
  bool _isInitialized = false;
  SyncStatus _status = SyncStatus.offline;
  String _statusMessage = 'Not Connected';
  RealtimeChannel? _realtimeChannel;

  // Debounce timer to prevent realtime event flood
  Timer? _debounceTimer;
  Timer? _heartbeatTimer;

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

  /// Background passive health monitor every 3 minutes (180s) to save 95% bandwidth.
  /// Only pings if the connection was marked offline or encountered an error.
  void _startHeartbeat(LocalDatabaseService localDb) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 3), (_) async {
      if (!_isInitialized) return;
      // If already live synced and healthy via WebSocket, skip HTTP egress
      if (_status == SyncStatus.synced) return;

      try {
        final client = Supabase.instance.client;
        await client.from('shop_settings').select('key').limit(1).timeout(const Duration(seconds: 4));
        _setStatus(SyncStatus.synced, 'Live Synced');
        unawaited(flushOfflineQueue(localDb));
      } catch (e) {
        if (_status != SyncStatus.syncing) {
          _setStatus(SyncStatus.offline, 'Cloud Connection Offline');
        }
      }
    });
  }

  /// On startup: pull from cloud, then flush any offline-queued operations.
  /// We do NOT push all local data — cloud is the single source of truth.
  Future<void> _performBackgroundSync(LocalDatabaseService localDb) async {
    try {
      // 1. Pull authoritative data from cloud into local
      await syncAllTablesFromCloud(localDb);
      // 2. Flush any operations queued while the device was offline
      await flushOfflineQueue(localDb);
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
    // Anti-spam debounce: If clicked rapidly within 3 seconds, do instant local UI refresh without network hammering
    if (!forceFullDownload && _lastManualTapTime != null && now.difference(_lastManualTapTime!).inSeconds < 3) {
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

    _setStatus(SyncStatus.syncing, 'Checking connection & syncing...');

    // Proactively probe server reachability for instant online/offline reflection
    try {
      final client = Supabase.instance.client;
      await client.from('shop_settings').select('key').limit(1).timeout(const Duration(milliseconds: 2500));
    } catch (e) {
      if (kDebugMode) print('Manual sync connectivity probe failed: $e');
      _setStatus(SyncStatus.error, 'Server Offline / Unreachable: $e');
      ShopRepository.notifyTableChanged('all');
      return;
    }

    try {
      await syncAllTablesFromCloud(localDb, force: forceFullDownload)
          .timeout(const Duration(seconds: 15));
      await flushOfflineQueue(localDb)
          .timeout(const Duration(seconds: 10));
      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Manual sync error: $e');
      _setStatus(SyncStatus.error, 'Sync Error: $e');
    } finally {
      // Always broadcast full UI refresh using local device resources (0 cloud egress)
      ShopRepository.notifyTableChanged('all');
    }
  }

  void _setStatus(SyncStatus status, String message) {
    _status = status;
    _statusMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  /// Subscribes to real-time table mutations broadcast by Supabase.
  /// Uses native WebSocket status & debounced targeted delta sync to fetch only new/modified rows per table.
  void _subscribeRealtime(LocalDatabaseService localDb) {
    try {
      _realtimeChannel?.unsubscribe();
      final client = Supabase.instance.client;

      final pendingTables = <String>{};

      _realtimeChannel = client.channel('public-db-changes')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          callback: (payload) {
            final table = payload.table;
            if (kDebugMode) print('Realtime change event on table: $table');
            pendingTables.add(table);
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
              final tablesToSync = Set<String>.from(pendingTables);
              pendingTables.clear();
              for (final t in tablesToSync) {
                await syncTableFromCloud(t, localDb);
              }
            });
          },
        )
        ..subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            if (kDebugMode) print('Supabase Realtime subscribed successfully');
            if (_status != SyncStatus.syncing) {
              _setStatus(SyncStatus.synced, 'Live Synced');
            }
            unawaited(flushOfflineQueue(localDb));
          } else if (status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            if (kDebugMode) print('Supabase Realtime connection state: $status (error: $error)');
            if (_status != SyncStatus.syncing) {
              _setStatus(SyncStatus.offline, 'Reconnecting to cloud...');
            }
          }
        });
    } catch (e) {
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
      final data = op['data'] as Map<String, dynamic>?;
      final pkColumn = op['primary_key_column'] as String?;
      final pkValue = op['primary_key_value'];

      try {
        if (operation == 'upsert' && data != null) {
          await client.from(tableName).upsert(data);
        } else if (operation == 'delete' && pkColumn != null) {
          await client.from(tableName).delete().eq(pkColumn, pkValue);
          // Also write tombstone for delete operations
          await client.from('deleted_records').upsert({
            'table_name': tableName,
            'record_id': pkValue.toString(),
          });
        }
        // Success: remove from queue
        await localDb.removePendingSyncEntry(hiveKey);
        if (kDebugMode) print('Flushed offline op: $operation on $tableName');
      } catch (e) {
        if (kDebugMode) print('Offline flush failed for $tableName: $e');
        // Leave in queue to retry next time
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
    } catch (e) {
      if (kDebugMode) print('Push all local error: $e');
    }
  }

  DateTime? _lastFullSyncTime;

  // ─── Cloud → Local Sync ────────────────────────────────────────────────────
  /// Fetches authoritative data from Supabase and mirrors into local Hive.
  /// Uses Delta Sync (updated_at filter) to download only changed rows,
  /// preserving 0ms local reads while reducing Egress by >90%.
  Future<void> syncAllTablesFromCloud(LocalDatabaseService localDb, {bool force = false}) async {
    if (!_isInitialized) return;

    // Throttling: If synced less than 30s ago and not forced, skip to save egress
    final now = DateTime.now();
    if (!force && _lastFullSyncTime != null && now.difference(_lastFullSyncTime!).inSeconds < 30) {
      if (kDebugMode) print('Sync skipped: synced recently (${now.difference(_lastFullSyncTime!).inSeconds}s ago)');
      return;
    }

    try {
      _setStatus(SyncStatus.syncing, 'Syncing changes from cloud...');
      final client = Supabase.instance.client;

      final lastSyncMillis = (UiPreferencesService.getValue('last_full_sync_timestamp') as num?)?.toInt() ?? 0;
      final String? lastSyncIso = (!force && lastSyncMillis > 0)
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncMillis - 30000, isUtc: true).toIso8601String()
          : null;
      final bool isDelta = lastSyncIso != null;

      if (kDebugMode) {
        print(isDelta
            ? '[SupabaseSync] Performing Delta Sync for changes after $lastSyncIso'
            : '[SupabaseSync] Performing Full Sync');
      }

      // ── Step 0: Apply remote deletions (tombstones) ────────────────────────
      try {
        var tombstoneQuery = client.from('deleted_records').select();
        if (isDelta) {
          tombstoneQuery = tombstoneQuery.gt('deleted_at', lastSyncIso);
        }
        final deletions = await tombstoneQuery.timeout(const Duration(seconds: 5));
        for (final d in deletions) {
          final tbl = d['table_name']?.toString() ?? '';
          final rid = d['record_id']?.toString();
          if (rid == null || rid.isEmpty) continue;
          switch (tbl) {
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
          }
        }
      } catch (e) {
        if (kDebugMode) print('Tombstone sync skipped: $e');
      }

      // ── Step 1: Inward Repairs ─────────────────────────────────────────────
      var inwardQuery = client.from('inward_repairs').select();
      var inwardItemsQuery = client.from('inward_estimate_items').select();
      if (isDelta) {
        inwardQuery = inwardQuery.gt('updated_at', lastSyncIso);
        inwardItemsQuery = inwardItemsQuery.gt('updated_at', lastSyncIso);
      }
      final inwardData = await inwardQuery.timeout(const Duration(seconds: 5));
      final inwardItemsData = await inwardItemsQuery.timeout(const Duration(seconds: 5));

      final repairsMap = <int, Map<String, dynamic>>{};
      final inwardItemsMap = <int, List<Map<String, dynamic>>>{};

      if (!isDelta) {
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
          final itemsJson = inwardItemsData
              .where((i) => i['job_no']?.toString() == cloudRepair.jobNo.toString())
              .map((i) => InwardEstimateItem.fromJson(Map<String, dynamic>.from(i)).toJson())
              .toList();
          inwardItemsMap[cloudRepair.jobNo] = itemsJson;
        }
        await localDb.saveAllInwardRepairs(repairsMap, inwardItemsMap, clearOthers: true);
      } else {
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
              .timeout(const Duration(seconds: 5));
          final fullItemsData = await client
              .from('inward_estimate_items')
              .select()
              .inFilter('job_no', affectedJobs.toList())
              .timeout(const Duration(seconds: 5));

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
      }

      // ── Step 2: Replacements ───────────────────────────────────────────────
      var replacementQuery = client.from('replacements').select();
      if (isDelta) replacementQuery = replacementQuery.gt('updated_at', lastSyncIso);
      final replacementData = await replacementQuery.timeout(const Duration(seconds: 5));
      final replacementMap = <String, Map<String, dynamic>>{};
      for (final json in replacementData) {
        final repl = Replacement.fromJson(Map<String, dynamic>.from(json));
        replacementMap[repl.jobNo] = repl.toJson();
      }
      await localDb.saveAllReplacements(replacementMap, clearOthers: !isDelta);

      // ── Step 3: Requests ───────────────────────────────────────────────────
      var requestQuery = client.from('requests').select();
      if (isDelta) requestQuery = requestQuery.gt('updated_at', lastSyncIso);
      final requestData = await requestQuery.timeout(const Duration(seconds: 5));
      final requestMap = <String, Map<String, dynamic>>{};
      for (final json in requestData) {
        final req = RequestOrder.fromJson(Map<String, dynamic>.from(json));
        requestMap[req.id] = req.toJson();
      }
      await localDb.saveAllRequests(requestMap, clearOthers: !isDelta);

      // ── Step 4: Calls ──────────────────────────────────────────────────────
      var callQuery = client.from('calls').select();
      if (isDelta) callQuery = callQuery.gt('updated_at', lastSyncIso);
      final callData = await callQuery.timeout(const Duration(seconds: 5));
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
      await localDb.saveAllCalls(callMap, clearOthers: !isDelta);

      // ── Step 5: Sales ──────────────────────────────────────────────────────
      var salesQuery = client.from('sales').select();
      var salesItemsQuery = client.from('sale_items').select();
      if (isDelta) {
        salesQuery = salesQuery.gt('updated_at', lastSyncIso);
        salesItemsQuery = salesItemsQuery.gt('updated_at', lastSyncIso);
      }
      final salesData = await salesQuery.timeout(const Duration(seconds: 5));
      final salesItemsData = await salesItemsQuery.timeout(const Duration(seconds: 5));
      final salesMap = <int, Map<String, dynamic>>{};
      final salesItemsMap = <int, List<Map<String, dynamic>>>{};

      if (!isDelta) {
        for (final json in salesData) {
          final sale = Sale.fromJson(Map<String, dynamic>.from(json));
          salesMap[sale.invoiceNo] = sale.toJson();
          final itemsJson = salesItemsData
              .where((i) => i['invoice_no']?.toString() == sale.invoiceNo.toString())
              .map((i) => SaleItem.fromJson(Map<String, dynamic>.from(i)).toJson())
              .toList();
          salesItemsMap[sale.invoiceNo] = itemsJson;
        }
        await localDb.saveAllSales(salesMap, salesItemsMap, clearOthers: true);
      } else {
        final affectedInvoices = <int>{};
        for (final json in salesData) {
          final inv = int.tryParse(json['invoice_no']?.toString() ?? '');
          if (inv != null) affectedInvoices.add(inv);
        }
        for (final json in salesItemsData) {
          final inv = int.tryParse(json['invoice_no']?.toString() ?? '');
          if (inv != null) affectedInvoices.add(inv);
        }

        if (affectedInvoices.isNotEmpty) {
          final fullSalesData = await client
              .from('sales')
              .select()
              .inFilter('invoice_no', affectedInvoices.toList())
              .timeout(const Duration(seconds: 5));
          final fullSaleItemsData = await client
              .from('sale_items')
              .select()
              .inFilter('invoice_no', affectedInvoices.toList())
              .timeout(const Duration(seconds: 5));

          for (final json in fullSalesData) {
            final sale = Sale.fromJson(Map<String, dynamic>.from(json));
            salesMap[sale.invoiceNo] = sale.toJson();
          }

          for (final inv in affectedInvoices) {
            final itemsJson = fullSaleItemsData
                .where((i) => i['invoice_no']?.toString() == inv.toString())
                .map((i) => SaleItem.fromJson(Map<String, dynamic>.from(i)).toJson())
                .toList();
            salesItemsMap[inv] = itemsJson;
          }

          await localDb.saveAllSales(salesMap, salesItemsMap, clearOthers: false);
        }
      }

      // ── Step 6: Purchases ──────────────────────────────────────────────────
      var purchaseQuery = client.from('purchases').select();
      var purchaseItemsQuery = client.from('purchase_order_items').select();
      if (isDelta) {
        purchaseQuery = purchaseQuery.gt('updated_at', lastSyncIso);
        purchaseItemsQuery = purchaseItemsQuery.gt('updated_at', lastSyncIso);
      }
      final purchaseData = await purchaseQuery.timeout(const Duration(seconds: 5));
      final purchaseItemsData = await purchaseItemsQuery.timeout(const Duration(seconds: 5));
      final purchasesMap = <String, Map<String, dynamic>>{};
      final purchaseItemsMap = <String, List<Map<String, dynamic>>>{};

      if (!isDelta) {
        for (final json in purchaseData) {
          final pur = PurchaseOrder.fromJson(Map<String, dynamic>.from(json));
          purchasesMap[pur.id] = pur.toJson();
          final itemsJson = purchaseItemsData
              .where((i) => i['purchase_id']?.toString() == pur.id.toString())
              .map((i) => PurchaseOrderItem.fromJson(Map<String, dynamic>.from(i)).toJson())
              .toList();
          purchaseItemsMap[pur.id] = itemsJson;
        }
        await localDb.saveAllPurchases(purchasesMap, purchaseItemsMap, clearOthers: true);
      } else {
        final affectedPurchases = <String>{};
        for (final json in purchaseData) {
          final pid = json['id']?.toString();
          if (pid != null && pid.isNotEmpty) affectedPurchases.add(pid);
        }
        for (final json in purchaseItemsData) {
          final pid = json['purchase_id']?.toString();
          if (pid != null && pid.isNotEmpty) affectedPurchases.add(pid);
        }

        if (affectedPurchases.isNotEmpty) {
          final fullPurchData = await client
              .from('purchases')
              .select()
              .inFilter('id', affectedPurchases.toList())
              .timeout(const Duration(seconds: 5));
          final fullItemsData = await client
              .from('purchase_order_items')
              .select()
              .inFilter('purchase_id', affectedPurchases.toList())
              .timeout(const Duration(seconds: 5));

          for (final json in fullPurchData) {
            final pur = PurchaseOrder.fromJson(Map<String, dynamic>.from(json));
            purchasesMap[pur.id] = pur.toJson();
          }

          for (final pid in affectedPurchases) {
            final itemsJson = fullItemsData
                .where((i) => i['purchase_id']?.toString() == pid)
                .map((i) => PurchaseOrderItem.fromJson(Map<String, dynamic>.from(i)).toJson())
                .toList();
            purchaseItemsMap[pid] = itemsJson;
          }

          await localDb.saveAllPurchases(purchasesMap, purchaseItemsMap, clearOthers: false);
        }
      }

      // ── Step 7: Pricelist ──────────────────────────────────────────────────
      var pricelistQuery = client.from('pricelist').select();
      if (isDelta) pricelistQuery = pricelistQuery.gt('updated_at', lastSyncIso);
      final pricelistData = await pricelistQuery.timeout(const Duration(seconds: 5));
      final pricelistMap = <int, Map<String, dynamic>>{};
      for (final json in pricelistData) {
        final item = PricelistItem.fromJson(Map<String, dynamic>.from(json));
        pricelistMap[item.id] = item.toJson();
      }
      await localDb.saveAllPricelistItems(pricelistMap, clearOthers: !isDelta);

      // ── Step 8: Users & Permissions ────────────────────────────────────────
      await UserPermissionService.syncUsersFromCloud(force: force);

      // ── Step 9: Shop Settings (UPI IDs, Active UPI ID, UPI Names) ──────────
      try {
        final settingsData = await client.from('shop_settings').select().timeout(const Duration(seconds: 5));
        final settingsMap = <String, dynamic>{};
        for (final item in settingsData) {
          final key = item['key']?.toString();
          if (key != null) {
            settingsMap[key] = item['value'];
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
              'updated_at': DateTime.now().toIso8601String(),
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
              'updated_at': DateTime.now().toIso8601String(),
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
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncMillis - 30000, isUtc: true).toIso8601String()
          : null;

      // Handle table deletion tombstones
      try {
        var tombstoneQuery = client.from('deleted_records').select();
        if (tableName != 'deleted_records') {
          tombstoneQuery = tombstoneQuery.eq('table_name', tableName);
        }
        if (lastSyncIso != null) {
          tombstoneQuery = tombstoneQuery.gt('deleted_at', lastSyncIso);
        }
        final deletions = await tombstoneQuery.timeout(const Duration(seconds: 4));
        for (final d in deletions) {
          final tbl = d['table_name']?.toString() ?? tableName;
          final rid = d['record_id']?.toString();
          if (rid == null || rid.isEmpty) continue;
          switch (tbl) {
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
            q = q.gt('updated_at', lastSyncIso);
            iq = iq.gt('updated_at', lastSyncIso);
          }
          final inwardData = await q.timeout(const Duration(seconds: 5));
          final inwardItemsData = await iq.timeout(const Duration(seconds: 5));

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
                .timeout(const Duration(seconds: 5));
            final fullItemsData = await client
                .from('inward_estimate_items')
                .select()
                .inFilter('job_no', affectedJobs.toList())
                .timeout(const Duration(seconds: 5));

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

        case 'calls':
          var q = client.from('calls').select();
          if (lastSyncIso != null) q = q.gt('updated_at', lastSyncIso);
          final callsData = await q.timeout(const Duration(seconds: 5));
          final callsMap = <int, Map<String, dynamic>>{};
          for (final json in callsData) {
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
            callsMap[cloudCall.id] = callJson;
          }
          if (callsMap.isNotEmpty) {
            await localDb.saveAllCalls(callsMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('calls');

        case 'sales':
        case 'sale_items':
          var q = client.from('sales').select();
          var sq = client.from('sale_items').select();
          if (lastSyncIso != null) {
            q = q.gt('updated_at', lastSyncIso);
            sq = sq.gt('updated_at', lastSyncIso);
          }
          final salesData = await q.timeout(const Duration(seconds: 5));
          final saleItemsData = await sq.timeout(const Duration(seconds: 5));

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
                .timeout(const Duration(seconds: 5));
            final fullSaleItemsData = await client
                .from('sale_items')
                .select()
                .inFilter('invoice_no', affectedInvoices.toList())
                .timeout(const Duration(seconds: 5));

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

        case 'replacements':
          var q = client.from('replacements').select();
          if (lastSyncIso != null) q = q.gt('updated_at', lastSyncIso);
          final replData = await q.timeout(const Duration(seconds: 5));
          final replMap = <String, Map<String, dynamic>>{};
          for (final json in replData) {
            final repl = Replacement.fromJson(Map<String, dynamic>.from(json));
            replMap[repl.jobNo] = repl.toJson();
          }
          if (replMap.isNotEmpty) {
            await localDb.saveAllReplacements(replMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('replacements');

        case 'requests':
          var q = client.from('requests').select();
          if (lastSyncIso != null) q = q.gt('updated_at', lastSyncIso);
          final reqData = await q.timeout(const Duration(seconds: 5));
          final reqMap = <String, Map<String, dynamic>>{};
          for (final json in reqData) {
            final req = RequestOrder.fromJson(Map<String, dynamic>.from(json));
            reqMap[req.id] = req.toJson();
          }
          if (reqMap.isNotEmpty) {
            await localDb.saveAllRequests(reqMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('requests');

        case 'purchases':
        case 'purchase_items':
        case 'purchase_order_items':
          var q = client.from('purchases').select();
          var pq = client.from('purchase_order_items').select();
          if (lastSyncIso != null) {
            q = q.gt('updated_at', lastSyncIso);
            pq = pq.gt('updated_at', lastSyncIso);
          }
          final purchData = await q.timeout(const Duration(seconds: 5));
          final purchItemsData = await pq.timeout(const Duration(seconds: 5));

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
                .timeout(const Duration(seconds: 5));
            final fullItemsData = await client
                .from('purchase_order_items')
                .select()
                .inFilter('purchase_id', affectedPurchases.toList())
                .timeout(const Duration(seconds: 5));

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

        case 'pricelist':
        case 'pricelist_items':
          var q = client.from('pricelist').select();
          if (lastSyncIso != null) q = q.gt('updated_at', lastSyncIso);
          final priceData = await q.timeout(const Duration(seconds: 5));
          final priceMap = <int, Map<String, dynamic>>{};
          for (final json in priceData) {
            final item = PricelistItem.fromJson(Map<String, dynamic>.from(json));
            priceMap[item.id] = item.toJson();
          }
          if (priceMap.isNotEmpty) {
            await localDb.saveAllPricelistItems(priceMap, clearOthers: false);
          }
          ShopRepository.notifyTableChanged('pricelist_items');

        case 'app_users':
          await UserPermissionService.syncUsersFromCloud(force: true);
          ShopRepository.notifyTableChanged('app_users');

        case 'shop_settings':
          final settingsData = await client.from('shop_settings').select().timeout(const Duration(seconds: 5));
          for (final row in settingsData) {
            final key = row['key']?.toString();
            final value = row['value'];
            if (key == 'upi_ids_list' && value is List) {
              await localDb.saveUpiIdsList(List<String>.from(value.map((e) => e.toString())), syncToCloud: false);
            } else if (key == 'active_upi_id' && value != null) {
              await localDb.setActiveUpiId(value.toString(), syncToCloud: false);
            } else if (key == 'upi_names_map' && value is Map) {
              final map = Map<String, String>.from(value.map((k, v) => MapEntry(k.toString(), v.toString())));
              await localDb.saveUpiNamesMap(map, syncToCloud: false);
            }
          }
          ShopRepository.notifyTableChanged('shop_settings');
      }

      await UiPreferencesService.setValue('last_full_sync_timestamp', DateTime.now().millisecondsSinceEpoch);
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

  /// Batch saves estimate items for a job after parent inward repair is saved
  Future<void> saveEstimateItemsForJob(
    int jobNo,
    List<InwardEstimateItem> items,
  ) async {
    if (!_isInitialized) return;

    try {
      _setStatus(SyncStatus.syncing, 'Syncing estimate items...');
      final client = Supabase.instance.client;
      await client.from('inward_estimate_items').delete().eq('job_no', jobNo);

      if (items.isNotEmpty) {
        final payload = items.map((e) {
          final m = e.toJson();
          m['updated_at'] = DateTime.now().toUtc().toIso8601String();
          return m;
        }).toList();
        await client.from('inward_estimate_items').upsert(payload);
      }
      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Save estimate items cloud error ($jobNo): $e');
      _setStatus(SyncStatus.error, 'Sync Error (Estimate Items): $e');
    }
  }

  /// Batch saves purchase order items after parent purchase order is saved
  Future<void> savePurchaseItemsForPurchase(
    String purchaseId,
    List<PurchaseOrderItem> items,
  ) async {
    if (!_isInitialized) return;

    try {
      _setStatus(SyncStatus.syncing, 'Syncing purchase items...');
      final client = Supabase.instance.client;
      await client
          .from('purchase_order_items')
          .delete()
          .eq('purchase_id', purchaseId);

      if (items.isNotEmpty) {
        final payload = items.map((e) {
          final m = e.toSupabaseJson();
          m['updated_at'] = DateTime.now().toUtc().toIso8601String();
          return m;
        }).toList();
        await client.from('purchase_order_items').upsert(payload);
      }
      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Save purchase items cloud error ($purchaseId): $e');
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
          'table_name': tableName,
          'record_id': idValue.toString(),
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        });
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

  /// One-click reset for production launch: Clears test data from Cloud & Local
  Future<bool> resetDatabaseForProductionLaunch(
    LocalDatabaseService localDb,
  ) async {
    try {
      _setStatus(SyncStatus.syncing, 'Clearing test data...');

      if (_isInitialized) {
        final client = Supabase.instance.client;
        try {
          await client.from('deleted_records').delete().neq('id', '00000000-0000-0000-0000-000000000000');
          await client.from('inward_repairs').delete().neq('job_no', -1);
          await client.from('replacements').delete().neq('job_no', '___');
          await client.from('requests').delete().neq('id', '___');
          await client.from('calls').delete().neq('id', -1);
          await client.from('sales').delete().neq('invoice_no', -1);
          await client.from('sale_items').delete().neq('invoice_no', -1);
          await client.from('purchases').delete().neq('id', '___');
          await client.from('pricelist').delete().neq('id', -1);
        } catch (e) {
          if (kDebugMode) print('Cloud clear error: $e');
        }
      }

      await localDb.clearDatabase();
      _setStatus(SyncStatus.synced, 'Fresh Production State Ready');
      return true;
    } catch (e) {
      _setStatus(SyncStatus.error, 'Reset Failed: $e');
      return false;
    }
  }
}

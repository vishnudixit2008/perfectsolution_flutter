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

      // On startup: pull from cloud only.
      // IMPORTANT: We do NOT push all local data on startup to prevent ghost
      // resurrection where an old device re-uploads deleted/stale data.
      unawaited(_performBackgroundSync(localDb));

      return true;
    } catch (e) {
      if (kDebugMode) print('Supabase connect error: $e');
      _setStatus(SyncStatus.error, 'Cloud Connection Failed');
      return false;
    }
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
      _setStatus(SyncStatus.error, '$e');
    }
  }

  /// Public method for manual sync triggered by user (pull only).
  Future<void> manualSync(LocalDatabaseService localDb) async {
    if (!_isInitialized) {
      try {
        final connected = await connectAndSubscribe(localDb);
        if (!connected) return;
      } catch (e) {
        _setStatus(SyncStatus.error, 'Connection Error: $e');
        return;
      }
    }
    _setStatus(SyncStatus.syncing, 'Syncing...');
    try {
      await syncAllTablesFromCloud(localDb, force: true)
          .timeout(const Duration(seconds: 15));
      await flushOfflineQueue(localDb)
          .timeout(const Duration(seconds: 10));
      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Manual sync error: $e');
      _setStatus(SyncStatus.error, 'Sync Error: $e');
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
  /// Uses a debounce timer to prevent a flood of 7-query syncs for every event.
  void _subscribeRealtime(LocalDatabaseService localDb) {
    try {
      _realtimeChannel?.unsubscribe();
      final client = Supabase.instance.client;

      _realtimeChannel = client.channel('public-db-changes')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          callback: (payload) {
            if (kDebugMode) print('Realtime change event: ${payload.table}');
            // Debounce: cancel any pending sync and schedule a new one after 500ms
            // This prevents 100+ queries when pushing bulk data
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 500), () {
              syncAllTablesFromCloud(localDb);
            });
          },
        )
        ..subscribe();
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
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncMillis - 5000).toIso8601String()
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

      for (final json in inwardData) {
        final cloudRepair = InwardRepair.fromJson(Map<String, dynamic>.from(json));
        Map<String, dynamic> repairJson = cloudRepair.toJson();

        // If cloud record was updated and explicitly has null/empty photo string (e.g. photo deleted or omitted),
        // check if existing local repair has a valid Google Drive URL to retain offline link when photo wasn't deleted
        if (cloudRepair.photo == null || cloudRepair.photo!.isEmpty) {
          // If updated_at is present in cloud JSON, it means user updated record.
          // If photo was explicitly cleared/deleted by user, sync the deletion.
          // Only preserve local photo if cloud didn't send photo field.
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
            .toList();
        List<Map<String, dynamic>> parsedItems = itemsJson
            .map(
              (i) => InwardEstimateItem.fromJson(
                Map<String, dynamic>.from(i),
              ).toJson(),
            )
            .toList();

        if (parsedItems.isEmpty) {
          final existingLocal = localDb.getInwardEstimateItems(cloudRepair.jobNo);
          if (existingLocal.isNotEmpty) {
            parsedItems = existingLocal.map((e) => e.toJson()).toList();
          }
        }

        inwardItemsMap[cloudRepair.jobNo] = parsedItems;
      }
      await localDb.saveAllInwardRepairs(repairsMap, inwardItemsMap, clearOthers: !isDelta);

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

      for (final json in salesData) {
        final sale = Sale.fromJson(Map<String, dynamic>.from(json));
        salesMap[sale.invoiceNo] = sale.toJson();
        var itemsJson = salesItemsData
            .where(
              (i) => i['invoice_no']?.toString() == sale.invoiceNo.toString(),
            )
            .toList();

        // In Delta Sync, if items weren't updated recently, retain existing local items for this invoice
        if (itemsJson.isEmpty) {
          final existingLocalItems = localDb.getSaleItems(sale.invoiceNo);
          if (existingLocalItems.isNotEmpty) {
            itemsJson = existingLocalItems.map((e) => e.toJson()).toList();
          }
        }

        salesItemsMap[sale.invoiceNo] = itemsJson
            .map(
              (i) => SaleItem.fromJson(Map<String, dynamic>.from(i)).toJson(),
            )
            .toList();
      }
      await localDb.saveAllSales(salesMap, salesItemsMap, clearOthers: !isDelta);

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

      for (final json in purchaseData) {
        final pur = PurchaseOrder.fromJson(Map<String, dynamic>.from(json));
        purchasesMap[pur.id] = pur.toJson();
        var itemsJson = purchaseItemsData
            .where((i) => i['purchase_id']?.toString() == pur.id.toString())
            .toList();

        if (itemsJson.isEmpty) {
          final existingLocalItems = localDb.getPurchaseOrderItems(pur.id);
          if (existingLocalItems.isNotEmpty) {
            itemsJson = existingLocalItems.map((e) => e.toSupabaseJson()).toList();
          }
        }

        purchaseItemsMap[pur.id] = itemsJson
            .map(
              (i) => PurchaseOrderItem.fromJson(
                Map<String, dynamic>.from(i),
              ).toJson(),
            )
            .toList();
      }
      await localDb.saveAllPurchases(purchasesMap, purchaseItemsMap, clearOthers: !isDelta);

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
    } catch (e) {
      if (kDebugMode) print('Sync from cloud error: $e');
      _setStatus(SyncStatus.error, 'Sync from cloud error: $e');
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
    if (!_isInitialized) {
      if (localDb != null) {
        await localDb.enqueuePendingSync({
          'operation': 'upsert',
          'table': tableName,
          'data': data,
          'queued_at': DateTime.now().toIso8601String(),
        });
      }
      return;
    }

    try {
      _setStatus(SyncStatus.syncing, 'Syncing change...');
      final client = Supabase.instance.client;
      try {
        await client.from(tableName).upsert(data);
      } catch (e) {
        // If cloud table doesn't have discount column yet, fallback without discount field
        if (data.containsKey('discount')) {
          final fallbackData = Map<String, dynamic>.from(data)
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
          'data': data,
          'queued_at': DateTime.now().toIso8601String(),
        });
        _setStatus(SyncStatus.offline, 'Saved Offline — will sync when connected');
      } else {
        _setStatus(SyncStatus.error, 'Sync Error: $e');
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
        final payload = items.map((e) => e.toJson()).toList();
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
        final payload = items.map((e) => e.toSupabaseJson()).toList();
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
          'queued_at': DateTime.now().toIso8601String(),
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

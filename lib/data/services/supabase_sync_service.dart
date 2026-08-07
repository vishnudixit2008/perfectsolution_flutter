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

enum SyncStatus { offline, syncing, synced, error }

class SupabaseSyncService extends ChangeNotifier {
  static const String _boxName = 'ui_preferences';
  static const String _urlKey = 'supabase_project_url';
  static const String _keyKey = 'supabase_anon_key';
  static const String _defaultUrl = 'https://fgsqgrgxjrclswkggnmc.supabase.co';
  static const String _defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZnc3Fncmd4anJjbHN3a2dnbm1jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ3MTU4NDgsImV4cCI6MjEwMDI5MTg0OH0._XyKP9DTbrs7mbHTsmlLmv6FkfYTjey4kXjfpNt0n0w';

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
    }
  }

  /// Public method for manual sync triggered by user (pull only).
  Future<void> manualSync(LocalDatabaseService localDb) async {
    if (!_isInitialized) return;
    _setStatus(SyncStatus.syncing, 'Syncing...');
    try {
      await syncAllTablesFromCloud(localDb);
      await flushOfflineQueue(localDb);
      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Manual sync error: $e');
      _setStatus(SyncStatus.error, 'Sync Failed');
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

  // ─── Cloud → Local Sync ────────────────────────────────────────────────────
  /// Fetches authoritative data from Supabase and mirrors into local Hive.
  /// Cloud is the single source of truth. Deleted records tombstones are
  /// applied first, then cloud data replaces local data.
  Future<void> syncAllTablesFromCloud(LocalDatabaseService localDb) async {
    if (!_isInitialized) return;

    try {
      _setStatus(SyncStatus.syncing, 'Syncing from cloud...');
      final client = Supabase.instance.client;

      // ── Step 0: Apply remote deletions (tombstones) ────────────────────────
      // This ensures records deleted on any device are removed everywhere.
      try {
        final deletions = await client.from('deleted_records').select();
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
        // Tombstone table may not exist yet on older deployments — safe to skip
        if (kDebugMode) print('Tombstone sync skipped: $e');
      }

      // ── Step 1: Inward Repairs ─────────────────────────────────────────────
      final inwardData = await client.from('inward_repairs').select();
      final inwardItemsData = await client
          .from('inward_estimate_items')
          .select();
      final repairsMap = <int, Map<String, dynamic>>{};
      final inwardItemsMap = <int, List<Map<String, dynamic>>>{};

      for (final json in inwardData) {
        final cloudRepair = InwardRepair.fromJson(Map<String, dynamic>.from(json));

        // Conflict resolution: if local has a newer updatedAt, keep local
        // but still store the cloud version in the map (cloud wins by default).
        // Individual saves via pushRecordToCloud already keep cloud updated.
        repairsMap[cloudRepair.jobNo] = cloudRepair.toJson();

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

        // Preserve local estimate items if cloud data hasn't populated yet
        if (parsedItems.isEmpty) {
          final existingLocal = localDb.getInwardEstimateItems(cloudRepair.jobNo);
          if (existingLocal.isNotEmpty) {
            parsedItems = existingLocal.map((e) => e.toJson()).toList();
          }
        }

        inwardItemsMap[cloudRepair.jobNo] = parsedItems;
      }
      await localDb.saveAllInwardRepairs(repairsMap, inwardItemsMap);

      // ── Step 2: Replacements ───────────────────────────────────────────────
      final replacementData = await client.from('replacements').select();
      final replacementMap = <String, Map<String, dynamic>>{};
      for (final json in replacementData) {
        final repl = Replacement.fromJson(Map<String, dynamic>.from(json));
        replacementMap[repl.jobNo] = repl.toJson();
      }
      await localDb.saveAllReplacements(replacementMap);

      // ── Step 3: Requests ───────────────────────────────────────────────────
      final requestData = await client.from('requests').select();
      final requestMap = <String, Map<String, dynamic>>{};
      for (final json in requestData) {
        final req = RequestOrder.fromJson(Map<String, dynamic>.from(json));
        requestMap[req.id] = req.toJson();
      }
      await localDb.saveAllRequests(requestMap);

      // ── Step 4: Calls ──────────────────────────────────────────────────────
      final callData = await client.from('calls').select();
      final callMap = <int, Map<String, dynamic>>{};
      final List<Map<String, dynamic>> callsToRepushWithPhoto = [];
      for (final json in callData) {
        final cloudCall = CallModel.fromJson(Map<String, dynamic>.from(json));
        Map<String, dynamic> callJson = cloudCall.toJson();

        // Preserve local photo if cloud has no photo (photo may be Base64 stored only locally)
        if ((cloudCall.photo == null || cloudCall.photo!.isEmpty)) {
          final localRaw = localDb.getCallById(cloudCall.id);
          if (localRaw != null) {
            final localPhoto = localRaw['photo']?.toString();
            if (localPhoto != null && localPhoto.isNotEmpty) {
              callJson['photo'] = localPhoto;
              // Re-push the photo to Supabase so it persists in cloud too
              callsToRepushWithPhoto.add(callJson);
            }
          }
        }

        callMap[cloudCall.id] = callJson;
      }
      await localDb.saveAllCalls(callMap);

      // Push back any calls where local had photo but cloud didn't
      for (final callJson in callsToRepushWithPhoto) {
        try {
          await client.from('calls').upsert(callJson);
        } catch (e) {
          if (kDebugMode) print('Re-push call photo error (id=${callJson['id']}): $e');
        }
      }

      // ── Step 5: Sales ──────────────────────────────────────────────────────
      final salesData = await client.from('sales').select();
      final salesItemsData = await client.from('sale_items').select();
      final salesMap = <int, Map<String, dynamic>>{};
      final salesItemsMap = <int, List<Map<String, dynamic>>>{};

      for (final json in salesData) {
        final sale = Sale.fromJson(Map<String, dynamic>.from(json));
        salesMap[sale.invoiceNo] = sale.toJson();
        final itemsJson = salesItemsData
            .where(
              (i) => i['invoice_no']?.toString() == sale.invoiceNo.toString(),
            )
            .toList();
        salesItemsMap[sale.invoiceNo] = itemsJson
            .map(
              (i) => SaleItem.fromJson(Map<String, dynamic>.from(i)).toJson(),
            )
            .toList();
      }
      await localDb.saveAllSales(salesMap, salesItemsMap);

      // ── Step 6: Purchases ──────────────────────────────────────────────────
      final purchaseData = await client.from('purchases').select();
      final purchaseItemsData = await client
          .from('purchase_order_items')
          .select();
      final purchasesMap = <String, Map<String, dynamic>>{};
      final purchaseItemsMap = <String, List<Map<String, dynamic>>>{};

      for (final json in purchaseData) {
        final pur = PurchaseOrder.fromJson(Map<String, dynamic>.from(json));
        purchasesMap[pur.id] = pur.toJson();
        final itemsJson = purchaseItemsData
            .where((i) => i['purchase_id']?.toString() == pur.id.toString())
            .toList();
        purchaseItemsMap[pur.id] = itemsJson
            .map(
              (i) => PurchaseOrderItem.fromJson(
                Map<String, dynamic>.from(i),
              ).toJson(),
            )
            .toList();
      }
      await localDb.saveAllPurchases(purchasesMap, purchaseItemsMap);

      // ── Step 7: Pricelist ──────────────────────────────────────────────────
      final pricelistData = await client.from('pricelist').select();
      final pricelistMap = <int, Map<String, dynamic>>{};
      for (final json in pricelistData) {
        final item = PricelistItem.fromJson(Map<String, dynamic>.from(json));
        pricelistMap[item.id] = item.toJson();
      }
      await localDb.saveAllPricelistItems(pricelistMap);

      // ── Step 8: Users & Permissions ────────────────────────────────────────
      await UserPermissionService.syncUsersFromCloud();

      // ── Step 9: Shop Settings (UPI IDs, Active UPI ID, UPI Names) ──────────
      try {
        final settingsData = await client.from('shop_settings').select();
        final settingsMap = <String, dynamic>{};
        for (final item in settingsData) {
          final key = item['key']?.toString();
          if (key != null) {
            settingsMap[key] = item['value'];
          }
        }

        // Active UPI ID
        if (settingsMap.containsKey('active_upi_id') && settingsMap['active_upi_id'] != null) {
          await localDb.setActiveUpiId(settingsMap['active_upi_id'].toString(), syncToCloud: false);
        } else {
          final localActive = localDb.getActiveUpiId();
          if (localActive != null && localActive.isNotEmpty) {
            await client.from('shop_settings').upsert({
              'key': 'active_upi_id',
              'value': localActive,
              'updated_at': DateTime.now().toIso8601String(),
            });
          }
        }

        // UPI IDs List
        if (settingsMap.containsKey('upi_ids_list') && settingsMap['upi_ids_list'] is List) {
          final list = (settingsMap['upi_ids_list'] as List).map((e) => e.toString()).toList();
          await localDb.saveUpiIdsList(list, syncToCloud: false);
        } else {
          final localList = localDb.getUpiIdsList();
          if (localList.isNotEmpty) {
            await client.from('shop_settings').upsert({
              'key': 'upi_ids_list',
              'value': localList,
              'updated_at': DateTime.now().toIso8601String(),
            });
          }
        }

        // UPI Names Map
        if (settingsMap.containsKey('upi_names_map') && settingsMap['upi_names_map'] is Map) {
          final map = Map<String, String>.from(
            (settingsMap['upi_names_map'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
          );
          await localDb.saveUpiNamesMap(map, syncToCloud: false);
        } else {
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

      _setStatus(SyncStatus.synced, 'All tables synchronized');
    } catch (e) {
      if (kDebugMode) print('Sync from cloud error: $e');
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
      _setStatus(SyncStatus.error, 'Sync Error');
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
      _setStatus(SyncStatus.error, 'Sync Error');
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
        _setStatus(SyncStatus.error, 'Delete Error');
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

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

      // Perform initial push & pull sync in background without blocking UI startup
      unawaited(_performBackgroundSync(localDb));

      return true;
    } catch (e) {
      if (kDebugMode) print('Supabase connect error: $e');
      _setStatus(SyncStatus.error, 'Cloud Connection Failed');
      return false;
    }
  }

  Future<void> _performBackgroundSync(LocalDatabaseService localDb) async {
    try {
      await pushAllLocalRecordsToCloud(localDb);
      await syncAllTablesFromCloud(localDb);
    } catch (e) {
      if (kDebugMode) print('Background sync error: $e');
    }
  }

  /// Public method for manual sync triggered by user
  Future<void> manualSync(LocalDatabaseService localDb) async {
    if (!_isInitialized) return;
    _setStatus(SyncStatus.syncing, 'Syncing...');
    try {
      await pushAllLocalRecordsToCloud(localDb);
      await syncAllTablesFromCloud(localDb);
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

  /// Pushes all pre-existing local Hive records to Supabase Cloud on initial connection
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
            localDb.getPurchaseOrderItems(p.id).map((i) => i.toJson()),
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
    } catch (e) {
      if (kDebugMode) print('Push all local error: $e');
    }
  }

  /// Fetches latest data from Supabase and mirrors into local Hive storage.
  /// Also calls notifyListeners() so ViewModels that listen can reload.
  Future<void> syncAllTablesFromCloud(LocalDatabaseService localDb) async {
    if (!_isInitialized) return;

    try {
      _setStatus(SyncStatus.syncing, 'Syncing from cloud...');
      final client = Supabase.instance.client;

      // 1. Inward Repairs
      final inwardData = await client.from('inward_repairs').select();
      final inwardItemsData = await client
          .from('inward_estimate_items')
          .select();
      final repairsMap = <int, Map<String, dynamic>>{};
      final inwardItemsMap = <int, List<Map<String, dynamic>>>{};

      for (final json in inwardData) {
        final repair = InwardRepair.fromJson(Map<String, dynamic>.from(json));
        repairsMap[repair.jobNo] = repair.toJson();
        final itemsJson = inwardItemsData
            .where((i) => i['job_no']?.toString() == repair.jobNo.toString())
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
          final existingLocal = localDb.getInwardEstimateItems(repair.jobNo);
          if (existingLocal.isNotEmpty) {
            parsedItems = existingLocal.map((e) => e.toJson()).toList();
          }
        }

        inwardItemsMap[repair.jobNo] = parsedItems;
      }
      await localDb.saveAllInwardRepairs(repairsMap, inwardItemsMap);

      // 2. Replacements
      final replacementData = await client.from('replacements').select();
      final replacementMap = <String, Map<String, dynamic>>{};
      for (final json in replacementData) {
        final repl = Replacement.fromJson(Map<String, dynamic>.from(json));
        replacementMap[repl.jobNo] = repl.toJson();
      }
      await localDb.saveAllReplacements(replacementMap);

      // 3. Requests
      final requestData = await client.from('requests').select();
      final requestMap = <String, Map<String, dynamic>>{};
      for (final json in requestData) {
        final req = RequestOrder.fromJson(Map<String, dynamic>.from(json));
        requestMap[req.id] = req.toJson();
      }
      await localDb.saveAllRequests(requestMap);

      // 4. Calls
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

      // 5. Sales
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

      // 6. Purchases
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

      // 7. Pricelist
      final pricelistData = await client.from('pricelist').select();
      final pricelistMap = <int, Map<String, dynamic>>{};
      for (final json in pricelistData) {
        final item = PricelistItem.fromJson(Map<String, dynamic>.from(json));
        pricelistMap[item.id] = item.toJson();
      }
      await localDb.saveAllPricelistItems(pricelistMap);

      // 8. Users & Permissions
      await UserPermissionService.syncUsersFromCloud();

      _setStatus(SyncStatus.synced, 'All tables synchronized');
      // notifyListeners is called by _setStatus above, ViewModels that
      // consume SupabaseSyncService via Provider will rebuild and re-read Hive.
    } catch (e) {
      if (kDebugMode) print('Sync from cloud error: $e');
    }
  }

  /// Uploads a single record to Supabase table when created/edited locally
  Future<void> pushRecordToCloud(
    String tableName,
    Map<String, dynamic> data,
  ) async {
    if (!_isInitialized) return;

    try {
      _setStatus(SyncStatus.syncing, 'Syncing change...');
      final client = Supabase.instance.client;
      await client.from(tableName).upsert(data);
      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Push to cloud error ($tableName): $e');
      _setStatus(SyncStatus.error, 'Sync Error');
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

  /// Deletes a record from Supabase table
  Future<void> deleteRecordFromCloud(
    String tableName,
    String primaryKeyColumn,
    dynamic idValue,
  ) async {
    if (!_isInitialized) return;

    try {
      _setStatus(SyncStatus.syncing, 'Deleting from cloud...');
      final client = Supabase.instance.client;
      await client.from(tableName).delete().eq(primaryKeyColumn, idValue);
      _setStatus(SyncStatus.synced, 'Live Synced');
    } catch (e) {
      if (kDebugMode) print('Delete from cloud error ($tableName): $e');
      _setStatus(SyncStatus.error, 'Delete Error');
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

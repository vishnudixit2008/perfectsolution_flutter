import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/pricelist_item.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/call_model.dart';
import '../models/inward_repair.dart';
import '../models/inward_estimate_item.dart';
import '../models/replacement.dart';
import '../models/request_order.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import 'supabase_sync_service.dart';
import 'kiosk_broadcast_service.dart';
import '../repositories/shop_repository.dart';
import '../../ui/shared/status_management_dialog.dart';

class LocalDatabaseService {
  /// Set to true if any Hive box opened via the fallback path (empty box).
  /// The sync service checks this flag to force a full cloud re-pull instead
  /// of a delta sync, because the box may be missing data.
  bool hadFallbackBoxOpen = false;
  static const String _pricelistBoxName = 'pricelist_box';
  static const String _settingsBoxName = 'settings_box';
  static const String _salesBoxName = 'sales_box';
  static const String _saleItemsBoxName = 'sale_items_box';
  static const String _callsBoxName = 'calls_box';
  static const String _inwardBoxName = 'inward_box';
  static const String _inwardItemsBoxName = 'inward_items_box';
  static const String _replacementBoxName = 'replacement_box';
  static const String _requestBoxName = 'request_box';
  static const String _purchaseBoxName = 'purchase_box';
  static const String _purchaseItemsBoxName = 'purchase_items_box';
  static const String _pendingSyncBoxName = 'pending_sync_queue';

  late Box _pricelistBox;
  late Box _settingsBox;
  late Box _salesBox;
  late Box _saleItemsBox;
  late Box _callsBox;
  late Box _inwardBox;
  late Box _inwardItemsBox;
  late Box _replacementBox;
  late Box _requestBox;
  late Box _purchaseBox;
  late Box _purchaseItemsBox;
  late Box _pendingSyncBox;

  Future<void> init({int? subWindowId}) async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final suffix = (subWindowId != null && subWindowId != 0) ? '_sub_$subWindowId' : '';
      final hiveDir = '${appSupportDir.path}/shop_management_hive$suffix';
      await Hive.initFlutter(hiveDir);
    } catch (_) {
      await Hive.initFlutter();
    }

    final boxes = await Future.wait([
      _openBoxSafely(_pricelistBoxName),
      _openBoxSafely(_settingsBoxName),
      _openBoxSafely(_salesBoxName),
      _openBoxSafely(_saleItemsBoxName),
      _openBoxSafely(_callsBoxName),
      _openBoxSafely(_inwardBoxName),
      _openBoxSafely(_inwardItemsBoxName),
      _openBoxSafely(_replacementBoxName),
      _openBoxSafely(_requestBoxName),
      _openBoxSafely(_purchaseBoxName),
      _openBoxSafely(_purchaseItemsBoxName),
      _openBoxSafely(_pendingSyncBoxName),
    ]);

    _pricelistBox = boxes[0];
    _settingsBox = boxes[1];
    _salesBox = boxes[2];
    _saleItemsBox = boxes[3];
    _callsBox = boxes[4];
    _inwardBox = boxes[5];
    _inwardItemsBox = boxes[6];
    _replacementBox = boxes[7];
    _requestBox = boxes[8];
    _purchaseBox = boxes[9];
    _purchaseItemsBox = boxes[10];
    _pendingSyncBox = boxes[11];

    // Seed data is disabled since Supabase is now the source of truth
  }

  Future<Box> _openBoxSafely(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    // First attempt
    try {
      return await Hive.openBox(boxName);
    } catch (e) {
      if (kDebugMode) print('Hive openBox lock/error for $boxName: $e. Retrying after 400ms...');
    }
    // Retry after a short delay — the previous app instance may still be releasing the lock
    await Future.delayed(const Duration(milliseconds: 400));
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    try {
      return await Hive.openBox(boxName);
    } catch (e) {
      if (kDebugMode) print('Hive second retry for $boxName: $e. Recovering...');
    }
    // Last resort: open fallback box in memory/isolated name
    try {
      hadFallbackBoxOpen = true;
      if (kDebugMode) print('[WARN] Hive: opening fallback box for $boxName — full cloud sync will be forced');
      return await Hive.openBox('${boxName}_fallback');
    } catch (err) {
      if (kDebugMode) print('Hive fallback openBox for $boxName: $err');
      hadFallbackBoxOpen = true;
      return await Hive.openBox('${boxName}_${DateTime.now().millisecondsSinceEpoch}');
    }
  }

  Map<String, dynamic> exportDbSnapshot() {
    Box? uiPrefBox;
    if (Hive.isBoxOpen('ui_preferences')) {
      uiPrefBox = Hive.box('ui_preferences');
    }
    Box? usersBox;
    if (Hive.isBoxOpen('app_users_box')) {
      usersBox = Hive.box('app_users_box');
    }

    return {
      'pricelist': _boxToMap(_pricelistBox),
      'settings': _boxToMap(_settingsBox),
      'sales': _boxToMap(_salesBox),
      'sale_items': _boxToMap(_saleItemsBox),
      'calls': _boxToMap(_callsBox),
      'inward': _boxToMap(_inwardBox),
      'inward_items': _boxToMap(_inwardItemsBox),
      'replacement': _boxToMap(_replacementBox),
      'request': _boxToMap(_requestBox),
      'purchase': _boxToMap(_purchaseBox),
      'purchase_items': _boxToMap(_purchaseItemsBox),
      'ui_preferences': uiPrefBox != null ? _boxToMap(uiPrefBox) : {},
      'app_users': usersBox != null ? _boxToMap(usersBox) : {},
    };
  }

  Map<String, dynamic> _boxToMap(Box box) {
    final map = <String, dynamic>{};
    for (final key in box.keys) {
      map[key.toString()] = box.get(key);
    }
    return map;
  }

  Future<void> importDbSnapshot(Map<String, dynamic> snapshot) async {
    for (final entry in snapshot.entries) {
      await importTableData(entry.key, entry.value);
    }
  }

  dynamic exportTableData(String tableName) {
    switch (tableName) {
      case 'pricelist':
      case 'pricelist_items':
        return _boxToMap(_pricelistBox);
      case 'shop_settings':
      case 'settings':
        return _boxToMap(_settingsBox);
      case 'custom_services':
        return _settingsBox.get('custom_services_list');
      case 'sales':
        return {
          'sales': _boxToMap(_salesBox),
          'sale_items': _boxToMap(_saleItemsBox),
        };
      case 'calls':
        return _boxToMap(_callsBox);
      case 'inward_repairs':
      case 'inward':
        return {
          'inward': _boxToMap(_inwardBox),
          'inward_items': _boxToMap(_inwardItemsBox),
        };
      case 'replacements':
      case 'replacement':
        return _boxToMap(_replacementBox);
      case 'requests':
      case 'request':
        return _boxToMap(_requestBox);
      case 'purchases':
      case 'purchase':
        return {
          'purchases': _boxToMap(_purchaseBox),
          'purchase_items': _boxToMap(_purchaseItemsBox),
        };
      default:
        return null;
    }
  }

  Map<dynamic, dynamic> _normalizeMapKeys(Map data) {
    final result = <dynamic, dynamic>{};
    for (final e in data.entries) {
      final k = int.tryParse(e.key.toString()) ?? e.key;
      result[k] = e.value;
    }
    return result;
  }

  Future<void> importTableData(String tableName, dynamic data) async {
    if (data == null) return;
    try {
      if ((tableName == 'pricelist' || tableName == 'pricelist_items') && data is Map) {
        await _pricelistBox.clear();
        await _pricelistBox.putAll(_normalizeMapKeys(data));
      } else if ((tableName == 'settings' || tableName == 'shop_settings') && data is Map) {
        await _settingsBox.clear();
        await _settingsBox.putAll(data);
      } else if (tableName == 'custom_services' && data is List) {
        await _settingsBox.put('custom_services_list', List<String>.from(data));
        ShopRepository.notifyTableChanged('custom_services');
      } else if (tableName == 'sales' && data is Map) {
        if (data.containsKey('sales') && data['sales'] is Map) {
          await _salesBox.clear();
          await _salesBox.putAll(_normalizeMapKeys(data['sales'] as Map));
        } else {
          await _salesBox.clear();
          await _salesBox.putAll(_normalizeMapKeys(data));
        }
        if (data.containsKey('sale_items') && data['sale_items'] is Map) {
          await _saleItemsBox.clear();
          await _saleItemsBox.putAll(_normalizeMapKeys(data['sale_items'] as Map));
        }
      } else if (tableName == 'calls' && data is Map) {
        await _callsBox.clear();
        await _callsBox.putAll(_normalizeMapKeys(data));
      } else if ((tableName == 'inward' || tableName == 'inward_repairs') && data is Map) {
        if (data.containsKey('inward') && data['inward'] is Map) {
          await _inwardBox.clear();
          await _inwardBox.putAll(_normalizeMapKeys(data['inward'] as Map));
        } else {
          await _inwardBox.clear();
          await _inwardBox.putAll(_normalizeMapKeys(data));
        }
        if (data.containsKey('inward_items') && data['inward_items'] is Map) {
          await _inwardItemsBox.clear();
          await _inwardItemsBox.putAll(_normalizeMapKeys(data['inward_items'] as Map));
        }
      } else if (tableName == 'replacements' || tableName == 'replacement') {
        if (data is Map) {
          await _replacementBox.clear();
          await _replacementBox.putAll(_normalizeMapKeys(data));
        }
      } else if (tableName == 'requests' || tableName == 'request') {
        if (data is Map) {
          await _requestBox.clear();
          await _requestBox.putAll(_normalizeMapKeys(data));
        }
      } else if (tableName == 'purchases' || tableName == 'purchase') {
        if (data is Map) {
          if (data.containsKey('purchases') && data['purchases'] is Map) {
            await _purchaseBox.clear();
            await _purchaseBox.putAll(_normalizeMapKeys(data['purchases'] as Map));
          } else {
            await _purchaseBox.clear();
            await _purchaseBox.putAll(_normalizeMapKeys(data));
          }
          if (data.containsKey('purchase_items') && data['purchase_items'] is Map) {
            await _purchaseItemsBox.clear();
            await _purchaseItemsBox.putAll(_normalizeMapKeys(data['purchase_items'] as Map));
          }
        }
      } else if (tableName == 'ui_preferences' && data is Map) {
        if (Hive.isBoxOpen('ui_preferences')) {
          final box = Hive.box('ui_preferences');
          await box.clear();
          await box.putAll(data);
          StatusManagementService.clearCache();
        }
      } else if ((tableName == 'app_users' || tableName == 'app_users_box') && data is Map) {
        if (Hive.isBoxOpen('app_users_box')) {
          final box = Hive.box('app_users_box');
          await box.clear();
          await box.putAll(data);
        }
      }
    } catch (e) {
      if (kDebugMode) print('LocalDatabaseService importTableData ($tableName) error: $e');
    }
  }

  Future<void> _seedPricelist() async {
    try {
      final jsonString = await rootBundle.loadString('assets/pricelist.json');
      final List<dynamic> jsonList = json.decode(jsonString);

      final Map<int, Map<String, dynamic>> seedData = {};
      for (var jsonMap in jsonList) {
        final item = PricelistItem.fromJson(jsonMap);
        seedData[item.id] = item.toJson();
      }

      await _pricelistBox.putAll(seedData);
    } catch (e) {
      // Failed to seed pricelist
    }
  }

  // ignore: unused_element
  Future<void> _seedSales() async {
    try {
      final salesJsonStr = await rootBundle.loadString('assets/sales.json');
      final List<dynamic> salesJsonList = json.decode(salesJsonStr);
      final Map<int, Map<String, dynamic>> salesMap = {};
      for (var s in salesJsonList) {
        final sale = Sale.fromJson(s);
        salesMap[sale.invoiceNo] = sale.toJson();
      }
      await _salesBox.putAll(salesMap);

      final itemsJsonStr = await rootBundle.loadString(
        'assets/sale_items.json',
      );
      final List<dynamic> itemsJsonList = json.decode(itemsJsonStr);
      final Map<int, List<Map<String, dynamic>>> itemsGroupByInvoice = {};
      for (var itemJson in itemsJsonList) {
        final item = SaleItem.fromJson(itemJson);
        if (!itemsGroupByInvoice.containsKey(item.invoiceNo)) {
          itemsGroupByInvoice[item.invoiceNo] = [];
        }
        itemsGroupByInvoice[item.invoiceNo]!.add(item.toJson());
      }

      final Map<int, List<dynamic>> itemsMap = {};
      itemsGroupByInvoice.forEach((invoiceNo, list) {
        itemsMap[invoiceNo] = list;
      });
      await _saleItemsBox.putAll(itemsMap);
    } catch (e) {
      // Failed to seed sales
    }
  }

  // ignore: unused_element
  Future<void> _seedCalls() async {
    try {
      final jsonString = await rootBundle.loadString('assets/calls.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      final Map<int, Map<String, dynamic>> seedData = {};
      for (var jsonMap in jsonList) {
        final item = CallModel.fromJson(jsonMap);
        seedData[item.id] = item.toJson();
      }
      await _callsBox.putAll(seedData);
    } catch (e) {
      // Failed to seed calls
    }
  }

  // ignore: unused_element
  Future<void> _seedInwardRepairs() async {
    try {
      final repairsJsonStr = await rootBundle.loadString(
        'assets/inward_repairs.json',
      );
      final List<dynamic> repairsJsonList = json.decode(repairsJsonStr);
      final Map<int, Map<String, dynamic>> repairsMap = {};
      for (var s in repairsJsonList) {
        final repair = InwardRepair.fromJson(s);
        repairsMap[repair.jobNo] = repair.toJson();
      }
      await _inwardBox.putAll(repairsMap);

      final itemsJsonStr = await rootBundle.loadString(
        'assets/inward_estimate_items.json',
      );
      final List<dynamic> itemsJsonList = json.decode(itemsJsonStr);
      final Map<int, List<Map<String, dynamic>>> itemsGroupByJob = {};
      for (var itemJson in itemsJsonList) {
        final item = InwardEstimateItem.fromJson(itemJson);
        if (!itemsGroupByJob.containsKey(item.jobNo)) {
          itemsGroupByJob[item.jobNo] = [];
        }
        itemsGroupByJob[item.jobNo]!.add(item.toJson());
      }

      final Map<int, List<dynamic>> itemsMap = {};
      itemsGroupByJob.forEach((jobNo, list) {
        itemsMap[jobNo] = list;
      });
      await _inwardItemsBox.putAll(itemsMap);
    } catch (e) {
      // Failed to seed inward repairs
    }
  }

  // ignore: unused_element
  Future<void> _seedReplacements() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/replacements.json',
      );
      final List<dynamic> jsonList = json.decode(jsonString);
      final Map<String, Map<String, dynamic>> seedData = {};
      for (var jsonMap in jsonList) {
        final item = Replacement.fromJson(jsonMap);
        seedData[item.jobNo] = item.toJson();
      }
      await _replacementBox.putAll(seedData);
    } catch (e) {
      // Failed to seed replacements
    }
  }

  // ignore: unused_element
  Future<void> _seedRequests() async {
    try {
      final jsonString = await rootBundle.loadString('assets/requests.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      final Map<String, Map<String, dynamic>> seedData = {};
      for (var jsonMap in jsonList) {
        final item = RequestOrder.fromJson(jsonMap);
        seedData[item.id] = item.toJson();
      }
      await _requestBox.putAll(seedData);
    } catch (e) {
      // Failed to seed requests
    }
  }

  // ignore: unused_element
  Future<void> _seedPurchases() async {
    try {
      final purchasesJsonStr = await rootBundle.loadString(
        'assets/purchases.json',
      );
      final List<dynamic> purchasesJsonList = json.decode(purchasesJsonStr);
      final Map<String, Map<String, dynamic>> purchasesMap = {};
      for (var s in purchasesJsonList) {
        final purchase = PurchaseOrder.fromJson(s);
        purchasesMap[purchase.id] = purchase.toJson();
      }
      await _purchaseBox.putAll(purchasesMap);

      final itemsJsonStr = await rootBundle.loadString(
        'assets/purchase_items.json',
      );
      final List<dynamic> itemsJsonList = json.decode(itemsJsonStr);
      final Map<String, List<Map<String, dynamic>>> itemsGroupByPurchase = {};
      for (var itemJson in itemsJsonList) {
        final item = PurchaseOrderItem.fromJson(itemJson);
        if (!itemsGroupByPurchase.containsKey(item.purchaseId)) {
          itemsGroupByPurchase[item.purchaseId] = [];
        }
        itemsGroupByPurchase[item.purchaseId]!.add(item.toJson());
      }

      final Map<String, List<dynamic>> itemsMap = {};
      itemsGroupByPurchase.forEach((purchaseId, list) {
        itemsMap[purchaseId] = list;
      });
      await _purchaseItemsBox.putAll(itemsMap);
    } catch (e) {
      // Failed to seed purchases
    }
  }

  // --- Pricelist Methods ---

  List<PricelistItem> getPricelist() {
    final List<PricelistItem> items = [];
    for (var key in _pricelistBox.keys) {
      final raw = _pricelistBox.get(key);
      if (raw != null) {
        items.add(PricelistItem.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return items;
  }

  int getNextPricelistId() {
    if (_pricelistBox.isEmpty) return 1;
    int maxId = 0;
    for (var key in _pricelistBox.keys) {
      final int? id = key is int ? key : int.tryParse(key.toString());
      if (id != null && id > maxId) {
        maxId = id;
      }
    }
    return maxId + 1;
  }

  Future<void> savePricelistItem(PricelistItem item) async {
    await _pricelistBox.put(item.id, item.toJson());
  }

  Future<void> deletePricelistItem(int id) async {
    await _pricelistBox.delete(id);
  }

  Future<void> clearDatabase() async {
    // Wipe ALL local Hive boxes so no stale data can be pushed back to cloud
    await _inwardBox.clear();
    await _inwardItemsBox.clear();
    await _callsBox.clear();
    await _salesBox.clear();
    await _saleItemsBox.clear();
    await _replacementBox.clear();
    await _requestBox.clear();
    await _purchaseBox.clear();
    await _purchaseItemsBox.clear();
    await _pricelistBox.clear();
    await _pendingSyncBox.clear();
    await _seedPricelist();
  }

  /// Clears and re-seeds ONLY the pricelist box from bundled assets.
  /// Does NOT touch sales, repairs, calls, purchases, or any other data.
  /// Use this for "Reset Pricelist to Default" actions.
  Future<void> clearPricelistOnly() async {
    await _pricelistBox.clear();
    await _seedPricelist();
  }

  // ─── Offline Pending Sync Queue ────────────────────────────────────────────
  /// Adds a pending operation to the offline queue so it can be retried
  /// when internet connectivity is restored.
  Future<void> enqueuePendingSync(Map<String, dynamic> operation) async {
    // Use microsecond timestamp + random hex suffix to prevent key collision
    // when multiple operations are enqueued within the same microsecond.
    final rnd = List<int>.generate(4, (_) => (DateTime.now().microsecondsSinceEpoch & 0xFF) ^ (DateTime.now().millisecond));
    final suffix = rnd.map((b) => (b ^ DateTime.now().microsecondsSinceEpoch).toRadixString(16).padLeft(2, '0')).join();
    final key = '${DateTime.now().microsecondsSinceEpoch}_$suffix';
    await _pendingSyncBox.put(key, operation);
  }

  /// Returns all pending operations in the order they were enqueued.
  List<Map<String, dynamic>> getPendingSyncQueue() {
    return _pendingSyncBox.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  /// Removes all pending operations after they have been successfully flushed.
  Future<void> clearPendingSyncQueue() async {
    await _pendingSyncBox.clear();
  }

  /// Removes a single operation from the queue by its Hive key.
  Future<void> removePendingSyncEntry(dynamic hiveKey) async {
    await _pendingSyncBox.delete(hiveKey);
  }

  /// Returns all pending operation keys (for targeted removal after flush).
  List<dynamic> getPendingSyncKeys() => _pendingSyncBox.keys.toList();

  // --- Settings & Sync Timestamp Methods ---

  String? getLastSyncTimestamp(String tableName) {
    return _settingsBox.get('last_sync_$tableName')?.toString();
  }

  Future<void> setLastSyncTimestamp(String tableName, String isoTimestamp) async {
    await _settingsBox.put('last_sync_$tableName', isoTimestamp);
  }

  String? getActiveUpiId() {
    return _settingsBox.get('active_upi_id');
  }

  /// Returns the selected Google Review business listing key ('perfect_solution' or 'laptop_repairing')
  String getGoogleReviewListing() {
    return (_settingsBox.get('google_review_listing') as String?) ?? 'perfect_solution';
  }

  /// Saves selected Google Review business listing and syncs to Supabase shop_settings
  Future<void> setGoogleReviewListing(String listingKey, {bool syncToCloud = true}) async {
    final current = _settingsBox.get('google_review_listing');
    if (current == listingKey && !syncToCloud) return;
    await _settingsBox.put('google_review_listing', listingKey);
    if (syncToCloud) {
      unawaited(SupabaseSyncService.instance.pushRecordToCloud(
        'shop_settings',
        {
          'key': 'google_review_listing',
          'value': listingKey,
          'updated_at': DateTime.now().toIso8601String(),
        },
        localDb: this,
      ));
    }
  }

  Future<void> setActiveUpiId(String upiId, {bool syncToCloud = true}) async {
    final current = _settingsBox.get('active_upi_id');
    if (current == upiId && !syncToCloud) return;
    await _settingsBox.put('active_upi_id', upiId);
    if (syncToCloud) {
      unawaited(SupabaseSyncService.instance.pushRecordToCloud(
        'shop_settings',
        {
          'key': 'active_upi_id',
          'value': upiId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        localDb: this,
      ));

      // Broadcast active UPI change in real-time to all connected devices
      try {
        final namesMap = getUpiNamesMap();
        final refName = namesMap[upiId] ?? '';
        unawaited(KioskBroadcastService.instance.broadcastActiveUpiChanged(
          upiId: upiId,
          upiName: refName,
        ));
      } catch (_) {}
    }
  }

  List<String> getUpiIdsList() {
    final List<dynamic>? list = _settingsBox.get('upi_ids_list');
    if (list == null) {
      final defaultList = ['upi@shop', 'manager@upi'];
      _settingsBox.put('upi_ids_list', defaultList);
      return defaultList;
    }
    return List<String>.from(list);
  }

  Future<void> saveUpiIdsList(List<String> upiIds, {bool syncToCloud = true}) async {
    await _settingsBox.put('upi_ids_list', upiIds);
    if (syncToCloud) {
      unawaited(SupabaseSyncService.instance.pushRecordToCloud(
        'shop_settings',
        {
          'key': 'upi_ids_list',
          'value': upiIds,
          'updated_at': DateTime.now().toIso8601String(),
        },
        localDb: this,
      ));
    }
  }

  Map<String, String> getUpiNamesMap() {
    final dynamic raw = _settingsBox.get('upi_names_map');
    if (raw is Map) {
      return Map<String, String>.from(raw);
    }
    return {};
  }

  Future<void> saveUpiNamesMap(Map<String, String> names, {bool syncToCloud = true}) async {
    await _settingsBox.put('upi_names_map', names);
    if (syncToCloud) {
      unawaited(SupabaseSyncService.instance.pushRecordToCloud(
        'shop_settings',
        {
          'key': 'upi_names_map',
          'value': names,
          'updated_at': DateTime.now().toIso8601String(),
        },
        localDb: this,
      ));
    }
  }

  List<String> getCustomServiceNames() {
    final List<dynamic>? list = _settingsBox.get('custom_services_list');
    if (list == null) {
      final defaultList = [
        'Display Fitting',
        'Charging Port Replacement',
        'Software Reset',
        'Battery Replacement',
        'Glass Replacement',
        'Camera Repair',
      ];
      _settingsBox.put('custom_services_list', defaultList);
      return defaultList;
    }
    return List<String>.from(list);
  }

  Future<void> saveCustomServiceName(String name, {bool syncToCloud = true}) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return;

    final capitalized = cleaned
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');

    final List<String> list = getCustomServiceNames();
    final bool exists = list.any(
      (item) => item.toLowerCase() == capitalized.toLowerCase(),
    );
    if (!exists) {
      list.add(capitalized);
      await _settingsBox.put('custom_services_list', list);
      ShopRepository.notifyTableChanged('custom_services');

      if (syncToCloud) {
        unawaited(SupabaseSyncService.instance.pushRecordToCloud(
          'shop_settings',
          {
            'key': 'custom_services_list',
            'value': list,
            'updated_at': DateTime.now().toIso8601String(),
          },
          localDb: this,
        ));
      }
    }
  }

  Future<void> deleteCustomServiceName(String name, {bool syncToCloud = true}) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return;

    final List<String> list = getCustomServiceNames();
    final initialLen = list.length;
    list.removeWhere((item) => item.toLowerCase() == cleaned.toLowerCase());

    if (list.length != initialLen) {
      await _settingsBox.put('custom_services_list', list);
      ShopRepository.notifyTableChanged('custom_services');

      if (syncToCloud) {
        unawaited(SupabaseSyncService.instance.pushRecordToCloud(
          'shop_settings',
          {
            'key': 'custom_services_list',
            'value': list,
            'updated_at': DateTime.now().toIso8601String(),
          },
          localDb: this,
        ));
      }
    }
  }

  Future<void> setCustomServicesList(List<String> services, {bool syncToCloud = false}) async {
    await _settingsBox.put('custom_services_list', services);
    ShopRepository.notifyTableChanged('custom_services');
    if (syncToCloud) {
      unawaited(SupabaseSyncService.instance.pushRecordToCloud(
        'shop_settings',
        {
          'key': 'custom_services_list',
          'value': services,
          'updated_at': DateTime.now().toIso8601String(),
        },
        localDb: this,
      ));
    }
  }

  // --- Detail Popup Size Persistence ---

  /// Returns the saved detail popup width, or null if not set.
  double? getDetailPopupWidth() {
    return _settingsBox.get('detail_popup_width') as double?;
  }

  /// Returns the saved detail popup height, or null if not set.
  double? getDetailPopupHeight() {
    return _settingsBox.get('detail_popup_height') as double?;
  }

  /// Saves the detail popup dimensions so they persist across sessions.
  Future<void> saveDetailPopupSize(double width, double height) async {
    await _settingsBox.put('detail_popup_width', width);
    await _settingsBox.put('detail_popup_height', height);
  }

  // --- Printer Configuration ---

  /// Returns the saved printer name (exact system name), or null if not configured.
  String? getSelectedPrinterName() {
    return _settingsBox.get('selected_printer_name') as String?;
  }

  /// Persists the chosen printer name so it survives restarts.
  Future<void> saveSelectedPrinterName(String name) async {
    await _settingsBox.put('selected_printer_name', name);
  }

  // --- Invoice Print Settings ---

  /// Page size: 'A5' | 'A4' | 'Thermal80' (80mm thermal roll)
  String getInvoicePageSize() {
    return (_settingsBox.get('invoice_page_size') as String?) ?? 'A5';
  }

  Future<void> saveInvoicePageSize(String size) async {
    await _settingsBox.put('invoice_page_size', size);
  }

  /// Top/bottom margin in mm.
  double getInvoiceMarginTB() {
    return (_settingsBox.get('invoice_margin_tb') as double?) ?? 10.0;
  }

  /// Left/right margin in mm.
  double getInvoiceMarginLR() {
    return (_settingsBox.get('invoice_margin_lr') as double?) ?? 10.0;
  }

  Future<void> saveInvoiceMargins(double topBottom, double leftRight) async {
    await _settingsBox.put('invoice_margin_tb', topBottom);
    await _settingsBox.put('invoice_margin_lr', leftRight);
  }

  /// Whether to include the shop header branding block.
  bool getInvoiceShowHeader() {
    return (_settingsBox.get('invoice_show_header') as bool?) ?? true;
  }

  Future<void> saveInvoiceShowHeader(bool value) async {
    await _settingsBox.put('invoice_show_header', value);
  }

  /// Whether to include the UPI QR code on the invoice.
  bool getInvoiceShowQr() {
    return (_settingsBox.get('invoice_show_qr') as bool?) ?? true;
  }

  Future<void> saveInvoiceShowQr(bool value) async {
    await _settingsBox.put('invoice_show_qr', value);
  }

  // --- Sales Methods ---

  int getNextInvoiceNo() {
    if (_salesBox.isEmpty) {
      return 1;
    }
    int maxInvoiceNo = 0;
    for (var key in _salesBox.keys) {
      int? k;
      if (key is int) {
        k = key;
      } else if (key != null) {
        k = int.tryParse(key.toString());
      }
      if (k != null && k > maxInvoiceNo) {
        maxInvoiceNo = k;
      }
    }
    return maxInvoiceNo + 1;
  }

  List<Sale> getSales() {
    final List<Sale> sales = [];
    for (var key in _salesBox.keys) {
      final raw = _salesBox.get(key);
      if (raw != null) {
        sales.add(Sale.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    // Sort sales by date descending (newest first)
    sales.sort((a, b) {
      final dayA = DateTime(a.saleDate.year, a.saleDate.month, a.saleDate.day);
      final dayB = DateTime(b.saleDate.year, b.saleDate.month, b.saleDate.day);
      final d = dayB.compareTo(dayA);
      if (d != 0) return d;
      return b.invoiceNo.compareTo(a.invoiceNo);
    });
    return sales;
  }

  List<SaleItem> getSaleItems(int invoiceNo) {
    dynamic rawList = _saleItemsBox.get(invoiceNo) ??
        _saleItemsBox.get(invoiceNo.toString());
    if (rawList == null) {
      for (final key in _saleItemsBox.keys) {
        if (key.toString() == invoiceNo.toString()) {
          rawList = _saleItemsBox.get(key);
          break;
        }
      }
    }
    if (rawList == null || rawList is! List) return [];
    return rawList
        .map((raw) => SaleItem.fromJson(Map<String, dynamic>.from(raw)))
        .toList();
  }

  // Lookup product from pricelist box by id or fallback name
  PricelistItem? _findPricelistProduct(dynamic itemId, String? fallbackName) {
    dynamic rawProduct;
    if (itemId != null) {
      rawProduct = _pricelistBox.get(itemId) ??
          _pricelistBox.get(itemId.toString()) ??
          _pricelistBox.get(int.tryParse(itemId.toString()));
    }
    if (rawProduct == null && fallbackName != null) {
      final target = fallbackName.trim().toLowerCase();
      if (target.isNotEmpty) {
        for (var key in _pricelistBox.keys) {
          final raw = _pricelistBox.get(key);
          if (raw != null) {
            final p = PricelistItem.fromJson(Map<String, dynamic>.from(raw));
            if (p.itemName.trim().toLowerCase() == target) {
              rawProduct = raw;
              break;
            }
          }
        }
      }
    }
    if (rawProduct != null) {
      return PricelistItem.fromJson(Map<String, dynamic>.from(rawProduct));
    }
    return null;
  }

  bool _isSaleConfirmed(String status) {
    final s = status.trim().toLowerCase();
    return s == 'confirmed' || s == 'complete' || s == 'completed';
  }

  Future<List<PricelistItem>> _adjustStockForSale(
    List<SaleItem> items, {
    required bool isDeducting,
  }) async {
    final List<PricelistItem> updatedProducts = [];

    for (var item in items) {
      if (item.lineType == 'Product') {
        final product = _findPricelistProduct(
          item.itemId,
          item.itemDescription,
        );

        if (product != null) {
          final updatedProduct = product.copyWith(
            stockQty: isDeducting
                ? (product.stockQty - item.quantity)
                : (product.stockQty + item.quantity),
          );
          await _pricelistBox.put(product.id, updatedProduct.toJson());
          updatedProducts.add(updatedProduct);
        }
      }
    }

    return updatedProducts;
  }

  Future<List<PricelistItem>> saveSale(Sale sale, List<SaleItem> items) async {
    final List<PricelistItem> updatedProducts = [];
    final rawExisting = _salesBox.get(sale.invoiceNo);

    // Resolve and backfill any missing itemId on Product line items before saving
    final resolvedItems = items.map((item) {
      if (item.lineType == 'Product' && item.itemId == null) {
        final product = _findPricelistProduct(
          null,
          item.itemDescription,
        );
        if (product != null) {
          return item.copyWith(itemId: product.id);
        }
      }
      return item;
    }).toList();

    if (rawExisting != null) {
      final existing = Sale.fromJson(Map<String, dynamic>.from(rawExisting));
      final wasConfirmed = _isSaleConfirmed(existing.orderStatus);
      final nowConfirmed = _isSaleConfirmed(sale.orderStatus);

      if (!wasConfirmed && nowConfirmed) {
        // Transitioned from pending to complete/confirmed — deduct stock
        final res = await _adjustStockForSale(resolvedItems, isDeducting: true);
        updatedProducts.addAll(res);
      } else if (wasConfirmed && !nowConfirmed) {
        // Reverted from complete/confirmed to pending — restore stock
        final oldItems = getSaleItems(sale.invoiceNo);
        final res = await _adjustStockForSale(oldItems, isDeducting: false);
        updatedProducts.addAll(res);
      } else if (wasConfirmed && nowConfirmed) {
        // Was confirmed, still confirmed but items or quantities may have changed — re-adjust
        final oldItems = getSaleItems(sale.invoiceNo);
        final res1 = await _adjustStockForSale(oldItems, isDeducting: false);
        final res2 = await _adjustStockForSale(resolvedItems, isDeducting: true);
        updatedProducts.addAll(res1);
        updatedProducts.addAll(res2);
      }
    } else {
      // New sale
      if (_isSaleConfirmed(sale.orderStatus)) {
        final res = await _adjustStockForSale(resolvedItems, isDeducting: true);
        updatedProducts.addAll(res);
      }
    }

    await _salesBox.put(sale.invoiceNo, sale.toJson());
    final itemsJson = resolvedItems.map((item) => item.toJson()).toList();
    await _saleItemsBox.put(sale.invoiceNo, itemsJson);

    return updatedProducts;
  }

  /// Saves sale metadata without wiping out existing items box
  Future<void> saveSaleHeaderOnly(Sale sale) async {
    await _salesBox.put(sale.invoiceNo, sale.toJson());
  }

  /// Upserts a single sale item into the existing items box for an invoice
  Future<void> saveSaleItemOnly(SaleItem item) async {
    final items = getSaleItems(item.invoiceNo);
    final idx = items.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      items[idx] = item;
    } else {
      items.add(item);
    }
    await _saleItemsBox.put(
      item.invoiceNo,
      items.map((i) => i.toJson()).toList(),
    );
  }

  // Confirm order and deduct inventory
  Future<List<PricelistItem>> confirmSale(int invoiceNo) async {
    final rawSale = _salesBox.get(invoiceNo);
    if (rawSale == null) return [];

    final sale = Sale.fromJson(Map<String, dynamic>.from(rawSale));
    if (_isSaleConfirmed(sale.orderStatus)) return []; // Already confirmed

    // 1. Mark sale as Complete
    final updatedSale = sale.copyWith(orderStatus: 'Complete');
    await _salesBox.put(invoiceNo, updatedSale.toJson());

    // 2. Deduct quantities from stock for all product lines
    final items = getSaleItems(invoiceNo);
    return await _adjustStockForSale(items, isDeducting: true);
  }

  // Revert order status to PENDING and add back the deducted stock quantities
  Future<List<PricelistItem>> setSaleStatusPending(int invoiceNo) async {
    final rawSale = _salesBox.get(invoiceNo);
    if (rawSale == null) return [];

    final sale = Sale.fromJson(Map<String, dynamic>.from(rawSale));
    if (!_isSaleConfirmed(sale.orderStatus)) return []; // Already pending

    // 1. Mark sale as Pending
    final updatedSale = sale.copyWith(orderStatus: 'Pending');
    await _salesBox.put(invoiceNo, updatedSale.toJson());

    // 2. Add quantities back to stock for all product lines (revert deduction)
    final items = getSaleItems(invoiceNo);
    return await _adjustStockForSale(items, isDeducting: false);
  }

  // Delete sale records and revert stock if it was already confirmed
  Future<List<PricelistItem>> deleteSale(int invoiceNo) async {
    final rawSale = _salesBox.get(invoiceNo);
    if (rawSale == null) return [];

    final sale = Sale.fromJson(Map<String, dynamic>.from(rawSale));
    final List<PricelistItem> restoredProducts = [];

    // Revert stock deduction if order was already completed/confirmed
    if (_isSaleConfirmed(sale.orderStatus)) {
      final items = getSaleItems(invoiceNo);
      final res = await _adjustStockForSale(items, isDeducting: false);
      restoredProducts.addAll(res);
    }

    // Delete from boxes
    await _salesBox.delete(invoiceNo);
    await _saleItemsBox.delete(invoiceNo);
    return restoredProducts;
  }

  // --- Calls Methods ---
  int getNextCallId() {
    if (_callsBox.isEmpty) return 1;
    int maxId = 0;
    for (var key in _callsBox.keys) {
      if (key is int && key > maxId) maxId = key;
    }
    return maxId + 1;
  }

  List<CallModel> getCalls() {
    final List<CallModel> list = [];
    for (var key in _callsBox.keys) {
      final raw = _callsBox.get(key);
      if (raw != null) {
        list.add(CallModel.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    list.sort((a, b) {
      final dayA = DateTime(a.date.year, a.date.month, a.date.day);
      final dayB = DateTime(b.date.year, b.date.month, b.date.day);
      final d = dayB.compareTo(dayA);
      if (d != 0) return d;
      return b.id.compareTo(a.id);
    });
    return list;
  }

  Future<void> saveCall(CallModel call) async {
    await _callsBox.put(call.id, call.toJson());
  }

  /// Returns the raw Hive map for a specific call by ID (used for photo preservation during sync)
  Map<String, dynamic>? getCallById(int id) {
    final raw = _callsBox.get(id);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw);
  }

  Future<void> deleteCall(int id) async {
    await _callsBox.delete(id);
  }

  // --- Inward Repairs Methods ---
  int getNextInwardJobNo() {
    final repairs = getInwardRepairs();
    if (repairs.isEmpty) return 1;
    int maxJobNo = 0;
    for (final r in repairs) {
      if (r.jobNo > maxJobNo) maxJobNo = r.jobNo;
    }
    return maxJobNo + 1;
  }

  List<InwardRepair> getInwardRepairs() {
    final Map<int, InwardRepair> map = {};
    for (var key in _inwardBox.keys) {
      final raw = _inwardBox.get(key);
      if (raw != null) {
        final r = InwardRepair.fromJson(Map<String, dynamic>.from(raw));
        map[r.jobNo] = r;
      }
    }
    final list = map.values.toList();
    list.sort((a, b) {
      final dayA = DateTime(a.date.year, a.date.month, a.date.day);
      final dayB = DateTime(b.date.year, b.date.month, b.date.day);
      final d = dayB.compareTo(dayA);
      if (d != 0) return d;
      return b.jobNo.compareTo(a.jobNo);
    });
    return list;
  }

  /// Returns raw InwardRepair for a specific jobNo by key (used for photo preservation during sync)
  InwardRepair? getInwardRepairByJobNo(int jobNo) {
    final raw = _inwardBox.get(jobNo) ?? _inwardBox.get(jobNo.toString());
    if (raw == null) return null;
    return InwardRepair.fromJson(Map<String, dynamic>.from(raw));
  }

  List<InwardEstimateItem> getInwardEstimateItems(int jobNo) {
    dynamic rawList = _inwardItemsBox.get(jobNo);
    rawList ??= _inwardItemsBox.get(jobNo.toString());
    if (rawList == null) {
      for (final k in _inwardItemsBox.keys) {
        if (k.toString() == jobNo.toString()) {
          rawList = _inwardItemsBox.get(k);
          break;
        }
      }
    }
    if (rawList == null || rawList is! List) return [];
    return (rawList)
        .map(
          (raw) => InwardEstimateItem.fromJson(Map<String, dynamic>.from(raw)),
        )
        .toList();
  }

  Future<void> saveInwardRepair(
    InwardRepair repair,
    List<InwardEstimateItem> items,
  ) async {
    await _inwardBox.put(repair.jobNo, repair.toJson());
    final itemsJson = items.map((item) => item.toJson()).toList();
    await _inwardItemsBox.put(repair.jobNo, itemsJson);
  }

  /// Saves inward repair header without overwriting the estimate items box
  Future<void> saveInwardRepairHeaderOnly(InwardRepair repair) async {
    await _inwardBox.put(repair.jobNo, repair.toJson());
  }

  /// Upserts a single inward estimate item into the existing items box for a job
  Future<void> saveInwardEstimateItemOnly(InwardEstimateItem item) async {
    final items = getInwardEstimateItems(item.jobNo);
    final idx = items.indexWhere((i) => i.lineId == item.lineId);
    if (idx >= 0) {
      items[idx] = item;
    } else {
      items.add(item);
    }
    await _inwardItemsBox.put(
      item.jobNo,
      items.map((i) => i.toJson()).toList(),
    );
  }

  /// Deletes a single inward estimate item by lineId
  Future<void> deleteInwardEstimateItem(String lineId, int? jobNo) async {
    if (jobNo != null) {
      final items = getInwardEstimateItems(jobNo);
      final initialCount = items.length;
      items.removeWhere((i) => i.lineId == lineId);
      if (items.length != initialCount) {
        await _inwardItemsBox.put(
          jobNo,
          items.map((i) => i.toJson()).toList(),
        );
      }
    } else {
      for (final key in _inwardItemsBox.keys) {
        final jno = key is int ? key : int.tryParse(key.toString());
        if (jno != null) {
          final items = getInwardEstimateItems(jno);
          final initialCount = items.length;
          items.removeWhere((i) => i.lineId == lineId);
          if (items.length != initialCount) {
            await _inwardItemsBox.put(
              jno,
              items.map((i) => i.toJson()).toList(),
            );
          }
        }
      }
    }
  }

  /// Deletes a single sale item by lineId / id
  Future<void> deleteSaleItem(String lineId, int? invoiceNo) async {
    if (invoiceNo != null) {
      final items = getSaleItems(invoiceNo);
      final initialCount = items.length;
      items.removeWhere((i) => i.id == lineId);
      if (items.length != initialCount) {
        await _saleItemsBox.put(
          invoiceNo,
          items.map((i) => i.toJson()).toList(),
        );
      }
    } else {
      for (final key in _saleItemsBox.keys) {
        final inv = key is int ? key : int.tryParse(key.toString());
        if (inv != null) {
          final items = getSaleItems(inv);
          final initialCount = items.length;
          items.removeWhere((i) => i.id == lineId);
          if (items.length != initialCount) {
            await _saleItemsBox.put(
              inv,
              items.map((i) => i.toJson()).toList(),
            );
          }
        }
      }
    }
  }

  /// Deletes a single purchase order item by lineId
  Future<void> deletePurchaseOrderItem(String lineId, String? purchaseId) async {
    if (purchaseId != null && purchaseId.isNotEmpty) {
      final items = getPurchaseOrderItems(purchaseId);
      final initialCount = items.length;
      items.removeWhere((i) => i.lineId == lineId);
      if (items.length != initialCount) {
        await _purchaseItemsBox.put(
          purchaseId,
          items.map((i) => i.toJson()).toList(),
        );
      }
    } else {
      for (final key in _purchaseItemsBox.keys) {
        final pid = key.toString();
        final items = getPurchaseOrderItems(pid);
        final initialCount = items.length;
        items.removeWhere((i) => i.lineId == lineId);
        if (items.length != initialCount) {
          await _purchaseItemsBox.put(
            pid,
            items.map((i) => i.toJson()).toList(),
          );
        }
      }
    }
  }

  /// Checks whether there are pending sync queue operations for a given parent record
  bool hasPendingSyncForParent(String table, String parentKeyColumn, dynamic parentKeyValue) {
    if (parentKeyValue == null) return false;
    final parentKeyStr = parentKeyValue.toString().trim().toLowerCase();
    final pendingOps = getPendingSyncQueue();
    return pendingOps.any((op) {
      final opTable = op['table']?.toString();
      if (opTable != table) return false;
      final opParentKey = op['parent_key_value']?.toString().trim().toLowerCase();
      if (opParentKey == parentKeyStr) return true;
      final data = op['data'];
      if (data is Map) {
        final val = data[parentKeyColumn]?.toString().trim().toLowerCase();
        if (val == parentKeyStr) return true;
      }
      return false;
    });
  }

  Future<void> saveAllInwardRepairs(
    Map<int, Map<String, dynamic>> repairsMap,
    Map<int, List<Map<String, dynamic>>> itemsMap, {
    bool clearOthers = true,
  }) async {
    if (clearOthers) {
      final existingKeys = Set.of(_inwardBox.keys);
      final validKeys = repairsMap.keys.toSet();
      final pendingOps = getPendingSyncQueue();
      final pendingJobNos = pendingOps
          .where((op) => op['table'] == 'inward_repairs' && op['data'] != null)
          .map((op) => int.tryParse(op['data']['job_no']?.toString() ?? ''))
          .whereType<int>()
          .toSet();

      for (final key in existingKeys) {
        final keyInt = key is int ? key : int.tryParse(key.toString());
        if (keyInt != null && !validKeys.contains(keyInt)) {
          if (pendingJobNos.contains(keyInt)) continue;
          await _inwardBox.delete(key);
          await _inwardItemsBox.delete(key);
        }
      }
    }
    if (repairsMap.isNotEmpty) await _inwardBox.putAll(repairsMap);
    if (itemsMap.isNotEmpty) await _inwardItemsBox.putAll(itemsMap);
  }

  Future<void> saveAllReplacements(
    Map<String, Map<String, dynamic>> map, {
    bool clearOthers = true,
  }) async {
    if (clearOthers) {
      final existingKeys = Set.of(_replacementBox.keys);
      final validKeys = map.keys.map((k) => k.trim().toUpperCase()).toSet();
      final pendingOps = getPendingSyncQueue();
      final pendingJobNos = pendingOps
          .where((op) => op['table'] == 'replacements' && op['data'] != null)
          .map((op) => op['data']['job_no']?.toString().trim().toUpperCase())
          .whereType<String>()
          .toSet();

      for (final key in existingKeys) {
        final keyStr = key.toString().trim().toUpperCase();
        if (!validKeys.contains(keyStr)) {
          if (pendingJobNos.contains(keyStr)) continue;
          await _replacementBox.delete(key);
        }
      }
    }
    if (map.isNotEmpty) await _replacementBox.putAll(map);
  }

  Future<void> saveAllRequests(
    Map<String, Map<String, dynamic>> map, {
    bool clearOthers = true,
  }) async {
    if (clearOthers) {
      final existingKeys = Set.of(_requestBox.keys);
      final validKeys = map.keys.map((k) => k.trim().toUpperCase()).toSet();
      final pendingOps = getPendingSyncQueue();
      final pendingIds = pendingOps
          .where((op) => op['table'] == 'requests' && op['data'] != null)
          .map((op) => op['data']['id']?.toString().trim().toUpperCase())
          .whereType<String>()
          .toSet();

      for (final key in existingKeys) {
        final keyStr = key.toString().trim().toUpperCase();
        if (!validKeys.contains(keyStr)) {
          if (pendingIds.contains(keyStr)) continue;
          await _requestBox.delete(key);
        }
      }
    }
    if (map.isNotEmpty) await _requestBox.putAll(map);
  }

  Future<void> saveAllCalls(
    Map<int, Map<String, dynamic>> map, {
    bool clearOthers = true,
  }) async {
    if (clearOthers) {
      final existingKeys = Set.of(_callsBox.keys);
      final validKeys = map.keys.toSet();
      final pendingOps = getPendingSyncQueue();
      final pendingIds = pendingOps
          .where((op) => op['table'] == 'calls' && op['data'] != null)
          .map((op) => int.tryParse(op['data']['id']?.toString() ?? ''))
          .whereType<int>()
          .toSet();

      for (final key in existingKeys) {
        final keyInt = key is int ? key : int.tryParse(key.toString());
        if (keyInt != null && !validKeys.contains(keyInt)) {
          if (pendingIds.contains(keyInt)) continue;
          await _callsBox.delete(key);
        }
      }
    }
    if (map.isNotEmpty) await _callsBox.putAll(map);
  }

  Future<void> saveAllSales(
    Map<int, Map<String, dynamic>> salesMap,
    Map<int, List<Map<String, dynamic>>> itemsMap, {
    bool clearOthers = true,
  }) async {
    if (clearOthers) {
      final existingKeys = Set.of(_salesBox.keys);
      final validKeys = salesMap.keys.toSet();
      final pendingOps = getPendingSyncQueue();
      final pendingInvoices = pendingOps
          .where((op) => op['table'] == 'sales' && op['data'] != null)
          .map((op) => int.tryParse(op['data']['invoice_no']?.toString() ?? ''))
          .whereType<int>()
          .toSet();

      for (final key in existingKeys) {
        final keyInt = key is int ? key : int.tryParse(key.toString());
        if (keyInt != null && !validKeys.contains(keyInt)) {
          if (pendingInvoices.contains(keyInt)) continue;
          await _salesBox.delete(key);
          await _saleItemsBox.delete(key);
        }
      }
    }
    if (salesMap.isNotEmpty) await _salesBox.putAll(salesMap);
    if (itemsMap.isNotEmpty) await _saleItemsBox.putAll(itemsMap);
  }

  Future<void> saveAllPurchases(
    Map<String, Map<String, dynamic>> purchasesMap,
    Map<String, List<Map<String, dynamic>>> itemsMap, {
    bool clearOthers = true,
  }) async {
    if (clearOthers) {
      final existingKeys = Set.of(_purchaseBox.keys);
      final validKeys = purchasesMap.keys.map((k) => k.trim().toUpperCase()).toSet();
      final pendingOps = getPendingSyncQueue();
      final pendingIds = pendingOps
          .where((op) => op['table'] == 'purchases' && op['data'] != null)
          .map((op) => op['data']['id']?.toString().trim().toUpperCase())
          .whereType<String>()
          .toSet();

      for (final key in existingKeys) {
        final keyStr = key.toString().trim().toUpperCase();
        if (!validKeys.contains(keyStr)) {
          if (pendingIds.contains(keyStr)) continue;
          await _purchaseBox.delete(key);
          await _purchaseItemsBox.delete(key);
        }
      }
    }
    if (purchasesMap.isNotEmpty) await _purchaseBox.putAll(purchasesMap);
    if (itemsMap.isNotEmpty) await _purchaseItemsBox.putAll(itemsMap);
  }

  Future<void> saveAllPricelistItems(
    Map<int, Map<String, dynamic>> map, {
    bool clearOthers = true,
  }) async {
    if (clearOthers) {
      final existingKeys = Set.of(_pricelistBox.keys);
      final validKeys = map.keys.toSet();
      final pendingOps = getPendingSyncQueue();
      final pendingIds = pendingOps
          .where((op) => op['table'] == 'pricelist' && op['data'] != null)
          .map((op) => int.tryParse(op['data']['id']?.toString() ?? ''))
          .whereType<int>()
          .toSet();

      for (final key in existingKeys) {
        final keyInt = key is int ? key : int.tryParse(key.toString());
        if (keyInt != null && !validKeys.contains(keyInt)) {
          if (pendingIds.contains(keyInt)) continue;
          await _pricelistBox.delete(key);
        }
      }
    }
    if (map.isNotEmpty) await _pricelistBox.putAll(map);
  }

  Future<void> deleteInwardRepair(int jobNo) async {
    await _inwardBox.delete(jobNo);
    await _inwardItemsBox.delete(jobNo);
  }

  // --- Replacement Methods ---
  String getNextReplacementJobNo() {
    if (_replacementBox.isEmpty) return 'Z1';
    int maxNum = 0;
    for (var key in _replacementBox.keys) {
      final keyStr = key.toString();
      if (keyStr.startsWith('Z')) {
        final parsed = int.tryParse(keyStr.substring(1));
        if (parsed != null && parsed > maxNum) {
          maxNum = parsed;
        }
      }
    }
    return 'Z${maxNum + 1}';
  }

  List<Replacement> getReplacements() {
    final List<Replacement> list = [];
    for (var key in _replacementBox.keys) {
      final raw = _replacementBox.get(key);
      if (raw != null) {
        list.add(Replacement.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    list.sort((a, b) {
      final dayA = DateTime(a.date.year, a.date.month, a.date.day);
      final dayB = DateTime(b.date.year, b.date.month, b.date.day);
      final d = dayB.compareTo(dayA);
      if (d != 0) return d;
      return b.jobNo.compareTo(a.jobNo);
    });
    return list;
  }

  Future<void> saveReplacement(Replacement repl) async {
    await _replacementBox.put(repl.jobNo, repl.toJson());
  }

  Future<void> deleteReplacement(String jobNo) async {
    await _replacementBox.delete(jobNo);
  }

  // --- Request Orders Methods ---
  String _generateRandomHexId() {
    final int ts = DateTime.now().microsecondsSinceEpoch;
    final String hex = ts.toRadixString(16);
    if (hex.length >= 8) {
      return hex.substring(hex.length - 8);
    }
    return hex.padLeft(8, '0');
  }

  String getNextRequestOrderId() {
    return _generateRandomHexId();
  }

  List<RequestOrder> getRequestOrders() {
    final List<RequestOrder> list = [];
    for (var key in _requestBox.keys) {
      final raw = _requestBox.get(key);
      if (raw != null) {
        list.add(RequestOrder.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    list.sort((a, b) {
      final dayA = DateTime(a.date.year, a.date.month, a.date.day);
      final dayB = DateTime(b.date.year, b.date.month, b.date.day);
      final d = dayB.compareTo(dayA);
      if (d != 0) return d;
      return b.id.compareTo(a.id);
    });
    return list;
  }

  Future<void> saveRequestOrder(RequestOrder order) async {
    await _requestBox.put(order.id, order.toJson());
  }

  Future<void> deleteRequestOrder(String id) async {
    await _requestBox.delete(id);
  }

  // --- Purchase Orders (Stock-In) Methods ---
  String getNextPurchaseOrderId() {
    return _generateRandomHexId();
  }

  List<PurchaseOrder> getPurchaseOrders() {
    final List<PurchaseOrder> list = [];
    for (var key in _purchaseBox.keys) {
      final raw = _purchaseBox.get(key);
      if (raw != null) {
        list.add(PurchaseOrder.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    list.sort((a, b) {
      final dayA = DateTime(a.date.year, a.date.month, a.date.day);
      final dayB = DateTime(b.date.year, b.date.month, b.date.day);
      final d = dayB.compareTo(dayA);
      if (d != 0) return d;
      return b.id.compareTo(a.id);
    });
    return list;
  }

  List<PurchaseOrderItem> getPurchaseOrderItems(String purchaseId) {
    dynamic rawList = _purchaseItemsBox.get(purchaseId);
    rawList ??= _purchaseItemsBox.get(purchaseId.toString());
    if (rawList == null) {
      for (final k in _purchaseItemsBox.keys) {
        if (k.toString() == purchaseId.toString()) {
          rawList = _purchaseItemsBox.get(k);
          break;
        }
      }
    }
    if (rawList == null || rawList is! List) return [];
    return rawList
        .map(
          (raw) => PurchaseOrderItem.fromJson(Map<String, dynamic>.from(raw)),
        )
        .toList();
  }

  /// Returns true if the given purchase status represents a 'stock-added' state.
  /// Treats 'CONFIRMED', 'confirmed', 'Complete', 'complete', 'COMPLETE' as equivalent.
  /// Returns true if the given purchase status represents a 'stock-added' state.
  /// Treats 'CONFIRMED', 'confirmed', 'Complete', 'complete', 'COMPLETE', 'Received', 'Inwarded', 'Stocked' as equivalent.
  bool _isPurchaseConfirmedStatus(String status) {
    final s = status.trim().toLowerCase();
    return s == 'confirmed' ||
        s == 'complete' ||
        s == 'completed' ||
        s == 'received' ||
        s == 'inwarded' ||
        s == 'stocked';
  }

  /// Returns true if the given purchase status represents a 'pending / not yet stocked' state.
  bool _isPurchasePendingStatus(String status) {
    final s = status.trim().toLowerCase();
    return s == 'pending';
  }

  Future<List<PricelistItem>> savePurchaseOrder(
    PurchaseOrder order,
    List<PurchaseOrderItem> items,
  ) async {
    final List<PricelistItem> updatedProducts = [];
    final rawExisting = _purchaseBox.get(order.id);

    if (rawExisting != null) {
      final existing = PurchaseOrder.fromJson(
        Map<String, dynamic>.from(rawExisting),
      );
      final wasConfirmed = _isPurchaseConfirmedStatus(existing.status);
      final nowConfirmed = _isPurchaseConfirmedStatus(order.status);

      if (!wasConfirmed && nowConfirmed) {
        // Transitioned to complete/confirmed — add stock
        final res = await _adjustStockForPurchase(items, isAdding: true);
        updatedProducts.addAll(res);
      } else if (wasConfirmed && !nowConfirmed) {
        // Reverted from complete/confirmed — remove stock
        final oldItems = getPurchaseOrderItems(order.id);
        final res = await _adjustStockForPurchase(oldItems, isAdding: false);
        updatedProducts.addAll(res);
      } else if (wasConfirmed && nowConfirmed) {
        // Was confirmed, still confirmed but items may have changed — re-adjust
        final oldItems = getPurchaseOrderItems(order.id);
        final res1 = await _adjustStockForPurchase(oldItems, isAdding: false);
        final res2 = await _adjustStockForPurchase(items, isAdding: true);
        updatedProducts.addAll(res1);
        updatedProducts.addAll(res2);
      }
    } else {
      // New purchase order
      if (_isPurchaseConfirmedStatus(order.status)) {
        final res = await _adjustStockForPurchase(items, isAdding: true);
        updatedProducts.addAll(res);
      }
    }

    await _purchaseBox.put(order.id, order.toJson());
    final itemsJson = items.map((item) => item.toJson()).toList();
    await _purchaseItemsBox.put(order.id, itemsJson);

    return updatedProducts;
  }

  /// Saves purchase order header without overwriting the items box
  Future<void> savePurchaseOrderHeaderOnly(PurchaseOrder order) async {
    await _purchaseBox.put(order.id, order.toJson());
  }

  /// Upserts a single purchase order item into the existing items box for a purchase
  Future<void> savePurchaseOrderItemOnly(PurchaseOrderItem item) async {
    final items = getPurchaseOrderItems(item.purchaseId);
    final idx = items.indexWhere((i) => i.lineId == item.lineId);
    if (idx >= 0) {
      items[idx] = item;
    } else {
      items.add(item);
    }
    await _purchaseItemsBox.put(
      item.purchaseId,
      items.map((i) => i.toJson()).toList(),
    );
  }

  Future<List<PricelistItem>> deletePurchaseOrder(String purchaseId) async {
    final List<PricelistItem> updatedProducts = [];
    final raw = _purchaseBox.get(purchaseId);
    if (raw != null) {
      final order = PurchaseOrder.fromJson(Map<String, dynamic>.from(raw));
      if (_isPurchaseConfirmedStatus(order.status)) {
        final items = getPurchaseOrderItems(purchaseId);
        final res = await _adjustStockForPurchase(items, isAdding: false);
        updatedProducts.addAll(res);
      }
    }
    await _purchaseBox.delete(purchaseId);
    await _purchaseItemsBox.delete(purchaseId);
    return updatedProducts;
  }

  Future<List<PricelistItem>> confirmPurchase(String purchaseId) async {
    final raw = _purchaseBox.get(purchaseId);
    if (raw == null) return [];
    final order = PurchaseOrder.fromJson(Map<String, dynamic>.from(raw));
    if (_isPurchaseConfirmedStatus(order.status)) return [];

    final updated = order.copyWith(status: 'CONFIRMED');
    await _purchaseBox.put(purchaseId, updated.toJson());

    final items = getPurchaseOrderItems(purchaseId);
    return await _adjustStockForPurchase(items, isAdding: true);
  }

  Future<List<PricelistItem>> setPurchaseStatusPending(String purchaseId) async {
    final raw = _purchaseBox.get(purchaseId);
    if (raw == null) return [];
    final order = PurchaseOrder.fromJson(Map<String, dynamic>.from(raw));
    if (_isPurchasePendingStatus(order.status)) return [];

    final updated = order.copyWith(status: 'PENDING');
    await _purchaseBox.put(purchaseId, updated.toJson());

    final items = getPurchaseOrderItems(purchaseId);
    return await _adjustStockForPurchase(items, isAdding: false);
  }

  Future<List<PricelistItem>> _adjustStockForPurchase(
    List<PurchaseOrderItem> items, {
    required bool isAdding,
  }) async {
    final List<PricelistItem> updatedProducts = [];

    for (var item in items) {
      final prod = _findPricelistProduct(
        item.itemId,
        item.itemName ?? item.customItemName,
      );

      if (prod != null) {
        final updated = prod.copyWith(
          stockQty: isAdding
              ? (prod.stockQty + item.quantity)
              : (prod.stockQty - item.quantity),
        );
        await _pricelistBox.put(prod.id, updated.toJson());
        updatedProducts.add(updated);
      }
    }

    return updatedProducts;
  }
}


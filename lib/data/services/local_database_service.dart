import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
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

class LocalDatabaseService {
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

  Future<void> init() async {
    await Hive.initFlutter();

    _pricelistBox = await Hive.openBox(_pricelistBoxName);
    _settingsBox = await Hive.openBox(_settingsBoxName);
    _salesBox = await Hive.openBox(_salesBoxName);
    _saleItemsBox = await Hive.openBox(_saleItemsBoxName);
    _callsBox = await Hive.openBox(_callsBoxName);
    _inwardBox = await Hive.openBox(_inwardBoxName);
    _inwardItemsBox = await Hive.openBox(_inwardItemsBoxName);
    _replacementBox = await Hive.openBox(_replacementBoxName);
    _requestBox = await Hive.openBox(_requestBoxName);
    _purchaseBox = await Hive.openBox(_purchaseBoxName);
    _purchaseItemsBox = await Hive.openBox(_purchaseItemsBoxName);

    // Seed data is disabled since Supabase is now the source of truth
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

  Future<void> savePricelistItem(PricelistItem item) async {
    await _pricelistBox.put(item.id, item.toJson());
  }

  Future<void> deletePricelistItem(int id) async {
    await _pricelistBox.delete(id);
  }

  Future<void> clearDatabase() async {
    await _pricelistBox.clear();
    await _seedPricelist();
  }

  // --- Settings Methods ---

  String? getActiveUpiId() {
    return _settingsBox.get('active_upi_id');
  }

  Future<void> setActiveUpiId(String upiId) async {
    await _settingsBox.put('active_upi_id', upiId);
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

  Future<void> saveUpiIdsList(List<String> upiIds) async {
    await _settingsBox.put('upi_ids_list', upiIds);
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

  Future<void> saveCustomServiceName(String name) async {
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

  // --- Sales Methods ---

  int getNextInvoiceNo() {
    if (_salesBox.isEmpty) {
      return 1001;
    }
    int maxInvoiceNo = 1000;
    for (var key in _salesBox.keys) {
      if (key is int && key > maxInvoiceNo) {
        maxInvoiceNo = key;
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
    sales.sort((a, b) => b.saleDate.compareTo(a.saleDate));
    return sales;
  }

  List<SaleItem> getSaleItems(int invoiceNo) {
    final List<dynamic>? rawList = _saleItemsBox.get(invoiceNo);
    if (rawList == null) return [];
    return rawList
        .map((raw) => SaleItem.fromJson(Map<String, dynamic>.from(raw)))
        .toList();
  }

  Future<void> saveSale(Sale sale, List<SaleItem> items) async {
    await _salesBox.put(sale.invoiceNo, sale.toJson());

    final itemsJson = items.map((item) => item.toJson()).toList();
    await _saleItemsBox.put(sale.invoiceNo, itemsJson);
  }

  // Confirm order and deduct inventory
  Future<List<PricelistItem>> confirmSale(int invoiceNo) async {
    final rawSale = _salesBox.get(invoiceNo);
    if (rawSale == null) return [];

    final sale = Sale.fromJson(Map<String, dynamic>.from(rawSale));
    if (sale.orderStatus == 'Confirmed') return []; // Already confirmed

    // 1. Mark sale as Confirmed
    final updatedSale = sale.copyWith(orderStatus: 'Confirmed');
    await _salesBox.put(invoiceNo, updatedSale.toJson());

    // 2. Deduct quantities from stock for all product lines
    final items = getSaleItems(invoiceNo);
    final List<PricelistItem> updatedProducts = [];

    for (var item in items) {
      if (item.lineType == 'Product') {
        dynamic rawProduct;
        if (item.itemId != null) {
          rawProduct = _pricelistBox.get(item.itemId);
        }
        if (rawProduct == null) {
          final targetDesc = (item.itemDescription ?? '').trim().toLowerCase();
          for (var key in _pricelistBox.keys) {
            final raw = _pricelistBox.get(key);
            if (raw != null) {
              final p = PricelistItem.fromJson(Map<String, dynamic>.from(raw));
              if (p.itemName.trim().toLowerCase() == targetDesc) {
                rawProduct = raw;
                break;
              }
            }
          }
        }

        if (rawProduct != null) {
          final product = PricelistItem.fromJson(
            Map<String, dynamic>.from(rawProduct),
          );
          final updatedProduct = product.copyWith(
            stockQty: product.stockQty - item.quantity,
          );
          await _pricelistBox.put(product.id, updatedProduct.toJson());
          updatedProducts.add(updatedProduct);
        }
      }
    }

    return updatedProducts;
  }

  // Revert order status to PENDING and add back the deducted stock quantities
  Future<List<PricelistItem>> setSaleStatusPending(int invoiceNo) async {
    final rawSale = _salesBox.get(invoiceNo);
    if (rawSale == null) return [];

    final sale = Sale.fromJson(Map<String, dynamic>.from(rawSale));
    if (sale.orderStatus == 'PENDING') return []; // Already pending

    // 1. Mark sale as PENDING
    final updatedSale = sale.copyWith(orderStatus: 'PENDING');
    await _salesBox.put(invoiceNo, updatedSale.toJson());

    // 2. Add quantities back to stock for all product lines (revert deduction)
    final items = getSaleItems(invoiceNo);
    final List<PricelistItem> updatedProducts = [];

    for (var item in items) {
      if (item.lineType == 'Product') {
        dynamic rawProduct;
        if (item.itemId != null) {
          rawProduct = _pricelistBox.get(item.itemId);
        }
        if (rawProduct == null) {
          final targetDesc = (item.itemDescription ?? '').trim().toLowerCase();
          for (var key in _pricelistBox.keys) {
            final raw = _pricelistBox.get(key);
            if (raw != null) {
              final p = PricelistItem.fromJson(Map<String, dynamic>.from(raw));
              if (p.itemName.trim().toLowerCase() == targetDesc) {
                rawProduct = raw;
                break;
              }
            }
          }
        }

        if (rawProduct != null) {
          final product = PricelistItem.fromJson(
            Map<String, dynamic>.from(rawProduct),
          );
          final updatedProduct = product.copyWith(
            stockQty: product.stockQty + item.quantity,
          );
          await _pricelistBox.put(product.id, updatedProduct.toJson());
          updatedProducts.add(updatedProduct);
        }
      }
    }

    return updatedProducts;
  }

  // Delete sale records and revert stock if it was already confirmed
  Future<bool> deleteSale(int invoiceNo) async {
    final rawSale = _salesBox.get(invoiceNo);
    if (rawSale == null) return false;

    final sale = Sale.fromJson(Map<String, dynamic>.from(rawSale));

    // Revert stock deduction if order was already confirmed
    if (sale.orderStatus == 'Confirmed') {
      final items = getSaleItems(invoiceNo);
      for (var item in items) {
        if (item.lineType == 'Product' && item.itemId != null) {
          final rawProduct = _pricelistBox.get(item.itemId);
          if (rawProduct != null) {
            final product = PricelistItem.fromJson(
              Map<String, dynamic>.from(rawProduct),
            );
            final updatedProduct = product.copyWith(
              stockQty: product.stockQty + item.quantity,
            );
            await _pricelistBox.put(product.id, updatedProduct.toJson());
          }
        }
      }
    }

    // Delete from boxes
    await _salesBox.delete(invoiceNo);
    await _saleItemsBox.delete(invoiceNo);
    return true;
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
    list.sort((a, b) => b.date.compareTo(a.date));
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
    if (_inwardBox.isEmpty) return 4111;
    int maxJobNo = 4110;
    for (var key in _inwardBox.keys) {
      if (key is int && key > maxJobNo) maxJobNo = key;
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
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
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

  Future<void> saveAllInwardRepairs(
    Map<int, Map<String, dynamic>> repairsMap,
    Map<int, List<Map<String, dynamic>>> itemsMap,
  ) async {
    final existingKeys = Set.of(_inwardBox.keys);
    final validKeys = repairsMap.keys.toSet();
    for (final key in existingKeys.difference(validKeys)) {
      await _inwardBox.delete(key);
      await _inwardItemsBox.delete(key);
    }
    if (repairsMap.isNotEmpty) await _inwardBox.putAll(repairsMap);
    if (itemsMap.isNotEmpty) await _inwardItemsBox.putAll(itemsMap);
  }

  Future<void> saveAllReplacements(
    Map<String, Map<String, dynamic>> map,
  ) async {
    final existingKeys = Set.of(_replacementBox.keys);
    final validKeys = map.keys.toSet();
    for (final key in existingKeys.difference(validKeys)) {
      await _replacementBox.delete(key);
    }
    if (map.isNotEmpty) await _replacementBox.putAll(map);
  }

  Future<void> saveAllRequests(Map<String, Map<String, dynamic>> map) async {
    final existingKeys = Set.of(_requestBox.keys);
    final validKeys = map.keys.toSet();
    for (final key in existingKeys.difference(validKeys)) {
      await _requestBox.delete(key);
    }
    if (map.isNotEmpty) await _requestBox.putAll(map);
  }

  Future<void> saveAllCalls(Map<int, Map<String, dynamic>> map) async {
    final existingKeys = Set.of(_callsBox.keys);
    final validKeys = map.keys.toSet();
    for (final key in existingKeys.difference(validKeys)) {
      await _callsBox.delete(key);
    }
    if (map.isNotEmpty) await _callsBox.putAll(map);
  }

  Future<void> saveAllSales(
    Map<int, Map<String, dynamic>> salesMap,
    Map<int, List<Map<String, dynamic>>> itemsMap,
  ) async {
    final existingKeys = Set.of(_salesBox.keys);
    final validKeys = salesMap.keys.toSet();
    for (final key in existingKeys.difference(validKeys)) {
      await _salesBox.delete(key);
      await _saleItemsBox.delete(key);
    }
    if (salesMap.isNotEmpty) await _salesBox.putAll(salesMap);
    if (itemsMap.isNotEmpty) await _saleItemsBox.putAll(itemsMap);
  }

  Future<void> saveAllPurchases(
    Map<String, Map<String, dynamic>> purchasesMap,
    Map<String, List<Map<String, dynamic>>> itemsMap,
  ) async {
    final existingKeys = Set.of(_purchaseBox.keys);
    final validKeys = purchasesMap.keys.toSet();
    for (final key in existingKeys.difference(validKeys)) {
      await _purchaseBox.delete(key);
      await _purchaseItemsBox.delete(key);
    }
    if (purchasesMap.isNotEmpty) await _purchaseBox.putAll(purchasesMap);
    if (itemsMap.isNotEmpty) await _purchaseItemsBox.putAll(itemsMap);
  }

  Future<void> saveAllPricelistItems(Map<int, Map<String, dynamic>> map) async {
    final existingKeys = Set.of(_pricelistBox.keys);
    final validKeys = map.keys.toSet();
    for (final key in existingKeys.difference(validKeys)) {
      await _pricelistBox.delete(key);
    }
    if (map.isNotEmpty) await _pricelistBox.putAll(map);
  }

  Future<void> deleteInwardRepair(int jobNo) async {
    await _inwardBox.delete(jobNo);
    await _inwardItemsBox.delete(jobNo);
  }

  // --- Replacement Methods ---
  String getNextReplacementJobNo() {
    if (_replacementBox.isEmpty) return 'Z223';
    int maxNum = 222;
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
    list.sort((a, b) => b.date.compareTo(a.date));
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
    list.sort((a, b) => b.date.compareTo(a.date));
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
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  List<PurchaseOrderItem> getPurchaseOrderItems(String purchaseId) {
    final List<dynamic>? rawList = _purchaseItemsBox.get(purchaseId);
    if (rawList == null) return [];
    return rawList
        .map(
          (raw) => PurchaseOrderItem.fromJson(Map<String, dynamic>.from(raw)),
        )
        .toList();
  }

  Future<void> savePurchaseOrder(
    PurchaseOrder order,
    List<PurchaseOrderItem> items,
  ) async {
    final rawExisting = _purchaseBox.get(order.id);
    if (rawExisting != null) {
      final existing = PurchaseOrder.fromJson(
        Map<String, dynamic>.from(rawExisting),
      );
      if (existing.status == 'PENDING' && order.status == 'CONFIRMED') {
        await _adjustStockForPurchase(items, isAdding: true);
      } else if (existing.status == 'CONFIRMED' && order.status == 'PENDING') {
        await _adjustStockForPurchase(items, isAdding: false);
      }
    } else {
      if (order.status == 'CONFIRMED') {
        await _adjustStockForPurchase(items, isAdding: true);
      }
    }

    await _purchaseBox.put(order.id, order.toJson());
    final itemsJson = items.map((item) => item.toJson()).toList();
    await _purchaseItemsBox.put(order.id, itemsJson);
  }

  Future<void> deletePurchaseOrder(String purchaseId) async {
    final raw = _purchaseBox.get(purchaseId);
    if (raw != null) {
      final order = PurchaseOrder.fromJson(Map<String, dynamic>.from(raw));
      if (order.status == 'CONFIRMED') {
        final items = getPurchaseOrderItems(purchaseId);
        await _adjustStockForPurchase(items, isAdding: false);
      }
    }
    await _purchaseBox.delete(purchaseId);
    await _purchaseItemsBox.delete(purchaseId);
  }

  Future<bool> confirmPurchase(String purchaseId) async {
    final raw = _purchaseBox.get(purchaseId);
    if (raw == null) return false;
    final order = PurchaseOrder.fromJson(Map<String, dynamic>.from(raw));
    if (order.status == 'CONFIRMED') return false;

    final updated = order.copyWith(status: 'CONFIRMED');
    await _purchaseBox.put(purchaseId, updated.toJson());

    final items = getPurchaseOrderItems(purchaseId);
    await _adjustStockForPurchase(items, isAdding: true);
    return true;
  }

  Future<bool> setPurchaseStatusPending(String purchaseId) async {
    final raw = _purchaseBox.get(purchaseId);
    if (raw == null) return false;
    final order = PurchaseOrder.fromJson(Map<String, dynamic>.from(raw));
    if (order.status == 'PENDING') return false;

    final updated = order.copyWith(status: 'PENDING');
    await _purchaseBox.put(purchaseId, updated.toJson());

    final items = getPurchaseOrderItems(purchaseId);
    await _adjustStockForPurchase(items, isAdding: false);
    return true;
  }

  Future<void> _adjustStockForPurchase(
    List<PurchaseOrderItem> items, {
    required bool isAdding,
  }) async {
    for (var item in items) {
      if (item.itemId != null) {
        final rawProd = _pricelistBox.get(item.itemId);
        if (rawProd != null) {
          final prod = PricelistItem.fromJson(
            Map<String, dynamic>.from(rawProd),
          );
          final updated = prod.copyWith(
            stockQty: isAdding
                ? (prod.stockQty + item.quantity)
                : (prod.stockQty - item.quantity),
          );
          await _pricelistBox.put(prod.id, updated.toJson());
        }
      }
    }
  }
}

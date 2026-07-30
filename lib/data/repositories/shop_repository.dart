import '../models/pricelist_item.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/call_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inward_repair.dart';
import '../models/inward_estimate_item.dart';
import '../models/replacement.dart';
import '../models/request_order.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../services/local_database_service.dart';
import '../services/supabase_sync_service.dart';

class ShopRepository {
  final LocalDatabaseService _localDb;

  ShopRepository({required LocalDatabaseService localDb}) : _localDb = localDb;

  LocalDatabaseService get localDb => _localDb;

  // Pricelist
  List<PricelistItem> getPricelist() => _localDb.getPricelist();
  Future<void> savePricelistItem(PricelistItem item) async {
    await _localDb.savePricelistItem(item);
    await SupabaseSyncService.instance.pushRecordToCloud(
      'pricelist',
      item.toJson(),
    );
  }

  Future<void> deletePricelistItem(int id) async {
    await _localDb.deletePricelistItem(id);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'pricelist',
      'id',
      id,
    );
  }

  Future<void> resetPricelistToDefault() async =>
      await _localDb.clearDatabase();

  // Settings
  String? getActiveUpiId() => _localDb.getActiveUpiId();
  Future<void> setActiveUpiId(String upiId) async =>
      await _localDb.setActiveUpiId(upiId);
  List<String> getUpiIdsList() => _localDb.getUpiIdsList();
  Future<void> saveUpiIdsList(List<String> upiIds) async =>
      await _localDb.saveUpiIdsList(upiIds);
  List<String> getCustomServiceNames() => _localDb.getCustomServiceNames();
  Future<void> saveCustomServiceName(String name) async =>
      await _localDb.saveCustomServiceName(name);
  double? getDetailPopupWidth() => _localDb.getDetailPopupWidth();
  double? getDetailPopupHeight() => _localDb.getDetailPopupHeight();
  Future<void> saveDetailPopupSize(double width, double height) async =>
      await _localDb.saveDetailPopupSize(width, height);

  // Sales
  int getNextInvoiceNo() => _localDb.getNextInvoiceNo();
  List<Sale> getSales() => _localDb.getSales();
  List<SaleItem> getSaleItems(int invoiceNo) =>
      _localDb.getSaleItems(invoiceNo);
  Future<void> saveSale(Sale sale, List<SaleItem> items) async {
    await _localDb.saveSale(sale, items);
    await SupabaseSyncService.instance.pushRecordToCloud(
      'sales',
      sale.toJson(),
    );
    for (final item in items) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'sale_items',
        item.toJson(),
      );
    }
  }

  Future<bool> confirmSale(int invoiceNo) async {
    final updatedProducts = await _localDb.confirmSale(invoiceNo);
    final sales = _localDb.getSales();
    final sale = sales.firstWhere(
      (s) => s.invoiceNo == invoiceNo,
      orElse: () => sales.first,
    );
    await SupabaseSyncService.instance.pushRecordToCloud(
      'sales',
      sale.toJson(),
    );
    for (final p in updatedProducts) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'pricelist',
        p.toJson(),
      );
    }
    return true;
  }

  Future<bool> setSaleStatusPending(int invoiceNo) async {
    final updatedProducts = await _localDb.setSaleStatusPending(invoiceNo);
    final sales = _localDb.getSales();
    final sale = sales.firstWhere(
      (s) => s.invoiceNo == invoiceNo,
      orElse: () => sales.first,
    );
    await SupabaseSyncService.instance.pushRecordToCloud(
      'sales',
      sale.toJson(),
    );
    for (final p in updatedProducts) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'pricelist',
        p.toJson(),
      );
    }
    return true;
  }

  Future<bool> updateSale(Sale sale, List<SaleItem> items) async {
    await _localDb.saveSale(sale, items);
    try {
      final client = Supabase.instance.client;
      await client.from('sales').upsert(sale.toJson());
      await client.from('sale_items').upsert(items.map((i) => i.toJson()).toList());
    } catch (_) {}
    return true;
  }

  Future<bool> deleteSale(int invoiceNo) async {
    final res = await _localDb.deleteSale(invoiceNo);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'sales',
      'invoice_no',
      invoiceNo,
    );
    return res;
  }

  // Calls
  int getNextCallId() => _localDb.getNextCallId();
  List<CallModel> getCalls() => _localDb.getCalls();
  Future<void> saveCall(CallModel call) async {
    await _localDb.saveCall(call);
    await SupabaseSyncService.instance.pushRecordToCloud(
      'calls',
      call.toJson(),
    );
  }

  Future<void> deleteCall(int id) async {
    await _localDb.deleteCall(id);
    await SupabaseSyncService.instance.deleteRecordFromCloud('calls', 'id', id);
  }

  // Inward Repairs
  int getNextInwardJobNo() => _localDb.getNextInwardJobNo();
  List<InwardRepair> getInwardRepairs() => _localDb.getInwardRepairs();
  List<InwardEstimateItem> getInwardEstimateItems(int jobNo) =>
      _localDb.getInwardEstimateItems(jobNo);
  Future<void> saveInwardRepair(
    InwardRepair repair,
    List<InwardEstimateItem> items,
  ) async {
    await _localDb.saveInwardRepair(repair, items);
    await SupabaseSyncService.instance.pushRecordToCloud(
      'inward_repairs',
      repair.toJson(),
    );
    await SupabaseSyncService.instance.saveEstimateItemsForJob(
      repair.jobNo,
      items,
    );
  }

  Future<void> deleteInwardRepair(int jobNo) async {
    await _localDb.deleteInwardRepair(jobNo);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'inward_repairs',
      'job_no',
      jobNo,
    );
    await SupabaseSyncService.instance.deleteEstimateItemsForJob(jobNo);
  }

  // Replacements
  String getNextReplacementJobNo() => _localDb.getNextReplacementJobNo();
  List<Replacement> getReplacements() => _localDb.getReplacements();
  Future<void> saveReplacement(Replacement repl) async {
    await _localDb.saveReplacement(repl);
    await SupabaseSyncService.instance.pushRecordToCloud(
      'replacements',
      repl.toJson(),
    );
  }

  Future<void> deleteReplacement(String jobNo) async {
    await _localDb.deleteReplacement(jobNo);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'replacements',
      'job_no',
      jobNo,
    );
  }

  // Request Orders
  String getNextRequestOrderId() => _localDb.getNextRequestOrderId();
  List<RequestOrder> getRequestOrders() => _localDb.getRequestOrders();
  Future<void> saveRequestOrder(RequestOrder order) async {
    await _localDb.saveRequestOrder(order);
    await SupabaseSyncService.instance.pushRecordToCloud(
      'requests',
      order.toJson(),
    );
  }

  Future<void> deleteRequestOrder(String id) async {
    await _localDb.deleteRequestOrder(id);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'requests',
      'id',
      id,
    );
  }

  // Purchase Orders
  String getNextPurchaseOrderId() => _localDb.getNextPurchaseOrderId();
  List<PurchaseOrder> getPurchaseOrders() => _localDb.getPurchaseOrders();
  List<PurchaseOrderItem> getPurchaseOrderItems(String purchaseId) =>
      _localDb.getPurchaseOrderItems(purchaseId);
  Future<void> savePurchaseOrder(
    PurchaseOrder order,
    List<PurchaseOrderItem> items,
  ) async {
    await _localDb.savePurchaseOrder(order, items);
    await SupabaseSyncService.instance.pushRecordToCloud(
      'purchases',
      order.toJson(),
    );
    for (final item in items) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'purchase_order_items',
        item.toJson(),
      );
    }
  }

  Future<void> deletePurchaseOrder(String purchaseId) async {
    await _localDb.deletePurchaseOrder(purchaseId);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'purchases',
      'id',
      purchaseId,
    );
  }

  Future<bool> confirmPurchase(String purchaseId) async {
    final res = await _localDb.confirmPurchase(purchaseId);
    final purchases = _localDb.getPurchaseOrders();
    final order = purchases.firstWhere(
      (p) => p.id == purchaseId,
      orElse: () => purchases.first,
    );
    await SupabaseSyncService.instance.pushRecordToCloud(
      'purchases',
      order.toJson(),
    );
    return res;
  }

  Future<bool> setPurchaseStatusPending(String purchaseId) async {
    final res = await _localDb.setPurchaseStatusPending(purchaseId);
    final purchases = _localDb.getPurchaseOrders();
    final order = purchases.firstWhere(
      (p) => p.id == purchaseId,
      orElse: () => purchases.first,
    );
    await SupabaseSyncService.instance.pushRecordToCloud(
      'purchases',
      order.toJson(),
    );
    return res;
  }
}

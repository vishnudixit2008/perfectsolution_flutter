import 'dart:async';
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
import '../models/product_history_record.dart';
import '../services/local_database_service.dart';
import '../services/supabase_sync_service.dart';
import '../services/supabase_photo_service.dart';
import '../services/google_drive_upload_service.dart';
import '../services/multi_window_sync_service.dart';
import '../../ui/shared/photo_attachment_widget.dart';

class ShopRepository {
  final LocalDatabaseService _localDb;

  static final StreamController<String> _tableDataChangedController =
      StreamController<String>.broadcast();

  Stream<String> get onTableDataChanged => _tableDataChangedController.stream;
  static Stream<String> get tableDataChangedStream => _tableDataChangedController.stream;

  static void notifyTableChanged(String tableName, {bool broadcastToOtherWindows = true}) {
    _tableDataChangedController.add(tableName);
    if (broadcastToOtherWindows) {
      MultiWindowSyncService.instance.broadcastTableChange(tableName);
    }
  }

  ShopRepository({required LocalDatabaseService localDb}) : _localDb = localDb;

  LocalDatabaseService get localDb => _localDb;

  // Pricelist
  List<PricelistItem> getPricelist() => _localDb.getPricelist();
  int getNextPricelistId() => _localDb.getNextPricelistId();
  Future<void> savePricelistItem(PricelistItem item) async {
    await _localDb.savePricelistItem(item);
    await SupabaseSyncService.instance.pushRecordToCloud(
      'pricelist',
      item.toJson(),
    );
  }

  Future<void> deletePricelistItem(int id) async {
    final items = _localDb.getPricelist();
    final match = items.where((i) => i.id == id).firstOrNull;
    if (match?.photo != null && match!.photo!.isNotEmpty) {
      for (final url in PhotoAttachmentWidget.parsePhotoUrls(match.photo)) {
        await SupabasePhotoService.deletePhoto(url);
      }
    }
    await _localDb.deletePricelistItem(id);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'pricelist',
      'id',
      id,
      localDb: _localDb,
    );
  }

  /// Resets only the pricelist back to the bundled default items.
  /// Sales, repairs, calls, purchases and all other data are untouched.
  Future<void> resetPricelistToDefault() async =>
      await _localDb.clearPricelistOnly();

  // Settings
  String? getActiveUpiId() => _localDb.getActiveUpiId();
  Future<void> setActiveUpiId(String upiId, {bool syncToCloud = true}) async =>
      await _localDb.setActiveUpiId(upiId, syncToCloud: syncToCloud);
  String getGoogleReviewListing() => _localDb.getGoogleReviewListing();
  Future<void> saveGoogleReviewListing(String listingKey, {bool syncToCloud = true}) async =>
      await _localDb.setGoogleReviewListing(listingKey, syncToCloud: syncToCloud);
  List<String> getUpiIdsList() => _localDb.getUpiIdsList();
  Future<void> saveUpiIdsList(List<String> upiIds) async =>
      await _localDb.saveUpiIdsList(upiIds);
  Map<String, String> getUpiNamesMap() => _localDb.getUpiNamesMap();
  Future<void> saveUpiNamesMap(Map<String, String> names) async =>
      await _localDb.saveUpiNamesMap(names);
  List<String> getCustomServiceNames() => _localDb.getCustomServiceNames();
  Future<void> saveCustomServiceName(String name, {bool syncToCloud = true}) async =>
      await _localDb.saveCustomServiceName(name, syncToCloud: syncToCloud);
  Future<void> deleteCustomServiceName(String name, {bool syncToCloud = true}) async =>
      await _localDb.deleteCustomServiceName(name, syncToCloud: syncToCloud);
  Future<void> setCustomServicesList(List<String> services, {bool syncToCloud = false}) async =>
      await _localDb.setCustomServicesList(services, syncToCloud: syncToCloud);
  double? getDetailPopupWidth() => _localDb.getDetailPopupWidth();
  double? getDetailPopupHeight() => _localDb.getDetailPopupHeight();
  Future<void> saveDetailPopupSize(double width, double height) async =>
      await _localDb.saveDetailPopupSize(width, height);

  // Printer configuration
  String? getSelectedPrinterName() => _localDb.getSelectedPrinterName();
  Future<void> saveSelectedPrinterName(String name) async =>
      await _localDb.saveSelectedPrinterName(name);

  // Invoice print settings
  String getInvoicePageSize() => _localDb.getInvoicePageSize();
  Future<void> saveInvoicePageSize(String size) async =>
      await _localDb.saveInvoicePageSize(size);
  double getInvoiceMarginTB() => _localDb.getInvoiceMarginTB();
  double getInvoiceMarginLR() => _localDb.getInvoiceMarginLR();
  Future<void> saveInvoiceMargins(double topBottom, double leftRight) async =>
      await _localDb.saveInvoiceMargins(topBottom, leftRight);
  bool getInvoiceShowHeader() => _localDb.getInvoiceShowHeader();
  Future<void> saveInvoiceShowHeader(bool value) async =>
      await _localDb.saveInvoiceShowHeader(value);
  bool getInvoiceShowQr() => _localDb.getInvoiceShowQr();
  Future<void> saveInvoiceShowQr(bool value) async =>
      await _localDb.saveInvoiceShowQr(value);

  // Sales
  int getNextInvoiceNo() => _localDb.getNextInvoiceNo();
  List<Sale> getSales() => _localDb.getSales();
  List<SaleItem> getSaleItems(int invoiceNo) =>
      _localDb.getSaleItems(invoiceNo);
  Future<void> saveSale(Sale sale, List<SaleItem> items) async {
    final updatedProducts = await _localDb.saveSale(sale, items);
    // Batch upsert sale items first so cloud has child rows before parent triggers Realtime
    await SupabaseSyncService.instance.saveSaleItemsForInvoice(
      sale.invoiceNo,
      items,
      localDb: _localDb,
    );
    await SupabaseSyncService.instance.pushRecordToCloud(
      'sales',
      sale.toJson(),
      localDb: _localDb,
    );
    for (final p in updatedProducts) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'pricelist',
        p.toJson(),
        localDb: _localDb,
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
      localDb: _localDb,
    );
    for (final p in updatedProducts) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'pricelist',
        p.toJson(),
        localDb: _localDb,
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
      localDb: _localDb,
    );
    for (final p in updatedProducts) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'pricelist',
        p.toJson(),
        localDb: _localDb,
      );
    }
    return true;
  }

  Future<bool> updateSale(Sale sale, List<SaleItem> items) async {
    await saveSale(sale, items);
    return true;
  }

  Future<bool> deleteSale(int invoiceNo) async {
    final updatedProducts = await _localDb.deleteSale(invoiceNo);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'sales',
      'invoice_no',
      invoiceNo,
      localDb: _localDb,
    );
    await SupabaseSyncService.instance.deleteSaleItemsForInvoice(invoiceNo);
    for (final p in updatedProducts) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'pricelist',
        p.toJson(),
        localDb: _localDb,
      );
    }
    return true;
  }

  // Calls
  int getNextCallId() => _localDb.getNextCallId();
  List<CallModel> getCalls() => _localDb.getCalls();
  Future<void> saveCall(CallModel call) async {
    await _localDb.saveCall(call);
    await SupabaseSyncService.instance.pushRecordToCloud(
      'calls',
      call.toJson(),
      localDb: _localDb,
    );
    if (call.photo != null && call.photo!.contains('data:image/')) {
      GoogleDriveUploadService.syncPendingLocalPhotos(this);
    }
  }

  Future<void> deleteCall(int id) async {
    final calls = _localDb.getCalls();
    final match = calls.where((c) => c.id == id).firstOrNull;
    if (match?.photo != null && match!.photo!.isNotEmpty) {
      for (final url in PhotoAttachmentWidget.parsePhotoUrls(match.photo)) {
        await SupabasePhotoService.deletePhoto(url);
      }
    }
    await _localDb.deleteCall(id);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'calls',
      'id',
      id,
      localDb: _localDb,
    );
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
    // Batch upsert estimate items first so cloud has child rows before parent triggers Realtime
    await SupabaseSyncService.instance.saveEstimateItemsForJob(
      repair.jobNo,
      items,
      localDb: _localDb,
    );
    await SupabaseSyncService.instance.pushRecordToCloud(
      'inward_repairs',
      repair.toJson(),
      localDb: _localDb,
    );
    if (repair.photo != null && repair.photo!.contains('data:image/')) {
      GoogleDriveUploadService.syncPendingLocalPhotos(this);
    }
  }

  Future<void> deleteInwardRepair(int jobNo) async {
    final repairs = _localDb.getInwardRepairs();
    final match = repairs.where((r) => r.jobNo == jobNo).firstOrNull;
    if (match?.photo != null && match!.photo!.isNotEmpty) {
      for (final url in PhotoAttachmentWidget.parsePhotoUrls(match.photo)) {
        await SupabasePhotoService.deletePhoto(url);
      }
    }
    await _localDb.deleteInwardRepair(jobNo);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'inward_repairs',
      'job_no',
      jobNo,
      localDb: _localDb,
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
      localDb: _localDb,
    );
    if (repl.photo != null && repl.photo!.contains('data:image/')) {
      GoogleDriveUploadService.syncPendingLocalPhotos(this);
    }
  }

  Future<void> deleteReplacement(String jobNo) async {
    final replacements = _localDb.getReplacements();
    final match = replacements.where((r) => r.jobNo == jobNo).firstOrNull;
    if (match?.photo != null && match!.photo!.isNotEmpty) {
      for (final url in PhotoAttachmentWidget.parsePhotoUrls(match.photo)) {
        await SupabasePhotoService.deletePhoto(url);
      }
    }
    await _localDb.deleteReplacement(jobNo);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'replacements',
      'job_no',
      jobNo,
      localDb: _localDb,
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
      localDb: _localDb,
    );
  }

  Future<void> deleteRequestOrder(String id) async {
    final requests = _localDb.getRequestOrders();
    final match = requests.where((r) => r.id == id).firstOrNull;
    if (match?.photo != null && match!.photo!.isNotEmpty) {
      for (final url in PhotoAttachmentWidget.parsePhotoUrls(match.photo)) {
        await SupabasePhotoService.deletePhoto(url);
      }
    }
    await _localDb.deleteRequestOrder(id);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'requests',
      'id',
      id,
      localDb: _localDb,
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
    final updatedProducts = await _localDb.savePurchaseOrder(order, items);
    // Batch upsert purchase items first so cloud has child rows before parent triggers Realtime
    await SupabaseSyncService.instance.savePurchaseItemsForPurchase(
      order.id,
      items,
      localDb: _localDb,
    );
    await SupabaseSyncService.instance.pushRecordToCloud(
      'purchases',
      order.toJson(),
      localDb: _localDb,
    );
    for (final p in updatedProducts) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'pricelist',
        p.toJson(),
        localDb: _localDb,
      );
    }
    if (order.photo != null && order.photo!.contains('data:image/')) {
      GoogleDriveUploadService.syncPendingLocalPhotos(this);
    }
  }

  Future<void> deletePurchaseOrder(String purchaseId) async {
    final purchases = _localDb.getPurchaseOrders();
    final match = purchases.where((p) => p.id == purchaseId).firstOrNull;
    if (match?.photo != null && match!.photo!.isNotEmpty) {
      for (final url in PhotoAttachmentWidget.parsePhotoUrls(match.photo)) {
        await SupabasePhotoService.deletePhoto(url);
      }
    }
    final updatedProducts = await _localDb.deletePurchaseOrder(purchaseId);
    await SupabaseSyncService.instance.deleteRecordFromCloud(
      'purchases',
      'id',
      purchaseId,
      localDb: _localDb,
    );
    await SupabaseSyncService.instance.deletePurchaseItemsForPurchase(purchaseId);
    for (final prod in updatedProducts) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'pricelist',
        prod.toJson(),
        localDb: _localDb,
      );
    }
  }

  Future<bool> confirmPurchase(String purchaseId) async {
    final updatedProducts = await _localDb.confirmPurchase(purchaseId);
    final purchases = _localDb.getPurchaseOrders();
    final order = purchases.firstWhere(
      (p) => p.id == purchaseId,
      orElse: () => purchases.first,
    );
    await SupabaseSyncService.instance.pushRecordToCloud(
      'purchases',
      order.toJson(),
      localDb: _localDb,
    );
    for (final prod in updatedProducts) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'pricelist',
        prod.toJson(),
        localDb: _localDb,
      );
    }
    return updatedProducts.isNotEmpty || order.status == 'CONFIRMED';
  }

  Future<bool> setPurchaseStatusPending(String purchaseId) async {
    final updatedProducts = await _localDb.setPurchaseStatusPending(purchaseId);
    final purchases = _localDb.getPurchaseOrders();
    final order = purchases.firstWhere(
      (p) => p.id == purchaseId,
      orElse: () => purchases.first,
    );
    await SupabaseSyncService.instance.pushRecordToCloud(
      'purchases',
      order.toJson(),
      localDb: _localDb,
    );
    for (final prod in updatedProducts) {
      await SupabaseSyncService.instance.pushRecordToCloud(
        'pricelist',
        prod.toJson(),
        localDb: _localDb,
      );
    }
    return true;
  }

  // Product History (Sales & Purchases)
  List<ProductHistoryRecord> getProductHistory(PricelistItem product) {
    final List<ProductHistoryRecord> records = [];
    final pNameLower = product.itemName.trim().toLowerCase();

    // 1. Process Sales
    final sales = getSales();
    for (final sale in sales) {
      final items = getSaleItems(sale.invoiceNo);
      for (final item in items) {
        final matchesId = item.itemId != null && item.itemId == product.id;
        final matchesName = item.itemDescription != null &&
            item.itemDescription!.trim().toLowerCase() == pNameLower;
        if (matchesId || matchesName) {
          records.add(
            ProductHistoryRecord(
              type: ProductHistoryType.sale,
              date: sale.saleDate,
              referenceNo: 'Invoice #${sale.invoiceNo}',
              partyName: sale.customerName != null && sale.customerName!.trim().isNotEmpty
                  ? sale.customerName!.trim()
                  : 'Cash / Walk-in',
              quantity: item.quantity,
              unitPrice: item.activePrice,
              totalAmount: item.totalAmount,
              status: sale.orderStatus,
              sale: sale,
              saleItems: items,
            ),
          );
        }
      }
    }

    // 2. Process Purchases
    final purchases = getPurchaseOrders();
    for (final purchase in purchases) {
      final items = getPurchaseOrderItems(purchase.id);
      for (final item in items) {
        final matchesId = item.itemId != null && item.itemId == product.id;
        final matchesName = (item.itemName != null && item.itemName!.trim().toLowerCase() == pNameLower) ||
            (item.customItemName != null && item.customItemName!.trim().toLowerCase() == pNameLower);
        if (matchesId || matchesName) {
          records.add(
            ProductHistoryRecord(
              type: ProductHistoryType.purchase,
              date: purchase.date,
              referenceNo: purchase.id,
              partyName: purchase.purchasedFrom.trim().isNotEmpty
                  ? purchase.purchasedFrom.trim()
                  : 'Supplier / Vendor',
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              totalAmount: item.amount,
              status: purchase.status,
              purchase: purchase,
              purchaseItems: items,
            ),
          );
        }
      }
    }

    // 3. Sort chronologically descending (newest first)
    records.sort((a, b) => b.date.compareTo(a.date));

    // 4. Compute closing stock for each historical record backward from current live stock
    int runningStock = product.stockQty;
    final List<ProductHistoryRecord> recordsWithClosingStock = [];

    for (final r in records) {
      final closingStock = runningStock;
      final statusUpper = r.status.trim().toUpperCase();
      final isPendingOrCancelled =
          statusUpper == 'PENDING' || statusUpper == 'CANCELLED';

      if (!isPendingOrCancelled) {
        if (r.isSale) {
          runningStock += r.quantity;
        } else if (r.isPurchase) {
          runningStock -= r.quantity;
        }
      }

      recordsWithClosingStock.add(
        ProductHistoryRecord(
          type: r.type,
          date: r.date,
          referenceNo: r.referenceNo,
          partyName: r.partyName,
          quantity: r.quantity,
          unitPrice: r.unitPrice,
          totalAmount: r.totalAmount,
          status: r.status,
          sale: r.sale,
          saleItems: r.saleItems,
          purchase: r.purchase,
          purchaseItems: r.purchaseItems,
          closingStock: closingStock,
        ),
      );
    }

    return recordsWithClosingStock;
  }
}


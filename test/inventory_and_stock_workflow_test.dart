import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shop_management_flutter/data/models/inward_estimate_item.dart';
import 'package:shop_management_flutter/data/models/inward_repair.dart';
import 'package:shop_management_flutter/data/models/pricelist_item.dart';
import 'package:shop_management_flutter/data/models/purchase_order.dart';
import 'package:shop_management_flutter/data/models/purchase_order_item.dart';
import 'package:shop_management_flutter/data/models/sale.dart';
import 'package:shop_management_flutter/data/models/sale_item.dart';
import 'package:shop_management_flutter/data/repositories/shop_repository.dart';
import 'package:shop_management_flutter/data/services/local_database_service.dart';
import 'package:shop_management_flutter/data/services/ui_preferences_service.dart';
import 'package:shop_management_flutter/data/services/user_permission_service.dart';
import 'package:shop_management_flutter/ui/shared/status_management_dialog.dart';
import 'package:shop_management_flutter/ui/features/pricelist/view_models/pricelist_view_model.dart';
import 'package:shop_management_flutter/ui/features/sales/view_models/sales_view_model.dart';

void main() {
  late Directory tempDir;
  late LocalDatabaseService localDb;
  late ShopRepository repository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('inventory_workflow_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );

    Hive.init(tempDir.path);
    await Hive.openBox('settings_box');
    await Hive.openBox('users_box');
    await Hive.openBox('status_management_box');
    await Hive.openBox('ui_preferences');
    await Hive.openBox('offline_queue');

    localDb = LocalDatabaseService();
    await localDb.init();
    await UserPermissionService.init();
    await StatusManagementService.init();
    await UiPreferencesService.init();
    repository = ShopRepository(localDb: localDb);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await localDb.clearDatabase();
  });

  group('Inventory & Stock Workflow Comprehensive Tests', () {
    test('1. Initial Opening Stock Setup & Catalog Integrity', () async {
      final ssdItem = PricelistItem(
        id: 338,
        itemName: '128 GB SIMMTRONICS SATA',
        price: 1500.0,
        stockQty: 10,
        openingStock: 10,
        category: 'SSD',
      );
      final mouseItem = PricelistItem(
        id: 212,
        itemName: 'USB MOUSE HP M10',
        price: 250.0,
        stockQty: 20,
        openingStock: 20,
        category: 'MOUSE',
      );

      await localDb.savePricelistItem(ssdItem);
      await localDb.savePricelistItem(mouseItem);

      final items = localDb.getPricelist();
      expect(items.any((i) => i.id == 338), isTrue);
      expect(items.any((i) => i.id == 212), isTrue);
      expect(items.firstWhere((i) => i.id == 338).stockQty, equals(10));
      expect(items.firstWhere((i) => i.id == 212).stockQty, equals(20));
    });

    test('2. Purchases Workflow: Confirmed PO increments stock, deletion reverts stock', () async {
      final ssd = PricelistItem(
        id: 338,
        itemName: '128 GB SIMMTRONICS SATA',
        price: 1500.0,
        stockQty: 10,
        openingStock: 10,
        category: 'SSD',
      );
      await localDb.savePricelistItem(ssd);

      // Create Confirmed Purchase of 5 units
      final po = PurchaseOrder(
        id: 'po_test_01',
        date: DateTime.now(),
        purchasedFrom: 'Simmtronics Vendor',
        totalAmount: 5000.0,
        status: 'CONFIRMED',
      );
      final poItems = [
        PurchaseOrderItem(
          lineId: 'line_po_1',
          purchaseId: 'po_test_01',
          itemId: 338,
          itemName: '128 GB SIMMTRONICS SATA',
          quantity: 5,
          unitPrice: 1000.0,
          amount: 5000.0,
        ),
      ];

      final updatedProds = await localDb.savePurchaseOrder(po, poItems);
      expect(updatedProds.length, equals(1));
      expect(updatedProds.first.stockQty, equals(15)); // 10 + 5 = 15

      // Verify stock in database
      final currentSsd = localDb.getPricelist().firstWhere((i) => i.id == 338);
      expect(currentSsd.stockQty, equals(15));

      // Delete Purchase Order -> stock should revert to 10
      final reverted = await localDb.deletePurchaseOrder('po_test_01');
      expect(reverted.length, equals(1));
      expect(reverted.first.stockQty, equals(10)); // 15 - 5 = 10
    });

    test('3. Purchases Workflow: Status transitions between Confirmed and Pending', () async {
      final item = PricelistItem(
        id: 29,
        itemName: 'SMPS',
        price: 650.0,
        stockQty: 5,
        openingStock: 5,
        category: 'SMPS',
      );
      await localDb.savePricelistItem(item);

      // Save as PENDING (no stock increase)
      final po = PurchaseOrder(
        id: 'po_pending_01',
        date: DateTime.now(),
        purchasedFrom: 'Local Supplier',
        totalAmount: 1300.0,
        status: 'PENDING',
      );
      final poItems = [
        PurchaseOrderItem(
          lineId: 'line_smps_1',
          purchaseId: 'po_pending_01',
          itemId: 29,
          itemName: 'SMPS',
          quantity: 2,
          unitPrice: 650.0,
          amount: 1300.0,
        ),
      ];

      await localDb.savePurchaseOrder(po, poItems);
      var check = localDb.getPricelist().firstWhere((i) => i.id == 29);
      expect(check.stockQty, equals(5)); // Pending does not add stock

      // Confirm Purchase -> stock increases
      final confirmedProds = await localDb.confirmPurchase('po_pending_01');
      expect(confirmedProds.first.stockQty, equals(7)); // 5 + 2 = 7

      // Revert to Pending -> stock decreases
      final revertedProds = await localDb.setPurchaseStatusPending('po_pending_01');
      expect(revertedProds.first.stockQty, equals(5)); // 7 - 2 = 5
    });

    test('4. Purchases Workflow: Quick-Add New Item generates unique itemId and stocks in', () async {
      final pricelistVM = PricelistViewModel(repository: repository);
      await pricelistVM.loadItems();

      final int nextId = pricelistVM.getNextId();
      final newProduct = PricelistItem(
        id: nextId,
        itemName: 'Brand New Gaming Headset',
        price: 2500.0,
        stockQty: 0,
        openingStock: 0,
        category: 'Audio',
      );

      await pricelistVM.addItem(newProduct);
      expect(pricelistVM.items.any((i) => i.id == nextId), isTrue);

      // Now create a purchase for this new product
      final po = PurchaseOrder(
        id: 'po_headset_01',
        date: DateTime.now(),
        purchasedFrom: 'Audio Dealer',
        totalAmount: 7500.0,
        status: 'CONFIRMED',
      );
      final poItems = [
        PurchaseOrderItem(
          lineId: 'line_hs_1',
          purchaseId: 'po_headset_01',
          itemId: nextId,
          itemName: 'Brand New Gaming Headset',
          quantity: 3,
          unitPrice: 2500.0,
          amount: 7500.0,
        ),
      ];

      await localDb.savePurchaseOrder(po, poItems);
      final stocked = localDb.getPricelist().firstWhere((i) => i.id == nextId);
      expect(stocked.stockQty, equals(3));
    });

    test('5. Sales Workflow: Confirmed sale immediately deducts stock', () async {
      final item = PricelistItem(
        id: 345,
        itemName: '256 GB SIMMTRONICS SATA',
        price: 2200.0,
        stockQty: 8,
        openingStock: 8,
        category: 'SSD',
      );
      await localDb.savePricelistItem(item);

      final sale = Sale(
        invoiceNo: 501,
        saleDate: DateTime.now(),
        customerName: 'Aarav Sharma',
        customerNumber: '9988776655',
        paymentMode: 'UPI',
        totalAmount: 4400.0,
        orderStatus: 'Confirmed',
      );
      final saleItems = [
        SaleItem(
          id: 'sale_item_1',
          invoiceNo: 501,
          itemId: 345,
          lineType: 'Product',
          itemDescription: '256 GB SIMMTRONICS SATA',
          quantity: 2,
          itemPrice: 2200.0,
          totalAmount: 4400.0,
        ),
      ];

      final updatedProds = await localDb.saveSale(sale, saleItems);
      expect(updatedProds.length, equals(1));
      expect(updatedProds.first.stockQty, equals(6)); // 8 - 2 = 6

      final dbItem = localDb.getPricelist().firstWhere((i) => i.id == 345);
      expect(dbItem.stockQty, equals(6));
    });

    test('6. Sales Workflow: Services do NOT alter inventory stock', () async {
      final prod = PricelistItem(
        id: 17,
        itemName: 'ADAPTOR LAPTOP',
        price: 650.0,
        stockQty: 10,
        openingStock: 10,
        category: 'ADAPTOR',
      );
      await localDb.savePricelistItem(prod);

      final sale = Sale(
        invoiceNo: 502,
        saleDate: DateTime.now(),
        customerName: 'Priya Verma',
        paymentMode: 'Cash',
        totalAmount: 1150.0,
        orderStatus: 'Confirmed',
      );
      final saleItems = [
        SaleItem(
          id: 'item_prod',
          invoiceNo: 502,
          itemId: 17,
          lineType: 'Product',
          itemDescription: 'ADAPTOR LAPTOP',
          quantity: 1,
          itemPrice: 650.0,
          totalAmount: 650.0,
        ),
        SaleItem(
          id: 'item_srv',
          invoiceNo: 502,
          itemId: null,
          lineType: 'Service',
          itemDescription: 'OS Installation & Formatting',
          quantity: 1,
          itemPrice: 500.0,
          totalAmount: 500.0,
        ),
      ];

      await localDb.saveSale(sale, saleItems);
      final check = localDb.getPricelist().firstWhere((i) => i.id == 17);
      expect(check.stockQty, equals(9)); // Only product is deducted (10 - 1 = 9)
    });

    test('7. Sales Workflow: Status changes and deletion properly reconcile stock', () async {
      final prod = PricelistItem(
        id: 60,
        itemName: 'HDD CASING 2.0',
        price: 450.0,
        stockQty: 15,
        openingStock: 15,
        category: 'CASING',
      );
      await localDb.savePricelistItem(prod);

      // 1. Save Pending Sale
      final sale = Sale(
        invoiceNo: 503,
        saleDate: DateTime.now(),
        orderStatus: 'Pending',
        paymentMode: 'Card',
        totalAmount: 900.0,
      );
      final saleItems = [
        SaleItem(
          id: 'si_casing_1',
          invoiceNo: 503,
          itemId: 60,
          lineType: 'Product',
          itemDescription: 'HDD CASING 2.0',
          quantity: 2,
          itemPrice: 450.0,
          totalAmount: 900.0,
        ),
      ];

      await localDb.saveSale(sale, saleItems);
      var item = localDb.getPricelist().firstWhere((i) => i.id == 60);
      expect(item.stockQty, equals(15)); // Pending -> no change

      // 2. Confirm Sale -> stock drops to 13
      var confirmed = await localDb.confirmSale(503);
      expect(confirmed.first.stockQty, equals(13));

      // 3. Revert to Pending -> stock restored to 15
      var reverted = await localDb.setSaleStatusPending(503);
      expect(reverted.first.stockQty, equals(15));

      // 4. Re-confirm and then Delete -> stock restored to 15
      await localDb.confirmSale(503);
      var deleted = await localDb.deleteSale(503);
      expect(deleted.first.stockQty, equals(15));
    });

    test('8. Inward Repair to Sale Conversion & Checkout Deduction', () async {
      final screenItem = PricelistItem(
        id: 101,
        itemName: '14.0 INCH FHD SCREEN',
        price: 3200.0,
        stockQty: 5,
        openingStock: 5,
        category: 'SCREEN',
      );
      await localDb.savePricelistItem(screenItem);

      // Inward Repair with 1 Product (Screen) and 1 Service (Labor)
      final repair = InwardRepair(
        jobNo: 9001,
        name: 'Vikas Gupta',
        mobileNo: '9123456780',
        devices: 'Dell Latitude 5420',
        date: DateTime.now(),
        status: 'Ready',
      );
      final estimates = [
        InwardEstimateItem(
          lineId: 'est_1',
          jobNo: 9001,
          lineType: 'Product',
          itemId: 101,
          itemName: '14.0 INCH FHD SCREEN',
          quantity: 1,
          unitPrice: 3200.0,
          totalAmount: 3200.0,
        ),
        InwardEstimateItem(
          lineId: 'est_2',
          jobNo: 9001,
          lineType: 'Service',
          itemName: 'Screen Replacement Labor',
          quantity: 1,
          servicePrice: 400.0,
          totalAmount: 400.0,
        ),
      ];

      await localDb.saveInwardRepair(repair, estimates);

      // Before conversion, stock should remain untouched (5 units)
      var screenCheck = localDb.getPricelist().firstWhere((i) => i.id == 101);
      expect(screenCheck.stockQty, equals(5));

      // Convert to Sale via SalesViewModel
      final salesVM = SalesViewModel(repository: repository);
      salesVM.clearCart();
      salesVM.setCustomerName(repair.name);
      salesVM.setCustomerNumber(repair.mobileNo ?? '');

      for (final est in estimates) {
        final double price = est.lineType == 'Service'
            ? (est.servicePrice > 0 ? est.servicePrice : est.unitPrice)
            : (est.unitPrice > 0 ? est.unitPrice : est.servicePrice);

        salesVM.addSaleItemToCart(
          itemId: est.itemId,
          lineType: est.lineType,
          itemDescription: est.itemName ?? 'Item',
          quantity: est.quantity,
          itemPrice: price,
        );
      }

      expect(salesVM.cartItems.length, equals(2));
      expect(salesVM.cartItems[0].itemId, equals(101));

      // Checkout as Confirmed
      salesVM.setPaymentMode('Cash');
      salesVM.setEditingOrderStatus('Confirmed');
      final invoiceNo = await salesVM.checkout();
      expect(invoiceNo, isNotNull);

      // Live stock for Screen should now be deducted from 5 to 4
      screenCheck = localDb.getPricelist().firstWhere((i) => i.id == 101);
      expect(screenCheck.stockQty, equals(4));
    });

    test('9. Full Multi-Transaction Inventory Ledger Verification', () async {
      // Starting item: Opening stock = 10
      final ram = PricelistItem(
        id: 260,
        itemName: 'RAM 8 GB DDR4 LAPTOP',
        price: 2000.0,
        stockQty: 10,
        openingStock: 10,
        category: 'RAM',
      );
      await localDb.savePricelistItem(ram);

      // Purchase #1: +4 units
      await localDb.savePurchaseOrder(
        PurchaseOrder(
          id: 'po_ram_1',
          date: DateTime.now(),
          purchasedFrom: 'Vendor A',
          totalAmount: 8000.0,
          status: 'CONFIRMED',
        ),
        [
          PurchaseOrderItem(
            lineId: 'l1',
            purchaseId: 'po_ram_1',
            itemId: 260,
            itemName: 'RAM 8 GB DDR4 LAPTOP',
            quantity: 4,
            unitPrice: 2000.0,
            amount: 8000.0,
          ),
        ],
      );

      // Sale #1: -3 units
      await localDb.saveSale(
        Sale(
          invoiceNo: 701,
          saleDate: DateTime.now(),
          orderStatus: 'Confirmed',
          paymentMode: 'UPI',
          totalAmount: 6000.0,
        ),
        [
          SaleItem(
            id: 's1',
            invoiceNo: 701,
            itemId: 260,
            lineType: 'Product',
            itemDescription: 'RAM 8 GB DDR4 LAPTOP',
            quantity: 3,
            itemPrice: 2000.0,
            totalAmount: 6000.0,
          ),
        ],
      );

      // Purchase #2: +6 units
      await localDb.savePurchaseOrder(
        PurchaseOrder(
          id: 'po_ram_2',
          date: DateTime.now(),
          purchasedFrom: 'Vendor B',
          totalAmount: 12000.0,
          status: 'CONFIRMED',
        ),
        [
          PurchaseOrderItem(
            lineId: 'l2',
            purchaseId: 'po_ram_2',
            itemId: 260,
            itemName: 'RAM 8 GB DDR4 LAPTOP',
            quantity: 6,
            unitPrice: 2000.0,
            amount: 12000.0,
          ),
        ],
      );

      // Sale #2: -5 units
      await localDb.saveSale(
        Sale(
          invoiceNo: 702,
          saleDate: DateTime.now(),
          orderStatus: 'Confirmed',
          paymentMode: 'Cash',
          totalAmount: 10000.0,
        ),
        [
          SaleItem(
            id: 's2',
            invoiceNo: 702,
            itemId: 260,
            lineType: 'Product',
            itemDescription: 'RAM 8 GB DDR4 LAPTOP',
            quantity: 5,
            itemPrice: 2000.0,
            totalAmount: 10000.0,
          ),
        ],
      );

      // Verification Formula:
      // Live Stock = Opening(10) + Purchases(4 + 6 = 10) - Sales(3 + 5 = 8) = 12 units
      final finalProduct = localDb.getPricelist().firstWhere((i) => i.id == 260);
      expect(finalProduct.stockQty, equals(12));
    });
  });
}

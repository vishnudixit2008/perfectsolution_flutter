import 'package:flutter_test/flutter_test.dart';
import 'package:shop_management_flutter/data/models/inward_estimate_item.dart';
import 'package:shop_management_flutter/data/models/inward_repair.dart';
import 'package:shop_management_flutter/ui/features/sales/view_models/sales_view_model.dart';
import 'package:shop_management_flutter/data/repositories/shop_repository.dart';
import 'package:shop_management_flutter/data/services/local_database_service.dart';

void main() {
  test(
    'Verifies inward estimate items & customer info convert into sale cart items with prices',
    () {
      final localDb = LocalDatabaseService();
      final repo = ShopRepository(localDb: localDb);
      final salesVM = SalesViewModel(repository: repo);

      // Mock inward repair and estimate items
      final repair = InwardRepair(
        jobNo: 4111,
        name: 'Ramesh Kumar',
        mobileNo: '9876543210',
        devices: 'iPhone 13 Screen',
        date: DateTime.now(),
        status: 'In Progress',
      );

      final estimateItems = [
        InwardEstimateItem(
          lineId: 'line_1',
          jobNo: 4111,
          lineType: 'Product',
          itemName: 'OLED Display Assembly',
          quantity: 1,
          unitPrice: 4500.0,
          totalAmount: 4500.0,
        ),
        InwardEstimateItem(
          lineId: 'line_2',
          jobNo: 4111,
          lineType: 'Service',
          itemName: 'Display Fitting & Waterproof Seal Service',
          quantity: 1,
          servicePrice: 500.0,
          totalAmount: 500.0,
        ),
      ];

      // Simulate _handleSalesPrefill logic
      salesVM.clearCart();
      salesVM.setCustomerName(repair.name);
      salesVM.setCustomerNumber(repair.mobileNo ?? '');

      for (final est in estimateItems) {
        final double price = est.lineType == 'Service'
            ? (est.servicePrice > 0 ? est.servicePrice : est.unitPrice)
            : (est.unitPrice > 0 ? est.unitPrice : est.servicePrice);

        salesVM.addSaleItemToCart(
          lineType: est.lineType,
          itemDescription: est.itemName ?? 'Item',
          quantity: est.quantity,
          itemPrice: price,
        );
      }

      expect(salesVM.customerName, equals('Ramesh Kumar'));
      expect(salesVM.customerNumber, equals('9876543210'));
      expect(salesVM.cartItems.length, equals(2));

      expect(
        salesVM.cartItems[0].itemDescription,
        equals('OLED Display Assembly'),
      );
      expect(salesVM.cartItems[0].lineType, equals('Product'));
      expect(salesVM.cartItems[0].itemPrice, equals(4500.0));
      expect(salesVM.cartItems[0].totalAmount, equals(4500.0));

      expect(
        salesVM.cartItems[1].itemDescription,
        equals('Display Fitting & Waterproof Seal Service'),
      );
      expect(salesVM.cartItems[1].lineType, equals('Service'));
      expect(salesVM.cartItems[1].itemPrice, equals(500.0));
      expect(salesVM.cartItems[1].totalAmount, equals(500.0));

      expect(salesVM.totalAmount, equals(5000.0));
    },
  );

  test(
    'Verifies inward repair advance and discount transfer to sale entry properly',
    () {
      final localDb = LocalDatabaseService();
      final repo = ShopRepository(localDb: localDb);
      final salesVM = SalesViewModel(repository: repo);

      final repair = InwardRepair(
        jobNo: 4112,
        name: 'Anita Verma',
        mobileNo: '9123456780',
        devices: 'MacBook Pro A2338',
        date: DateTime.now(),
        status: 'In Progress',
        discount: 200.0,
        advance: 1000.0,
      );

      final estimateItems = [
        InwardEstimateItem(
          lineId: 'line_3',
          jobNo: 4112,
          lineType: 'Service',
          itemName: 'Logic Board Repair & Clean',
          quantity: 1,
          servicePrice: 3500.0,
          totalAmount: 3500.0,
        ),
      ];

      // Simulate conversion prefill
      salesVM.clearCart();
      salesVM.setCustomerName(repair.name);
      salesVM.setCustomerNumber(repair.mobileNo ?? '');
      salesVM.setDiscount(repair.discount);
      salesVM.setAdvance(repair.advance);

      for (final est in estimateItems) {
        salesVM.addSaleItemToCart(
          lineType: est.lineType,
          itemDescription: est.itemName ?? 'Item',
          quantity: est.quantity,
          itemPrice: est.servicePrice,
        );
      }

      expect(salesVM.customerName, equals('Anita Verma'));
      expect(salesVM.customerNumber, equals('9123456780'));
      expect(salesVM.discount, equals(200.0));
      expect(salesVM.advance, equals(1000.0));
      expect(salesVM.subtotal, equals(3500.0));
      // Net total should be subtotal (3500) - discount (200) - advance (1000) = 2300.0
      expect(salesVM.totalAmount, equals(2300.0));
    },
  );
}

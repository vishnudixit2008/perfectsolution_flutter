import 'package:flutter_test/flutter_test.dart';
import 'package:shop_management_flutter/data/models/sale.dart';
import 'package:shop_management_flutter/data/models/sale_item.dart';
import 'package:shop_management_flutter/data/repositories/shop_repository.dart';
import 'package:shop_management_flutter/data/services/local_database_service.dart';
import 'package:shop_management_flutter/ui/features/sales/view_models/sales_view_model.dart';

void main() {
  group('Sales Feature Updates Tests', () {
    test('SaleItem handles item secondary description/notes correctly', () {
      final item = SaleItem(
        id: 'test_1',
        invoiceNo: 1001,
        lineType: 'Service',
        itemDescription: 'SERVICE CHARGE',
        notes: 'NETWORKING 2 SYSTEM 1 PRINTER',
        quantity: 3,
        itemPrice: 500.0,
        totalAmount: 1500.0,
      );

      expect(item.notes, equals('NETWORKING 2 SYSTEM 1 PRINTER'));

      final json = item.toJson();
      expect(json['notes'], equals('NETWORKING 2 SYSTEM 1 PRINTER'));

      final fromJsonItem = SaleItem.fromJson(json);
      expect(fromJsonItem.notes, equals('NETWORKING 2 SYSTEM 1 PRINTER'));
      expect(fromJsonItem.itemDescription, equals('SERVICE CHARGE'));
    });

    test('SaleItem copyWith supports lineType and notes updates', () {
      final item = SaleItem(
        id: 'test_2',
        invoiceNo: 1002,
        lineType: 'Product',
        itemDescription: 'RJ 45 Connector Dlink',
        quantity: 6,
        itemPrice: 10.0,
        totalAmount: 60.0,
      );

      final updated = item.copyWith(
        lineType: 'Service',
        notes: 'RJ 45 CONNECTOR',
      );

      expect(updated.lineType, equals('Service'));
      expect(updated.notes, equals('RJ 45 CONNECTOR'));
      expect(updated.itemDescription, equals('RJ 45 Connector Dlink'));
    });

    test('editedItems list handles dynamic Map addition without type error', () {
      final initialItems = [
        SaleItem(
          id: '1',
          invoiceNo: 1001,
          lineType: 'Product',
          itemDescription: 'Item 1',
          quantity: 1,
          itemPrice: 100.0,
          totalAmount: 100.0,
        ),
      ];

      final List<Map<String, dynamic>> editedItems = initialItems.map<Map<String, dynamic>>((item) {
        return <String, dynamic>{
          'item': item,
          'lineType': item.lineType,
          'nameController': 'Item 1',
          'notesController': '',
          'priceController': '100',
          'qtyController': '1',
        };
      }).toList();

      expect(() {
        editedItems.add(<String, dynamic>{
          'item': SaleItem(
            id: 'edit_prod_123',
            invoiceNo: 1001,
            lineType: 'Product',
            itemDescription: 'New Product',
            quantity: 1,
            itemPrice: 0.0,
            totalAmount: 0.0,
          ),
          'lineType': 'Product',
          'nameController': 'New Product',
          'notesController': '',
          'priceController': '0',
          'qtyController': '1',
        });
      }, returnsNormally);

      expect(editedItems.length, equals(2));
      expect(editedItems[1]['lineType'], equals('Product'));
    });

    test('SalesViewModel loadSaleForEditing populates cart and edit state correctly', () {
      final sale = Sale(
        invoiceNo: 1005,
        saleDate: DateTime(2026, 8, 1),
        customerName: 'John Doe',
        customerNumber: '9876543210',
        paymentMode: 'Cash',
        advance: 100.0,
        discount: 50.0,
        totalAmount: 450.0,
        orderStatus: 'Confirmed',
      );

      final items = [
        SaleItem(
          id: 'item_1',
          invoiceNo: 1005,
          lineType: 'Product',
          itemDescription: 'SSD 500GB',
          quantity: 1,
          itemPrice: 500.0,
          totalAmount: 500.0,
        ),
      ];

      final vm = SalesViewModel(repository: ShopRepository(localDb: LocalDatabaseService()));
      vm.loadSaleForEditing(sale, items);

      expect(vm.isEditing, isTrue);
      expect(vm.editingInvoiceNo, equals(1005));
      expect(vm.editingOrderStatus, equals('Confirmed'));
      expect(vm.customerName, equals('John Doe'));
      expect(vm.customerNumber, equals('9876543210'));
      expect(vm.paymentMode, equals('Cash'));
      expect(vm.advance, equals(100.0));
      expect(vm.discount, equals(50.0));
      expect(vm.cartItems.length, equals(1));
      expect(vm.cartItems.first.itemDescription, equals('SSD 500GB'));

      vm.clearCart();
      expect(vm.isEditing, isFalse);
      expect(vm.editingInvoiceNo, null);
      expect(vm.cartItems, isEmpty);
    });
  });
}

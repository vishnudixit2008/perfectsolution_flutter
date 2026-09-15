import 'package:flutter_test/flutter_test.dart';
import 'package:shop_management_flutter/data/models/dealer.dart';
import 'package:shop_management_flutter/data/models/purchase_order.dart';
import 'package:shop_management_flutter/data/models/purchase_order_item.dart';
import 'package:shop_management_flutter/data/services/item_category_detector.dart';
import 'package:shop_management_flutter/data/services/dealer_recommendation_service.dart';

void main() {
  group('ItemCategoryDetector Tests', () {
    test('Correctly detects Battery, HP Brand, and Model Code', () {
      final res = ItemCategoryDetector.classify('HP 15-DA Battery HT03XL');
      expect(res.category, ItemCategory.batteries);
      expect(res.brand, 'HP');
      expect(res.modelCode, 'HT03XL');
      expect(res.searchKeywords, contains('battery'));
    });

    test('Correctly detects Screen, Dell Brand, Model, and Specs', () {
      final res = ItemCategoryDetector.classify('Dell Inspiron 3511 screen 30 pin FHD');
      expect(res.category, ItemCategory.screens);
      expect(res.brand, 'Dell');
      expect(res.specTokens, contains('30 PIN'));
      expect(res.specTokens, contains('FHD'));
    });

    test('Correctly detects Asus Battery with Wh spec', () {
      final res = ItemCategoryDetector.classify('Asus ROG Zephyrus G14 76Wh battery');
      expect(res.category, ItemCategory.batteries);
      expect(res.brand, 'Asus');
      expect(res.specTokens, contains('76WH'));
    });

    test('Correctly detects Motherboard & Chips', () {
      final res = ItemCategoryDetector.classify('Lenovo IdeaPad L340 motherboard repair with IT8586E IO chip');
      expect(res.category, ItemCategory.motherboards);
      expect(res.brand, 'Lenovo');
    });

    test('Correctly detects Apple MacBook Keyboard', () {
      final res = ItemCategoryDetector.classify('Apple MacBook Air A1965 keyboard backlit');
      expect(res.category, ItemCategory.keyboards);
      expect(res.brand, 'Apple');
      expect(res.specTokens, contains('BACKLIT'));
    });

    test('Correctly detects Power Adapter with Wattage', () {
      final res = ItemCategoryDetector.classify('Type C 65W charger for Lenovo laptop');
      expect(res.category, ItemCategory.chargers);
      expect(res.brand, 'Lenovo');
      expect(res.specTokens, contains('65W'));
    });

    test('Correctly detects Laptop Body trade shorthand (ABH, ABCD, ABCDH, CD, Panels)', () {
      final res1 = ItemCategoryDetector.classify('Dell 3511 ABH');
      expect(res1.category, ItemCategory.hingesAndBody);
      expect(res1.brand, 'Dell');
      expect(res1.searchKeywords, contains('abh'));

      final res2 = ItemCategoryDetector.classify('HP 15-da ABCD');
      expect(res2.category, ItemCategory.hingesAndBody);
      expect(res2.brand, 'HP');
      expect(res2.searchKeywords, contains('abcd'));

      final res3 = ItemCategoryDetector.classify('Lenovo V15 ABCDH');
      expect(res3.category, ItemCategory.hingesAndBody);
      expect(res3.brand, 'Lenovo');
      expect(res3.searchKeywords, contains('abcdh'));

      final res4 = ItemCategoryDetector.classify('Acer Aspire CD');
      expect(res4.category, ItemCategory.hingesAndBody);
      expect(res4.brand, 'Acer');

      final res5 = ItemCategoryDetector.classify('Dell 3511 top cover');
      expect(res5.category, ItemCategory.hingesAndBody);

      final res6 = ItemCategoryDetector.classify('HP top pannel');
      expect(res6.category, ItemCategory.hingesAndBody);

      final res7 = ItemCategoryDetector.classify('Lenovo bezzel');
      expect(res7.category, ItemCategory.hingesAndBody);

      final res8 = ItemCategoryDetector.classify('Acer bottom base');
      expect(res8.category, ItemCategory.hingesAndBody);

      final res9 = ItemCategoryDetector.classify('Asus hinge');
      expect(res9.category, ItemCategory.hingesAndBody);

      final res10 = ItemCategoryDetector.classify('Dell touchpad');
      expect(res10.category, ItemCategory.hingesAndBody);
    });

    test('Dealer.fromJson automatically normalizes legacy abcd and a,b,c,d into Laptop Body Parts', () {
      final d = Dealer.fromJson({
        'id': 'd-test',
        'name': 'Test Dealer',
        'products': 'keyboard,fan,abcd,display cable,a,b,c,d',
      });
      expect(d.products, 'keyboard,fan,laptop body parts,display cable');
    });
  });

  group('DealerRecommendationService Tests', () {
    final dealers = [
      Dealer(
        id: 'dlr-1',
        name: 'Siddharth Screen Hub',
        mobileNo: '9811111111',
        address: 'Nehru Place',
        buildingName: 'Siddharth Building',
        category: 'Screens',
        products: 'laptop display, 30pin, 40pin, fhd, oled',
      ),
      Dealer(
        id: 'dlr-2',
        name: 'Battery World',
        mobileNo: '9822222222',
        address: 'Nehru Place',
        buildingName: 'Meghdoot Building',
        category: 'Batteries',
        products: 'dell hp lenovo battery, 42wh, 76wh',
      ),
      Dealer(
        id: 'dlr-3',
        name: 'General Spares Co',
        mobileNo: '9833333333',
        address: 'Nehru Place',
        buildingName: 'Shakarpur',
        category: 'General',
        products: 'cables, screws, thermal paste',
      ),
      Dealer(
        id: 'dlr-4',
        name: 'Nehru Place Casing Hub',
        mobileNo: '9844444444',
        address: 'Nehru Place',
        buildingName: 'Deepak Building',
        category: 'Laptop Body & Hinges',
        products: 'Laptop Body Parts, Hinges',
      ),
    ];

    test('Ranks Casing Hub #1 for ABCDH, top cover, top pannel, bezzel, base, hinge, and touchpad', () {
      final queries = [
        'Dell 3511 ABCDH',
        'HP 15-da ABCD',
        'Dell 3511 ABH',
        'HP 15-da top cover',
        'Lenovo top pannel',
        'Acer bezzel',
        'Asus bottom base',
        'HP laptop hinge',
        'Dell Inspiron touchpad',
      ];

      for (final q in queries) {
        final rec = DealerRecommendationService.getRecommendations(
          itemText: q,
          allDealers: dealers,
          purchaseOrders: const [],
          getPurchaseItems: (_) => const [],
        );
        expect(rec.isNotEmpty, true, reason: 'Failed for query: $q');
        expect(rec.first.dealer.id, 'dlr-4', reason: 'dlr-4 should be #1 for query: $q');
      }
    });

    test('Ranks Battery World #1 when Battery is requested', () {
      final recommendations = DealerRecommendationService.getRecommendations(
        itemText: 'HP 15-DA Battery HT03XL',
        allDealers: dealers,
        purchaseOrders: const [],
        getPurchaseItems: (_) => const [],
      );

      expect(recommendations.isNotEmpty, true);
      expect(recommendations.first.dealer.id, 'dlr-2');
      expect(recommendations.first.matchReasons.any((r) => r.contains('Battery')), true);
    });

    test('Auto-learning from purchase history boosts frequent supplier', () {
      // Suppose we have 4 past purchase orders from General Spares Co specifically for screens
      final fakeOrders = [
        PurchaseOrder(id: 'po-1', date: DateTime.now(), purchasedFrom: 'General Spares Co'),
        PurchaseOrder(id: 'po-2', date: DateTime.now(), purchasedFrom: 'General Spares Co'),
        PurchaseOrder(id: 'po-3', date: DateTime.now(), purchasedFrom: 'General Spares Co'),
        PurchaseOrder(id: 'po-4', date: DateTime.now(), purchasedFrom: 'General Spares Co'),
      ];

      final fakeItems = [
        PurchaseOrderItem(lineId: 'l1', purchaseId: 'po-1', customItemName: '15.6 FHD Screen 30 pin', amount: 2200),
      ];

      final recommendations = DealerRecommendationService.getRecommendations(
        itemText: '15.6 FHD Screen 30 pin',
        allDealers: dealers,
        purchaseOrders: fakeOrders,
        getPurchaseItems: (id) => fakeItems,
      );

      // Even though General Spares didn't tag screens in products, purchase history auto-learns!
      final generalSparesRec = recommendations.firstWhere((r) => r.dealer.id == 'dlr-3');
      expect(generalSparesRec.pastCategoryPurchaseCount, 4);
      expect(generalSparesRec.matchReasons.any((r) => r.contains('⭐ Frequent Supplier')), true);
    });
  });
}

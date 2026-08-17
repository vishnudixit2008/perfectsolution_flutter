import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../data/models/purchase_order.dart';
import '../../../../data/models/purchase_order_item.dart';
import '../../../../data/repositories/shop_repository.dart';

class PurchasesViewModel extends ChangeNotifier {
  final ShopRepository _repository;
  StreamSubscription? _dataSubscription;

  PurchasesViewModel({required ShopRepository repository})
    : _repository = repository {
    _dataSubscription = _repository.onTableDataChanged.listen((table) {
      if (table == 'purchases' || table == 'all') {
        loadPurchases();
      } else if (table == 'app_users') {
        loadPurchases();
      }
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  List<PurchaseOrder> _purchases = [];
  bool _isLoading = false;

  List<PurchaseOrder> get purchases => _purchases;
  bool get isLoading => _isLoading;

  Future<void> loadPurchases() async {
    _isLoading = true;
    notifyListeners();
    try {
      _purchases = _repository.getPurchaseOrders();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading purchases: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<PurchaseOrderItem> getPurchaseItems(String purchaseId) {
    return _repository.getPurchaseOrderItems(purchaseId);
  }

  String getNextId() {
    return _repository.getNextPurchaseOrderId();
  }

  Future<void> savePurchase(
    PurchaseOrder order,
    List<PurchaseOrderItem> items,
  ) async {
    await _repository.savePurchaseOrder(order, items);
    await loadPurchases();
  }

  Future<void> deletePurchase(String id) async {
    await _repository.deletePurchaseOrder(id);
    await loadPurchases();
  }

  Future<bool> confirmPurchase(String id) async {
    final success = await _repository.confirmPurchase(id);
    await loadPurchases();
    return success;
  }

  Future<bool> revertPurchaseToPending(String id) async {
    final success = await _repository.setPurchaseStatusPending(id);
    await loadPurchases();
    return success;
  }
}

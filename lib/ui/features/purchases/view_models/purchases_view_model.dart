import '../../../../data/services/supabase_sync_service.dart';
import 'package:flutter/foundation.dart';
import '../../../../data/models/purchase_order.dart';
import '../../../../data/models/purchase_order_item.dart';
import '../../../../data/repositories/shop_repository.dart';

class PurchasesViewModel extends ChangeNotifier {
  final ShopRepository _repository;

  PurchasesViewModel({required ShopRepository repository})
    : _repository = repository {
    SupabaseSyncService.instance.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (SupabaseSyncService.instance.status == SyncStatus.synced) {
      loadPurchases();
    }
  }

  @override
  void dispose() {
    SupabaseSyncService.instance.removeListener(_onSyncChanged);
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

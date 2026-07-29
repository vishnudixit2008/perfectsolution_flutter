import '../../../../data/services/supabase_sync_service.dart';
import 'package:flutter/foundation.dart';
import '../../../../data/models/request_order.dart';
import '../../../../data/repositories/shop_repository.dart';

class RequestsViewModel extends ChangeNotifier {
  final ShopRepository _repository;

  RequestsViewModel({required ShopRepository repository})
    : _repository = repository {
    SupabaseSyncService.instance.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (SupabaseSyncService.instance.status == SyncStatus.synced) {
      loadRequests();
    }
  }

  @override
  void dispose() {
    SupabaseSyncService.instance.removeListener(_onSyncChanged);
    super.dispose();
  }

  List<RequestOrder> _requests = [];
  bool _isLoading = false;

  List<RequestOrder> get requests => _requests;
  bool get isLoading => _isLoading;

  Future<void> loadRequests() async {
    _isLoading = true;
    notifyListeners();
    try {
      _requests = _repository.getRequestOrders();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading requests: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String getNextId() {
    return _repository.getNextRequestOrderId();
  }

  Future<void> saveRequest(RequestOrder order) async {
    await _repository.saveRequestOrder(order);
    await loadRequests();
  }

  Future<void> deleteRequest(String id) async {
    await _repository.deleteRequestOrder(id);
    await loadRequests();
  }
}

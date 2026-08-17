import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../data/models/request_order.dart';
import '../../../../data/repositories/shop_repository.dart';

class RequestsViewModel extends ChangeNotifier {
  final ShopRepository _repository;
  StreamSubscription? _dataSubscription;

  RequestsViewModel({required ShopRepository repository})
    : _repository = repository {
    _dataSubscription = _repository.onTableDataChanged.listen((table) {
      if (table == 'requests' || table == 'all') {
        loadRequests();
      } else if (table == 'app_users') {
        loadRequests();
      }
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
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

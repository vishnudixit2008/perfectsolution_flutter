import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../data/models/purchase_order.dart';
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

  List<RequestOrder> getRunnerTasks({String? runnerId}) {
    return _repository.getRunnerTasks(runnerId: runnerId);
  }

  Future<void> assignRunner({
    required String requestId,
    required String runnerId,
    required String runnerName,
    String? dealerName,
    String? building,
    String? shopNo,
  }) async {
    await _repository.assignRequestToRunner(
      requestId: requestId,
      runnerId: runnerId,
      runnerName: runnerName,
      dealerName: dealerName,
      building: building,
      shopNo: shopNo,
    );
    await loadRequests();
  }

  Future<void> markCollected({
    required String requestId,
    required double actualCost,
    String? billPhoto,
  }) async {
    await _repository.markRequestCollected(
      requestId: requestId,
      actualCost: actualCost,
      billPhoto: billPhoto,
    );
    await loadRequests();
  }

  Future<PurchaseOrder> convertToPurchase(RequestOrder request) async {
    final purchase = await _repository.convertRequestToPurchase(request);
    await loadRequests();
    return purchase;
  }

  Future<void> updateStatus(String requestId, String newStatus) async {
    final match = _requests.where((r) => r.id == requestId).firstOrNull;
    if (match == null) return;
    final updated = match.copyWith(
      status: newStatus,
      updatedAt: DateTime.now(),
    );
    await saveRequest(updated);
  }
}

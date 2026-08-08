import '../../../../data/services/supabase_sync_service.dart';
import 'package:flutter/foundation.dart';
import '../../../../data/models/sale.dart';
import '../../../../data/models/sale_item.dart';
import '../../../../data/repositories/shop_repository.dart';

class RecentSalesViewModel extends ChangeNotifier {
  final ShopRepository _repository;

  RecentSalesViewModel({required ShopRepository repository})
    : _repository = repository {
    SupabaseSyncService.instance.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (SupabaseSyncService.instance.status == SyncStatus.synced) {
      loadSales();
    }
  }

  @override
  void dispose() {
    SupabaseSyncService.instance.removeListener(_onSyncChanged);
    super.dispose();
  }

  List<Sale> _sales = [];
  bool _isLoading = false;
  String? _activeUpiId;
  int _currentPage = 1;
  int _itemsPerPage = 20;

  // Getters
  List<Sale> get sales => _sales;
  bool get isLoading => _isLoading;
  String? get activeUpiId => _activeUpiId;
  int get currentPage => _currentPage;
  int get itemsPerPage => _itemsPerPage;

  void setPage(int page, int totalPages) {
    if (page >= 1 && page <= totalPages) {
      _currentPage = page;
      notifyListeners();
    }
  }

  void nextPage(int totalPages) {
    if (_currentPage < totalPages) {
      _currentPage++;
      notifyListeners();
    }
  }

  void previousPage() {
    if (_currentPage > 1) {
      _currentPage--;
      notifyListeners();
    }
  }

  void setItemsPerPage(int count) {
    if (count > 0) {
      _itemsPerPage = count;
      _currentPage = 1;
      notifyListeners();
    }
  }

  // Dynamically retrieve the latest active UPI ID from the database
  String? getActiveUpiId() {
    return _repository.getActiveUpiId();
  }

  // Load past sales list from DB
  Future<void> loadSales() async {
    _isLoading = true;
    notifyListeners();

    try {
      _sales = _repository.getSales();
      _activeUpiId = _repository.getActiveUpiId();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading sales ledger: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get line items list for specific invoice
  List<SaleItem> getSaleItems(int invoiceNo) {
    return _repository.getSaleItems(invoiceNo);
  }

  String getUpiReferenceName(String upiId) {
    return _repository.getUpiNamesMap()[upiId] ?? '';
  }

  Sale? getSaleByInvoiceNo(int invoiceNo) {
    try {
      return _sales.firstWhere((s) => s.invoiceNo == invoiceNo);
    } catch (_) {
      return null;
    }
  }

  // Verify and Confirm Order (Deducts Catalog Stock)
  Future<bool> confirmOrder(int invoiceNo) async {
    try {
      final success = await _repository.confirmSale(invoiceNo);
      if (success) {
        await loadSales(); // Reload sales list
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error confirming order: $e');
      }
      return false;
    }
  }

  // Revert order status to PENDING (Adds back catalog stock)
  Future<bool> setSaleStatusPending(int invoiceNo) async {
    try {
      final success = await _repository.setSaleStatusPending(invoiceNo);
      if (success) {
        await loadSales();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error changing status to pending: $e');
      }
      return false;
    }
  }

  // Delete sale records completely (reverts stock if confirmed)
  Future<bool> deleteSale(int invoiceNo) async {
    try {
      final success = await _repository.deleteSale(invoiceNo);
      if (success) {
        await loadSales();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting sale: $e');
      }
      return false;
    }
  }

  Future<bool> updateSale(Sale sale, List<SaleItem> items) async {
    try {
      final success = await _repository.updateSale(sale, items);
      if (success) {
        await loadSales();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error updating sale: $e');
      }
      return false;
    }
  }
}

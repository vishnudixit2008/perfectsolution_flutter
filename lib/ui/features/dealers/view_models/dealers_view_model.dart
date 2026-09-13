import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../data/models/dealer.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/smart_search_utils.dart';

class DealersViewModel extends ChangeNotifier {
  final ShopRepository _repository;
  StreamSubscription? _dataSubscription;

  List<Dealer> _dealers = [];
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoading = false;

  DealersViewModel({required ShopRepository repository})
      : _repository = repository {
    _dataSubscription = _repository.onTableDataChanged.listen((table) {
      if (table == 'dealers' || table == 'all') {
        loadDealers();
      }
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  List<Dealer> get dealers => _dealers;
  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;

  List<String> get categories {
    final set = <String>{'All'};
    for (final d in _dealers) {
      if (d.category != null && d.category!.trim().isNotEmpty) {
        set.add(d.category!.trim());
      }
    }
    return set.toList();
  }

  List<Dealer> get filteredDealers {
    return _dealers.where((d) {
      if (_selectedCategory != 'All') {
        if ((d.category ?? '').trim().toLowerCase() != _selectedCategory.toLowerCase()) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final combined =
            '${d.name} ${d.contactPerson ?? ""} ${d.mobileNo ?? ""} ${d.buildingName ?? ""} ${d.address} ${d.products ?? ""} ${d.category ?? ""}';
        return SmartSearchUtils.matchesQuery(combined, _searchQuery);
      }
      return true;
    }).toList();
  }

  Future<void> loadDealers() async {
    _isLoading = true;
    notifyListeners();
    try {
      _dealers = _repository.getDealers();
    } catch (e) {
      if (kDebugMode) print('Error loading dealers: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query.trim();
    notifyListeners();
  }

  Future<void> saveDealer(Dealer dealer) async {
    await _repository.saveDealer(dealer);
    await loadDealers();
  }

  Future<void> deleteDealer(String id) async {
    await _repository.deleteDealer(id);
    await loadDealers();
  }
}

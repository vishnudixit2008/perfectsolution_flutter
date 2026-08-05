import 'package:flutter/foundation.dart';
import '../../../../data/models/pricelist_item.dart';
import '../../../../data/models/product_history_record.dart';
import '../../../../data/repositories/shop_repository.dart';

class PricelistViewModel extends ChangeNotifier {
  final ShopRepository _repository;

  PricelistViewModel({required ShopRepository repository})
    : _repository = repository;

  List<PricelistItem> _items = [];
  String _searchQuery = '';
  String? _selectedCategory;
  String _sortColumn = 'itemName';
  bool _sortAscending = true;
  bool _isLoading = false;
  int _currentPage = 1;
  int _itemsPerPage = 20;

  // Getters
  List<PricelistItem> get items => _items;
  String get searchQuery => _searchQuery;
  String? get selectedCategory => _selectedCategory;
  String get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  bool get isLoading => _isLoading;
  int get currentPage => _currentPage;
  int get itemsPerPage => _itemsPerPage;
  int get totalPages {
    final int count = filteredItems.length;
    if (count == 0) return 1;
    return (count / _itemsPerPage).ceil();
  }

  // Get distinct categories present in catalog
  List<String> get categories {
    final Set<String> distinct = {};
    for (var item in _items) {
      if (item.category != null && item.category!.trim().isNotEmpty) {
        distinct.add(item.category!.trim());
      }
    }
    final sorted = distinct.toList()..sort();
    return sorted;
  }

  // Load items from local database
  Future<void> loadItems() async {
    _isLoading = true;
    notifyListeners();

    try {
      _items = _repository.getPricelist();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading items in view model: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Filter query updater
  void setSearchQuery(String query) {
    _searchQuery = query.toLowerCase();
    _currentPage = 1;
    notifyListeners();
  }

  void setSelectedCategory(String? category) {
    _selectedCategory = category;
    _currentPage = 1;
    notifyListeners();
  }

  // Pagination Actions
  void setPage(int page) {
    if (page >= 1 && page <= totalPages) {
      _currentPage = page;
      notifyListeners();
    }
  }

  void nextPage() {
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

  // Toggle sorting logic
  void toggleSort(String column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    notifyListeners();
  }

  // Generate next sequential integer ID
  int getNextId() {
    if (_items.isEmpty) return 1;
    int maxId = 0;
    for (var item in _items) {
      if (item.id > maxId) maxId = item.id;
    }
    return maxId + 1;
  }

  Future<void> resetDatabase() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _repository.resetPricelistToDefault();
      _items = _repository.getPricelist();
    } catch (e) {
      if (kDebugMode) {
        print('Error resetting database: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // CRUD Operations
  Future<void> addItem(PricelistItem item) async {
    await _repository.savePricelistItem(item);
    await loadItems();
  }

  Future<void> updateItem(PricelistItem item) async {
    await _repository.savePricelistItem(item);
    await loadItems();
  }

  Future<void> deleteItem(int id) async {
    await _repository.deletePricelistItem(id);
    await loadItems();
  }

  // Get processed list of items
  List<PricelistItem> get filteredItems {
    List<PricelistItem> list = [..._items];

    // 1. Search Query Filter (Item Name or Category)
    if (_searchQuery.isNotEmpty) {
      list = list.where((item) {
        final nameMatch = item.itemName.toLowerCase().contains(_searchQuery);
        final descMatch =
            item.itemDescription?.toLowerCase().contains(_searchQuery) ?? false;
        final catMatch =
            item.category?.toLowerCase().contains(_searchQuery) ?? false;
        return nameMatch || descMatch || catMatch;
      }).toList();
    }

    // 2. Category Dropdown Filter
    if (_selectedCategory != null) {
      list = list.where((item) => item.category == _selectedCategory).toList();
    }

    // 3. Sorting
    list.sort((a, b) {
      dynamic valA;
      dynamic valB;

      switch (_sortColumn) {
        case 'id':
          valA = a.id;
          valB = b.id;
          break;
        case 'itemName':
          valA = a.itemName.toLowerCase();
          valB = b.itemName.toLowerCase();
          break;
        case 'price':
          valA = a.price;
          valB = b.price;
          break;
        case 'stockQty':
          valA = a.stockQty;
          valB = b.stockQty;
          break;
        case 'category':
          valA = (a.category ?? '').toLowerCase();
          valB = (b.category ?? '').toLowerCase();
          break;
        default:
          valA = a.itemName.toLowerCase();
          valB = b.itemName.toLowerCase();
      }

      int comparison;
      if (valA is String && valB is String) {
        comparison = valA.compareTo(valB);
      } else {
        comparison = (valA as num).compareTo(valB as num);
      }

      return _sortAscending ? comparison : -comparison;
    });

    return list;
  }

  // Get paged items to minimize rendering memory and lag
  List<PricelistItem> get pagedItems {
    final list = filteredItems;
    final int startIndex = (_currentPage - 1) * _itemsPerPage;
    if (startIndex >= list.length) return [];
    return list.skip(startIndex).take(_itemsPerPage).toList();
  }

  // Get items grouped by category for Android/mobile listing
  Map<String, List<PricelistItem>> get groupedFilteredItems {
    final map = <String, List<PricelistItem>>{};
    for (final item in filteredItems) {
      final cat = (item.category != null && item.category!.trim().isNotEmpty)
          ? item.category!.trim()
          : 'General';
      map.putIfAbsent(cat, () => []).add(item);
    }
    return map;
  }

  // Product History Methods
  List<ProductHistoryRecord> getProductHistory(PricelistItem product) {
    return _repository.getProductHistory(product);
  }
}

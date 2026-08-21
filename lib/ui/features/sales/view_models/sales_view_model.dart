import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../data/models/pricelist_item.dart';
import '../../../../data/models/sale.dart';
import '../../../../data/models/sale_item.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/smart_search_utils.dart';

class SalesViewModel extends ChangeNotifier {
  final ShopRepository _repository;
  StreamSubscription? _dataSubscription;

  SalesViewModel({required ShopRepository repository})
    : _repository = repository {
    _dataSubscription = _repository.onTableDataChanged.listen((table) {
      if (table == 'pricelist_items' || table == 'pricelist' || table == 'all') {
        loadCatalog();
      } else if (table == 'app_users') {
        loadCatalog();
      }
      if (table == 'custom_services' || table == 'shop_settings' || table == 'all') {
        loadSavedServices();
      }
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  // Search catalog state
  List<PricelistItem> _catalogItems = [];
  String _searchQuery = '';

  // Cart state
  final List<SaleItem> _cartItems = [];
  String _customerName = '';
  String _customerNumber = '';
  String _paymentMode = 'UPI'; // Default to UPI
  double _advance = 0.0;
  double _discount = 0.0;
  bool _isSaving = false;
  List<String> _savedServices = [];

  // Editing Sale state
  int? _editingInvoiceNo;
  String? _editingOrderStatus;
  DateTime? _editingSaleDate;
  String? _editingPhoto;

  // Getters
  List<SaleItem> get cartItems => _cartItems;
  String get customerName => _customerName;
  String get customerNumber => _customerNumber;
  String get paymentMode => _paymentMode;
  double get advance => _advance;
  double get discount => _discount;
  bool get isSaving => _isSaving;
  String get searchQuery => _searchQuery;
  List<String> get savedServices => _savedServices;
  List<PricelistItem> get catalogItems => _catalogItems;

  bool get isEditing => _editingInvoiceNo != null;
  int? get editingInvoiceNo => _editingInvoiceNo;
  String? get editingOrderStatus => _editingOrderStatus;

  int get currentOrNextInvoiceNo {
    return _editingInvoiceNo ?? _repository.getNextInvoiceNo();
  }

  // Load available catalog list for item selector
  void loadCatalog() {
    _catalogItems = _repository.getPricelist();
    loadSavedServices();
  }

  void loadSavedServices() {
    _savedServices = _repository.getCustomServiceNames();
    notifyListeners();
  }

  // Get filtered items based on smart multi-token search query
  List<PricelistItem> get searchResults {
    if (_searchQuery.trim().isEmpty) return [];
    return SmartSearchUtils.filterPricelist(_catalogItems, _searchQuery);
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // Add Product Item to Cart
  void addProductToCart(PricelistItem product) {
    // Check if product is already in cart
    final existingIdx = _cartItems.indexWhere(
      (item) => item.lineType == 'Product' && item.itemId == product.id,
    );

    if (existingIdx != -1 && existingIdx >= 0) {
      // Increment quantity
      final item = _cartItems[existingIdx];
      _cartItems[existingIdx] = item.copyWith(
        quantity: item.quantity + 1,
        totalAmount: (item.quantity + 1) * item.activePrice,
      );
    } else {
      // Create new line item (temp invoiceNo = 0, will assign on checkout)
      final newItem = SaleItem(
        id: 'prod_${product.id}_${DateTime.now().millisecondsSinceEpoch}',
        invoiceNo: 0,
        lineType: 'Product',
        itemId: product.id,
        itemDescription: product.itemName,
        quantity: 1,
        itemPrice: product.price,
        totalAmount: product.price,
        notes: product.itemDescription,
      );
      _cartItems.add(newItem);
    }
    _searchQuery = '';
    notifyListeners();
  }

  // Add Custom Service to Cart
  Future<void> addCustomServiceToCart(String serviceName, double price, {String? notes}) async {
    await _repository.saveCustomServiceName(serviceName);
    loadSavedServices();

    final newItem = SaleItem(
      id: 'srv_${DateTime.now().millisecondsSinceEpoch}',
      invoiceNo: 0,
      lineType: 'Service',
      itemDescription: serviceName,
      quantity: 1,
      itemPrice: price,
      totalAmount: price,
      notes: notes,
    );
    _cartItems.add(newItem);
    notifyListeners();
  }

  // Add SaleItem to Cart (for prefilling estimates/products/services)
  void addSaleItemToCart({
    int? itemId,
    required String lineType,
    required String itemDescription,
    required int quantity,
    required double itemPrice,
    double? customPrice,
    String? notes,
  }) {
    final int qty = quantity > 0 ? quantity : 1;
    final double effectivePrice = customPrice ?? itemPrice;
    final newItem = SaleItem(
      id: '${lineType.toLowerCase()}_${DateTime.now().microsecondsSinceEpoch}_${_cartItems.length}_${_cartItems.hashCode}',
      invoiceNo: 0,
      itemId: itemId,
      lineType: lineType,
      itemDescription: itemDescription,
      quantity: qty,
      itemPrice: itemPrice,
      customPrice: customPrice,
      totalAmount: qty * effectivePrice,
      notes: notes,
    );
    _cartItems.add(newItem);
    notifyListeners();
  }

  // Update item notes / secondary description
  void updateItemNotes(String cartItemId, String? notes) {
    final idx = _cartItems.indexWhere((item) => item.id == cartItemId);
    if (idx >= 0) {
      final item = _cartItems[idx];
      _cartItems[idx] = item.copyWith(
        notes: notes,
      );
      notifyListeners();
    }
  }

  // Update item quantity
  void updateItemQuantity(String cartItemId, int quantity) {
    if (quantity <= 0) {
      removeCartItem(cartItemId);
      return;
    }

    final idx = _cartItems.indexWhere((item) => item.id == cartItemId);
    if (idx >= 0) {
      final item = _cartItems[idx];
      _cartItems[idx] = item.copyWith(
        quantity: quantity,
        totalAmount: quantity * item.activePrice,
      );
      notifyListeners();
    }
  }

  // Update custom price override
  void updateItemCustomPrice(String cartItemId, double? price) {
    final idx = _cartItems.indexWhere((item) => item.id == cartItemId);
    if (idx >= 0) {
      final item = _cartItems[idx];
      final double activeRate = price ?? item.itemPrice;
      _cartItems[idx] = item.copyWith(
        customPrice: price,
        clearCustomPrice: price == null,
        totalAmount: item.quantity * activeRate,
      );
      notifyListeners();
    }
  }

  // Remove cart item
  void removeCartItem(String cartItemId) {
    final index = _cartItems.indexWhere((item) => item.id == cartItemId);
    if (index >= 0) {
      _cartItems.removeAt(index);
      notifyListeners();
    }
  }

  // Setters for customer details
  void setCustomerName(String name) {
    _customerName = name;
  }

  void setCustomerNumber(String num) {
    _customerNumber = num;
  }

  void setPaymentMode(String mode) {
    _paymentMode = mode;
    notifyListeners();
  }

  void setAdvance(double val) {
    _advance = val;
    notifyListeners();
  }

  void setDiscount(double val) {
    _discount = val;
    notifyListeners();
  }

  // Totals calculations
  double get subtotal {
    return _cartItems.fold(0.0, (sum, item) => sum + item.totalAmount);
  }

  double get totalAmount {
    final double net = subtotal - _discount - _advance;
    return net < 0.0 ? 0.0 : net;
  }

  // Load existing sale into cart for editing
  void loadSaleForEditing(Sale sale, List<SaleItem> items) {
    _editingInvoiceNo = sale.invoiceNo;
    _editingOrderStatus = sale.orderStatus;
    _editingSaleDate = sale.saleDate;
    _editingPhoto = sale.photo;

    _cartItems.clear();
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final uniqueId = item.id.trim().isNotEmpty
          ? item.id
          : 'edit_item_${sale.invoiceNo}_${i}_${DateTime.now().microsecondsSinceEpoch}';
      _cartItems.add(item.copyWith(id: uniqueId));
    }

    _customerName = sale.customerName ?? '';
    _customerNumber = sale.customerNumber ?? '';
    _paymentMode = ['UPI', 'Cash', 'Card'].contains(sale.paymentMode)
        ? sale.paymentMode
        : 'UPI';
    _advance = sale.advance;
    _discount = sale.discount;
    _searchQuery = '';
    notifyListeners();
  }

  DateTime get selectedSaleDate => _editingSaleDate ?? DateTime.now();

  void setSelectedSaleDate(DateTime dt) {
    _editingSaleDate = dt;
    notifyListeners();
  }

  void setEditingOrderStatus(String status) {
    _editingOrderStatus = status;
    notifyListeners();
  }

  // Checkout (creates new sale or updates existing sale if editing)
  Future<int?> checkout() async {
    if (_cartItems.isEmpty) return null;

    _isSaving = true;
    notifyListeners();

    try {
      final int invoiceNo =
          _editingInvoiceNo ?? _repository.getNextInvoiceNo();
      final DateTime saleDate = _editingSaleDate ?? DateTime.now();
      final String orderStatus = _editingOrderStatus ?? 'PENDING';

      final List<SaleItem> finalItems = _cartItems.map((item) {
        return item.copyWith(invoiceNo: invoiceNo);
      }).toList();

      final sale = Sale(
        invoiceNo: invoiceNo,
        saleDate: saleDate,
        customerName: _customerName.trim().isEmpty
            ? null
            : _customerName.trim(),
        customerNumber: _customerNumber.trim().isEmpty
            ? null
            : _customerNumber.trim(),
        paymentMode: _paymentMode,
        advance: _advance,
        discount: _discount,
        totalAmount: totalAmount,
        orderStatus: orderStatus,
        photo: _editingPhoto,
      );

      await _repository.saveSale(sale, finalItems);

      // Clear Cart
      clearCart();
      return invoiceNo;
    } catch (e) {
      if (kDebugMode) {
        print('Checkout error: $e');
      }
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void clearCart() {
    _cartItems.clear();
    _customerName = '';
    _customerNumber = '';
    _paymentMode = 'UPI';
    _advance = 0.0;
    _discount = 0.0;
    _searchQuery = '';
    _editingInvoiceNo = null;
    _editingOrderStatus = null;
    _editingSaleDate = null;
    _editingPhoto = null;
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';
import '../../../../data/repositories/shop_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  final ShopRepository _repository;

  SettingsViewModel({required ShopRepository repository})
    : _repository = repository;

  // ── UPI ──────────────────────────────────────────────────────────────────
  List<String> _upiIds = [];
  String? _activeUpiId;

  List<String> get upiIds => _upiIds;
  String? get activeUpiId => _activeUpiId;

  // ── Invoice Print Settings ─────────────────────────────────────────────────
  String _invoicePageSize = 'A5';
  double _marginTB = 10.0;
  double _marginLR = 10.0;
  bool _showHeader = true;
  bool _showQr = true;

  String get invoicePageSize => _invoicePageSize;
  double get marginTB => _marginTB;
  double get marginLR => _marginLR;
  bool get showHeader => _showHeader;
  bool get showQr => _showQr;

  // ── Loading ───────────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // ── Initialisation ────────────────────────────────────────────────────────
  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      _upiIds = _repository.getUpiIdsList();
      _activeUpiId = _repository.getActiveUpiId();

      // Auto-assign the first UPI ID as active if none is set
      if (_activeUpiId == null && _upiIds.isNotEmpty) {
        _activeUpiId = _upiIds.first;
        await _repository.setActiveUpiId(_activeUpiId!);
      }

      // Invoice print settings
      _invoicePageSize = _repository.getInvoicePageSize();
      _marginTB = _repository.getInvoiceMarginTB();
      _marginLR = _repository.getInvoiceMarginLR();
      _showHeader = _repository.getInvoiceShowHeader();
      _showQr = _repository.getInvoiceShowQr();
    } catch (e) {
      if (kDebugMode) print('Error loading settings: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── UPI Methods ───────────────────────────────────────────────────────────
  Future<void> selectActiveUpiId(String upiId) async {
    if (_upiIds.contains(upiId)) {
      _activeUpiId = upiId;
      await _repository.setActiveUpiId(upiId);
      notifyListeners();
    }
  }

  Future<bool> addUpiId(String upiId) async {
    final cleaned = upiId.trim();
    if (cleaned.isEmpty || !cleaned.contains('@')) return false;
    if (_upiIds.contains(cleaned)) return false;

    _upiIds.add(cleaned);
    await _repository.saveUpiIdsList(_upiIds);

    if (_activeUpiId == null) {
      _activeUpiId = cleaned;
      await _repository.setActiveUpiId(cleaned);
    }

    notifyListeners();
    return true;
  }

  Future<void> deleteUpiId(String upiId) async {
    _upiIds.remove(upiId);
    await _repository.saveUpiIdsList(_upiIds);

    if (_activeUpiId == upiId) {
      if (_upiIds.isNotEmpty) {
        _activeUpiId = _upiIds.first;
        await _repository.setActiveUpiId(_activeUpiId!);
      } else {
        _activeUpiId = null;
        await _repository.setActiveUpiId('');
      }
    }

    notifyListeners();
  }

  // ── Invoice Print Settings Methods ────────────────────────────────────────

  Future<void> setInvoicePageSize(String size) async {
    _invoicePageSize = size;
    await _repository.saveInvoicePageSize(size);
    notifyListeners();
  }

  Future<void> setMargins(double topBottom, double leftRight) async {
    _marginTB = topBottom;
    _marginLR = leftRight;
    await _repository.saveInvoiceMargins(topBottom, leftRight);
    notifyListeners();
  }

  Future<void> setShowHeader(bool value) async {
    _showHeader = value;
    await _repository.saveInvoiceShowHeader(value);
    notifyListeners();
  }

  Future<void> setShowQr(bool value) async {
    _showQr = value;
    await _repository.saveInvoiceShowQr(value);
    notifyListeners();
  }
}

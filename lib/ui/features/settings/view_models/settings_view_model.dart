import 'package:flutter/foundation.dart';
import '../../../../data/repositories/shop_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  final ShopRepository _repository;

  SettingsViewModel({required ShopRepository repository})
    : _repository = repository;

  List<String> _upiIds = [];
  String? _activeUpiId;
  bool _isLoading = false;

  // Getters
  List<String> get upiIds => _upiIds;
  String? get activeUpiId => _activeUpiId;
  bool get isLoading => _isLoading;

  // Load Settings from Local Database
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
    } catch (e) {
      if (kDebugMode) {
        print('Error loading settings: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Set active UPI key
  Future<void> selectActiveUpiId(String upiId) async {
    if (_upiIds.contains(upiId)) {
      _activeUpiId = upiId;
      await _repository.setActiveUpiId(upiId);
      notifyListeners();
    }
  }

  // Add new UPI ID
  Future<bool> addUpiId(String upiId) async {
    final cleaned = upiId.trim();
    if (cleaned.isEmpty || !cleaned.contains('@')) {
      return false; // Invalid UPI ID
    }

    if (_upiIds.contains(cleaned)) {
      return false; // Already exists
    }

    _upiIds.add(cleaned);
    await _repository.saveUpiIdsList(_upiIds);

    // If it is the only UPI ID, set it active immediately
    if (_activeUpiId == null) {
      _activeUpiId = cleaned;
      await _repository.setActiveUpiId(cleaned);
    }

    notifyListeners();
    return true;
  }

  // Delete UPI ID
  Future<void> deleteUpiId(String upiId) async {
    _upiIds.remove(upiId);
    await _repository.saveUpiIdsList(_upiIds);

    // Handle active UPI ID replacement
    if (_activeUpiId == upiId) {
      if (_upiIds.isNotEmpty) {
        _activeUpiId = _upiIds.first;
        await _repository.setActiveUpiId(_activeUpiId!);
      } else {
        _activeUpiId = null;
        // Delete active UPI key in repository
        await _repository.setActiveUpiId('');
      }
    }

    notifyListeners();
  }
}

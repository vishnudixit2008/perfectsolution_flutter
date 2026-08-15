import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../data/models/replacement.dart';
import '../../../../data/repositories/shop_repository.dart';

class ReplacementsViewModel extends ChangeNotifier {
  final ShopRepository _repository;
  StreamSubscription? _dataSubscription;

  ReplacementsViewModel({required ShopRepository repository})
    : _repository = repository {
    _dataSubscription = _repository.onTableDataChanged.listen((table) {
      if (table == 'replacements' || table == 'all') {
        loadReplacements();
      }
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  List<Replacement> _replacements = [];
  bool _isLoading = false;

  List<Replacement> get replacements => _replacements;
  bool get isLoading => _isLoading;

  Future<void> loadReplacements() async {
    _isLoading = true;
    notifyListeners();
    try {
      _replacements = _repository.getReplacements();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading replacements: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String getNextJobNo() {
    return _repository.getNextReplacementJobNo();
  }

  Future<void> saveReplacement(Replacement repl) async {
    await _repository.saveReplacement(repl);
    await loadReplacements();
  }

  Future<void> deleteReplacement(String jobNo) async {
    await _repository.deleteReplacement(jobNo);
    await loadReplacements();
  }
}

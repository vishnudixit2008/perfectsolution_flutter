import '../../../../data/services/supabase_sync_service.dart';
import 'package:flutter/foundation.dart';
import '../../../../data/models/replacement.dart';
import '../../../../data/repositories/shop_repository.dart';

class ReplacementsViewModel extends ChangeNotifier {
  final ShopRepository _repository;

  ReplacementsViewModel({required ShopRepository repository})
    : _repository = repository {
    SupabaseSyncService.instance.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (SupabaseSyncService.instance.status == SyncStatus.synced) {
      loadReplacements();
    }
  }

  @override
  void dispose() {
    SupabaseSyncService.instance.removeListener(_onSyncChanged);
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

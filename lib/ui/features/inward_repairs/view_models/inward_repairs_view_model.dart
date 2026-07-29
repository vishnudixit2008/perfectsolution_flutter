import '../../../../data/services/supabase_sync_service.dart';
import 'package:flutter/foundation.dart';
import '../../../../data/models/inward_repair.dart';
import '../../../../data/models/inward_estimate_item.dart';
import '../../../../data/repositories/shop_repository.dart';

class InwardRepairsViewModel extends ChangeNotifier {
  final ShopRepository _repository;

  InwardRepairsViewModel({required ShopRepository repository})
    : _repository = repository {
    SupabaseSyncService.instance.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (SupabaseSyncService.instance.status == SyncStatus.synced) {
      loadRepairs();
    }
  }

  @override
  void dispose() {
    SupabaseSyncService.instance.removeListener(_onSyncChanged);
    super.dispose();
  }

  List<InwardRepair> _repairs = [];
  bool _isLoading = false;

  List<InwardRepair> get repairs => _repairs;
  bool get isLoading => _isLoading;

  Future<void> loadRepairs() async {
    _isLoading = true;
    notifyListeners();
    try {
      _repairs = _repository.getInwardRepairs();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading inward repairs: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<InwardEstimateItem> getEstimateItems(int jobNo) {
    return _repository.getInwardEstimateItems(jobNo);
  }

  int getNextJobNo() {
    return _repository.getNextInwardJobNo();
  }

  Future<void> saveRepair(
    InwardRepair repair,
    List<InwardEstimateItem> items,
  ) async {
    await _repository.saveInwardRepair(repair, items);
    await loadRepairs();
  }

  Future<void> deleteRepair(int jobNo) async {
    await _repository.deleteInwardRepair(jobNo);
    await loadRepairs();
  }
}

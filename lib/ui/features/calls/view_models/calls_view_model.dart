import '../../../../data/services/supabase_sync_service.dart';
import 'package:flutter/foundation.dart';
import '../../../../data/models/call_model.dart';
import '../../../../data/repositories/shop_repository.dart';

class CallsViewModel extends ChangeNotifier {
  final ShopRepository _repository;

  CallsViewModel({required ShopRepository repository})
    : _repository = repository {
    SupabaseSyncService.instance.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (SupabaseSyncService.instance.status == SyncStatus.synced) {
      loadCalls();
    }
  }

  @override
  void dispose() {
    SupabaseSyncService.instance.removeListener(_onSyncChanged);
    super.dispose();
  }

  List<CallModel> _calls = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedStatus = 'All';
  String _selectedAssigned = 'All';

  List<CallModel> get calls => _calls;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String get selectedStatus => _selectedStatus;
  String get selectedAssigned => _selectedAssigned;

  List<String> get availableAssignedPersons {
    final set = <String>{'All', 'Unassigned'};
    for (final call in _calls) {
      if (call.assignedTo.trim().isNotEmpty &&
          call.assignedTo != 'N/A') {
        set.add(call.assignedTo.trim());
      }
    }
    return set.toList();
  }

  List<CallModel> get filteredCalls {
    return _calls.where((call) {
      final matchesSearch =
          call.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (call.mobileNo?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false) ||
          (call.query?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false) ||
          (call.address?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false);

      final matchesStatus =
          _selectedStatus == 'All' ||
          call.status.toLowerCase() == _selectedStatus.toLowerCase();

      bool matchesAssigned = true;
      if (_selectedAssigned == 'Unassigned') {
        matchesAssigned =
            call.assignedTo.trim().isEmpty ||
            call.assignedTo == 'N/A';
      } else if (_selectedAssigned != 'All') {
        matchesAssigned = call.assignedTo.trim() == _selectedAssigned;
      }

      return matchesSearch && matchesStatus && matchesAssigned;
    }).toList();
  }

  Map<String, List<CallModel>> get groupedFilteredCalls {
    final map = <String, List<CallModel>>{};
    for (final call in filteredCalls) {
      final key =
          (call.assignedTo.trim().isNotEmpty &&
              call.assignedTo != 'N/A')
          ? 'Assigned to: ${call.assignedTo.trim()}'
          : 'Unassigned';
      map.putIfAbsent(key, () => []).add(call);
    }
    return map;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedStatus(String status) {
    _selectedStatus = status;
    notifyListeners();
  }

  void setSelectedAssigned(String assigned) {
    _selectedAssigned = assigned;
    notifyListeners();
  }

  Future<void> loadCalls() async {
    _isLoading = true;
    notifyListeners();
    try {
      _calls = _repository.getCalls();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading calls: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  int getNextCallId() {
    return _repository.getNextCallId();
  }

  Future<void> saveCall(CallModel call) async {
    await _repository.saveCall(call);
    await loadCalls();
  }

  Future<void> deleteCall(int id) async {
    await _repository.deleteCall(id);
    await loadCalls();
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../data/models/call_model.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/user_permission_service.dart';

class CallsViewModel extends ChangeNotifier {
  final ShopRepository _repository;
  StreamSubscription? _dataSubscription;

  CallsViewModel({required ShopRepository repository})
    : _repository = repository {
    _dataSubscription = _repository.onTableDataChanged.listen((table) {
      if (table == 'calls' || table == 'all') {
        loadCalls();
      } else if (table == 'app_users') {
        loadCalls();
      }
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
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
    final Map<String, String> uniqueNamesByLower = {};
    uniqueNamesByLower['all'] = 'All';
    uniqueNamesByLower['unassigned'] = 'Unassigned';

    for (final call in _calls) {
      if (call.assignedTo.trim().isNotEmpty &&
          call.assignedTo.trim() != 'N/A') {
        final displayName = UserPermissionService.formatStaffName(call.assignedTo);
        if (displayName.isNotEmpty &&
            displayName.toLowerCase() != 'unassigned' &&
            !uniqueNamesByLower.containsKey(displayName.toLowerCase())) {
          uniqueNamesByLower[displayName.toLowerCase()] = displayName;
        }
      }
    }
    return uniqueNamesByLower.values.toList();
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
            call.assignedTo.trim() == 'N/A';
      } else if (_selectedAssigned != 'All') {
        final callStaff = UserPermissionService.formatStaffName(call.assignedTo);
        matchesAssigned =
            callStaff.toLowerCase() == _selectedAssigned.toLowerCase() ||
            call.assignedTo.trim().toLowerCase() == _selectedAssigned.toLowerCase();
      }

      return matchesSearch && matchesStatus && matchesAssigned;
    }).toList();
  }

  Map<String, List<CallModel>> get groupedFilteredCalls {
    final map = <String, List<CallModel>>{};
    for (final call in filteredCalls) {
      final key =
          (call.assignedTo.trim().isNotEmpty &&
              call.assignedTo.trim() != 'N/A')
          ? 'Assigned to: ${UserPermissionService.formatStaffName(call.assignedTo)}'
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

import 'package:flutter/foundation.dart';

class NavigationViewModel extends ChangeNotifier {
  static const int calls = 0;
  static const int inward = 1;
  static const int replacement = 2;
  static const int pricelist = 3;
  static const int sales = 4;
  static const int request = 5;
  static const int purchase = 6;
  static const int dealers = 7;
  static const int runner = 8;
  static const int settings = 9;

  int _currentIndex = calls; // Default to Calls tab

  // Pre-filled data to pass between modules
  Map<String, dynamic>? _pendingPrefillData;

  final Map<int, int> _tabRevisions = {};

  int get currentIndex => _currentIndex;
  Map<String, dynamic>? get pendingPrefillData => _pendingPrefillData;
  Map<int, int> get tabRevisions => Map.unmodifiable(_tabRevisions);

  int getTabRevision(int index) => _tabRevisions[index] ?? 0;

  void resetTab(int index) {
    _tabRevisions[index] = (_tabRevisions[index] ?? 0) + 1;
    notifyListeners();
  }

  void setIndex(int index, {Map<String, dynamic>? prefillData, bool resetView = false}) {
    final bool sameTab = _currentIndex == index;
    _currentIndex = index;
    _pendingPrefillData = prefillData;
    if (resetView || (sameTab && prefillData == null)) {
      _tabRevisions[index] = (_tabRevisions[index] ?? 0) + 1;
    }
    notifyListeners();
  }

  void clearPrefillData() {
    _pendingPrefillData = null;
  }

  /// Called after a manual cloud sync so all listening views can reload their data.
  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  void notifySync() {
    _lastSyncTime = DateTime.now();
    notifyListeners();
  }
}

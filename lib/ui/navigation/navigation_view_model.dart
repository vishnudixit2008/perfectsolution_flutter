import 'package:flutter/foundation.dart';

class NavigationViewModel extends ChangeNotifier {
  static const int calls = 0;
  static const int inward = 1;
  static const int replacement = 2;
  static const int pricelist = 3;
  static const int sales = 4;
  static const int request = 5;
  static const int purchase = 6;
  static const int settings = 7;

  int _currentIndex = calls; // Default to Calls tab

  // Pre-filled data to pass between modules
  Map<String, dynamic>? _pendingPrefillData;

  int get currentIndex => _currentIndex;
  Map<String, dynamic>? get pendingPrefillData => _pendingPrefillData;

  void setIndex(int index, {Map<String, dynamic>? prefillData}) {
    _currentIndex = index;
    _pendingPrefillData = prefillData;
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

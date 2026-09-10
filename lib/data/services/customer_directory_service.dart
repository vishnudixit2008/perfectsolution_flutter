import 'dart:async';
import '../models/customer_profile.dart';
import '../repositories/shop_repository.dart';

class CustomerDirectoryService {
  CustomerDirectoryService._();
  static final CustomerDirectoryService instance =
      CustomerDirectoryService._();

  ShopRepository? _repository;
  StreamSubscription? _tableSub;
  bool _isDirty = true;
  Map<String, CustomerProfile> _profilesByPhone = {};

  /// Initialize with ShopRepository and listen for data changes
  void init(ShopRepository repository) {
    _repository = repository;
    _tableSub?.cancel();
    _tableSub = ShopRepository.tableDataChangedStream.listen((table) {
      if ({
        'sales',
        'sale_items',
        'inward_repairs',
        'inward_estimate_items',
        'calls',
        'replacements',
        'requests',
      }.contains(table)) {
        _isDirty = true;
      }
    });
    _isDirty = true;
  }

  void dispose() {
    _tableSub?.cancel();
  }

  void invalidateCache() {
    _isDirty = true;
  }

  /// Normalizes phone numbers to standard 10 digits
  /// Handles '+91', leading '0', spaces, dashes, etc.
  static String? normalizePhone(String? input) {
    if (input == null) return null;
    final digitsOnly = input.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length == 10) {
      return digitsOnly;
    }
    if (digitsOnly.length == 11 && digitsOnly.startsWith('0')) {
      return digitsOnly.substring(1);
    }
    if (digitsOnly.length == 12 && digitsOnly.startsWith('91')) {
      return digitsOnly.substring(2);
    }
    if (digitsOnly.length > 10) {
      return digitsOnly.substring(digitsOnly.length - 10);
    }
    return digitsOnly.isNotEmpty ? digitsOnly : null;
  }

  /// Formats 10-digit number as '+91 XXXXX XXXXX' or readable format
  static String formatDisplayPhone(String phone) {
    final clean = normalizePhone(phone) ?? phone;
    if (clean.length == 10) {
      return '${clean.substring(0, 5)} ${clean.substring(5)}';
    }
    return phone;
  }

  void _ensureIndexed() {
    if (!_isDirty && _profilesByPhone.isNotEmpty) return;
    if (_repository == null) return;

    final repo = _repository!;
    final Map<String, List<CustomerTimelineEvent>> eventsMap = {};
    final Map<String, List<String>> namesMap = {};
    final Map<String, String> addressMap = {};

    void addEvent({
      required String? rawPhone,
      required String? rawName,
      String? address,
      required CustomerTimelineEvent event,
    }) {
      final phone = normalizePhone(rawPhone);
      if (phone == null || phone.length < 10) return;

      eventsMap.putIfAbsent(phone, () => []).add(event);

      final trimmedName = rawName?.trim() ?? '';
      if (trimmedName.isNotEmpty &&
          trimmedName.toLowerCase() != 'walk-in customer') {
        namesMap.putIfAbsent(phone, () => []).add(trimmedName);
      }

      final trimmedAddr = address?.trim() ?? '';
      if (trimmedAddr.isNotEmpty && !addressMap.containsKey(phone)) {
        addressMap[phone] = trimmedAddr;
      }
    }

    // 1. Inward Repairs
    final repairs = repo.getInwardRepairs();
    for (final repair in repairs) {
      final estimateItems = repo.getInwardEstimateItems(repair.jobNo);
      double estimateTotal = 0.0;
      for (final it in estimateItems) {
        estimateTotal += it.totalAmount;
      }
      final double netAmount = estimateTotal > 0
          ? (estimateTotal - repair.discount).clamp(0.0, double.infinity)
          : 0.0;

      addEvent(
        rawPhone: repair.mobileNo,
        rawName: repair.name,
        event: CustomerTimelineEvent(
          type: CustomerEventType.inwardRepair,
          id: '#${repair.jobNo}',
          timestamp: repair.date,
          title: 'Inward Repair #${repair.jobNo}',
          subtitle:
              '${repair.devices}${repair.query != null && repair.query!.isNotEmpty ? " • ${repair.query!}" : ""}',
          status: repair.status,
          amount: netAmount > 0 ? netAmount : null,
          rawObject: repair,
        ),
      );
    }

    // 2. Sales
    final sales = repo.getSales();
    for (final sale in sales) {
      addEvent(
        rawPhone: sale.customerNumber,
        rawName: sale.customerName,
        event: CustomerTimelineEvent(
          type: CustomerEventType.sale,
          id: 'Inv #${sale.invoiceNo}',
          timestamp: sale.saleDate,
          title: 'Sale Invoice #${sale.invoiceNo}',
          subtitle: '${sale.paymentMode} • ${sale.orderStatus}',
          status: sale.orderStatus,
          amount: sale.totalAmount,
          rawObject: sale,
        ),
      );
    }

    // 3. Calls
    final calls = repo.getCalls();
    for (final call in calls) {
      addEvent(
        rawPhone: call.mobileNo,
        rawName: call.name,
        address: call.address,
        event: CustomerTimelineEvent(
          type: CustomerEventType.call,
          id: 'Call #${call.id}',
          timestamp: call.date,
          title: 'Customer Call #${call.id}',
          subtitle: call.query ?? 'Customer inquiry',
          status: call.status,
          address: call.address,
          rawObject: call,
        ),
      );
    }

    // 4. Replacements
    final replacements = repo.getReplacements();
    for (final repl in replacements) {
      addEvent(
        rawPhone: repl.mobileNo,
        rawName: repl.name,
        event: CustomerTimelineEvent(
          type: CustomerEventType.replacement,
          id: 'Job ${repl.jobNo}',
          timestamp: repl.date,
          title: 'Replacement ${repl.jobNo}',
          subtitle: repl.item,
          status: repl.status,
          rawObject: repl,
        ),
      );
    }

    // 5. Request Orders
    final requests = repo.getRequestOrders();
    for (final req in requests) {
      addEvent(
        rawPhone: req.mobileNo,
        rawName: req.customerName,
        event: CustomerTimelineEvent(
          type: CustomerEventType.request,
          id: 'Req ${req.id.length > 6 ? req.id.substring(0, 6) : req.id}',
          timestamp: req.date,
          title: 'Request Order',
          subtitle: req.item,
          status: req.status,
          amount: req.totalAmount > 0 ? req.totalAmount : null,
          rawObject: req,
        ),
      );
    }

    // Build final CustomerProfiles
    final Map<String, CustomerProfile> newProfiles = {};
    for (final entry in eventsMap.entries) {
      final phone = entry.key;
      final events = entry.value;
      // Sort newest first
      events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final namesList = namesMap[phone] ?? [];
      final displayName = namesList.isNotEmpty
          ? namesList.first
          : 'Customer $phone';

      newProfiles[phone] = CustomerProfile(
        canonicalPhone: phone,
        displayName: displayName,
        allNames: namesList.toSet(),
        lastAddress: addressMap[phone],
        events: events,
      );
    }

    _profilesByPhone = newProfiles;
    _isDirty = false;
  }

  /// Direct lookup by phone (accepts raw formatted or unformatted)
  CustomerProfile? lookupCustomer(String? rawPhone) {
    if (rawPhone == null || rawPhone.trim().isEmpty) return null;
    final phone = normalizePhone(rawPhone);
    if (phone == null || phone.length < 10) return null;

    _ensureIndexed();
    return _profilesByPhone[phone];
  }

  /// Fuzzy search by phone or name for autocomplete/search dialogs
  List<CustomerProfile> searchCustomers(String query) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    _ensureIndexed();
    final digitsQuery = cleanQuery.replaceAll(RegExp(r'\D'), '');

    final results = <CustomerProfile>[];
    for (final profile in _profilesByPhone.values) {
      if (digitsQuery.isNotEmpty &&
          profile.canonicalPhone.contains(digitsQuery)) {
        results.add(profile);
      } else if (profile.displayName.toLowerCase().contains(cleanQuery) ||
          profile.allNames.any((n) => n.toLowerCase().contains(cleanQuery))) {
        results.add(profile);
      }
      if (results.length >= 20) break;
    }

    return results;
  }
}

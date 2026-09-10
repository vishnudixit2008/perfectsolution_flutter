enum CustomerEventType {
  inwardRepair,
  sale,
  call,
  replacement,
  request,
}

class CustomerTimelineEvent {
  final CustomerEventType type;
  final String id; // Job No, Invoice No, Call ID, etc.
  final DateTime timestamp;
  final String title;
  final String subtitle;
  final String status;
  final double? amount;
  final String? address;
  final Object rawObject;

  CustomerTimelineEvent({
    required this.type,
    required this.id,
    required this.timestamp,
    required this.title,
    required this.subtitle,
    required this.status,
    this.amount,
    this.address,
    required this.rawObject,
  });
}

class CustomerProfile {
  final String canonicalPhone;
  final String displayName;
  final Set<String> allNames;
  final String? lastAddress;
  final List<CustomerTimelineEvent> events;

  CustomerProfile({
    required this.canonicalPhone,
    required this.displayName,
    required this.allNames,
    this.lastAddress,
    required this.events,
  });

  int get visitCount => events.length;

  double get totalSpent {
    double total = 0.0;
    for (final e in events) {
      if (e.amount != null && e.amount! > 0) {
        total += e.amount!;
      }
    }
    return total;
  }

  DateTime? get lastVisitDate =>
      events.isNotEmpty ? events.first.timestamp : null;
  DateTime? get firstVisitDate =>
      events.isNotEmpty ? events.last.timestamp : null;

  int get inwardCount =>
      events.where((e) => e.type == CustomerEventType.inwardRepair).length;
  int get salesCount =>
      events.where((e) => e.type == CustomerEventType.sale).length;
  int get callsCount =>
      events.where((e) => e.type == CustomerEventType.call).length;
  int get replacementsCount =>
      events.where((e) => e.type == CustomerEventType.replacement).length;
  int get requestsCount =>
      events.where((e) => e.type == CustomerEventType.request).length;
}

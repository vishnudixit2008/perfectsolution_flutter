import '../../ui/shared/photo_attachment_widget.dart';

class RequestOrder {
  static const String statusInquirySent = 'Inquiry Sent';
  static const String statusCustomerApproved = 'Customer Approved';
  static const String statusRunnerAssigned = 'Assigned to runner';
  static const String statusCollected = 'Collected';
  static const String statusCompleted = 'Complete';

  static const List<String> allStatuses = [
    'Pending',
    'Assigned to runner',
    'Received',
    'HOLD',
    'Complete',
  ];

  static String normalizeStatus(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Pending';
    final s = raw.trim().toLowerCase();
    if (s == 'complete' || s == 'completed' || s == 'done') {
      return 'Complete';
    }
    if (s == 'assigned to runner' || s == 'runner assigned' || s == 'runner_assigned') {
      return 'Assigned to runner';
    }
    if (s == 'pending' || s == 'inquiry' || s == 'inquiry sent' || s == 'inquiry_sent') {
      return 'Pending';
    }
    if (s == 'received' || s == 'collected' || s == 'picked up' || s == 'picked_up') {
      return 'Received';
    }
    if (s == 'hold') {
      return 'HOLD';
    }
    return raw.trim();
  }

  final String id; // Alphanumeric ID (e.g. UUID)
  final DateTime date;
  final String customerName;
  final String? mobileNo;
  final String item;
  final double advance;
  final double totalAmount;
  final String? dealerName;
  final String status;
  final String? estimate;
  final String? photo;
  final DateTime updatedAt;

  // Market Runner & Sourcing Fields
  final String? assignedRunnerId;
  final String? assignedRunnerName;
  final String? targetBuilding;
  final String? targetShopNo;
  final double? actualPurchaseCost;
  final String? billPhoto;
  final DateTime? collectedAt;

  RequestOrder({
    required this.id,
    required this.date,
    required this.customerName,
    this.mobileNo,
    required this.item,
    this.advance = 0.0,
    this.totalAmount = 0.0,
    this.dealerName,
    String status = statusInquirySent,
    this.estimate,
    this.photo,
    this.assignedRunnerId,
    this.assignedRunnerName,
    this.targetBuilding,
    this.targetShopNo,
    this.actualPurchaseCost,
    this.billPhoto,
    this.collectedAt,
    DateTime? updatedAt,
  })  : status = normalizeStatus(status),
        updatedAt = updatedAt ?? DateTime.now();

  List<String> get photoList => PhotoAttachmentWidget.parsePhotoUrls(photo);
  List<String> get billPhotoList => PhotoAttachmentWidget.parsePhotoUrls(billPhoto);

  factory RequestOrder.fromJson(Map<String, dynamic> json) {
    return RequestOrder(
      id: json['id']?.toString() ?? '',
      date: json['date'] != null
          ? DateTime.tryParse(json['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      customerName: json['customer_name'] ?? json['coustmer_name'] ?? '',
      mobileNo: json['mobile_no']?.toString(),
      item: json['item'] ?? '',
      advance: json['advance'] is num
          ? (json['advance'] as num).toDouble()
          : double.tryParse(json['advance']?.toString() ?? '') ?? 0.0,
      totalAmount: json['total_amount'] is num
          ? (json['total_amount'] as num).toDouble()
          : double.tryParse(json['total_amount']?.toString() ?? '') ?? 0.0,
      dealerName: json['dealer_name']?.toString(),
      status: normalizeStatus(json['status']?.toString()),
      estimate: json['estimate']?.toString(),
      photo: json['photo']?.toString(),
      assignedRunnerId: json['assigned_runner_id']?.toString(),
      assignedRunnerName: json['assigned_runner_name']?.toString(),
      targetBuilding: json['target_building']?.toString(),
      targetShopNo: json['target_shop_no']?.toString(),
      actualPurchaseCost: json['actual_purchase_cost'] is num
          ? (json['actual_purchase_cost'] as num).toDouble()
          : double.tryParse(json['actual_purchase_cost']?.toString() ?? ''),
      billPhoto: json['bill_photo']?.toString(),
      collectedAt: json['collected_at'] != null
          ? DateTime.tryParse(json['collected_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'customer_name': customerName,
      'mobile_no': mobileNo,
      'item': item,
      'advance': advance,
      'total_amount': totalAmount,
      'dealer_name': dealerName,
      'status': status,
      'estimate': estimate,
      'photo': photo,
      'assigned_runner_id': assignedRunnerId,
      'assigned_runner_name': assignedRunnerName,
      'target_building': targetBuilding,
      'target_shop_no': targetShopNo,
      'actual_purchase_cost': actualPurchaseCost,
      'bill_photo': billPhoto,
      'collected_at': collectedAt?.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  RequestOrder copyWith({
    String? id,
    DateTime? date,
    String? customerName,
    String? mobileNo,
    String? item,
    double? advance,
    double? totalAmount,
    String? dealerName,
    String? status,
    String? estimate,
    String? photo,
    String? assignedRunnerId,
    String? assignedRunnerName,
    String? targetBuilding,
    String? targetShopNo,
    double? actualPurchaseCost,
    String? billPhoto,
    DateTime? collectedAt,
    DateTime? updatedAt,
  }) {
    return RequestOrder(
      id: id ?? this.id,
      date: date ?? this.date,
      customerName: customerName ?? this.customerName,
      mobileNo: mobileNo ?? this.mobileNo,
      item: item ?? this.item,
      advance: advance ?? this.advance,
      totalAmount: totalAmount ?? this.totalAmount,
      dealerName: dealerName ?? this.dealerName,
      status: status ?? this.status,
      estimate: estimate ?? this.estimate,
      photo: photo ?? this.photo,
      assignedRunnerId: assignedRunnerId ?? this.assignedRunnerId,
      assignedRunnerName: assignedRunnerName ?? this.assignedRunnerName,
      targetBuilding: targetBuilding ?? this.targetBuilding,
      targetShopNo: targetShopNo ?? this.targetShopNo,
      actualPurchaseCost: actualPurchaseCost ?? this.actualPurchaseCost,
      billPhoto: billPhoto ?? this.billPhoto,
      collectedAt: collectedAt ?? this.collectedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

import '../../ui/shared/photo_attachment_widget.dart';

class RequestOrder {
  final String id; // Alphanumeric ID (e.g. UUID)
  final DateTime date;
  final String customerName;
  final String? mobileNo;
  final String item;
  final double advance;
  final double totalAmount;
  final String? dealerName;
  final String status; // Pending, Received, Complete, etc.
  final String? estimate;
  final String? photo;

  RequestOrder({
    required this.id,
    required this.date,
    required this.customerName,
    this.mobileNo,
    required this.item,
    this.advance = 0.0,
    this.totalAmount = 0.0,
    this.dealerName,
    this.status = 'Pending',
    this.estimate,
    this.photo,
  });

  List<String> get photoList => PhotoAttachmentWidget.parsePhotoUrls(photo);

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
      status: json['status'] ?? 'Pending',
      estimate: json['estimate']?.toString(),
      photo: json['photo']?.toString(),
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
    );
  }
}

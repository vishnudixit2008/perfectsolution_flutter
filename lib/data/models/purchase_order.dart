import '../../ui/shared/photo_attachment_widget.dart';

class PurchaseOrder {
  final String id; // Alphanumeric stock-in ID (e.g. UUID)
  final DateTime date;
  final String purchasedFrom; // Vendor / Dealer name
  final double totalAmount;
  final String status; // PENDING, CONFIRMED
  final String? notes;
  final String? photo;
  final DateTime updatedAt;

  PurchaseOrder({
    required this.id,
    required this.date,
    required this.purchasedFrom,
    this.totalAmount = 0.0,
    this.status = 'PENDING',
    this.notes,
    this.photo,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  List<String> get photoList => PhotoAttachmentWidget.parsePhotoUrls(photo);

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      id: json['id']?.toString() ?? '',
      date: json['date'] != null
          ? DateTime.tryParse(json['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      purchasedFrom: json['purchased_from'] ?? '',
      totalAmount: json['total_amount'] is num
          ? (json['total_amount'] as num).toDouble()
          : double.tryParse(json['total_amount']?.toString() ?? '') ?? 0.0,
      status: json['status'] ?? 'PENDING',
      notes: json['notes']?.toString(),
      photo: json['photo']?.toString(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'purchased_from': purchasedFrom,
      'total_amount': totalAmount,
      'status': status,
      'notes': notes,
      'photo': photo,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PurchaseOrder copyWith({
    String? id,
    DateTime? date,
    String? purchasedFrom,
    double? totalAmount,
    String? status,
    String? notes,
    String? photo,
    DateTime? updatedAt,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      date: date ?? this.date,
      purchasedFrom: purchasedFrom ?? this.purchasedFrom,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      photo: photo ?? this.photo,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

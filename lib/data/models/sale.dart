import '../../ui/shared/photo_attachment_widget.dart';

class Sale {
  final int invoiceNo;
  final DateTime saleDate;
  final String? customerName;
  final String? customerNumber;
  final String paymentMode; // 'Cash', 'UPI', etc.
  final double advance;
  final double discount;
  final double totalAmount;
  final String? invoicePdf;
  final String orderStatus; // 'PENDING' or 'Confirmed'
  final String? photo;
  final DateTime updatedAt;

  Sale({
    required this.invoiceNo,
    required this.saleDate,
    this.customerName,
    this.customerNumber,
    required this.paymentMode,
    this.advance = 0.0,
    this.discount = 0.0,
    required this.totalAmount,
    this.invoicePdf,
    this.orderStatus = 'PENDING',
    this.photo,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  List<String> get photoList => PhotoAttachmentWidget.parsePhotoUrls(photo);

  /// Remaining total amount after deducting advance & discount
  double get dueAmount => totalAmount;

  Sale copyWith({
    int? invoiceNo,
    DateTime? saleDate,
    String? customerName,
    String? customerNumber,
    String? paymentMode,
    double? advance,
    double? discount,
    double? totalAmount,
    String? invoicePdf,
    String? orderStatus,
    String? photo,
    DateTime? updatedAt,
  }) {
    return Sale(
      invoiceNo: invoiceNo ?? this.invoiceNo,
      saleDate: saleDate ?? this.saleDate,
      customerName: customerName ?? this.customerName,
      customerNumber: customerNumber ?? this.customerNumber,
      paymentMode: paymentMode ?? this.paymentMode,
      advance: advance ?? this.advance,
      discount: discount ?? this.discount,
      totalAmount: totalAmount ?? this.totalAmount,
      invoicePdf: invoicePdf ?? this.invoicePdf,
      orderStatus: orderStatus ?? this.orderStatus,
      photo: photo ?? this.photo,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      invoiceNo: json['invoice_no'] is int
          ? json['invoice_no']
          : int.parse(json['invoice_no'].toString()),
      saleDate: json['sale_date'] != null
          ? DateTime.parse(json['sale_date'])
          : DateTime.now(),
      customerName: json['customer_name'],
      customerNumber: json['customer_number'],
      paymentMode: json['payment_mode'] ?? 'Cash',
      advance: json['advance'] is num
          ? (json['advance'] as num).toDouble()
          : double.parse(json['advance']?.toString() ?? '0.0'),
      discount: json['discount'] is num
          ? (json['discount'] as num).toDouble()
          : double.parse(json['discount']?.toString() ?? '0.0'),
      totalAmount: json['total_amount'] is num
          ? (json['total_amount'] as num).toDouble()
          : double.parse(json['total_amount']?.toString() ?? '0.0'),
      invoicePdf: json['invoice_pdf'],
      orderStatus: json['order_status'] ?? 'PENDING',
      photo: json['photo']?.toString(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'invoice_no': invoiceNo,
      'sale_date': saleDate.toIso8601String(),
      'customer_name': customerName,
      'customer_number': customerNumber,
      'payment_mode': paymentMode,
      'advance': advance,
      'discount': discount,
      'total_amount': totalAmount,
      'invoice_pdf': invoicePdf,
      'order_status': orderStatus,
      'photo': photo,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

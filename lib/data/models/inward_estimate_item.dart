class InwardEstimateItem {
  final String lineId;
  final int jobNo;
  final String lineType; // Product, Service, Custom
  final int? itemId; // References PricelistItem ID if Product
  final String? itemName;
  final String? itemDescription;
  final int quantity;
  final double unitPrice;
  final double servicePrice;
  final double totalAmount;
  final String? notes;

  InwardEstimateItem({
    required this.lineId,
    required this.jobNo,
    required this.lineType,
    this.itemId,
    this.itemName,
    this.itemDescription,
    this.quantity = 1,
    this.unitPrice = 0.0,
    this.servicePrice = 0.0,
    required this.totalAmount,
    this.notes,
  });

  factory InwardEstimateItem.fromJson(Map<String, dynamic> json) {
    return InwardEstimateItem(
      lineId: json['line_id']?.toString() ?? json['id']?.toString() ?? '',
      jobNo: json['job_no'] is int
          ? json['job_no']
          : int.tryParse(json['job_no']?.toString() ?? '') ?? 0,
      lineType: json['line_type'] ?? 'Product',
      itemId: json['item_id'] is int
          ? json['item_id']
          : int.tryParse(json['item_id']?.toString() ?? ''),
      itemName: json['item_name']?.toString(),
      itemDescription: json['item_description']?.toString(),
      quantity: json['quantity'] is int
          ? json['quantity']
          : int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      unitPrice: json['unit_price'] is num
          ? (json['unit_price'] as num).toDouble()
          : double.tryParse(json['unit_price']?.toString() ?? '') ?? 0.0,
      servicePrice: json['service_price'] is num
          ? (json['service_price'] as num).toDouble()
          : double.tryParse(json['service_price']?.toString() ?? '') ?? 0.0,
      totalAmount: json['total_amount'] is num
          ? (json['total_amount'] as num).toDouble()
          : (json['amount'] is num
                ? (json['amount'] as num).toDouble()
                : double.tryParse(
                        json['total_amount']?.toString() ??
                            json['amount']?.toString() ??
                            '',
                      ) ??
                      0.0),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'line_id': lineId,
      'job_no': jobNo,
      'line_type': lineType,
      'item_id': itemId,
      'item_name': itemName,
      'item_description': itemDescription,
      'quantity': quantity,
      'unit_price': unitPrice,
      'service_price': servicePrice,
      'total_amount': totalAmount,
      'notes': notes,
    };
  }
}

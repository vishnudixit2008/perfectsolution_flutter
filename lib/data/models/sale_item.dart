class SaleItem {
  final String id; // Custom hash or ID
  final int invoiceNo;
  final String lineType; // 'Product' or 'Service'
  final int? itemId; // Refers to PricelistItem id
  final String? itemDescription; // Display name / custom description
  final int quantity;
  final double itemPrice;
  final double? customPrice; // Override price
  final String? serviceName;
  final double? servicePrice;
  final double totalAmount;
  final String? notes;

  SaleItem({
    required this.id,
    required this.invoiceNo,
    required this.lineType,
    this.itemId,
    this.itemDescription,
    required this.quantity,
    required this.itemPrice,
    this.customPrice,
    this.serviceName,
    this.servicePrice,
    required this.totalAmount,
    this.notes,
  });

  // Get active price (returns custom price override if set, else base price)
  double get activePrice => customPrice ?? itemPrice;

  SaleItem copyWith({
    String? id,
    int? invoiceNo,
    String? lineType,
    int? itemId,
    String? itemDescription,
    int? quantity,
    double? itemPrice,
    double? customPrice,
    String? serviceName,
    double? servicePrice,
    double? totalAmount,
    String? notes,
  }) {
    return SaleItem(
      id: id ?? this.id,
      invoiceNo: invoiceNo ?? this.invoiceNo,
      lineType: lineType ?? this.lineType,
      itemId: itemId ?? this.itemId,
      itemDescription: itemDescription ?? this.itemDescription,
      quantity: quantity ?? this.quantity,
      itemPrice: itemPrice ?? this.itemPrice,
      customPrice: customPrice ?? this.customPrice,
      serviceName: serviceName ?? this.serviceName,
      servicePrice: servicePrice ?? this.servicePrice,
      totalAmount: totalAmount ?? this.totalAmount,
      notes: notes ?? this.notes,
    );
  }

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    final String rawId =
        json['id']?.toString() ?? json['line_id']?.toString() ?? '';
    final String parsedId = rawId.isNotEmpty
        ? rawId
        : 'item_${DateTime.now().microsecondsSinceEpoch}_${json['item_id'] ?? json['item_description'] ?? 'sale'}';
    final int parsedInvoiceNo = json['invoice_no'] is int
        ? json['invoice_no']
        : int.tryParse(json['invoice_no']?.toString() ?? '') ?? 0;
    final String parsedLineType = json['line_type']?.toString() ?? 'Product';
    final int? parsedItemId = json['item_id'] != null
        ? (json['item_id'] is int
              ? json['item_id']
              : int.tryParse(json['item_id'].toString()))
        : null;
    final String? parsedDesc =
        json['item_description']?.toString() ?? json['item_name']?.toString();
    final int parsedQty = json['quantity'] is int
        ? json['quantity']
        : int.tryParse(json['quantity']?.toString() ?? '') ?? 1;
    final double parsedItemPrice = json['item_price'] is num
        ? (json['item_price'] as num).toDouble()
        : (json['unit_price'] is num
              ? (json['unit_price'] as num).toDouble()
              : double.tryParse(
                      json['item_price']?.toString() ??
                          json['unit_price']?.toString() ??
                          '',
                    ) ??
                    0.0);
    final double? parsedCustomPrice = json['custom_price'] != null
        ? (json['custom_price'] is num
              ? (json['custom_price'] as num).toDouble()
              : double.tryParse(json['custom_price'].toString()))
        : null;
    final String? parsedServiceName = json['service_name']?.toString();
    final double? parsedServicePrice = json['service_price'] != null
        ? (json['service_price'] is num
              ? (json['service_price'] as num).toDouble()
              : double.tryParse(json['service_price'].toString()))
        : null;
    final double parsedTotal = json['total_amount'] is num
        ? (json['total_amount'] as num).toDouble()
        : double.tryParse(json['total_amount']?.toString() ?? '') ?? 0.0;
    final String? parsedNotes = json['notes']?.toString();

    return SaleItem(
      id: parsedId,
      invoiceNo: parsedInvoiceNo,
      lineType: parsedLineType,
      itemId: parsedItemId,
      itemDescription: parsedDesc,
      quantity: parsedQty,
      itemPrice: parsedItemPrice,
      customPrice: parsedCustomPrice,
      serviceName: parsedServiceName,
      servicePrice: parsedServicePrice,
      totalAmount: parsedTotal,
      notes: parsedNotes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'line_id': id,
      'invoice_no': invoiceNo,
      'line_type': lineType,
      'item_id': itemId,
      'item_description': itemDescription,
      'item_name': itemDescription ?? serviceName ?? '',
      'quantity': quantity,
      'item_price': itemPrice,
      'unit_price': activePrice,
      'custom_price': customPrice,
      'service_name': serviceName,
      'service_price': servicePrice,
      'total_amount': totalAmount,
      'notes': notes,
    };
  }
}

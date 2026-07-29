class PurchaseOrderItem {
  final String lineId;
  final String purchaseId; // References PurchaseOrder ID
  final int? itemId; // References PricelistItem ID if not custom
  final String? itemName;
  final String? customItemName;
  final int quantity;
  final double unitPrice;
  final double amount;

  PurchaseOrderItem({
    required this.lineId,
    required this.purchaseId,
    this.itemId,
    this.itemName,
    this.customItemName,
    this.quantity = 1,
    this.unitPrice = 0.0,
    required this.amount,
  });

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      lineId: json['line_id']?.toString() ?? json['id']?.toString() ?? '',
      purchaseId: json['purchase_id']?.toString() ?? '',
      itemId: json['item_id'] is int
          ? json['item_id']
          : int.tryParse(json['item_id']?.toString() ?? ''),
      itemName: json['item_name']?.toString(),
      customItemName: json['custom_item_name']?.toString(),
      quantity: json['quantity'] is int
          ? json['quantity']
          : int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      unitPrice: json['unit_price'] is num
          ? (json['unit_price'] as num).toDouble()
          : double.tryParse(json['unit_price']?.toString() ?? '') ?? 0.0,
      amount: json['amount'] is num
          ? (json['amount'] as num).toDouble()
          : (json['total_amount'] is num
                ? (json['total_amount'] as num).toDouble()
                : double.tryParse(
                        json['amount']?.toString() ??
                            json['total_amount']?.toString() ??
                            '',
                      ) ??
                      0.0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'line_id': lineId,
      'id': lineId,
      'purchase_id': purchaseId,
      'item_id': itemId,
      'item_name': itemName,
      'custom_item_name': customItemName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'amount': amount,
      'total_amount': amount,
    };
  }

  PurchaseOrderItem copyWith({
    String? lineId,
    String? purchaseId,
    int? itemId,
    String? itemName,
    String? customItemName,
    int? quantity,
    double? unitPrice,
    double? amount,
  }) {
    return PurchaseOrderItem(
      lineId: lineId ?? this.lineId,
      purchaseId: purchaseId ?? this.purchaseId,
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      customItemName: customItemName ?? this.customItemName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      amount: amount ?? this.amount,
    );
  }
}

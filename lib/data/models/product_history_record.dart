import 'sale.dart';
import 'sale_item.dart';
import 'purchase_order.dart';
import 'purchase_order_item.dart';

enum ProductHistoryType { sale, purchase }

class ProductHistoryRecord {
  final ProductHistoryType type;
  final DateTime date;
  final String referenceNo; // Invoice No e.g. "#1016" or Purchase ID e.g. "PO-001"
  final String partyName; // Customer Name or Vendor Name
  final int quantity;
  final double unitPrice;
  final double totalAmount;
  final String status; // e.g. PENDING, CONFIRMED
  final Sale? sale;
  final List<SaleItem>? saleItems;
  final PurchaseOrder? purchase;
  final List<PurchaseOrderItem>? purchaseItems;

  ProductHistoryRecord({
    required this.type,
    required this.date,
    required this.referenceNo,
    required this.partyName,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.status,
    this.sale,
    this.saleItems,
    this.purchase,
    this.purchaseItems,
  });

  bool get isSale => type == ProductHistoryType.sale;
  bool get isPurchase => type == ProductHistoryType.purchase;
}

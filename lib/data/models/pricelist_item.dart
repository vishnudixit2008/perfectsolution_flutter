import '../../ui/shared/photo_attachment_widget.dart';

class PricelistItem {
  final int id;
  final String itemName;
  final String? itemDescription;
  final double price;
  final int stockQty;
  final int openingStock;
  final String? category;
  final String? photo;

  PricelistItem({
    required this.id,
    required this.itemName,
    this.itemDescription,
    required this.price,
    this.stockQty = 0,
    this.openingStock = 0,
    this.category,
    this.photo,
  });

  List<String> get photoList => PhotoAttachmentWidget.parsePhotoUrls(photo);

  PricelistItem copyWith({
    int? id,
    String? itemName,
    String? itemDescription,
    double? price,
    int? stockQty,
    int? openingStock,
    String? category,
    String? photo,
  }) {
    return PricelistItem(
      id: id ?? this.id,
      itemName: itemName ?? this.itemName,
      itemDescription: itemDescription ?? this.itemDescription,
      price: price ?? this.price,
      stockQty: stockQty ?? this.stockQty,
      openingStock: openingStock ?? this.openingStock,
      category: category ?? this.category,
      photo: photo ?? this.photo,
    );
  }

  factory PricelistItem.fromJson(Map<String, dynamic> json) {
    return PricelistItem(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      itemName: json['item_name'] ?? '',
      itemDescription: json['item_description'],
      price: json['price'] is num
          ? (json['price'] as num).toDouble()
          : double.tryParse(json['price']?.toString() ?? '') ?? 0.0,
      stockQty: json['stock_qty'] is int
          ? json['stock_qty']
          : int.tryParse(json['stock_qty']?.toString() ?? '') ?? 0,
      openingStock: json['opening_stock'] is int
          ? json['opening_stock']
          : int.tryParse(json['opening_stock']?.toString() ?? '') ?? 0,
      category: json['category'],
      photo: json['photo']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'item_name': itemName,
      'item_description': itemDescription,
      'price': price,
      'stock_qty': stockQty,
      'opening_stock': openingStock,
      'category': category,
      'photo': photo,
    };
  }
}

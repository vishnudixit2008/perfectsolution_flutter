class Dealer {
  final String id;
  final String name;
  final String? contactPerson;
  final String? mobileNo;
  final String? alternateMobile;
  final String? buildingName;
  final String? shopNo;
  final String address;
  final String city;
  final String? category;
  final String? products;
  final String? googleMapsUrl;
  final String? notes;
  final double rating;
  final DateTime updatedAt;

  Dealer({
    required this.id,
    required this.name,
    this.contactPerson,
    this.mobileNo,
    this.alternateMobile,
    this.buildingName,
    this.shopNo,
    required this.address,
    this.city = 'New Delhi',
    this.category,
    this.products,
    this.googleMapsUrl,
    this.notes,
    this.rating = 5.0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Normalized list of keywords extracted from products, category, notes, and name
  List<String> get productKeywords {
    final tokens = <String>{};
    void addTokens(String? text) {
      if (text == null || text.trim().isEmpty) return;
      final clean = text.toLowerCase().replaceAll(RegExp(r'[,/|;•\-_()]'), ' ');
      for (final word in clean.split(RegExp(r'\s+'))) {
        if (word.length >= 2) tokens.add(word);
      }
    }

    addTokens(products);
    addTokens(category);
    addTokens(notes);
    addTokens(name);
    return tokens.toList();
  }

  factory Dealer.fromJson(Map<String, dynamic> json) {
    return Dealer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      contactPerson: json['contact_person']?.toString(),
      mobileNo: json['mobile_no']?.toString(),
      alternateMobile: json['alternate_mobile']?.toString(),
      buildingName: json['building_name']?.toString(),
      shopNo: json['shop_no']?.toString(),
      address: json['address']?.toString() ?? '',
      city: json['city']?.toString() ?? 'New Delhi',
      category: json['category']?.toString(),
      products: json['products']?.toString(),
      googleMapsUrl: json['google_maps_url']?.toString(),
      notes: json['notes']?.toString(),
      rating: json['rating'] is num
          ? (json['rating'] as num).toDouble()
          : double.tryParse(json['rating']?.toString() ?? '') ?? 5.0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'contact_person': contactPerson,
      'mobile_no': mobileNo,
      'alternate_mobile': alternateMobile,
      'building_name': buildingName,
      'shop_no': shopNo,
      'address': address,
      'city': city,
      'category': category,
      'products': products,
      'google_maps_url': googleMapsUrl,
      'notes': notes,
      'rating': rating,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Dealer copyWith({
    String? id,
    String? name,
    String? contactPerson,
    String? mobileNo,
    String? alternateMobile,
    String? buildingName,
    String? shopNo,
    String? address,
    String? city,
    String? category,
    String? products,
    String? googleMapsUrl,
    String? notes,
    double? rating,
    DateTime? updatedAt,
  }) {
    return Dealer(
      id: id ?? this.id,
      name: name ?? this.name,
      contactPerson: contactPerson ?? this.contactPerson,
      mobileNo: mobileNo ?? this.mobileNo,
      alternateMobile: alternateMobile ?? this.alternateMobile,
      buildingName: buildingName ?? this.buildingName,
      shopNo: shopNo ?? this.shopNo,
      address: address ?? this.address,
      city: city ?? this.city,
      category: category ?? this.category,
      products: products ?? this.products,
      googleMapsUrl: googleMapsUrl ?? this.googleMapsUrl,
      notes: notes ?? this.notes,
      rating: rating ?? this.rating,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

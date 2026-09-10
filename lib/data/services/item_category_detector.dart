// ==============================================================================
// Item Category & Hardware Specification Detector
// Purpose: Intelligent keyword & NLP parser for Indian IT market / repair shops
// Extracts: Category, Brand, Model code, and Spec tokens
// ==============================================================================

enum ItemCategory {
  screens,
  batteries,
  keyboards,
  motherboards,
  chargers,
  hingesAndBody,
  coolingFans,
  ramAndStorage,
  printers,
  cablesAndJacks,
  accessories,
  general;

  String get displayName {
    switch (this) {
      case ItemCategory.screens:
        return 'Screens & Displays';
      case ItemCategory.batteries:
        return 'Batteries';
      case ItemCategory.keyboards:
        return 'Keyboards & Panels';
      case ItemCategory.motherboards:
        return 'Motherboard & Chips';
      case ItemCategory.chargers:
        return 'Power Adapters';
      case ItemCategory.hingesAndBody:
        return 'Hinges & Body Covers';
      case ItemCategory.coolingFans:
        return 'Cooling & Fans';
      case ItemCategory.ramAndStorage:
        return 'RAM & SSD';
      case ItemCategory.printers:
        return 'Printers & Cartridges';
      case ItemCategory.cablesAndJacks:
        return 'Cables & DC Jacks';
      case ItemCategory.accessories:
        return 'Accessories';
      case ItemCategory.general:
        return 'General Hardware';
    }
  }

  String get iconName {
    switch (this) {
      case ItemCategory.screens:
        return 'monitor';
      case ItemCategory.batteries:
        return 'battery_charging_full';
      case ItemCategory.keyboards:
        return 'keyboard';
      case ItemCategory.motherboards:
        return 'memory';
      case ItemCategory.chargers:
        return 'power';
      case ItemCategory.hingesAndBody:
        return 'laptop';
      case ItemCategory.coolingFans:
        return 'mode_fan';
      case ItemCategory.ramAndStorage:
        return 'storage';
      case ItemCategory.printers:
        return 'print';
      case ItemCategory.cablesAndJacks:
        return 'cable';
      case ItemCategory.accessories:
        return 'devices_other';
      case ItemCategory.general:
        return 'build';
    }
  }
}

class ItemClassification {
  final ItemCategory category;
  final String? brand;
  final String? modelCode;
  final List<String> specTokens;
  final List<String> searchKeywords;
  final double confidence;

  const ItemClassification({
    required this.category,
    this.brand,
    this.modelCode,
    this.specTokens = const [],
    this.searchKeywords = const [],
    this.confidence = 1.0,
  });

  String get summary {
    final buffer = StringBuffer(category.displayName);
    if (brand != null) buffer.write(' • $brand');
    if (modelCode != null) buffer.write(' ($modelCode)');
    return buffer.toString();
  }
}

class ItemCategoryDetector {
  static const Map<String, String> _knownBrands = {
    'alienware': 'Dell',
    'dell': 'Dell',
    'compaq': 'HP',
    'hewlett': 'HP',
    'hp': 'HP',
    'thinkpad': 'Lenovo',
    'ideapad': 'Lenovo',
    'legion': 'Lenovo',
    'lenovo': 'Lenovo',
    'rog': 'Asus',
    'tuf': 'Asus',
    'zenbook': 'Asus',
    'asus': 'Asus',
    'predator': 'Acer',
    'nitro': 'Acer',
    'aspire': 'Acer',
    'acer': 'Acer',
    'macbook': 'Apple',
    'imac': 'Apple',
    'apple': 'Apple',
    'mac': 'Apple',
    'msi': 'MSI',
    'samsung': 'Samsung',
    'vaio': 'Sony',
    'sony': 'Sony',
    'toshiba': 'Toshiba',
    'lg': 'LG',
    'surface': 'Microsoft',
    'microsoft': 'Microsoft',
    'fujitsu': 'Fujitsu',
    'epson': 'Epson',
    'canon': 'Canon',
    'brother': 'Brother',
    'logitech': 'Logitech',
    'zebronics': 'Zebronics',
  };

  static const Map<ItemCategory, List<String>> _categoryKeywords = {
    ItemCategory.screens: [
      'screen', 'display', 'panel', 'led', 'lcd', 'oled', 'fhd', 'touch screen',
      '30 pin', '40 pin', '30pin', '40pin', 'paper slim', 'slim screen',
      '14.0', '15.6', '13.3', '11.6', '16.0', '17.3', 'b140han', 'nt156', 'edp'
    ],
    ItemCategory.batteries: [
      'battery', 'batt', 'cell', '42wh', '56wh', '76wh', '60wh', 'mah',
      'ht03xl', 'wdx0r', 'c21n1818', 'a1965', 'a1466', 'l18m3pf1', 'c31n1843'
    ],
    ItemCategory.keyboards: [
      'keyboard', 'keypad', 'kbd', 'keys', 'backlit', 'non backlit',
      'c cover', 'palmrest', 'c-panel', 'touchpad', 'trackpad'
    ],
    ItemCategory.motherboards: [
      'motherboard', 'mboard', 'logic board', 'mainboard', 'io board', 'io chip',
      'charging ic', 'bios chip', 'super io', 'it8586', 'ite', 'ene', 'kb9012',
      'pch', 'graphic chip', 'gpu chip', 'power ic'
    ],
    ItemCategory.chargers: [
      'charger', 'adapter', 'adaptor', 'power supply', 'type c charger',
      'type-c 65w', '65w', '90w', '135w', '230w', 'blue pin', 'yellow pin',
      '4.5mm', 'barrel pin', 'power cord'
    ],
    ItemCategory.hingesAndBody: [
      'hinge', 'hinges', 'hing pair', 'body', 'a cover', 'b cover', 'c cover',
      'd cover', 'top cover', 'bottom base', 'bezel', 'front bezel', 'back cover'
    ],
    ItemCategory.coolingFans: [
      'fan', 'cpu fan', 'gpu fan', 'cooling fan', 'heatsink', 'heat sink',
      'thermal paste', 'thermal pad'
    ],
    ItemCategory.ramAndStorage: [
      'ram', 'ddr3', 'ddr4', 'ddr5', 'sodimm', '8gb ram', '16gb ram', '32gb ram',
      'ssd', 'nvme', 'm.2', '2.5 ssd', 'sata ssd', 'hard disk', 'hdd'
    ],
    ItemCategory.printers: [
      'printer', 'cartridge', 'toner', 'printhead', 'drum', 'roller',
      'laserjet', 'ink tank', 'pickup roller', 'teflon', 'fuser film', '88a'
    ],
    ItemCategory.cablesAndJacks: [
      'dc jack', 'charging jack', 'screen cable', 'edp cable', 'lvds cable',
      'hdd cable', 'battery cable', 'power button cable', 'flex cable'
    ],
    ItemCategory.accessories: [
      'mouse', 'headphone', 'bag', 'sleeve', 'cleaning kit', 'hub',
      'converter', 'hdmi cable', 'usb drive', 'pendrive', 'thermal grizzly'
    ],
  };

  /// Classifies a raw item description into structured categories, brand, and keywords.
  static ItemClassification classify(String rawText) {
    if (rawText.trim().isEmpty) {
      return const ItemClassification(category: ItemCategory.general);
    }

    final lower = rawText.toLowerCase();

    // 1. Detect Brand
    String? detectedBrand;
    for (final entry in _knownBrands.entries) {
      final regex = RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false);
      if (regex.hasMatch(lower)) {
        detectedBrand = entry.value;
        break;
      }
    }

    // 2. Detect Category by keyword scoring
    ItemCategory bestCategory = ItemCategory.general;
    int maxMatches = 0;

    for (final entry in _categoryKeywords.entries) {
      int matches = 0;
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) {
          // Give higher weight to exact primary keywords (e.g. 'battery', 'screen')
          final weight = keyword.length > 5 ? 2 : 1;
          matches += weight;
        }
      }
      if (matches > maxMatches) {
        maxMatches = matches;
        bestCategory = entry.key;
      }
    }

    // 3. Extract Specific Model Code (e.g., HT03XL, WDX0R, G14, 3511, L340, A1965)
    String? detectedModel;
    final modelMatch = RegExp(r'\b([A-Za-z]{1,4}[0-9]{2,5}[A-Za-z0-9_-]*|[0-9]{3,5}[A-Za-z0-9_-]+)\b')
        .firstMatch(rawText);
    if (modelMatch != null) {
      final candidate = modelMatch.group(1);
      if (candidate != null && candidate.length >= 3 && !candidate.toLowerCase().contains('mah')) {
        detectedModel = candidate.toUpperCase();
      }
    }

    // 4. Extract Spec Tokens (e.g. 30 pin, FHD, 65W, 76Wh, DDR4, Type-C)
    final specTokens = <String>[];
    final specPatterns = [
      RegExp(r'\b(30\s*pin|40\s*pin)\b', caseSensitive: false),
      RegExp(r'\b(fhd|4k|oled|ips|hd\+|144hz|165hz)\b', caseSensitive: false),
      RegExp(r'\b(\d{2,3}w)\b', caseSensitive: false), // 65w, 90w
      RegExp(r'\b(\d{2,3}wh)\b', caseSensitive: false), // 42wh, 76wh
      RegExp(r'\b(ddr[345]|nvme|sata)\b', caseSensitive: false),
      RegExp(r'\b(type-?c|usb-?c)\b', caseSensitive: false),
      RegExp(r'\b(1[1-7]\.[0-9])\b', caseSensitive: false), // 14.0, 15.6 screen sizes
      RegExp(r'\b(backlit|non-?backlit)\b', caseSensitive: false),
    ];

    for (final pattern in specPatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null) {
        specTokens.add(match.group(0)!.trim().toUpperCase());
      }
    }

    // 5. Generate search keywords (for dealer products/notes matching)
    final searchKeywords = <String>{};
    if (detectedBrand != null) {
      searchKeywords.add(detectedBrand.toLowerCase().split(' ').first);
    }
    if (detectedModel != null) {
      searchKeywords.add(detectedModel.toLowerCase());
    }
    // Add primary category keyword names
    switch (bestCategory) {
      case ItemCategory.screens:
        searchKeywords.addAll(['screen', 'display', 'panel']);
        break;
      case ItemCategory.batteries:
        searchKeywords.addAll(['battery', 'batt']);
        break;
      case ItemCategory.keyboards:
        searchKeywords.addAll(['keyboard', 'c-panel', 'keypad']);
        break;
      case ItemCategory.motherboards:
        searchKeywords.addAll(['motherboard', 'board', 'chip', 'ic']);
        break;
      case ItemCategory.chargers:
        searchKeywords.addAll(['charger', 'adapter', 'power']);
        break;
      case ItemCategory.hingesAndBody:
        searchKeywords.addAll(['hinge', 'body', 'cover']);
        break;
      case ItemCategory.coolingFans:
        searchKeywords.addAll(['fan', 'cooling']);
        break;
      case ItemCategory.ramAndStorage:
        searchKeywords.addAll(['ram', 'ssd', 'nvme']);
        break;
      case ItemCategory.printers:
        searchKeywords.addAll(['printer', 'toner', 'cartridge']);
        break;
      case ItemCategory.cablesAndJacks:
        searchKeywords.addAll(['cable', 'jack', 'dc jack']);
        break;
      default:
        break;
    }

    for (final token in specTokens) {
      searchKeywords.add(token.toLowerCase());
    }

    return ItemClassification(
      category: bestCategory,
      brand: detectedBrand,
      modelCode: detectedModel,
      specTokens: specTokens,
      searchKeywords: searchKeywords.toList(),
      confidence: maxMatches > 0 ? 0.95 : 0.5,
    );
  }
}

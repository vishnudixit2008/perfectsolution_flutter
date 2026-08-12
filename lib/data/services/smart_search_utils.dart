import '../models/pricelist_item.dart';

class SmartSearchUtils {
  /// Evaluates whether a [targetText] matches all search tokens in [rawQuery].
  /// Supports multi-word matching regardless of token order.
  /// Example: query "hp mouse" matches "usb mouse hp m10".
  static bool matchesQuery(String targetText, String rawQuery) {
    final queryTokens = rawQuery.trim().toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (queryTokens.isEmpty) return true;

    final normalizedTarget = targetText.toLowerCase();
    for (final token in queryTokens) {
      if (!normalizedTarget.contains(token)) {
        return false;
      }
    }
    return true;
  }

  /// Filters a list of [PricelistItem] using smart multi-token matching across
  /// item name, category, description, and ID.
  /// Results are sorted by relevance (items where tokens match item name first).
  static List<PricelistItem> filterPricelist(List<PricelistItem> items, String rawQuery) {
    final cleanQuery = rawQuery.trim().toLowerCase();
    if (cleanQuery.isEmpty) return items;

    final tokens = cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return items;

    final List<MapEntry<PricelistItem, int>> scoredMatches = [];

    for (final item in items) {
      final nameLower = item.itemName.toLowerCase();
      final catLower = (item.category ?? '').toLowerCase();
      final descLower = (item.itemDescription ?? '').toLowerCase();
      final idStr = item.id.toString();

      final combined = '$nameLower $catLower $descLower $idStr';

      // All tokens must be present in at least one of the fields
      bool matchesAll = true;
      for (final t in tokens) {
        if (!combined.contains(t)) {
          matchesAll = false;
          break;
        }
      }

      if (matchesAll) {
        // Calculate relevance score (higher is better)
        int score = 0;
        
        // Exact full query match on item name gets highest priority
        if (nameLower == cleanQuery) {
          score += 1000;
        } else if (nameLower.startsWith(cleanQuery)) {
          score += 500;
        }

        // Count how many tokens appear directly in item name
        for (final t in tokens) {
          if (nameLower.contains(t)) {
            score += 100;
          }
          if (catLower.contains(t)) {
            score += 20;
          }
          if (descLower.contains(t)) {
            score += 10;
          }
        }

        scoredMatches.add(MapEntry(item, score));
      }
    }

    // Sort by score descending
    scoredMatches.sort((a, b) => b.value.compareTo(a.value));
    return scoredMatches.map((e) => e.key).toList();
  }
}

import '../models/pricelist_item.dart';

class SmartSearchUtils {
  /// Evaluates whether a [targetText] matches all search tokens in [rawQuery].
  /// Supports multi-word matching regardless of token order.
  /// Example: query "hp mouse" matches "usb mouse hp m10".
  /// Evaluates whether a [targetText] matches all search tokens in [rawQuery].
  /// Supports:
  /// - Multi-word matching regardless of token order (e.g. "hp mouse" matches "usb mouse hp")
  /// - Compound words / space tolerance (e.g. "pendrive" matches "pen drive" and vice versa)
  /// - Punctuation / hyphen tolerance (e.g. "type-c" matches "type c", "wi-fi" matches "wifi")
  static bool matchesQuery(String targetText, String rawQuery) {
    final cleanQuery = rawQuery.trim().toLowerCase();
    if (cleanQuery.isEmpty) return true;

    final normalizedTarget = targetText.toLowerCase();
    final compactTarget = normalizedTarget.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactQuery = cleanQuery.replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Quick full compact match (e.g. query "pen drive" matching "pendrive" or "pendrive" matching "pen drive")
    if (compactQuery.isNotEmpty && compactTarget.contains(compactQuery)) {
      return true;
    }

    final queryTokens = cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (queryTokens.isEmpty) return true;

    for (final token in queryTokens) {
      final compactToken = token.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final hasStandard = normalizedTarget.contains(token);
      final hasCompact = compactToken.isNotEmpty && compactTarget.contains(compactToken);

      if (!hasStandard && !hasCompact) {
        return false;
      }
    }
    return true;
  }

  /// Filters a list of [PricelistItem] using smart multi-token matching across
  /// item name, category, description, and ID with full space & compound-word tolerance.
  /// Results are sorted by relevance (items where tokens match item name first).
  static List<PricelistItem> filterPricelist(
    List<PricelistItem> items,
    String rawQuery, {
    bool Function(PricelistItem)? customFilter,
  }) {
    final cleanQuery = rawQuery.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      if (customFilter != null) {
        return items.where(customFilter).toList();
      }
      return items;
    }

    final tokens = cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) {
      if (customFilter != null) {
        return items.where(customFilter).toList();
      }
      return items;
    }

    final compactQuery = cleanQuery.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final List<MapEntry<PricelistItem, int>> scoredMatches = [];

    for (final item in items) {
      if (customFilter != null && !customFilter(item)) {
        continue;
      }
      final nameLower = item.itemName.toLowerCase();
      final catLower = (item.category ?? '').toLowerCase();
      final descLower = (item.itemDescription ?? '').toLowerCase();
      final idStr = item.id.toString();

      final combined = '$nameLower $catLower $descLower $idStr';
      final compactCombined = combined.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final compactName = nameLower.replaceAll(RegExp(r'[^a-z0-9]'), '');

      // Check match: either full compact match or all tokens present (standard or compact)
      bool matches = false;
      if (compactQuery.isNotEmpty && compactCombined.contains(compactQuery)) {
        matches = true;
      } else {
        bool allTokensMatch = true;
        for (final t in tokens) {
          final compactT = t.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final standardHit = combined.contains(t);
          final compactHit = compactT.isNotEmpty && compactCombined.contains(compactT);

          if (!standardHit && !compactHit) {
            allTokensMatch = false;
            break;
          }
        }
        matches = allTokensMatch;
      }

      if (matches) {
        // Calculate relevance score (higher is better)
        int score = 0;

        // Exact full query match or exact compact match on item name gets highest priority
        if (nameLower == cleanQuery || (compactQuery.isNotEmpty && compactName == compactQuery)) {
          score += 1000;
        } else if (nameLower.startsWith(cleanQuery) || (compactQuery.isNotEmpty && compactName.startsWith(compactQuery))) {
          score += 500;
        }

        // Count how many tokens appear directly in item name
        for (final t in tokens) {
          final compactT = t.replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (nameLower.contains(t) || (compactT.isNotEmpty && compactName.contains(compactT))) {
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

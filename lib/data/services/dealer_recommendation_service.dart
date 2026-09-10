// ==============================================================================
// Intelligent Dealer Recommendation & Procurement Frequency Service
// Purpose: Matches and ranks dealers using flexible keywords + auto-learning
// from local purchase history (zero network overhead, instant 0ms calculation)
// ==============================================================================

import '../models/dealer.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import 'item_category_detector.dart';

class DealerRecommendation {
  final Dealer dealer;
  final double score;
  final int pastCategoryPurchaseCount;
  final List<String> matchReasons;
  final bool isTopMatch;

  const DealerRecommendation({
    required this.dealer,
    required this.score,
    this.pastCategoryPurchaseCount = 0,
    this.matchReasons = const [],
    this.isTopMatch = false,
  });
}

class DealerRecommendationService {
  /// Recommends and ranks dealers for a given item description based on:
  /// 1. Auto-learned historical purchase frequency from `purchases` table
  /// 2. Staff-written product notes, category, and shop tags
  /// 3. Brand specialization and building location proximity
  static List<DealerRecommendation> getRecommendations({
    required String itemText,
    required List<Dealer> allDealers,
    required List<PurchaseOrder> purchaseOrders,
    required List<PurchaseOrderItem> Function(String purchaseId) getPurchaseItems,
    int maxResults = 8,
  }) {
    if (allDealers.isEmpty) return const [];

    final classification = ItemCategoryDetector.classify(itemText);
    final searchTokens = classification.searchKeywords.map((s) => s.toLowerCase()).toSet();
    final detectedBrandLower = classification.brand?.toLowerCase();

    // ── Step 1: Pre-calculate Purchase Frequency per Dealer ────────────────────
    // Maps dealer clean name -> { count: int, lastDate: DateTime? }
    final purchaseHistory = <String, _DealerPurchaseStats>{};

    for (final po in purchaseOrders) {
      final dealerClean = _normalizeName(po.purchasedFrom);
      if (dealerClean.isEmpty) continue;

      final items = getPurchaseItems(po.id);
      bool orderMatched = false;

      for (final item in items) {
        final itemName = '${item.itemName ?? ''} ${item.customItemName ?? ''}'.toLowerCase();
        
        // Check if this purchased item matched the requested category or keywords
        for (final token in searchTokens) {
          if (itemName.contains(token)) {
            orderMatched = true;
            break;
          }
        }
        if (orderMatched) break;
      }

      // If this PO had matching items (or if PO notes contain keywords)
      if (orderMatched) {
        final current = purchaseHistory[dealerClean] ?? _DealerPurchaseStats();
        current.count += 1;
        if (current.lastDate == null || po.date.isAfter(current.lastDate!)) {
          current.lastDate = po.date;
        }
        purchaseHistory[dealerClean] = current;
      }
    }

    // ── Step 2: Score Each Dealer ──────────────────────────────────────────────
    final scoredList = <DealerRecommendation>[];

    for (final dealer in allDealers) {
      // Must have mobile number for WhatsApp dispatch
      final hasMobile = dealer.mobileNo != null && dealer.mobileNo!.trim().isNotEmpty;
      if (!hasMobile) continue;

      final dealerClean = _normalizeName(dealer.name);
      final stats = purchaseHistory[dealerClean];
      final pastCount = stats?.count ?? 0;

      double score = 0.0;
      final reasons = <String>[];

      // A. Purchase Frequency Score (Strongest Signal: Auto-Learning)
      if (pastCount > 0) {
        score += pastCount * 30.0;
        reasons.add('⭐ Frequent Supplier ($pastCount past orders)');
      }

      // B. Staff-Written Product / Notes Keyword Matches
      final dealerTokens = dealer.productKeywords.map((w) => w.toLowerCase()).toSet();
      final matchedKeywords = <String>[];

      for (final token in searchTokens) {
        if (dealerTokens.contains(token)) {
          matchedKeywords.add(token);
        }
      }

      if (matchedKeywords.isNotEmpty) {
        score += matchedKeywords.length * 15.0;
        final preview = matchedKeywords
            .take(3)
            .map((w) => w.length > 1 ? '${w[0].toUpperCase()}${w.substring(1)}' : w.toUpperCase())
            .join(', ');
        reasons.add('🎯 Deals in: $preview');
      }

      // C. Brand Match (e.g. Dell specialist)
      if (detectedBrandLower != null) {
        final brandWord = detectedBrandLower.split(' ').first;
        if (dealerTokens.contains(brandWord) || dealerClean.contains(brandWord)) {
          score += 20.0;
          reasons.add('🏷️ ${classification.brand} Stockist');
        }
      }

      // D. Building Location
      if (dealer.buildingName != null && dealer.buildingName!.trim().isNotEmpty) {
        reasons.add('🏢 ${dealer.buildingName}');
      }

      // E. Dealer Rating Boost
      score += (dealer.rating * 2.0);

      // F. Recency Bonus
      if (stats?.lastDate != null) {
        final daysAgo = DateTime.now().difference(stats!.lastDate!).inDays;
        if (daysAgo <= 30) {
          score += 15.0;
        } else if (daysAgo <= 90) {
          score += 8.0;
        }
      }

      scoredList.add(
        DealerRecommendation(
          dealer: dealer,
          score: score,
          pastCategoryPurchaseCount: pastCount,
          matchReasons: reasons,
        ),
      );
    }

    // ── Step 3: Sort by Highest Affinity Score ────────────────────────────────
    scoredList.sort((a, b) => b.score.compareTo(a.score));

    // Return top N recommendations, marking top matches
    final topResults = scoredList.take(maxResults).toList();
    return topResults.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      return DealerRecommendation(
        dealer: item.dealer,
        score: item.score,
        pastCategoryPurchaseCount: item.pastCategoryPurchaseCount,
        matchReasons: item.matchReasons,
        isTopMatch: index < 3 && item.score > 15.0,
      );
    }).toList();
  }

  static String _normalizeName(String? name) {
    if (name == null) return '';
    return name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}

class _DealerPurchaseStats {
  int count = 0;
  DateTime? lastDate;
}

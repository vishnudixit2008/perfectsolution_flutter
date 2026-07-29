import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

class AppStockBadge extends StatelessWidget {
  final int stockQty;
  final int? customLowThreshold;

  const AppStockBadge({
    super.key,
    required this.stockQty,
    this.customLowThreshold,
  });

  @override
  Widget build(BuildContext context) {
    final threshold = customLowThreshold ?? AppTheme.kDefaultLowStockThreshold;

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (stockQty <= 0) {
      badgeColor = AppTheme.danger;
      badgeText = 'Out of stock';
      badgeIcon = Icons.remove_circle_outline_rounded;
    } else if (stockQty <= threshold) {
      badgeColor = AppTheme.warning;
      badgeText = 'Low: $stockQty units';
      badgeIcon = Icons.warning_amber_rounded;
    } else {
      badgeColor = AppTheme.success;
      badgeText = 'In stock: $stockQty units';
      badgeIcon = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 12, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            badgeText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}

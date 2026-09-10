import 'package:flutter/material.dart';

/// An Apple-inspired section header used across all module tables and lists.
/// Features clean, crisp typography, an illuminated status dot,
/// a high-contrast count pill, and an elegant trailing divider track.
class AppStatusSectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final String? singularLabel;
  final String? pluralLabel;
  final Color color;
  final bool showCount;
  final String? customCountText;

  const AppStatusSectionHeader({
    super.key,
    required this.title,
    this.count = 0,
    this.singularLabel,
    this.pluralLabel,
    required this.color,
    this.showCount = true,
    this.customCountText,
  });

  @override
  Widget build(BuildContext context) {
    final String cleanTitle = title.trim();
    final bool isCompletedStatus = cleanTitle.toLowerCase() == 'complete' ||
        cleanTitle.toLowerCase() == 'completed' ||
        cleanTitle.toLowerCase() == 'confirmed';

    final bool shouldDisplayCount =
        showCount && (!isCompletedStatus || customCountText != null);

    String countLabel = '';
    if (customCountText != null) {
      countLabel = customCountText!;
    } else if (count > 0 && singularLabel != null) {
      countLabel = '$count ${count == 1 ? singularLabel : (pluralLabel ?? '${singularLabel}s')}';
    } else if (count > 0) {
      countLabel = '$count';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.015),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.04), width: 0.8),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          // Apple-style Pill Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 0.9,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glowing Status Dot
                Container(
                  width: 6.5,
                  height: 6.5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 4,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Crisp, Bold Header Title
                Text(
                  cleanTitle.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: color,
                  ),
                ),
                // High-Contrast Count Pill
                if (shouldDisplayCount && countLabel.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      countLabel,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Subtle Trailing Divider Track
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
        ],
      ),
    );
  }
}

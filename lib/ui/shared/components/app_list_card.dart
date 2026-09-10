import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/motion/motion.dart';

class AppListCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? statusBadge;
  final List<Widget>? metadataRows;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Widget? trailing;
  final int index;

  const AppListCard({
    super.key,
    required this.title,
    this.subtitle,
    this.statusBadge,
    this.metadataRows,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.trailing,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cardContent = Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: AppTheme.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.cardBorder, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Title + Status / Popup Menu
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.title3.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: AppTypography.subhead.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (statusBadge case final Widget badge) badge,
                if (trailing case final Widget tr) tr,
                if (onDelete != null || onEdit != null) ...[
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    position: PopupMenuPosition.under,
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: AppTheme.textMuted,
                      size: 18,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    color: const Color(0xFF1B243B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onSelected: (value) {
                      if (value == 'edit' && onEdit != null) onEdit!();
                      if (value == 'delete' && onDelete != null) onDelete!();
                    },
                    itemBuilder: (context) => [
                      if (onEdit != null)
                        PopupMenuItem(
                          value: 'edit',
                          height: 36,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.edit_rounded,
                                size: 16,
                                color: AppTheme.textPrimary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Edit',
                                style: AppTypography.callout.copyWith(
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (onDelete != null)
                        PopupMenuItem(
                          value: 'delete',
                          height: 36,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                                color: AppTheme.danger,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: AppTypography.callout.copyWith(
                                  color: AppTheme.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),

            // Metadata Rows
            if (metadataRows != null && metadataRows!.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...metadataRows!,
            ],
          ],
        ),
      ),
    );

    return StaggeredSlideFade(
      index: index,
      child: BouncyPressable(
        scaleFactor: 0.982,
        hoverBorderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: cardContent,
      ),
    );
  }
}

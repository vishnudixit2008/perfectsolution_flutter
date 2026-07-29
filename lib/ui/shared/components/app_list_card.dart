import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

class AppListCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? statusBadge;
  final List<Widget>? metadataRows;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Widget? trailing;

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
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: AppTheme.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.cardBorder, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
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
                          const PopupMenuItem(
                            value: 'edit',
                            height: 36,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit_rounded,
                                  size: 16,
                                  color: AppTheme.textPrimary,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Edit',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            height: 36,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: AppTheme.danger,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Delete',
                                  style: TextStyle(
                                    fontSize: 13,
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
      ),
    );
  }
}

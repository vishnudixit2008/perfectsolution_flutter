import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

class AppPaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int itemsPerPage;
  final ValueChanged<int> onItemsPerPageChanged;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;

  const AppPaginationBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.itemsPerPage,
    required this.onItemsPerPageChanged,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        margin: const EdgeInsets.only(top: 6, bottom: 6, left: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF131A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Items Per Page Dropdown
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: itemsPerPage,
                dropdownColor: const Color(0xFF1B243B),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
                icon: const Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 16,
                  color: AppTheme.primaryLight,
                ),
                items: [10, 20, 50, 100].map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text('$value'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) onItemsPerPageChanged(val);
                },
              ),
            ),
            const SizedBox(width: 4),
            Container(height: 14, width: 1, color: Colors.white12),
            IconButton(
              onPressed: currentPage > 1 ? onPreviousPage : null,
              icon: const Icon(Icons.chevron_left_rounded),
              iconSize: 18,
              color: AppTheme.primaryLight,
              disabledColor: Colors.white24,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            Text(
              '$currentPage / $totalPages',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            IconButton(
              onPressed: currentPage < totalPages ? onNextPage : null,
              icon: const Icon(Icons.chevron_right_rounded),
              iconSize: 18,
              color: AppTheme.primaryLight,
              disabledColor: Colors.white24,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

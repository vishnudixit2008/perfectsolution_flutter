import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../navigation/navigation_view_model.dart';
import '../../features/pricelist/view_models/pricelist_view_model.dart';
import '../../features/auth/view_models/auth_view_model.dart';
import '../../../data/services/user_permission_service.dart';

class AppBottomNavBar extends StatefulWidget {
  final int currentIndex;

  const AppBottomNavBar({super.key, required this.currentIndex});

  @override
  State<AppBottomNavBar> createState() => _AppBottomNavBarState();
}

class _AppBottomNavBarState extends State<AppBottomNavBar> {
  final ScrollController _scrollController = ScrollController();

  static const List<Map<String, dynamic>> allTabs = [
    {'title': 'Calls', 'icon': Icons.phone_callback_rounded, 'index': 0, 'module': 'calls'},
    {'title': 'Inward', 'icon': Icons.build_rounded, 'index': 1, 'module': 'inward'},
    {'title': 'Replacements', 'icon': Icons.swap_horiz_rounded, 'index': 2, 'module': 'replacements'},
    {'title': 'Pricelist', 'icon': Icons.inventory_2_rounded, 'index': 3, 'module': 'pricelist'},
    {'title': 'Sales', 'icon': Icons.receipt_long_rounded, 'index': 4, 'module': 'sales'},
    {'title': 'Requests', 'icon': Icons.help_outline_rounded, 'index': 5, 'module': 'requests'},
    {'title': 'Purchases', 'icon': Icons.shopping_cart_rounded, 'index': 6, 'module': 'purchases'},
    {'title': 'Settings', 'icon': Icons.tune_rounded, 'index': 7, 'module': 'settings'},
  ];

  @override
  void didUpdateWidget(covariant AppBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _scrollToActiveTab();
    }
  }

  void _scrollToActiveTab() {
    if (!_scrollController.hasClients) return;
    const itemWidth = 76.0;
    final targetOffset = (widget.currentIndex * itemWidth) - 100.0;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: AppTheme.danger, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Logout Confirmation',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out of your session?',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AuthViewModel>().logout();
            },
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleTabs = allTabs.where((item) {
      final moduleKey = item['module'] as String;
      return UserPermissionService.canAccessPage(moduleKey);
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1322),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              // Horizontally Draggable Tab ScrollView
              Expanded(
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: visibleTabs.map((item) {
                          final int idx = item['index'] as int;
                          final bool isActive = widget.currentIndex == idx;

                          return SizedBox(
                            width: 76,
                            child: InkWell(
                              onTap: () {
                                if (idx == 3) {
                                  try {
                                    context.read<PricelistViewModel>().resetSortAndFilters();
                                  } catch (_) {}
                                }
                                context.read<NavigationViewModel>().setIndex(idx);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? AppTheme.primary.withValues(alpha: 0.2)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        item['icon'] as IconData,
                                        size: 20,
                                        color: isActive
                                            ? AppTheme.primaryLight
                                            : AppTheme.textSecondary.withValues(
                                                alpha: 0.6,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item['title'] as String,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: isActive
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isActive
                                            ? AppTheme.primaryLight
                                            : AppTheme.textSecondary.withValues(
                                                alpha: 0.6,
                                              ),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Fade gradient on right edge of scrollable tabs
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 16,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF0F1322).withValues(alpha: 0.0),
                                const Color(0xFF0F1322),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Vertical Divider separating Tabs and Logout Button
              Container(
                width: 1,
                height: 28,
                color: Colors.white.withValues(alpha: 0.08),
              ),

              // Pinned Mobile Logout Button (Zero overlap, compact)
              SizedBox(
                width: 58,
                child: InkWell(
                  onTap: () => _showLogoutConfirmation(context),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: AppTheme.danger,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.danger,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8.0, left: 2.0),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: const Text(
                      'v1.0.8',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

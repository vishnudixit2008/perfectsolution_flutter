import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/motion/motion.dart';
import '../../navigation/navigation_view_model.dart';
import '../../features/pricelist/view_models/pricelist_view_model.dart';
import '../../../data/services/user_permission_service.dart';

class AppBottomNavBar extends StatefulWidget {
  final int currentIndex;

  const AppBottomNavBar({super.key, required this.currentIndex});

  @override
  State<AppBottomNavBar> createState() => _AppBottomNavBarState();
}

class _AppBottomNavBarState extends State<AppBottomNavBar> {
  final ScrollController _scrollController = ScrollController();
  static const double _tabWidth = 80.0;

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
    final visibleTabs = _getVisibleTabs();
    final activeVisibleIndex = visibleTabs.indexWhere((t) => (t['index'] as int) == widget.currentIndex);
    if (activeVisibleIndex < 0) return;

    final targetCenter = activeVisibleIndex * _tabWidth + _tabWidth / 2;
    final viewportWidth = _scrollController.position.viewportDimension;
    final targetOffset = targetCenter - viewportWidth / 2;

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  List<Map<String, dynamic>> _getVisibleTabs() {
    return allTabs.where((item) {
      final moduleKey = item['module'] as String;
      return UserPermissionService.canAccessPage(moduleKey);
    }).toList();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleTabs = _getVisibleTabs();

    return RepaintBoundary(
      child: Container(
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
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: visibleTabs.map((item) {
                      final int idx = item['index'] as int;
                      final bool isActive = widget.currentIndex == idx;

                      return _TelegramLiquidTabItem(
                        title: item['title'] as String,
                        icon: item['icon'] as IconData,
                        isActive: isActive,
                        width: _tabWidth,
                        onTap: () {
                          if (idx == 3) {
                            try {
                              context.read<PricelistViewModel>().resetSortAndFilters();
                            } catch (_) {}
                          }
                          context.read<NavigationViewModel>().setIndex(idx);
                        },
                      );
                    }).toList(),
                  ),
                ),

                // Subtle edge fade mask on right edge
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 14,
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
        ),
      ),
    );
  }
}

/// Telegram-Signature Tab Item with Localized Liquid Spring Pop-Out Capsule
class _TelegramLiquidTabItem extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final double width;
  final VoidCallback onTap;

  const _TelegramLiquidTabItem({
    required this.title,
    required this.icon,
    required this.isActive,
    required this.width,
    required this.onTap,
  });

  @override
  State<_TelegramLiquidTabItem> createState() => _TelegramLiquidTabItemState();
}

class _TelegramLiquidTabItemState extends State<_TelegramLiquidTabItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController;
  late final Animation<double> _scaleXAnimation;
  late final Animation<double> _scaleYAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    // 420ms duration gives eyes enough time to clearly appreciate the smooth liquid pop
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    // Liquid Horizontal Elastic Pop-Out: 0.0 -> 1.16 -> 1.0 with juicy spring overshoot
    _scaleXAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.16).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.16, end: 1.0).chain(
          CurveTween(curve: const Cubic(0.175, 0.885, 0.32, 1.25)),
        ),
        weight: 45,
      ),
    ]).animate(_popController);

    // Liquid Vertical Elastic Pop-Out: 0.0 -> 1.12 -> 1.0
    _scaleYAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.12).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.12, end: 1.0).chain(
          CurveTween(curve: const Cubic(0.175, 0.885, 0.32, 1.2)),
        ),
        weight: 45,
      ),
    ]).animate(_popController);

    // Smooth early opacity fade in
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _popController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    if (widget.isActive) {
      _popController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _TelegramLiquidTabItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _popController.forward(from: 0.0);
    } else if (oldWidget.isActive && !widget.isActive) {
      _popController.reverse();
    }
  }

  @override
  void dispose() {
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = AppTheme.primaryLight;
    final inactiveColor = const Color(0xFF8E8E93);

    return SizedBox(
      width: widget.width,
      height: 58,
      child: BouncyPressable(
        scaleFactor: 0.92,
        enableHaptics: true,
        onTap: widget.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Localized Liquid Pop-Out Capsule & Icon ───────────────
            SizedBox(
              height: 30,
              width: 58,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ── Pop-Out Capsule from Behind the Button ──────────
                  AnimatedBuilder(
                    animation: _popController,
                    builder: (context, child) {
                      final op = _opacityAnimation.value;
                      if (op <= 0.001) return const SizedBox.shrink();

                      return Opacity(
                        opacity: op,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.diagonal3Values(
                            _scaleXAnimation.value,
                            _scaleYAnimation.value,
                            1.0,
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      width: 58,
                      height: 30,
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: activeColor.withValues(alpha: 0.35),
                          width: 0.75,
                        ),
                      ),
                    ),
                  ),

                  // ── Animated Icon with Elastic Scale & Color Morph ──
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: widget.isActive ? 1.0 : 1.06,
                      end: widget.isActive ? 1.08 : 1.0,
                    ),
                    duration: const Duration(milliseconds: 380),
                    curve: const Cubic(0.175, 0.885, 0.32, 1.25),
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: child,
                      );
                    },
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(
                        begin: widget.isActive ? inactiveColor : activeColor,
                        end: widget.isActive ? activeColor : inactiveColor,
                      ),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      builder: (context, color, _) {
                        return Icon(
                          widget.icon,
                          size: 20,
                          color: color,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),

            // ── Responsive Text Label ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: widget.width - 8,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(
                      begin: widget.isActive ? inactiveColor : activeColor,
                      end: widget.isActive ? activeColor : inactiveColor,
                    ),
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    builder: (context, textColor, _) {
                      return Text(
                        widget.title,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
                          letterSpacing: widget.isActive ? 0.1 : 0.0,
                          color: textColor,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

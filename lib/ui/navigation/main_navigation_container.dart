import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../features/pricelist/views/pricelist_view.dart';
import '../features/sales/views/sales_view.dart';
import '../features/settings/views/settings_view.dart';
import '../features/calls/views/calls_view.dart';
import '../features/inward_repairs/views/inward_repairs_view.dart';
import '../features/replacements/views/replacements_view.dart';
import '../features/requests/views/requests_view.dart';
import '../features/purchases/views/purchases_view.dart';
import '../../data/services/supabase_sync_service.dart';
import 'package:provider/provider.dart';
import 'navigation_view_model.dart';
import 'package:shop_management_flutter/data/repositories/shop_repository.dart';
import '../features/calls/view_models/calls_view_model.dart';
import '../features/inward_repairs/view_models/inward_repairs_view_model.dart';
import '../features/replacements/view_models/replacements_view_model.dart';
import '../features/requests/view_models/requests_view_model.dart';
import '../features/purchases/view_models/purchases_view_model.dart';
import '../features/dashboard/view_models/recent_sales_view_model.dart';
import '../features/pricelist/view_models/pricelist_view_model.dart';
import '../shared/components/app_bottom_nav_bar.dart';
import '../shared/update_dialog.dart';
import '../features/settings/views/upi_qr_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/services/user_permission_service.dart';
import '../../data/models/app_user.dart';
import '../features/auth/view_models/auth_view_model.dart';

import 'package:shop_management_flutter/data/services/kiosk_broadcast_service.dart';
import 'package:shop_management_flutter/data/services/ui_preferences_service.dart';

class MainNavigationContainer extends StatefulWidget {
  const MainNavigationContainer({super.key});

  @override
  State<MainNavigationContainer> createState() =>
      _MainNavigationContainerState();
}

class _MainNavigationContainerState extends State<MainNavigationContainer> {
  bool _isSyncing = false;
  Timer? _updateCheckTimer;
  StreamSubscription<KioskBroadcastPayload>? _kioskShowSubscription;
  StreamSubscription<void>? _kioskDismissSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateDialog.showIfNeeded(context);
      _setupKioskBroadcastListener();
    });
    // Check for app updates every 1 hour while the app is kept running
    _updateCheckTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (mounted) {
        UpdateDialog.showIfNeeded(context);
      }
    });
  }

  void _setupKioskBroadcastListener() {
    KioskBroadcastService.instance.init();

    _kioskShowSubscription = KioskBroadcastService.instance.onShowQr.listen((payload) {
      if (!mounted) return;
      if (!UiPreferencesService.isKioskMode()) return;

      // Pop active dialog if already showing QR
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      final timeout = UiPreferencesService.getKioskTimeoutSeconds();
      _openKioskQrModal(
        amount: payload.amount,
        invoiceNo: payload.invoiceNo,
        customerName: payload.customerName,
        autoCloseSeconds: timeout,
      );
    });

    _kioskDismissSubscription = KioskBroadcastService.instance.onDismissQr.listen((_) {
      if (!mounted) return;
      if (!UiPreferencesService.isKioskMode()) return;

      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }

  void _openKioskQrModal({
    required double amount,
    String? invoiceNo,
    String? customerName,
    int? autoCloseSeconds,
  }) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      showDialog(
        context: context,
        useSafeArea: false,
        builder: (_) => Dialog.fullscreen(
          backgroundColor: const Color(0xFF080D1A),
          child: UpiQrScreen(
            initialAmount: amount,
            invoiceNo: invoiceNo,
            customerName: customerName,
            autoCloseSeconds: autoCloseSeconds,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFF0F1524),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppTheme.secondary.withValues(alpha: 0.25)),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: UpiQrScreen(
            initialAmount: amount,
            invoiceNo: invoiceNo,
            customerName: customerName,
            autoCloseSeconds: autoCloseSeconds,
          ),
        ),
      );
    }
  }

  final List<Widget> _views = [
    const CallsView(),
    const InwardRepairsView(),
    const ReplacementsView(),
    const PricelistView(),
    const SalesView(),
    const RequestsView(),
    const PurchasesView(),
    const SettingsView(),
  ];

  final List<Map<String, dynamic>> _navItems = [
    {'title': 'Calls', 'icon': Icons.phone_callback_rounded, 'index': 0, 'module': 'calls'},
    {'title': 'Inward Repairs', 'icon': Icons.build_rounded, 'index': 1, 'module': 'inward'},
    {'title': 'Replacements', 'icon': Icons.swap_horiz_rounded, 'index': 2, 'module': 'replacements'},
    {'title': 'Pricelist', 'icon': Icons.inventory_2_rounded, 'index': 3, 'module': 'pricelist'},
    {'title': 'Sales', 'icon': Icons.receipt_long_rounded, 'index': 4, 'module': 'sales'},
    {'title': 'Requests', 'icon': Icons.help_outline_rounded, 'index': 5, 'module': 'requests'},
    {'title': 'Purchases', 'icon': Icons.shopping_cart_rounded, 'index': 6, 'module': 'purchases'},
    {'title': 'Settings', 'icon': Icons.tune_rounded, 'index': 7, 'module': 'settings'},
  ];

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    _kioskShowSubscription?.cancel();
    _kioskDismissSubscription?.cancel();
    super.dispose();
  }

  Future<void> _triggerManualSync(BuildContext context) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final localDb = context.read<ShopRepository>().localDb;
      await SupabaseSyncService.instance.manualSync(localDb);
      // After sync, reload all view models
      if (context.mounted) {
        _reloadAllViewModels(context);
      }
      // Always re-check for updates after a manual sync tap — forceCheck
      // bypasses the within-session throttle so the popup shows every time
      // the user taps the sync button, even if they skipped it before.
      if (context.mounted) {
        await UpdateDialog.showIfNeeded(context, forceCheck: true);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _reloadAllViewModels(BuildContext context) {
    context.read<NavigationViewModel>().notifySync();
    try {
      context.read<CallsViewModel>().loadCalls();
    } catch (_) {}
    try {
      context.read<InwardRepairsViewModel>().loadRepairs();
    } catch (_) {}
    try {
      context.read<ReplacementsViewModel>().loadReplacements();
    } catch (_) {}
    try {
      context.read<RequestsViewModel>().loadRequests();
    } catch (_) {}
    try {
      context.read<PurchasesViewModel>().loadPurchases();
    } catch (_) {}
    try {
      context.read<RecentSalesViewModel>().loadSales();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 750;
    final navViewModel = context.watch<NavigationViewModel>();
    final int currentIndex = navViewModel.currentIndex;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(currentIndex),
          Expanded(
            child: SafeArea(
              top: true,
              bottom: isDesktop,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isDesktop ? 16.0 : 12.0,
                  isDesktop ? 16.0 : 8.0,
                  isDesktop ? 16.0 : 12.0,
                  isDesktop ? 16.0 : 0.0,
                ),
                child: _buildActiveView(currentIndex),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: !isDesktop
          ? AppBottomNavBar(currentIndex: currentIndex)
          : null,
    );
  }

  void _openUpiQrScreen(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      showDialog(
        context: context,
        useSafeArea: false,
        builder: (_) => Dialog.fullscreen(
          backgroundColor: const Color(0xFF080D1A),
          child: const UpiQrScreen(),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFF0F1524),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppTheme.secondary.withValues(alpha: 0.25)),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: const UpiQrScreen(),
        ),
      );
    }
  }

  Widget _buildActiveView(int currentIndex) {
    if (currentIndex < 0 || currentIndex >= _navItems.length) {
      return _buildAccessDeniedWidget('Module');
    }
    final item = _navItems[currentIndex];
    final moduleKey = item['module'] as String;
    if (!UserPermissionService.canAccessPage(moduleKey)) {
      return _buildAccessDeniedWidget(item['title'] as String);
    }
    return _views[currentIndex];
  }

  Widget _buildAccessDeniedWidget(String moduleTitle) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF131A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_person_rounded,
                size: 48,
                color: AppTheme.danger,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Access Restricted',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'You do not have permission to access "$moduleTitle". Access to this module page is disabled for your account by the Administrator.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(int currentIndex) {
    final visibleItems = _navItems.where((item) {
      final moduleKey = item['module'] as String;
      return UserPermissionService.canAccessPage(moduleKey);
    }).toList();

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: const Color(0xFF0F1322),
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo Area
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.layers_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Perfect',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Solution',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.secondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Cloud Sync Button (clickable)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Consumer<SupabaseSyncService>(
              builder: (context, syncService, _) {
                final isSynced = syncService.status == SyncStatus.synced;
                final isSyncing =
                    syncService.status == SyncStatus.syncing || _isSyncing;
                final isError = syncService.status == SyncStatus.error;

                return InkWell(
                  onTap: () => _triggerManualSync(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSynced
                          ? AppTheme.success.withValues(alpha: 0.1)
                          : isSyncing
                          ? AppTheme.primaryLight.withValues(alpha: 0.1)
                          : isError
                          ? AppTheme.danger.withValues(alpha: 0.1)
                          : AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSynced
                            ? AppTheme.success.withValues(alpha: 0.25)
                            : isSyncing
                            ? AppTheme.primaryLight.withValues(alpha: 0.25)
                            : isError
                            ? AppTheme.danger.withValues(alpha: 0.25)
                            : AppTheme.warning.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        isSyncing
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppTheme.primaryLight,
                                ),
                              )
                            : Icon(
                                isSynced
                                    ? Icons.cloud_done_rounded
                                    : isError
                                    ? Icons.cloud_off_rounded
                                    : Icons.cloud_sync_rounded,
                                size: 14,
                                color: isSynced
                                    ? AppTheme.success
                                    : isError
                                    ? AppTheme.danger
                                    : AppTheme.warning,
                              ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isSyncing
                                ? 'Syncing...'
                                : isSynced
                                ? 'Cloud Synced'
                                : isError
                                ? 'Sync Error — Tap to Retry'
                                : 'Offline — Tap to Sync',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSynced
                                  ? AppTheme.success
                                  : isSyncing
                                  ? AppTheme.primaryLight
                                  : isError
                                  ? AppTheme.danger
                                  : AppTheme.warning,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.refresh_rounded,
                          size: 14,
                          color: isSynced
                              ? AppTheme.success.withValues(alpha: 0.5)
                              : AppTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // QR Pay Button (Desktop Sidebar)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: InkWell(
              onTap: () => _openUpiQrScreen(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.secondary, Color(0xFF2DD4BF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.secondary.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'UPI QR Pay',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),

          // Navigation Links
          Expanded(
            child: ListView.builder(
              itemCount: visibleItems.length,
              itemBuilder: (context, index) {
                final item = visibleItems[index];
                final int navIndex = item['index'] as int;
                final bool isActive = currentIndex == navIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 2.0,
                  ),
                  child: InkWell(
                    onTap: () {
                      if (navIndex == 3) {
                        try {
                          context.read<PricelistViewModel>().resetSortAndFilters();
                        } catch (_) {}
                      }
                      context.read<NavigationViewModel>().setIndex(navIndex);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppTheme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive
                              ? AppTheme.primary.withValues(alpha: 0.25)
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item['icon'],
                            color: isActive
                                ? AppTheme.primaryLight
                                : AppTheme.textSecondary,
                            size: 18,
                          ),
                          const SizedBox(width: 14),
                          Text(
                            item['title'],
                            style: TextStyle(
                              color: isActive
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Footer / User info
          const Divider(color: Colors.white10, height: 1),
          Consumer<AuthViewModel>(
            builder: (context, authViewModel, _) {
              final user = UserPermissionService.getCurrentUser();
              final isPureAdmin = AppUser.isPermanentAdmin(user.email);

              return Padding(
                padding: const EdgeInsets.all(12.0),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isPureAdmin
                          ? AppTheme.primaryLight.withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: user.isAdmin
                            ? AppTheme.primary.withValues(alpha: 0.2)
                            : Colors.white10,
                        child: Icon(
                          user.isAdmin
                              ? Icons.admin_panel_settings_rounded
                              : Icons.person_rounded,
                          color: user.isAdmin
                              ? AppTheme.primaryLight
                              : AppTheme.textMuted,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              isPureAdmin
                                  ? 'Permanent Admin'
                                  : user.role.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isPureAdmin
                                    ? AppTheme.primaryLight
                                    : user.isAdmin
                                        ? AppTheme.success
                                        : AppTheme.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => authViewModel.logout(),
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: AppTheme.danger,
                          size: 18,
                        ),
                        tooltip: 'Logout / Switch Account',
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.hasData ? snapshot.data!.version : '1.1.3';
              final buildNumber = snapshot.hasData ? snapshot.data!.buildNumber : '27';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0, top: 4.0),
                child: Center(
                  child: Text(
                    'v$version (b$buildNumber)',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

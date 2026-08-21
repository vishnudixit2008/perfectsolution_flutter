import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/motion/motion.dart';
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
import '../features/sales/view_models/sales_view_model.dart';
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
import 'package:shop_management_flutter/data/services/kiosk_overlay_helper.dart';

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
  StreamSubscription? _kioskUpiSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Cold app launch: always check for update and bypass 1-hour skip suppression
      UpdateDialog.showIfNeeded(context, isAppLaunch: true);
      _setupKioskBroadcastListener();
    });
    // Check for app updates every 1 hour while the app is kept running
    _updateCheckTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (mounted) {
        UpdateDialog.showIfNeeded(context, isAppLaunch: false);
      }
    });
  }

  void _setupKioskBroadcastListener() {
    KioskBroadcastService.instance.init();

    _kioskShowSubscription = KioskBroadcastService.instance.onShowQr.listen((payload) {
      if (!mounted) return;
      if (!UiPreferencesService.isKioskMode()) return;

      // Bring Android app to front over other apps if minimized
      KioskOverlayHelper.bringAppToFront();

      // Update local repository active UPI for this display (syncToCloud: false prevents sync loop)
      if (payload.upiId != null && payload.upiId!.trim().isNotEmpty) {
        try {
          final repo = context.read<ShopRepository>();
          repo.setActiveUpiId(payload.upiId!.trim(), syncToCloud: false);
        } catch (_) {}
      }

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
        upiId: payload.upiId,
        upiName: payload.upiName,
      );
    });

    _kioskDismissSubscription = KioskBroadcastService.instance.onDismissQr.listen((_) {
      if (!mounted) return;
      if (!UiPreferencesService.isKioskMode()) return;

      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });

    _kioskUpiSubscription = KioskBroadcastService.instance.onActiveUpiChanged.listen((map) {
      if (!mounted) return;
      final upiId = map['upiId']?.trim();
      if (upiId != null && upiId.isNotEmpty) {
        try {
          final repo = context.read<ShopRepository>();
          repo.setActiveUpiId(upiId, syncToCloud: false);
        } catch (_) {}
      }
    });
  }

  void _openKioskQrModal({
    required double amount,
    String? invoiceNo,
    String? customerName,
    int? autoCloseSeconds,
    String? upiId,
    String? upiName,
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
            upiId: upiId,
            upiName: upiName,
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
            upiId: upiId,
            upiName: upiName,
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
    _kioskUpiSubscription?.cancel();
    super.dispose();
  }

  Future<void> _triggerManualSync(BuildContext context, {bool forceFullDownload = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    final syncService = SupabaseSyncService.instance;
    try {
      final localDb = context.read<ShopRepository>().localDb;
      await syncService.manualSync(localDb, forceFullDownload: forceFullDownload);
      // After sync, reload all view models
      if (context.mounted) {
        _reloadAllViewModels(context);
      }
      // Re-check for updates after manual sync tap (forceCheck: true guarantees instant popup if an update exists)
      if (context.mounted) {
        await UpdateDialog.showIfNeeded(context, isAppLaunch: false, forceCheck: true);
      }
    } catch (_) {
      // Handled silently by SupabaseSyncService status updates
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSyncOptionsDialog(BuildContext context) {
    final syncService = SupabaseSyncService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1524),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: const Row(
          children: [
            Icon(Icons.sync_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Cloud Sync Options', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (syncService.status == SyncStatus.error) ...[
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  syncService.statusMessage.isEmpty ? 'Unknown error' : syncService.statusMessage,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.danger),
                ),
              ),
            ],
            const Text(
              'Choose sync mode:',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bolt_rounded, color: AppTheme.success),
              title: const Text('Quick Delta Sync', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: const Text('Fetches only new changes + refreshes screen (0 cloud bandwidth)', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _triggerManualSync(context, forceFullDownload: false);
              },
            ),
            const Divider(color: Colors.white12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_download_rounded, color: Colors.orange),
              title: const Text('Force Full Database Re-Sync', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: const Text('Downloads 100% of all tables from cloud from scratch', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _triggerManualSync(context, forceFullDownload: true);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppTheme.textMuted)),
          ),
        ],
      ),
    );
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
    try {
      context.read<SalesViewModel>().loadCatalog();
    } catch (_) {}
    try {
      context.read<PricelistViewModel>().loadItems();
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
                child: _FadeScaleIndexedStack(
                  index: currentIndex.clamp(0, _views.length - 1),
                  children: List.generate(
                    _views.length,
                    (index) => _buildActiveView(index),
                  ),
                ),
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

                return BouncyPressable(
                  onTap: () => _triggerManualSync(context, forceFullDownload: false),
                  onSecondaryTap: () => _showSyncOptionsDialog(context),
                  onLongPress: () => _showSyncOptionsDialog(context),
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
                                ? 'Sync Error — Click to Retry'
                                : 'Offline — Click to Sync',
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
            child: BouncyPressable(
              onTap: () => _openUpiQrScreen(context),
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
                  child: BouncyPressable(
                    scaleFactor: 0.94,
                    onTap: () {
                      if (navIndex == 3) {
                        try {
                          context.read<PricelistViewModel>().resetSortAndFilters();
                        } catch (_) {}
                      }
                      context.read<NavigationViewModel>().setIndex(navIndex);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppTheme.primary.withValues(alpha: 0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActive
                              ? AppTheme.primary.withValues(alpha: 0.28)
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 3.5,
                            height: isActive ? 16 : 0,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppTheme.primaryLight
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          SizedBox(width: isActive ? 10 : 4),
                          AnimatedScale(
                            scale: isActive ? 1.08 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: AppleMotion.spring,
                            child: Icon(
                              item['icon'],
                              color: isActive
                                  ? AppTheme.primaryLight
                                  : AppTheme.textSecondary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item['title'],
                              style: TextStyle(
                                color: isActive
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 13,
                                letterSpacing: -0.1,
                              ),
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

/// Keeps all views mounted and alive in memory while rendering a rich,
/// liquid 380ms spring fade-scale-slide transition when switching tabs.
class _FadeScaleIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _FadeScaleIndexedStack({
    required this.index,
    required this.children,
  });

  @override
  State<_FadeScaleIndexedStack> createState() => _FadeScaleIndexedStackState();
}

class _FadeScaleIndexedStackState extends State<_FadeScaleIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    final curved = CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.175, 0.885, 0.32, 1.15),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.70, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.02),
      end: Offset.zero,
    ).animate(curved);

    _scaleAnimation = Tween<double>(
      begin: 0.98,
      end: 1.0,
    ).animate(curved);

    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _FadeScaleIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = widget.index.clamp(0, widget.children.length - 1);

    return Stack(
      fit: StackFit.expand,
      children: List.generate(widget.children.length, (i) {
        final isActive = i == activeIndex;
        if (!isActive) {
          return Offstage(
            offstage: true,
            child: widget.children[i],
          );
        }

        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: widget.children[i],
            ),
          ),
        );
      }),
    );
  }
}


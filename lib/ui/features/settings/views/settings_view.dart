import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shop_management_flutter/ui/core/app_theme.dart';
import 'package:shop_management_flutter/ui/features/settings/view_models/settings_view_model.dart';
import 'package:shop_management_flutter/data/services/user_permission_service.dart';
import 'package:shop_management_flutter/data/models/app_user.dart';
import 'package:shop_management_flutter/ui/features/auth/view_models/auth_view_model.dart';
import 'package:shop_management_flutter/ui/shared/components/app_page_header.dart';
import 'package:shop_management_flutter/ui/shared/components/app_floating_action_button.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shop_management_flutter/data/services/ui_preferences_service.dart';
import 'package:shop_management_flutter/data/services/kiosk_broadcast_service.dart';
import 'package:shop_management_flutter/data/services/kiosk_overlay_helper.dart';
import 'package:shop_management_flutter/ui/shared/update_dialog.dart';
import 'user_management_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final TextEditingController _upiController = TextEditingController();
  final TextEditingController _upiNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<SettingsViewModel>();
      await vm.loadSettings();
    });
  }

  @override
  void dispose() {
    _upiController.dispose();
    _upiNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isDesktop = screenWidth >= 880;

        final bool canManageUpi = UserPermissionService.canPerformModuleAction(
            'settings', 'canManageUpi');
        final bool canManageInvoiceLayout =
            UserPermissionService.canPerformModuleAction(
                'settings', 'canManageInvoiceLayout');
        final bool canManageUsers = UserPermissionService.canPerformModuleAction(
            'settings', 'canManageUsers');

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton:
              !isDesktop ? const AppFloatingActionButton.qrOnly() : null,
          body: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppPageHeader(
                  title: 'Settings',
                  subtitle:
                      'User preferences, payment config, invoice review QR & permissions',
                ),

                // ── Top Card: Account & Device Preferences ───────────────────
                _buildUserProfileAndLogoutCard(context),

                const SizedBox(height: 20),

                // ── Main Content Grid ─────────────────────────────────────────
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Payment Config
                      if (canManageUpi)
                        Expanded(
                          flex: 11,
                          child: _buildUpiCard(context, viewModel),
                        ),

                      if (canManageUpi &&
                          (canManageInvoiceLayout || canManageUsers))
                        const SizedBox(width: 20),

                      // Right Column: Invoice Review QR + User Access
                      if (canManageInvoiceLayout || canManageUsers)
                        Expanded(
                          flex: 9,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (canManageInvoiceLayout)
                                _buildLayoutAndPrinterCard(context, viewModel),
                              if (canManageInvoiceLayout && canManageUsers)
                                const SizedBox(height: 20),
                              if (canManageUsers)
                                _buildUserManagementCard(context),
                            ],
                          ),
                        ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canManageUpi) ...[
                        _buildUpiCard(context, viewModel),
                        const SizedBox(height: 20),
                      ],
                      if (canManageInvoiceLayout) ...[
                        _buildLayoutAndPrinterCard(context, viewModel),
                        const SizedBox(height: 20),
                      ],
                      if (canManageUsers) ...[
                        _buildUserManagementCard(context),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),

                // ── App Version at Bottom (Original Clean Minimal Format) ─────
                const SizedBox(height: 32),
                Center(
                  child: Column(
                    children: [
                      const Text(
                        'Perfect Solution App',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snapshot) {
                          final version = snapshot.hasData
                              ? snapshot.data!.version
                              : '1.2.3';
                          final buildNumber = snapshot.hasData
                              ? snapshot.data!.buildNumber
                              : '37';
                          return Text(
                            'Version $version (Build $buildNumber)',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Checking for updates...'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                          await UpdateDialog.showIfNeeded(context, forceCheck: true);
                        },
                        icon: const Icon(Icons.sync_rounded, size: 14),
                        label: const Text('Check for Updates', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryLight,
                          side: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // My Account, Logout & Device Preferences Card (Responsive & Overflow-Free)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildUserProfileAndLogoutCard(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, authViewModel, _) {
        final user = UserPermissionService.getCurrentUser();
        final isPureAdmin = AppUser.isPermanentAdmin(user.email);

        return LayoutBuilder(
          builder: (context, constraints) {
            final bool isNarrow = constraints.maxWidth < 620;

            if (isNarrow) {
              // Mobile / Android layout: stacked rows with zero horizontal overflow
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.glassCardDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
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
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      user.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (isPureAdmin
                                              ? AppTheme.primaryLight
                                              : (user.isAdmin
                                                  ? AppTheme.success
                                                  : AppTheme.warning))
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: (isPureAdmin
                                                ? AppTheme.primaryLight
                                                : (user.isAdmin
                                                    ? AppTheme.success
                                                    : AppTheme.warning))
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      isPureAdmin
                                          ? 'PERMANENT ADMIN'
                                          : user.role.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.4,
                                        color: isPureAdmin
                                            ? AppTheme.primaryLight
                                            : (user.isAdmin
                                                ? AppTheme.success
                                                : AppTheme.warning),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user.email,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.primary
                                    .withValues(alpha: 0.25)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.dark_mode_rounded,
                                  size: 13, color: AppTheme.primaryLight),
                              SizedBox(width: 5),
                              Text(
                                'Dark Mode Active',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _showLogoutConfirmationDialog(context),
                          icon: const Icon(Icons.logout_rounded, size: 14),
                          label: const Text('Logout'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: BorderSide(
                                color: AppTheme.danger.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    if (user.email.toLowerCase().trim() ==
                        'sale.perfectsolutionnoida@gmail.com') ...[
                      const SizedBox(height: 14),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 10),
                      _buildKioskModeCard(context),
                    ],
                  ],
                ),
              );
            }

            // Desktop & wide view: inline horizontal row
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.glassCardDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 24,
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
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (isPureAdmin
                                            ? AppTheme.primaryLight
                                            : (user.isAdmin
                                                ? AppTheme.success
                                                : AppTheme.warning))
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: (isPureAdmin
                                              ? AppTheme.primaryLight
                                              : (user.isAdmin
                                                  ? AppTheme.success
                                                  : AppTheme.warning))
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    isPureAdmin
                                        ? 'PERMANENT ADMIN'
                                        : user.role.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                      color: isPureAdmin
                                          ? AppTheme.primaryLight
                                          : (user.isAdmin
                                              ? AppTheme.success
                                              : AppTheme.warning),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              user.email,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // App Theme Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppTheme.primary
                                  .withValues(alpha: 0.25)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dark_mode_rounded,
                                size: 14, color: AppTheme.primaryLight),
                            SizedBox(width: 6),
                            Text(
                              'Dark Mode',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Logout Button
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showLogoutConfirmationDialog(context),
                        icon: const Icon(Icons.logout_rounded, size: 15),
                        label: const Text('Logout'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: BorderSide(
                              color: AppTheme.danger.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                  if (user.email.toLowerCase().trim() ==
                      'sale.perfectsolutionnoida@gmail.com') ...[
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 12),
                    _buildKioskModeCard(context),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showLogoutConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A26),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: AppTheme.danger,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Logout Confirmation',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
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
            child:
                const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Customer QR Display Settings Card
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildKioskModeCard(BuildContext context) {
    final bool isKiosk = UiPreferencesService.isKioskMode();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer QR Display Mode',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Turn on this mode on dedicated counter-facing tablet/PC screens to automatically display dynamic payment QR codes when staff billed from billing devices.',
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textMuted,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isKiosk
                ? AppTheme.secondary.withValues(alpha: 0.08)
                : const Color(0xFF131826),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isKiosk
                  ? AppTheme.secondary.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isKiosk ? AppTheme.secondary : AppTheme.textMuted)
                          .withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.desktop_windows_rounded,
                      color: isKiosk ? AppTheme.secondary : AppTheme.textMuted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Set QR Display Mode',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isKiosk
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isKiosk
                              ? 'Active — Ready to show payment QRs'
                              : 'Disabled — Turn ON for counter display',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isKiosk,
                    activeColor: AppTheme.secondary,
                    onChanged: (val) async {
                      await UiPreferencesService.setKioskMode(val);
                      if (val) {
                        KioskBroadcastService.instance.init();
                        await KioskOverlayHelper.startKioskForegroundService();
                        if (mounted) setState(() {});
                        // Check overlay & battery permissions on Android
                        final hasOverlay = await KioskOverlayHelper
                            .isOverlayPermissionGranted();
                        final isBatteryIgnored = await KioskOverlayHelper
                            .isBatteryOptimizationIgnored();
                        if ((!hasOverlay || !isBatteryIgnored) &&
                            context.mounted) {
                          _showKioskAndroidSetupDialog(context);
                        }
                      } else {
                        await KioskOverlayHelper.stopKioskForegroundService();
                        if (mounted) setState(() {});
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              val
                                  ? 'QR Display Mode enabled! This device will now automatically show payment QRs.'
                                  : 'QR Display Mode disabled.',
                            ),
                            backgroundColor:
                                val ? AppTheme.secondary : AppTheme.warning,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              if (isKiosk) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppTheme.success.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sensors_rounded,
                            size: 12,
                            color: AppTheme.success,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'LISTENING FOR QR BROADCASTS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.success,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FutureBuilder<bool>(
                      future: KioskOverlayHelper.isOverlayPermissionGranted(),
                      builder: (context, snapshot) {
                        final hasPermission = snapshot.data ?? true;
                        if (hasPermission) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0EA5E9)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF0EA5E9)
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.layers_rounded,
                                  size: 12,
                                  color: Color(0xFF0EA5E9),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'OVERLAY ACTIVE (MINIMIZED POPUP)',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0EA5E9),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return InkWell(
                          onTap: () async {
                            await KioskOverlayHelper.requestOverlayPermission();
                            if (mounted) setState(() {});
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.warning.withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 12,
                                  color: AppTheme.warning,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'GRANT OVERLAY (FOR POPUP)',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.warning,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    FutureBuilder<bool>(
                      future:
                          KioskOverlayHelper.isBatteryOptimizationIgnored(),
                      builder: (context, snapshot) {
                        final isIgnored = snapshot.data ?? true;
                        if (isIgnored) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.teal.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.battery_charging_full_rounded,
                                  size: 12,
                                  color: Colors.tealAccent,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'UNRESTRICTED 24/7 BACKGROUND',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.tealAccent,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return InkWell(
                          onTap: () async {
                            await KioskOverlayHelper
                                .requestIgnoreBatteryOptimization();
                            if (mounted) setState(() {});
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.warning.withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.battery_alert_rounded,
                                  size: 12,
                                  color: AppTheme.warning,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'DISABLE BATTERY SLEEP RESTRICTIONS',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.warning,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showKioskAndroidSetupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1524),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.secondary.withValues(alpha: 0.3)),
        ),
        title: const Row(
          children: [
            Icon(Icons.phonelink_setup_rounded,
                color: AppTheme.secondary, size: 24),
            SizedBox(width: 10),
            Text(
              'Kiosk Android Permissions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'For your phone to reliably wake up and pop up payment QR codes even when minimized or when the screen is locked, enable these 2 Android settings:',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1. Display over other apps',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Allows QR to pop up over home screen & other apps',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0EA5E9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      await KioskOverlayHelper.requestOverlayPermission();
                      if (mounted) setState(() {});
                    },
                    child: const Text('Open Setting'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '2. Unrestricted Battery',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Prevents Android from putting app to sleep when screen is off',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      await KioskOverlayHelper
                          .requestIgnoreBatteryOptimization();
                      if (mounted) setState(() {});
                    },
                    child: const Text('Allow 24/7'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '3. Autostart & Background Pop-up',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'For Xiaomi / Vivo / Oppo / Samsung: Enable Autostart & "Display pop-up windows in background"',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      await KioskOverlayHelper.openAppDetailsSettings();
                    },
                    child: const Text('App Info'),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UPI Card (Responsive inputs and list items)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildUpiCard(BuildContext context, SettingsViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCardDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.qr_code_2_rounded,
                  color: AppTheme.primaryLight,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UPI Payment Configuration',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Configure scan-to-pay QR codes generated on checkout invoices.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Input Form (Responsive Layout)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: LayoutBuilder(
              builder: (context, formConstraints) {
                final bool isNarrowForm = formConstraints.maxWidth < 460;

                void submitUpi() {
                  final vpa = _upiController.text.trim();
                  final refName = _upiNameController.text.trim();
                  if (vpa.isNotEmpty) {
                    viewModel.addUpiId(vpa, referenceName: refName);
                    _upiController.clear();
                    _upiNameController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('UPI ID added successfully.'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  }
                }

                if (isNarrowForm) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _upiController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. 9876543210@paytm, shopname@upi',
                          labelText: 'Business UPI VPA *',
                          prefixIcon: Icon(Icons.qr_code_rounded, size: 18),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _upiNameController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Main Counter, Vishnu HDFC',
                          labelText: 'Account Reference Name',
                          prefixIcon: Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 18),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: submitUpi,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add UPI Address'),
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _upiController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. 9876543210@paytm, shopname@upi',
                        labelText: 'Business UPI VPA *',
                        prefixIcon: Icon(Icons.qr_code_rounded, size: 18),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _upiNameController,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Main Counter, Vishnu HDFC',
                              labelText: 'Account Reference Name',
                              prefixIcon: Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 18),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: submitUpi,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add UPI'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Registered List Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Registered UPI Accounts',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${viewModel.upiIds.length} Added',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (viewModel.upiIds.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 32, color: AppTheme.textMuted),
                  SizedBox(height: 8),
                  Text(
                    'No UPI IDs added yet.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: viewModel.upiIds.length,
              itemBuilder: (context, index) {
                final upi = viewModel.upiIds[index];
                final bool isActive = viewModel.activeUpiId == upi;
                final String refName = viewModel.getUpiReferenceName(upi);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.primary.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isActive
                          ? AppTheme.primary.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.05),
                      width: isActive ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Active indicator / Avatar
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive
                              ? AppTheme.primary.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.04),
                          border: Border.all(
                            color: isActive
                                ? AppTheme.primary.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Icon(
                          isActive
                              ? Icons.check_circle_rounded
                              : Icons.account_balance_rounded,
                          size: 17,
                          color: isActive
                              ? AppTheme.primaryLight
                              : AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Name & VPA
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    refName.isNotEmpty
                                        ? refName
                                        : 'UPI Account',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isActive) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.success
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'ACTIVE',
                                      style: TextStyle(
                                        color: AppTheme.success,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              upi,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isActive
                                    ? AppTheme.primaryLight
                                    : AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Action buttons
                      if (!isActive)
                        TextButton(
                          onPressed: () => viewModel.selectActiveUpiId(upi),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryLight,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                          ),
                          child: const Text(
                            'Set Active',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: AppTheme.textMuted,
                          size: 17,
                        ),
                        onPressed: () => _showEditUpiNameDialog(
                          context,
                          viewModel,
                          upi,
                          refName,
                        ),
                        tooltip: 'Edit Reference Name',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppTheme.danger,
                          size: 17,
                        ),
                        onPressed: () {
                          viewModel.deleteUpiId(upi);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('UPI ID deleted.'),
                              backgroundColor: AppTheme.warning,
                            ),
                          );
                        },
                        tooltip: 'Delete Key',
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showEditUpiNameDialog(
    BuildContext context,
    SettingsViewModel viewModel,
    String upiVpa,
    String currentName,
  ) {
    final nameCtrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.person_rounded, color: AppTheme.primaryLight, size: 20),
            SizedBox(width: 8),
            Text(
              'Edit Reference Name',
              style: TextStyle(fontSize: 16, color: AppTheme.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'UPI VPA: $upiVpa',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Vishnu - HDFC, Main Counter GPay',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await viewModel.updateUpiReferenceName(upiVpa, nameCtrl.text);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('UPI reference name updated.'),
                    backgroundColor: AppTheme.success,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // User Management Card (RBAC)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildUserManagementCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCardDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Color(0xFF818CF8),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User Access & Permissions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Role-Based Access Control (RBAC)',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Manage app employees, role assignments, and granular page, action, and field visibility permissions.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),

          // Feature chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildFeatureChip('👥 Staff Roles'),
              _buildFeatureChip('🔒 Page Access'),
              _buildFeatureChip('⚡ Actions Matrix'),
              _buildFeatureChip('📋 Status Ordering'),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UserManagementView(),
                  ),
                );
              },
              icon: const Icon(Icons.manage_accounts_rounded, size: 18),
              label: const Text('Manage Users & Permissions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Invoice Review QR Card (Minimal Business Review Listing Selector)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLayoutAndPrinterCard(
      BuildContext context, SettingsViewModel viewModel) {
    final bool isLaptopRepairing =
        viewModel.googleReviewListing == 'laptop_repairing';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCardDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.reviews_rounded,
                  color: AppTheme.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invoice Review QR Code',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Select which review QR code is printed on invoices.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Option 1: Perfect Solution ─────────────────────────────────────
          _buildListingOption(
            context: context,
            isSelected: !isLaptopRepairing,
            title: 'Perfect Solution',
            icon: Icons.storefront_rounded,
            activeColor: AppTheme.secondary,
            onTap: () async {
              if (isLaptopRepairing) {
                await viewModel.setGoogleReviewListing('perfect_solution');
              }
            },
          ),
          const SizedBox(height: 10),

          // ── Option 2: LAPTOP REPAIRING SERVICE ─────────────────────────────
          _buildListingOption(
            context: context,
            isSelected: isLaptopRepairing,
            title: 'LAPTOP REPAIRING SERVICE',
            icon: Icons.laptop_chromebook_rounded,
            activeColor: const Color(0xFF6366F1),
            onTap: () async {
              if (!isLaptopRepairing) {
                await viewModel.setGoogleReviewListing('laptop_repairing');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildListingOption({
    required BuildContext context,
    required bool isSelected,
    required String title,
    required IconData icon,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.06),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Radio indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? activeColor : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? activeColor
                        : AppTheme.textMuted.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Center(
                        child: Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Icon
              Icon(
                icon,
                size: 18,
                color: isSelected ? activeColor : AppTheme.textMuted,
              ),
              const SizedBox(width: 10),

              // Title
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
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

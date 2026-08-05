import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shop_management_flutter/ui/core/app_theme.dart';
import 'package:shop_management_flutter/ui/features/settings/view_models/settings_view_model.dart';
import 'package:shop_management_flutter/data/services/user_permission_service.dart';
import 'package:shop_management_flutter/data/models/app_user.dart';
import 'package:shop_management_flutter/ui/features/auth/view_models/auth_view_model.dart';
import 'package:shop_management_flutter/ui/shared/components/app_page_header.dart';
import 'user_management_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final TextEditingController _upiController = TextEditingController();
  final TextEditingController _marginTBController = TextEditingController();
  final TextEditingController _marginLRController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<SettingsViewModel>();
      await vm.loadSettings();
      if (mounted) {
        _marginTBController.text = vm.marginTB.toStringAsFixed(0);
        _marginLRController.text = vm.marginLR.toStringAsFixed(0);
      }
    });
  }

  @override
  void dispose() {
    _upiController.dispose();
    _marginTBController.dispose();
    _marginLRController.dispose();
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
        final bool isDesktop = screenWidth >= 750;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppPageHeader(
                title: 'Settings',
                subtitle:
                    'Invoice layout, margins, UPI payments & app preferences',
              ),

              // Responsive Cards Layout
              isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildUpiCard(context, viewModel)),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            children: [
                              _buildLayoutAndPrinterCard(context, viewModel),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildMobileUserLogoutCard(context),
                        const SizedBox(height: 20),
                        _buildUpiCard(context, viewModel),
                        const SizedBox(height: 20),
                        _buildLayoutAndPrinterCard(context, viewModel),
                      ],
                    ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mobile User / Logout Card (unchanged)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMobileUserLogoutCard(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, authViewModel, _) {
        final user = UserPermissionService.getCurrentUser();
        final isPureAdmin = AppUser.isPermanentAdmin(user.email);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.glassCardDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: 12,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: user.isAdmin
                    ? AppTheme.primary.withValues(alpha: 0.2)
                    : Colors.white10,
                child: Icon(
                  user.isAdmin
                      ? Icons.admin_panel_settings_rounded
                      : Icons.person_rounded,
                  color: user.isAdmin ? AppTheme.primaryLight : AppTheme.textMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user.email,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isPureAdmin
                                ? AppTheme.primaryLight
                                : (user.isAdmin ? AppTheme.success : AppTheme.warning))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isPureAdmin ? 'Permanent Admin' : user.role.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isPureAdmin
                              ? AppTheme.primaryLight
                              : (user.isAdmin ? AppTheme.success : AppTheme.warning),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF161A26),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.logout_rounded,
                                color: AppTheme.danger, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text('Logout Confirmation',
                              style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      content: const Text(
                        'Are you sure you want to log out of your session?',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel',
                              style: TextStyle(color: AppTheme.textMuted)),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            authViewModel.logout();
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
                },
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger.withValues(alpha: 0.2),
                  foregroundColor: AppTheme.danger,
                  elevation: 0,
                  side: const BorderSide(color: AppTheme.danger, width: 1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UPI Card (unchanged)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildUpiCard(BuildContext context, SettingsViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCardDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.qr_code_2_rounded,
                  color: AppTheme.primaryLight,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'UPI Payment Config',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Add your business UPI accounts. The marked "Active" key is dynamically compiled into a scan-to-pay QR code on invoices during checkout.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _upiController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. shopname@upi, 9876543210@paytm',
                    labelText: 'Business UPI VPA *',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  final vpa = _upiController.text.trim();
                  if (vpa.isNotEmpty) {
                    viewModel.addUpiId(vpa);
                    _upiController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('UPI ID added successfully.'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
                child: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 24),

          const Text(
            'Registered UPI Addresses',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          viewModel.upiIds.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No UPI IDs added yet.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: viewModel.upiIds.length,
                  itemBuilder: (context, index) {
                    final upi = viewModel.upiIds[index];
                    final bool isActive = viewModel.activeUpiId == upi;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppTheme.primary.withOpacity(0.08)
                            : Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive
                              ? AppTheme.primary.withOpacity(0.3)
                              : Colors.white.withOpacity(0.06),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  upi,
                                  style: TextStyle(
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isActive
                                        ? AppTheme.textPrimary
                                        : AppTheme.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                                if (isActive) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: AppTheme.success,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'ACTIVE SYSTEM DEFAULT',
                                        style: TextStyle(
                                          color:
                                              AppTheme.success.withOpacity(0.9),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              if (!isActive)
                                TextButton(
                                  onPressed: () =>
                                      viewModel.selectActiveUpiId(upi),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.primaryLight,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                  ),
                                  child: const Text(
                                    'Set Active',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppTheme.danger,
                                  size: 18,
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
                        ],
                      ),
                    );
                  },
                ),

          const SizedBox(height: 24),

          // User Management Tile
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryLight.withOpacity(0.3)),
            ),
            child: MediaQuery.of(context).size.width < 600
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.admin_panel_settings_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'User Access & Permissions (RBAC)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Manage app employees, role-based access, and granular page/action permissions.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: UserPermissionService
                                  .canPerformModuleAction(
                                      'settings', 'canManageUsers')
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const UserManagementView(),
                                    ),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.manage_accounts_rounded,
                              size: 18),
                          label: const Text('Manage Users'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'User Access & Permissions (RBAC)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Manage app employees, role-based access, and granular page/action permissions.',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: UserPermissionService
                                .canPerformModuleAction(
                                    'settings', 'canManageUsers')
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const UserManagementView(),
                                  ),
                                );
                              }
                            : null,
                        icon: const Icon(Icons.manage_accounts_rounded,
                            size: 18),
                        label: const Text('Manage Users'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Google Drive Photo Storage Card
  // ─────────────────────────────────────────────────────────────────────────


  // ─────────────────────────────────────────────────────────────────────────
  // Layout & Printer Card (EXPANDED — now includes printer config + live layout
  // editing with page size, margins, and visibility toggles)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLayoutAndPrinterCard(
      BuildContext context, SettingsViewModel viewModel) {
    const sectionLabel = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: AppTheme.textPrimary,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCardDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ──────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: AppTheme.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Invoice Layout & Format',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Configure invoice page size, margins and content toggles. Printed invoices open directly in your system PDF viewer.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // ── Page Size ─────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Print Paper Format', style: sectionLabel),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              for (final size in ['A5', 'A4', 'Thermal80'])
                Expanded(
                  child: GestureDetector(
                    onTap: () => viewModel.setInvoicePageSize(size),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(right: size == 'Thermal80' ? 0 : 8),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: viewModel.invoicePageSize == size
                            ? AppTheme.primaryLight.withOpacity(0.12)
                            : Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: viewModel.invoicePageSize == size
                              ? AppTheme.primaryLight.withOpacity(0.5)
                              : Colors.white.withOpacity(0.08),
                          width: viewModel.invoicePageSize == size ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            size == 'Thermal80'
                                ? Icons.receipt_long_rounded
                                : Icons.description_outlined,
                            color: viewModel.invoicePageSize == size
                                ? AppTheme.primaryLight
                                : AppTheme.textMuted,
                            size: 22,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            size == 'Thermal80' ? '80mm\nThermal' : size,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: viewModel.invoicePageSize == size
                                  ? AppTheme.primaryLight
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // ── SECTION 3: Margins ────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Print Margins (mm)', style: sectionLabel),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MarginField(
                  label: 'Top / Bottom',
                  controller: _marginTBController,
                  onSave: (val) {
                    viewModel.setMargins(val, viewModel.marginLR);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MarginField(
                  label: 'Left / Right',
                  controller: _marginLRController,
                  onSave: (val) {
                    viewModel.setMargins(viewModel.marginTB, val);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── SECTION 4: Content Toggles ────────────────────────────────────
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Invoice Content', style: sectionLabel),
            ],
          ),
          const SizedBox(height: 12),

          _ToggleRow(
            label: 'Show Shop Header Branding',
            subtitle: 'Business name, address, phone on every invoice',
            value: viewModel.showHeader,
            onChanged: (v) => viewModel.setShowHeader(v),
          ),
          const SizedBox(height: 10),
          _ToggleRow(
            label: 'Show UPI QR Code',
            subtitle: 'Scan-to-pay QR printed at the bottom',
            value: viewModel.showQr,
            onChanged: (v) => viewModel.setShowQr(v),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Numeric text field for margin input with on-submit save.
class _MarginField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final void Function(double) onSave;

  const _MarginField({
    required this.label,
    required this.controller,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'mm',
        suffixStyle:
            const TextStyle(color: AppTheme.textMuted, fontSize: 12),
      ),
      onSubmitted: (val) {
        final d = double.tryParse(val);
        if (d != null) onSave(d);
      },
      onEditingComplete: () {
        final d = double.tryParse(controller.text);
        if (d != null) onSave(d);
      },
    );
  }
}

/// Toggle row that matches the app's dark-glass aesthetic.
class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primaryLight,
            activeTrackColor: AppTheme.primaryLight.withOpacity(0.25),
            inactiveThumbColor: AppTheme.textMuted,
            inactiveTrackColor: Colors.white.withOpacity(0.08),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shop_management_flutter/data/services/google_drive_upload_service.dart';
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
  late final TextEditingController _scriptUrlController;
  late final TextEditingController _folderIdController;

  @override
  void initState() {
    super.initState();
    _scriptUrlController = TextEditingController(
      text: GoogleDriveUploadService.appsScriptUrl ?? '',
    );
    _folderIdController = TextEditingController(
      text: GoogleDriveUploadService.driveFolderId ?? '',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsViewModel>().loadSettings();
    });
  }

  @override
  void dispose() {
    _upiController.dispose();
    _scriptUrlController.dispose();
    _folderIdController.dispose();
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
                    'Google Drive photo cloud, UPI payment configuration, & app preferences',
              ),

              // Responsive Cards Layout
              isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildUpiCard(context, viewModel)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildLayoutCard(context)),
                      ],
                    )
                  : Column(
                      children: [
                        _buildMobileUserLogoutCard(context),
                        const SizedBox(height: 20),
                        _buildUpiCard(context, viewModel),
                        const SizedBox(height: 20),
                        _buildLayoutCard(context),
                      ],
                    ),
            ],
          ),
        );
      },
    );
  }

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
                        color: (isPureAdmin ? AppTheme.primaryLight : (user.isAdmin ? AppTheme.success : AppTheme.warning)).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isPureAdmin ? 'Permanent Admin' : user.role.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isPureAdmin ? AppTheme.primaryLight : (user.isAdmin ? AppTheme.success : AppTheme.warning),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

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

          // Add UPI Input Field
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

          // Registered List
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
                                          color: AppTheme.success.withOpacity(
                                            0.9,
                                          ),
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
        ],
      ),
    );
  }

  Widget _buildLayoutCard(BuildContext context) {
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
                  color: AppTheme.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.print_rounded,
                  color: AppTheme.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Layout & Page Configuration',
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
            'Configure layout constraints and invoice prints page sizes. Layouts are optimized for physical printing systems.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // Paper size selector
          const Text(
            'Print Paper Format',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        color: AppTheme.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'A5 Portrait Page',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DEFAULT SELECTED',
                    style: TextStyle(
                      color: AppTheme.secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Print parameters list
          const Text(
            'Default Print Margins & Settings',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Column(
            children: [
              _PrintParameterRow(
                label: 'Top / Bottom Margins',
                value: '10 mm (Compact)',
              ),
              _PrintParameterRow(
                label: 'Left / Right Margins',
                value: '10 mm (Compact)',
              ),
              _PrintParameterRow(
                label: 'Include Shop Header Branding',
                value: 'Yes',
              ),
              _PrintParameterRow(
                label: 'Include Dynamic UPI QR Code',
                value: 'Yes',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // User Management & Access Control Tile
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
                          onPressed: UserPermissionService.canPerformModuleAction(
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
                          icon: const Icon(
                            Icons.manage_accounts_rounded,
                            size: 18,
                          ),
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
                        onPressed: UserPermissionService.canPerformModuleAction(
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
                        icon: const Icon(
                          Icons.manage_accounts_rounded,
                          size: 18,
                        ),
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
}

class _PrintParameterRow extends StatelessWidget {
  final String label;
  final String value;

  const _PrintParameterRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

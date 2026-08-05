import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../data/models/app_user.dart';
import '../../../../data/services/supabase_sync_service.dart';
import '../../../../data/services/user_permission_service.dart';
import '../../../../ui/core/app_theme.dart';
import '../../../shared/status_management_dialog.dart';
import '../../auth/view_models/auth_view_model.dart';

class UserManagementView extends StatefulWidget {
  const UserManagementView({super.key});

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  List<AppUser> _users = [];
  late AppUser _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    SupabaseSyncService.instance.addListener(_loadUsers);
  }

  @override
  void dispose() {
    SupabaseSyncService.instance.removeListener(_loadUsers);
    super.dispose();
  }

  void _loadUsers() {
    if (!mounted) return;
    setState(() {
      _users = UserPermissionService.getAllUsers();
      _currentUser = UserPermissionService.getCurrentUser();
    });
  }

  void _showAddEditUserPage([AppUser? existingUser]) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    if (isMobile) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => _UserPermissionsPage(
            existingUser: existingUser,
            onSaved: _loadUsers,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _UserPermissionsDialog(
          existingUser: existingUser,
          onSaved: _loadUsers,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1524),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131A2E),
        title: Text(
          isMobile ? 'Users & Permissions' : 'User Management & Permissions',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.person_add_alt_1_rounded,
              color: AppTheme.primaryLight,
            ),
            onPressed: () => _showAddEditUserPage(),
            tooltip: 'Add New Employee User',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Active User Switcher Banner ─────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF161A23),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryLight.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active Logged-In User Context',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.account_circle_rounded,
                        color: AppTheme.primaryLight,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentUser.name,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _currentUser.email,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Use PopupMenuButton to avoid unbounded dropdown overflow
                      PopupMenuButton<String>(
                        tooltip: 'Switch User',
                        color: const Color(0xFF131A2E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.primaryLight.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.swap_horiz_rounded,
                                color: AppTheme.primaryLight,
                                size: 18,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Switch',
                                style: TextStyle(
                                  color: AppTheme.primaryLight,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        itemBuilder: (ctx) => _users
                            .map(
                              (u) => PopupMenuItem<String>(
                                value: u.email,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      u.name,
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '${u.email} · ${u.role}',
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onSelected: (val) async {
                          await UserPermissionService.setCurrentUser(val);
                          _loadUsers();
                          if (context.mounted) {
                            try {
                              context.read<AuthViewModel>().notifyPermissionChanged();
                            } catch (_) {}
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Section Header ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Configured App Users',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddEditUserPage(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add User'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Users List ──────────────────────────────────────────────
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
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
                          color: user.isAdmin
                              ? AppTheme.primaryLight
                              : AppTheme.textMuted,
                          size: 20,
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
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
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
                                    color: user.isAdmin
                                        ? AppTheme.primary.withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    user.role.toUpperCase(),
                                    style: TextStyle(
                                      color: user.isAdmin
                                          ? AppTheme.primaryLight
                                          : AppTheme.textMuted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.email,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit_rounded,
                          color: AppTheme.primaryLight,
                          size: 20,
                        ),
                        onPressed: () => _showAddEditUserPage(user),
                        tooltip: 'Configure Permissions',
                        visualDensity: VisualDensity.compact,
                      ),
                      if (!user.isAdmin)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppTheme.danger,
                            size: 20,
                          ),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF131A2E),
                                title: const Text(
                                  'Delete User?',
                                  style: TextStyle(color: AppTheme.textPrimary),
                                ),
                                content: Text(
                                  'Remove "${user.name}" permanently?',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text(
                                      'Delete',
                                      style:
                                          TextStyle(color: AppTheme.danger),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await UserPermissionService.deleteUser(
                                user.email,
                              );
                              _loadUsers();
                            }
                          },
                          tooltip: 'Delete User',
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-Screen Page for Mobile (Add / Edit User)
// ─────────────────────────────────────────────────────────────────────────────

class _UserPermissionsPage extends StatefulWidget {
  final AppUser? existingUser;
  final VoidCallback onSaved;

  const _UserPermissionsPage({this.existingUser, required this.onSaved});

  @override
  State<_UserPermissionsPage> createState() => _UserPermissionsPageState();
}

class _UserPermissionsPageState extends State<_UserPermissionsPage>
    with _UserPermissionsLogic<_UserPermissionsPage> {
  @override
  void initState() {
    super.initState();
    initPermissions(widget.existingUser);
  }

  @override
  void dispose() {
    disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1524),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131A2E),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.existingUser != null ? 'Edit User' : 'Add New User',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => saveUser(
              existingUser: widget.existingUser,
              onSaved: widget.onSaved,
              context: context,
            ),
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryLight,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ],
      ),
      body: Form(
        key: formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── User Info Section ─────────────────────────────────
                  _SectionLabel(label: 'User Information'),
                  const SizedBox(height: 10),

                  // Name field
                  TextFormField(
                    controller: nameController,
                    enabled: widget.existingUser == null ||
                        widget.existingUser?.email !=
                            'admin@perfectsolution.com',
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: _inputDec('Full Name *'),
                    validator: (val) =>
                        val == null || val.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),

                  // Email field
                  TextFormField(
                    controller: emailController,
                    enabled: widget.existingUser == null,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    keyboardType: TextInputType.emailAddress,
                    decoration: _inputDec('Email ID (Login Identifier) *'),
                    validator: (val) =>
                        val == null || val.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),

                  // Password field
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: _inputDec('Password *'),
                    validator: (val) {
                      if (widget.existingUser == null &&
                          (val == null || val.trim().isEmpty)) {
                        return 'Password required for new user';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Role picker
                  DropdownButtonFormField<String>(
                    value: role,
                    isExpanded: true,
                    decoration: _inputDec('Role Type'),
                    dropdownColor: const Color(0xFF131A2E),
                    items: const [
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text(
                          'Admin (Full Control)',
                          style: TextStyle(color: AppTheme.textPrimary),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'employee',
                        child: Text(
                          'Employee (Custom Rules)',
                          style: TextStyle(color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => role = val);
                    },
                  ),

                  if (role == 'employee') ...[
                    const SizedBox(height: 20),

                    // ── Quick Presets ─────────────────────────────────
                    _SectionLabel(label: 'Quick Presets'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildPresetChip(
                            'Full Access', 'full', AppTheme.success),
                        _buildPresetChip('Standard Staff', 'standard',
                            AppTheme.primaryLight),
                        _buildPresetChip(
                            'View Only', 'readonly', AppTheme.warning),
                        _buildPresetChip('Hide Financials', 'hide_financials',
                            AppTheme.danger),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Module Permissions ────────────────────────────
                    _SectionLabel(label: 'Module Permissions'),
                    const SizedBox(height: 10),
                    ...AppUser.modules.map((moduleKey) {
                      return _buildMobileModuleTile(moduleKey);
                    }),
                  ] else ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryLight.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            color: AppTheme.primaryLight,
                            size: 36,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Administrator Account',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Admin users have unrestricted access to all pages, actions, and columns.',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),

            // ── Bottom Save Bar ─────────────────────────────────────────
            Container(
              color: const Color(0xFF131A2E),
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                12 + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => saveUser(
                    existingUser: widget.existingUser,
                    onSaved: widget.onSaved,
                    context: context,
                  ),
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text(
                    'Save User Permissions',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileModuleTile(String moduleKey) {
    final moduleLabel = AppUser.moduleLabels[moduleKey] ?? moduleKey;
    final isPageEnabled = pageAccess[moduleKey] ?? false;
    final isExpanded = expandedModuleKey == moduleKey;
    final subTab = activeSubTab[moduleKey] ?? 'actions';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isExpanded
            ? const Color(0xFF161E33)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpanded
              ? AppTheme.primaryLight.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          // Module header row
          InkWell(
            onTap: () {
              setState(() {
                expandedModuleKey =
                    isExpanded ? '' : moduleKey;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Icon(
                    getModuleIcon(moduleKey),
                    color: isPageEnabled
                        ? AppTheme.primaryLight
                        : AppTheme.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      moduleLabel,
                      style: TextStyle(
                        color: isPageEnabled
                            ? AppTheme.textPrimary
                            : AppTheme.textMuted,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isPageEnabled
                          ? AppTheme.success.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isPageEnabled ? 'ENABLED' : 'DISABLED',
                      style: TextStyle(
                        color: isPageEnabled
                            ? AppTheme.success
                            : AppTheme.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: isPageEnabled,
                    activeThumbColor: AppTheme.primaryLight,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) {
                      setState(() {
                        pageAccess[moduleKey] = val;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          if (isExpanded && isPageEnabled) ...[
            const Divider(height: 1, color: Colors.white10),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sub-tab buttons — wrapped for mobile
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildSubTabButton(
                        moduleKey,
                        'actions',
                        'Actions',
                        Icons.touch_app_rounded,
                        subTab == 'actions',
                      ),
                      _buildSubTabButton(
                        moduleKey,
                        'fields',
                        'Columns',
                        Icons.table_chart_rounded,
                        subTab == 'fields',
                      ),
                      if (moduleKey != 'pricelist' &&
                          moduleKey != 'settings')
                        _buildSubTabButton(
                          moduleKey,
                          'statuses',
                          'Status',
                          Icons.low_priority_rounded,
                          subTab == 'statuses',
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (subTab == 'actions')
                    buildModuleActionsGrid(moduleKey)
                  else if (subTab == 'fields')
                    buildModuleFieldsMatrix(moduleKey)
                  else
                    buildModuleStatusPermissionsMatrix(moduleKey),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog for Desktop (unchanged behavior)
// ─────────────────────────────────────────────────────────────────────────────

class _UserPermissionsDialog extends StatefulWidget {
  final AppUser? existingUser;
  final VoidCallback onSaved;

  const _UserPermissionsDialog({this.existingUser, required this.onSaved});

  @override
  State<_UserPermissionsDialog> createState() => _UserPermissionsDialogState();
}

class _UserPermissionsDialogState extends State<_UserPermissionsDialog>
    with _UserPermissionsLogic<_UserPermissionsDialog> {
  @override
  void initState() {
    super.initState();
    initPermissions(widget.existingUser);
  }

  @override
  void dispose() {
    disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      backgroundColor: const Color(0xFF131A2E),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: screenWidth * 0.92,
        constraints: const BoxConstraints(maxWidth: 850, maxHeight: 800),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title & Close Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: AppTheme.primaryLight,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.existingUser != null
                                ? 'Configure User Permissions & Column Access'
                                : 'Add New Employee User',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Control page actions & column visibility/editability per user',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Basic Info Fields (Name, Email, Role) — 4-col row for desktop
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: nameController,
                      enabled: widget.existingUser == null ||
                          widget.existingUser?.email !=
                              'admin@perfectsolution.com',
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Employee Name *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: emailController,
                      enabled: widget.existingUser == null,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Email ID (Login Identifier) *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'User Password (Secret Key) *',
                        hintText: 'Enter login password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (widget.existingUser == null &&
                            (val == null || val.trim().isEmpty)) {
                          return 'Password required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: role,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Role Type',
                        border: OutlineInputBorder(),
                      ),
                      dropdownColor: const Color(0xFF131A2E),
                      items: const [
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('Admin (Full Control)',
                              style:
                                  TextStyle(color: AppTheme.textPrimary)),
                        ),
                        DropdownMenuItem(
                          value: 'employee',
                          child: Text('Employee (Custom Rules)',
                              style:
                                  TextStyle(color: AppTheme.textPrimary)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => role = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (role == 'employee') ...[
                // Global Presets Toolbar
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF182238),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Quick Presets:',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildPresetChip(
                              'Full Access', 'full', AppTheme.success),
                          _buildPresetChip('Standard Staff', 'standard',
                              AppTheme.primaryLight),
                          _buildPresetChip(
                              'View Only', 'readonly', AppTheme.warning),
                          _buildPresetChip('Hide Financials',
                              'hide_financials', AppTheme.danger),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: ListView.builder(
                    itemCount: AppUser.modules.length,
                    itemBuilder: (context, index) {
                      final moduleKey = AppUser.modules[index];
                      final moduleLabel =
                          AppUser.moduleLabels[moduleKey] ?? moduleKey;
                      final isPageEnabled = pageAccess[moduleKey] ?? false;
                      final isExp = expandedModuleKey == moduleKey;
                      final subTab = activeSubTab[moduleKey] ?? 'actions';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isExp
                              ? const Color(0xFF161E33)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isExp
                                ? AppTheme.primaryLight
                                    .withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: ExpansionTile(
                          key: Key('module_tile_$moduleKey'),
                          initiallyExpanded: isExp,
                          onExpansionChanged: (expanded) {
                            if (expanded) {
                              setState(() => expandedModuleKey = moduleKey);
                            }
                          },
                          leading: Icon(
                            getModuleIcon(moduleKey),
                            color: isPageEnabled
                                ? AppTheme.primaryLight
                                : AppTheme.textMuted,
                          ),
                          title: Row(
                            children: [
                              Text(
                                moduleLabel,
                                style: TextStyle(
                                  color: isPageEnabled
                                      ? AppTheme.textPrimary
                                      : AppTheme.textMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPageEnabled
                                      ? AppTheme.success
                                          .withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isPageEnabled ? 'ENABLED' : 'DISABLED',
                                  style: TextStyle(
                                    color: isPageEnabled
                                        ? AppTheme.success
                                        : AppTheme.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Switch(
                            value: isPageEnabled,
                            activeThumbColor: AppTheme.primaryLight,
                            onChanged: (val) {
                              setState(() {
                                pageAccess[moduleKey] = val;
                              });
                            },
                          ),
                          children: [
                            if (isPageEnabled)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Divider(color: Colors.white10),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _buildSubTabButton(
                                          moduleKey,
                                          'actions',
                                          'Actions',
                                          Icons.touch_app_rounded,
                                          subTab == 'actions',
                                        ),
                                        const SizedBox(width: 8),
                                        _buildSubTabButton(
                                          moduleKey,
                                          'fields',
                                          'Columns',
                                          Icons.table_chart_rounded,
                                          subTab == 'fields',
                                        ),
                                        if (moduleKey != 'pricelist' &&
                                            moduleKey != 'settings') ...[
                                          const SizedBox(width: 8),
                                          _buildSubTabButton(
                                            moduleKey,
                                            'statuses',
                                            'Status Access & Edits',
                                            Icons.low_priority_rounded,
                                            subTab == 'statuses',
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    if (subTab == 'actions')
                                      buildModuleActionsGrid(moduleKey)
                                    else if (subTab == 'fields')
                                      buildModuleFieldsMatrix(moduleKey)
                                    else
                                      buildModuleStatusPermissionsMatrix(
                                          moduleKey),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ] else
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          color: AppTheme.primaryLight,
                          size: 48,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Administrator Account',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Admin users automatically have unrestricted access to all pages, actions, and columns.',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => saveUser(
                      existingUser: widget.existingUser,
                      onSaved: widget.onSaved,
                      context: context,
                    ),
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('Save User Permissions'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Logic Mixin (avoids code duplication between Page & Dialog)
// ─────────────────────────────────────────────────────────────────────────────

mixin _UserPermissionsLogic<T extends StatefulWidget> on State<T> {
  final formKey = GlobalKey<FormState>();
  late TextEditingController nameController;
  late TextEditingController emailController;
  late TextEditingController passwordController;
  late String role;
  late bool isActive;
  late Map<String, bool> pageAccess;
  late Map<String, bool> actionAccess;
  late Map<String, Map<String, bool>> pageActionAccess;
  late Map<String, Map<String, FieldPermission>> fieldAccess;
  late Map<String, List<String>> statusVisibilityAccess;
  late Map<String, List<String>> statusSelectableAccess;

  String expandedModuleKey = 'inward';
  final Map<String, String> activeSubTab = {};

  void initPermissions(AppUser? u) {
    nameController = TextEditingController(text: u?.name ?? '');
    emailController = TextEditingController(text: u?.email ?? '');
    passwordController = TextEditingController(text: u?.password ?? '');
    role = u?.role ?? 'employee';
    isActive = u?.isActive ?? true;

    pageAccess = u != null
        ? Map.from(u.pageAccess)
        : {for (var m in AppUser.modules) m: m != 'settings'};

    actionAccess = u != null ? Map.from(u.actionAccess) : {};

    pageActionAccess = u != null
        ? {
            for (var entry in u.pageActionAccess.entries)
              entry.key: Map<String, bool>.from(entry.value)
          }
        : {
            for (var m in AppUser.modules)
              m: {
                for (var act in (AppUser.moduleActions[m] ?? {}).keys)
                  act: act != 'canDelete' && act != 'canManageUsers'
              }
          };

    fieldAccess = u != null
        ? {
            for (var entry in u.fieldAccess.entries)
              entry.key: {
                for (var fEntry in entry.value.entries)
                  fEntry.key: fEntry.value.copyWith()
              }
          }
        : {
            for (var m in AppUser.modules)
              m: {
                for (var f in (AppUser.moduleFields[m] ?? {}).keys)
                  f: FieldPermission.allTrue()
              }
          };

    statusVisibilityAccess = u != null
        ? {
            for (var entry in u.statusVisibilityAccess.entries)
              entry.key: List<String>.from(entry.value)
          }
        : {for (var m in AppUser.modules) m: ['*']};

    statusSelectableAccess = u != null
        ? {
            for (var entry in u.statusSelectableAccess.entries)
              entry.key: List<String>.from(entry.value)
          }
        : {for (var m in AppUser.modules) m: ['*']};

    for (var m in AppUser.modules) {
      activeSubTab[m] = 'actions';
    }
  }

  void disposeControllers() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
  }

  void saveUser({
    required AppUser? existingUser,
    required VoidCallback onSaved,
    required BuildContext context,
  }) async {
    if (!formKey.currentState!.validate()) return;

    final user = AppUser(
      email: emailController.text.trim().toLowerCase(),
      name: nameController.text.trim(),
      role: role,
      isActive: isActive,
      password: passwordController.text.trim().isNotEmpty
          ? passwordController.text.trim()
          : existingUser?.password,
      pageAccess: pageAccess,
      actionAccess: actionAccess,
      pageActionAccess: pageActionAccess,
      fieldAccess: fieldAccess,
      statusVisibilityAccess: statusVisibilityAccess,
      statusSelectableAccess: statusSelectableAccess,
    );

    await UserPermissionService.saveUser(user);
    onSaved();
    if (context.mounted) Navigator.pop(context);
  }

  IconData getModuleIcon(String moduleKey) {
    switch (moduleKey) {
      case 'inward':
        return Icons.build_rounded;
      case 'calls':
        return Icons.phone_callback_rounded;
      case 'replacements':
        return Icons.swap_horiz_rounded;
      case 'requests':
        return Icons.help_outline_rounded;
      case 'purchases':
        return Icons.shopping_cart_rounded;
      case 'sales':
        return Icons.receipt_long_rounded;
      case 'pricelist':
        return Icons.inventory_2_rounded;
      case 'settings':
        return Icons.tune_rounded;
      default:
        return Icons.folder_rounded;
    }
  }

  Widget _buildPresetChip(String label, String key, Color color) {
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      onPressed: () => _applyPreset(key),
    );
  }

  void _applyPreset(String preset) {
    setState(() {
      if (preset == 'full') {
        for (var m in AppUser.modules) {
          pageAccess[m] = true;
          final actions = AppUser.moduleActions[m] ?? {};
          pageActionAccess[m] = {for (var k in actions.keys) k: true};
          final fields = AppUser.moduleFields[m] ?? {};
          fieldAccess[m] = {
            for (var f in fields.keys) f: FieldPermission.allTrue()
          };
        }
      } else if (preset == 'standard') {
        for (var m in AppUser.modules) {
          pageAccess[m] = m != 'settings';
          final actions = AppUser.moduleActions[m] ?? {};
          pageActionAccess[m] = {
            for (var k in actions.keys)
              k: k != 'canDelete' &&
                  k != 'canManageUsers' &&
                  k != 'canManageSync'
          };
          final fields = AppUser.moduleFields[m] ?? {};
          fieldAccess[m] = {
            for (var f in fields.keys) f: FieldPermission.allTrue()
          };
        }
      } else if (preset == 'readonly') {
        for (var m in AppUser.modules) {
          pageAccess[m] = m != 'settings';
          final actions = AppUser.moduleActions[m] ?? {};
          pageActionAccess[m] = {
            for (var k in actions.keys)
              k: k == 'canView' || k == 'canPrint'
          };
          final fields = AppUser.moduleFields[m] ?? {};
          fieldAccess[m] = {
            for (var f in fields.keys) f: FieldPermission.readOnly()
          };
        }
      } else if (preset == 'hide_financials') {
        final sensitiveFields = [
          'estimate',
          'estimateItems',
          'cashPrice',
          'inclGstPrice',
          'totalAmount',
          'advance',
          'discount'
        ];
        for (var m in AppUser.modules) {
          final fields = AppUser.moduleFields[m] ?? {};
          final current = fieldAccess[m] ?? {};
          for (var f in fields.keys) {
            if (sensitiveFields.contains(f)) {
              current[f] = FieldPermission.hidden();
            }
          }
          fieldAccess[m] = current;
        }
      }
    });
  }

  Widget _buildSubTabButton(
    String moduleKey,
    String tabKey,
    String label,
    IconData icon,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () {
        setState(() {
          activeSubTab[moduleKey] = tabKey;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryLight
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color:
                  isSelected ? AppTheme.primaryLight : AppTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? AppTheme.textPrimary
                    : AppTheme.textMuted,
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildModuleActionsGrid(String moduleKey) {
    final availableActions = AppUser.moduleActions[moduleKey] ?? {};
    final activeActions = pageActionAccess[moduleKey] ?? {};

    return Column(
      children: availableActions.entries.map((e) {
        final actionKey = e.key;
        final actionLabel = e.value;
        final isAllowed = activeActions[actionKey] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isAllowed
                ? AppTheme.primary.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isAllowed
                  ? AppTheme.primaryLight.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    color: isAllowed
                        ? AppTheme.textPrimary
                        : AppTheme.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
              Switch(
                value: isAllowed,
                activeThumbColor: AppTheme.primaryLight,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (val) {
                  setState(() {
                    pageActionAccess[moduleKey] ??= {};
                    pageActionAccess[moduleKey]![actionKey] = val;
                  });
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget buildModuleFieldsMatrix(String moduleKey) {
    final availableFields = AppUser.moduleFields[moduleKey] ?? {};
    final fieldPerms = fieldAccess[moduleKey] ?? {};

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1524),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Field',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Visible',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Add',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Edit',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),

          ...availableFields.entries.map((e) {
            final fieldKey = e.key;
            final fieldLabel = e.value;
            final perm =
                fieldPerms[fieldKey] ?? FieldPermission.allTrue();

            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      fieldLabel,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Checkbox(
                        value: perm.visible,
                        activeColor: AppTheme.primaryLight,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onChanged: (val) {
                          setState(() {
                            fieldAccess[moduleKey] ??= {};
                            fieldAccess[moduleKey]![fieldKey] =
                                perm.copyWith(visible: val ?? true);
                          });
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Checkbox(
                        value: perm.creatable,
                        activeColor: AppTheme.primaryLight,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onChanged: (val) {
                          setState(() {
                            fieldAccess[moduleKey] ??= {};
                            fieldAccess[moduleKey]![fieldKey] =
                                perm.copyWith(creatable: val ?? true);
                          });
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Checkbox(
                        value: perm.editable,
                        activeColor: AppTheme.primaryLight,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onChanged: (val) {
                          setState(() {
                            fieldAccess[moduleKey] ??= {};
                            fieldAccess[moduleKey]![fieldKey] =
                                perm.copyWith(editable: val ?? true);
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildQuickStatusActionChip(
    String label,
    bool isActive,
    VoidCallback onPressed,
  ) {
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          color: isActive ? AppTheme.success : AppTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: isActive
          ? AppTheme.success.withValues(alpha: 0.15)
          : Colors.white.withValues(alpha: 0.04),
      side: BorderSide(
        color: isActive
            ? AppTheme.success.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.1),
      ),
      onPressed: onPressed,
    );
  }

  Widget buildModuleStatusPermissionsMatrix(String moduleKey) {
    final configuredStatuses =
        StatusManagementService.getStatuses(moduleKey);
    final currentVisibility = statusVisibilityAccess[moduleKey] ?? ['*'];
    final currentSelectable = statusSelectableAccess[moduleKey] ?? ['*'];

    final bool isVisAll =
        currentVisibility.isEmpty || currentVisibility.contains('*');
    final bool isSelAll =
        currentSelectable.isEmpty || currentSelectable.contains('*');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section 1: Visibility
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1524),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.visibility_rounded,
                    size: 16,
                    color: AppTheme.primaryLight,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Viewable Entry Statuses',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildQuickStatusActionChip(
                    'All',
                    isVisAll,
                    () {
                      setState(() {
                        statusVisibilityAccess[moduleKey] = ['*'];
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Unchecked statuses will be hidden from the list for this user.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: configuredStatuses.map((st) {
                  final bool isSelected = isVisAll ||
                      currentVisibility.any(
                        (s) => s.toLowerCase() == st.toLowerCase(),
                      );
                  return FilterChip(
                    label: Text(st,
                        style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    selectedColor:
                        AppTheme.primary.withValues(alpha: 0.25),
                    checkmarkColor: AppTheme.primaryLight,
                    backgroundColor:
                        Colors.white.withValues(alpha: 0.03),
                    side: BorderSide(
                      color: isSelected
                          ? AppTheme.primaryLight
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        List<String> list = isVisAll
                            ? List<String>.from(configuredStatuses)
                            : List<String>.from(currentVisibility);
                        list.remove('*');
                        if (selected) {
                          if (!list.any((s) =>
                              s.toLowerCase() == st.toLowerCase())) {
                            list.add(st);
                          }
                        } else {
                          list.removeWhere((s) =>
                              s.toLowerCase() == st.toLowerCase());
                        }
                        if (list.length == configuredStatuses.length ||
                            list.isEmpty) {
                          statusVisibilityAccess[moduleKey] = ['*'];
                        } else {
                          statusVisibilityAccess[moduleKey] = list;
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Section 2: Selectable Statuses
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1524),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.edit_note_rounded,
                    size: 16,
                    color: AppTheme.secondary,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Selectable Status Options',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildQuickStatusActionChip(
                    'All',
                    isSelAll,
                    () {
                      setState(() {
                        statusSelectableAccess[moduleKey] = ['*'];
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Status choices available to this user in dropdowns when editing.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: configuredStatuses.map((st) {
                  final bool isSelected = isSelAll ||
                      currentSelectable.any(
                        (s) => s.toLowerCase() == st.toLowerCase(),
                      );
                  return FilterChip(
                    label: Text(st,
                        style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    selectedColor:
                        AppTheme.secondary.withValues(alpha: 0.25),
                    checkmarkColor: AppTheme.secondary,
                    backgroundColor:
                        Colors.white.withValues(alpha: 0.03),
                    side: BorderSide(
                      color: isSelected
                          ? AppTheme.secondary
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        List<String> list = isSelAll
                            ? List<String>.from(configuredStatuses)
                            : List<String>.from(currentSelectable);
                        list.remove('*');
                        if (selected) {
                          if (!list.any((s) =>
                              s.toLowerCase() == st.toLowerCase())) {
                            list.add(st);
                          }
                        } else {
                          list.removeWhere((s) =>
                              s.toLowerCase() == st.toLowerCase());
                        }
                        if (list.length == configuredStatuses.length ||
                            list.isEmpty) {
                          statusSelectableAccess[moduleKey] = ['*'];
                        } else {
                          statusSelectableAccess[moduleKey] = list;
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppTheme.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );
  }
}

InputDecoration _inputDec(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppTheme.primaryLight),
    ),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.04),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

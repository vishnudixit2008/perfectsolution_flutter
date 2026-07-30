import 'package:flutter/material.dart';
import '../../../../data/models/app_user.dart';
import '../../../../data/services/user_permission_service.dart';
import '../../../../ui/core/app_theme.dart';
import '../../../shared/status_management_dialog.dart';

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
  }

  void _loadUsers() {
    setState(() {
      _users = UserPermissionService.getAllUsers();
      _currentUser = UserPermissionService.getCurrentUser();
    });
  }

  void _showAddEditUserDialog([AppUser? existingUser]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UserPermissionsDialog(
        existingUser: existingUser,
        onSaved: () {
          _loadUsers();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1524),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131A2E),
        title: const Text(
          'User Management & Permissions',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.person_add_alt_1_rounded,
              color: AppTheme.primaryLight,
            ),
            onPressed: () => _showAddEditUserDialog(),
            tooltip: 'Add New Employee User',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current User Switcher Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161A23),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryLight.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_circle_rounded,
                    color: AppTheme.primaryLight,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Logged-In User Context',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_currentUser.name} (${_currentUser.email})',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DropdownButton<String>(
                    value: _users.any((u) => u.email == _currentUser.email)
                        ? _currentUser.email
                        : (_users.isNotEmpty ? _users.first.email : null),
                    dropdownColor: const Color(0xFF131A2E),
                    underline: const SizedBox.shrink(),
                    icon: const Icon(
                      Icons.swap_horiz_rounded,
                      color: AppTheme.primaryLight,
                    ),
                    items: _users.map((u) => u.email).toSet().map((email) {
                      final u = _users.firstWhere((usr) => usr.email == email);
                      return DropdownMenuItem(
                        value: email,
                        child: Text(
                          '${u.name} (${u.role})',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) async {
                      if (val != null) {
                        await UserPermissionService.setCurrentUser(val);
                        _loadUsers();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

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
                  onPressed: () => _showAddEditUserDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add User'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Users list
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
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
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  user.name,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
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
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.email,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
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
                        onPressed: () => _showAddEditUserDialog(user),
                        tooltip: 'Configure Permissions',
                      ),
                      if (!user.isAdmin)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppTheme.danger,
                            size: 20,
                          ),
                          onPressed: () async {
                            await UserPermissionService.deleteUser(user.email);
                            _loadUsers();
                          },
                          tooltip: 'Delete User',
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

class _UserPermissionsDialog extends StatefulWidget {
  final AppUser? existingUser;
  final VoidCallback onSaved;

  const _UserPermissionsDialog({this.existingUser, required this.onSaved});

  @override
  State<_UserPermissionsDialog> createState() => _UserPermissionsDialogState();
}

class _UserPermissionsDialogState extends State<_UserPermissionsDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late String _role;
  late bool _isActive;
  late Map<String, bool> _pageAccess;
  late Map<String, bool> _actionAccess;
  late Map<String, Map<String, bool>> _pageActionAccess;
  late Map<String, Map<String, FieldPermission>> _fieldAccess;
  late Map<String, List<String>> _statusVisibilityAccess;
  late Map<String, List<String>> _statusSelectableAccess;

  String _expandedModuleKey = 'inward';
  final Map<String, String> _activeSubTab = {}; // 'actions', 'fields', or 'statuses'

  @override
  void initState() {
    super.initState();
    final u = widget.existingUser;
    _nameController = TextEditingController(text: u?.name ?? '');
    _emailController = TextEditingController(text: u?.email ?? '');
    _passwordController = TextEditingController(text: u?.password ?? '');
    _role = u?.role ?? 'employee';
    _isActive = u?.isActive ?? true;

    _pageAccess = u != null
        ? Map.from(u.pageAccess)
        : {for (var m in AppUser.modules) m: m != 'settings'};

    _actionAccess = u != null ? Map.from(u.actionAccess) : {};

    _pageActionAccess = u != null
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

    _fieldAccess = u != null
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

    _statusVisibilityAccess = u != null
        ? {
            for (var entry in u.statusVisibilityAccess.entries)
              entry.key: List<String>.from(entry.value)
          }
        : {for (var m in AppUser.modules) m: ['*']};

    _statusSelectableAccess = u != null
        ? {
            for (var entry in u.statusSelectableAccess.entries)
              entry.key: List<String>.from(entry.value)
          }
        : {for (var m in AppUser.modules) m: ['*']};

    for (var m in AppUser.modules) {
      _activeSubTab[m] = 'actions';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _applyPreset(String preset) {
    setState(() {
      if (preset == 'full') {
        for (var m in AppUser.modules) {
          _pageAccess[m] = true;
          final actions = AppUser.moduleActions[m] ?? {};
          _pageActionAccess[m] = {for (var k in actions.keys) k: true};
          final fields = AppUser.moduleFields[m] ?? {};
          _fieldAccess[m] = {for (var f in fields.keys) f: FieldPermission.allTrue()};
        }
      } else if (preset == 'standard') {
        for (var m in AppUser.modules) {
          _pageAccess[m] = m != 'settings';
          final actions = AppUser.moduleActions[m] ?? {};
          _pageActionAccess[m] = {
            for (var k in actions.keys)
              k: k != 'canDelete' && k != 'canManageUsers' && k != 'canManageSync'
          };
          final fields = AppUser.moduleFields[m] ?? {};
          _fieldAccess[m] = {for (var f in fields.keys) f: FieldPermission.allTrue()};
        }
      } else if (preset == 'readonly') {
        for (var m in AppUser.modules) {
          _pageAccess[m] = m != 'settings';
          final actions = AppUser.moduleActions[m] ?? {};
          _pageActionAccess[m] = {
            for (var k in actions.keys) k: k == 'canView' || k == 'canPrint'
          };
          final fields = AppUser.moduleFields[m] ?? {};
          _fieldAccess[m] = {for (var f in fields.keys) f: FieldPermission.readOnly()};
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
          final current = _fieldAccess[m] ?? {};
          for (var f in fields.keys) {
            if (sensitiveFields.contains(f)) {
              current[f] = FieldPermission.hidden();
            }
          }
          _fieldAccess[m] = current;
        }
      }
    });
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = AppUser(
      email: _emailController.text.trim().toLowerCase(),
      name: _nameController.text.trim(),
      role: _role,
      isActive: _isActive,
      password: _passwordController.text.trim().isNotEmpty
          ? _passwordController.text.trim()
          : widget.existingUser?.password,
      pageAccess: _pageAccess,
      actionAccess: _actionAccess,
      pageActionAccess: _pageActionAccess,
      fieldAccess: _fieldAccess,
      statusVisibilityAccess: _statusVisibilityAccess,
      statusSelectableAccess: _statusSelectableAccess,
    );

    await UserPermissionService.saveUser(user);
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  IconData _getModuleIcon(String moduleKey) {
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
          key: _formKey,
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
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Basic Info Fields (Name, Email, Role)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nameController,
                      enabled:
                          widget.existingUser == null ||
                          widget.existingUser?.email !=
                              'admin@perfectsolution.com',
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Employee Name *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _emailController,
                      enabled: widget.existingUser == null,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Email ID (Login Identifier) *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'User Password (Secret Key) *',
                        hintText: 'Enter login password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (widget.existingUser == null && (val == null || val.trim().isEmpty)) {
                          return 'Password required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _role,
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
                              style: TextStyle(color: AppTheme.textPrimary)),
                        ),
                        DropdownMenuItem(
                          value: 'employee',
                          child: Text('Employee (Custom Rules)',
                              style: TextStyle(color: AppTheme.textPrimary)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _role = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_role == 'employee') ...[
                // Global Presets Toolbar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF182238),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                          _buildPresetChip('Full Access', 'full', AppTheme.success),
                          _buildPresetChip('Standard Staff', 'standard', AppTheme.primaryLight),
                          _buildPresetChip('View Only', 'readonly', AppTheme.warning),
                          _buildPresetChip('Hide Financials', 'hide_financials', AppTheme.danger),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Main Permissions Editor (Module List with Accordions)
                Expanded(
                  child: ListView.builder(
                    itemCount: AppUser.modules.length,
                    itemBuilder: (context, index) {
                      final moduleKey = AppUser.modules[index];
                      final moduleLabel =
                          AppUser.moduleLabels[moduleKey] ?? moduleKey;
                      final isPageEnabled = _pageAccess[moduleKey] ?? false;
                      final isExpanded = _expandedModuleKey == moduleKey;
                      final subTab = _activeSubTab[moduleKey] ?? 'actions';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
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
                        child: ExpansionTile(
                          key: Key('module_tile_$moduleKey'),
                          initiallyExpanded: isExpanded,
                          onExpansionChanged: (expanded) {
                            if (expanded) {
                              setState(() => _expandedModuleKey = moduleKey);
                            }
                          },
                          leading: Icon(
                            _getModuleIcon(moduleKey),
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
                                      ? AppTheme.success.withValues(alpha: 0.2)
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
                                _pageAccess[moduleKey] = val;
                              });
                            },
                          ),
                          children: [
                            if (isPageEnabled)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Divider(color: Colors.white10),
                                    const SizedBox(height: 8),

                                     // Sub-Tab Switcher (Page Actions, Column Fields & Status Permissions)
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
                                         if (moduleKey != 'pricelist' && moduleKey != 'settings') ...[
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
                                       _buildModuleActionsGrid(moduleKey)
                                     else if (subTab == 'fields')
                                       _buildModuleFieldsMatrix(moduleKey)
                                     else
                                       _buildModuleStatusPermissionsMatrix(moduleKey),
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
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Bottom Action Buttons
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
                    onPressed: _save,
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
          _activeSubTab[moduleKey] = tabKey;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppTheme.primaryLight : AppTheme.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.textPrimary : AppTheme.textMuted,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleActionsGrid(String moduleKey) {
    final availableActions = AppUser.moduleActions[moduleKey] ?? {};
    final activeActions = _pageActionAccess[moduleKey] ?? {};

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: availableActions.entries.map((e) {
        final actionKey = e.key;
        final actionLabel = e.value;
        final isAllowed = activeActions[actionKey] ?? false;

        return SizedBox(
          width: 250,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                      fontSize: 12,
                    ),
                  ),
                ),
                Switch(
                  value: isAllowed,
                  activeThumbColor: AppTheme.primaryLight,
                  onChanged: (val) {
                    setState(() {
                      _pageActionAccess[moduleKey] ??= {};
                      _pageActionAccess[moduleKey]![actionKey] = val;
                    });
                  },
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildModuleFieldsMatrix(String moduleKey) {
    final availableFields = AppUser.moduleFields[moduleKey] ?? {};
    final fieldPerms = _fieldAccess[moduleKey] ?? {};

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    'Form Column / Field Name',
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
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Add Entry',
                    textAlign: TextAlign.center,
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
                    'Editable',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),

          // Field Rows
          ...availableFields.entries.map((e) {
            final fieldKey = e.key;
            final fieldLabel = e.value;
            final perm = fieldPerms[fieldKey] ?? FieldPermission.allTrue();

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
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
                        onChanged: (val) {
                          setState(() {
                            _fieldAccess[moduleKey] ??= {};
                            _fieldAccess[moduleKey]![fieldKey] = perm.copyWith(
                              visible: val ?? true,
                            );
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
                        onChanged: (val) {
                          setState(() {
                            _fieldAccess[moduleKey] ??= {};
                            _fieldAccess[moduleKey]![fieldKey] = perm.copyWith(
                              creatable: val ?? true,
                            );
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
                        onChanged: (val) {
                          setState(() {
                            _fieldAccess[moduleKey] ??= {};
                            _fieldAccess[moduleKey]![fieldKey] = perm.copyWith(
                              editable: val ?? true,
                            );
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

  Widget _buildModuleStatusPermissionsMatrix(String moduleKey) {
    final configuredStatuses = StatusManagementService.getStatuses(moduleKey);
    final currentVisibility = _statusVisibilityAccess[moduleKey] ?? ['*'];
    final currentSelectable = _statusSelectableAccess[moduleKey] ?? ['*'];

    final bool isVisAll =
        currentVisibility.isEmpty || currentVisibility.contains('*');
    final bool isSelAll =
        currentSelectable.isEmpty || currentSelectable.contains('*');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section 1: Entry Visibility Rules
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1524),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.visibility_rounded,
                    size: 18,
                    color: AppTheme.primaryLight,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '1. Viewable Entry Statuses (List & Search Visibility)',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildQuickStatusActionChip(
                    'All Statuses',
                    isVisAll,
                    () {
                      setState(() {
                        _statusVisibilityAccess[moduleKey] = ['*'];
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Unchecked status entries will be completely hidden from list view, search, and count totals for this user.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: configuredStatuses.map((st) {
                  final bool isSelected = isVisAll ||
                      currentVisibility.any(
                        (s) => s.toLowerCase() == st.toLowerCase(),
                      );

                  return FilterChip(
                    label: Text(st),
                    selected: isSelected,
                    selectedColor: AppTheme.primary.withValues(alpha: 0.25),
                    checkmarkColor: AppTheme.primaryLight,
                    backgroundColor: Colors.white.withValues(alpha: 0.03),
                    side: BorderSide(
                      color: isSelected
                          ? AppTheme.primaryLight
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        List<String> list = isVisAll
                            ? List<String>.from(configuredStatuses)
                            : List<String>.from(currentVisibility);
                        list.remove('*');
                        if (selected) {
                          if (!list.any(
                            (s) => s.toLowerCase() == st.toLowerCase(),
                          )) {
                            list.add(st);
                          }
                        } else {
                          list.removeWhere(
                            (s) => s.toLowerCase() == st.toLowerCase(),
                          );
                        }
                        if (list.length == configuredStatuses.length ||
                            list.isEmpty) {
                          _statusVisibilityAccess[moduleKey] = ['*'];
                        } else {
                          _statusVisibilityAccess[moduleKey] = list;
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Section 2: Allowed Selectable Statuses for Editing
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1524),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.edit_note_rounded,
                    size: 18,
                    color: AppTheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '2. Selectable Status Options (Edit & Status Change)',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildQuickStatusActionChip(
                    'All Statuses',
                    isSelAll,
                    () {
                      setState(() {
                        _statusSelectableAccess[moduleKey] = ['*'];
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Controls which status choices this user can pick in dropdowns when adding/editing a record or changing status.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: configuredStatuses.map((st) {
                  final bool isSelected = isSelAll ||
                      currentSelectable.any(
                        (s) => s.toLowerCase() == st.toLowerCase(),
                      );

                  return FilterChip(
                    label: Text(st),
                    selected: isSelected,
                    selectedColor: AppTheme.secondary.withValues(alpha: 0.25),
                    checkmarkColor: AppTheme.secondary,
                    backgroundColor: Colors.white.withValues(alpha: 0.03),
                    side: BorderSide(
                      color: isSelected
                          ? AppTheme.secondary
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        List<String> list = isSelAll
                            ? List<String>.from(configuredStatuses)
                            : List<String>.from(currentSelectable);
                        list.remove('*');
                        if (selected) {
                          if (!list.any(
                            (s) => s.toLowerCase() == st.toLowerCase(),
                          )) {
                            list.add(st);
                          }
                        } else {
                          list.removeWhere(
                            (s) => s.toLowerCase() == st.toLowerCase(),
                          );
                        }
                        if (list.length == configuredStatuses.length ||
                            list.isEmpty) {
                          _statusSelectableAccess[moduleKey] = ['*'];
                        } else {
                          _statusSelectableAccess[moduleKey] = list;
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


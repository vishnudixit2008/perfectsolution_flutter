import 'package:flutter/material.dart';
import '../../../shared/date_time_picker_field.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/call_model.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/supabase_sync_service.dart';
import '../../../../data/services/ui_preferences_service.dart';
import '../../../../data/services/whatsapp_service.dart';
import '../../../../ui/core/app_theme.dart';
import '../../calls/view_models/calls_view_model.dart';
import '../../../navigation/navigation_view_model.dart';
import '../../../shared/components/app_page_header.dart';
import '../../../shared/components/app_list_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_floating_action_button.dart';
import '../../../shared/components/app_header_sync_button.dart';
import '../../../shared/components/app_search_filter_bar.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../../../shared/resizable_detail_popup.dart';
import '../../../shared/status_management_dialog.dart';
import '../../../shared/whatsapp_icon.dart';
import '../../../../data/services/user_permission_service.dart';

class CallsView extends StatefulWidget {
  const CallsView({super.key});

  @override
  State<CallsView> createState() => _CallsViewState();
}

class _CallsViewState extends State<CallsView> {
  final TextEditingController _searchController = TextEditingController();

  // Table column widths for desktop (resizable, no ID column)
  double _dateWidth = 110.0;
  double _nameWidth = 180.0;
  double _mobileWidth = 130.0;
  double _queryWidth = 220.0;
  double _assignedWidth = 200.0;
  // ignore: unused_field
  double _statusWidth = 130.0;

  void _loadSavedColumnWidths() {
    _dateWidth = UiPreferencesService.getColumnWidth('calls', 'date') ?? 110.0;
    _nameWidth = UiPreferencesService.getColumnWidth('calls', 'name') ?? 180.0;
    _mobileWidth =
        UiPreferencesService.getColumnWidth('calls', 'mobile') ?? 130.0;
    _queryWidth =
        UiPreferencesService.getColumnWidth('calls', 'query') ?? 220.0;
    _assignedWidth =
        UiPreferencesService.getColumnWidth('calls', 'assigned') ?? 200.0;
    _statusWidth =
        UiPreferencesService.getColumnWidth('calls', 'status') ?? 130.0;
  }

  void _updateColumnWidth(String columnKey, double newWidth) {
    setState(() {
      switch (columnKey) {
        case 'date':
          _dateWidth = newWidth;
          break;
        case 'name':
          _nameWidth = newWidth;
          break;
        case 'mobile':
          _mobileWidth = newWidth;
          break;
        case 'query':
          _queryWidth = newWidth;
          break;
        case 'assigned':
          _assignedWidth = newWidth;
          break;
        case 'status':
          _statusWidth = newWidth;
          break;
      }
    });
    UiPreferencesService.setColumnWidth('calls', columnKey, newWidth);
  }

  String _selectedStatus = 'All';
  String _selectedAssigned = 'All';

  // Dynamic status list from StatusManagementService
  List<String> get _allStatuses => [
        'All',
        ...StatusManagementService.getStatuses('calls'),
      ];

  // Status priority for sorting (lower = shows first)
  // ignore: unused_element
  static int _statusPriority(String status) {
    switch (status.toLowerCase()) {
      case 'pre-complete':
        return 0;
      case 'pending':
        return 1;
      case 'pending payment':
        return 2;
      case 'complete':
        return 3;
      default:
        return 4;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedColumnWidths();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CallsViewModel>().loadCalls();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CallsViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading && viewModel.calls.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isDesktop = screenWidth >= 800;

        // Apply local filtering
        final query = _searchController.text.trim().toLowerCase();
        final filteredCalls = viewModel.calls.where((c) {
          if (!UserPermissionService.isStatusVisible('calls', c.status)) {
            return false;
          }
          final matchesSearch =
              c.name.toLowerCase().contains(query) ||
              (c.mobileNo?.toLowerCase().contains(query) ?? false) ||
              (c.query?.toLowerCase().contains(query) ?? false) ||
              (c.address?.toLowerCase().contains(query) ?? false) ||
              (c.assignedTo.toLowerCase().contains(query));

          bool matchesAssigned = true;
          if (_selectedAssigned == 'Unassigned') {
            matchesAssigned =
                c.assignedTo.trim().isEmpty || c.assignedTo.trim() == 'N/A';
          } else if (_selectedAssigned != 'All') {
            matchesAssigned =
                c.assignedTo.trim().toLowerCase() ==
                _selectedAssigned.trim().toLowerCase();
          }

          if (_selectedStatus == 'All') {
            return matchesSearch && matchesAssigned;
          }
          return matchesSearch &&
              matchesAssigned &&
              c.status.toLowerCase() == _selectedStatus.toLowerCase();
        }).toList();

        // Sort by ID descending (newest calls first)
        filteredCalls.sort((a, b) => b.id.compareTo(a.id));

        final groupedCalls = _getGroupedCalls(filteredCalls);

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: (!isDesktop && UserPermissionService.canPerformModuleAction('calls', 'canAdd'))
              ? AppFloatingActionButton(
                  onPressed: () => _showAddEditDialog(context),
                  tooltip: 'Log Call',
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: 'Calls',
                subtitle: 'Customer Support & Inquiries',
                actions: [
                  if (isDesktop && UserPermissionService.canPerformModuleAction('calls', 'canAdd'))
                    AppHeaderActionButton(
                      label: 'New Call',
                      icon: Icons.add_ic_call_rounded,
                      onPressed: () => _showAddEditDialog(context),
                    ),
                  if (!isDesktop)
                    AppHeaderSyncButton(
                      onSynced: () => context.read<CallsViewModel>().loadCalls(),
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () {
                      StatusManagementDialog.show(
                        context,
                        moduleKey: 'calls',
                        moduleTitle: 'Call',
                        onStatusesUpdated: () {
                          StatusManagementService.invalidateCache('calls');
                          context.read<CallsViewModel>().loadCalls();
                          setState(() {});
                        },
                      );
                    },
                    icon: const Icon(
                      Icons.low_priority_rounded,
                      color: AppTheme.primaryLight,
                      size: 20,
                    ),
                    tooltip: 'Manage & Reorder Statuses',
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),

              // Search & Filters
              if (isDesktop)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText:
                                'Search customer, mobile, query, staff...',
                            hintStyle: const TextStyle(fontSize: 12),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: AppTheme.textMuted,
                              size: 18,
                            ),
                            border: InputBorder.none,
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Status: ',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedStatus,
                              dropdownColor: const Color(0xFF0F1524),
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                              ),
                              items: _allStatuses.map((status) {
                                return DropdownMenuItem<String>(
                                  value: status,
                                  child: Text(status),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedStatus = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _selectedAssigned != 'All'
                            ? AppTheme.primary.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedAssigned != 'All'
                              ? AppTheme.primaryLight.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_search_rounded,
                            size: 16,
                            color: _selectedAssigned != 'All'
                                ? AppTheme.primaryLight
                                : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Assigned To: ',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedAssigned,
                              dropdownColor: const Color(0xFF0F1524),
                              style: TextStyle(
                                color: _selectedAssigned != 'All'
                                    ? AppTheme.primaryLight
                                    : AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: _selectedAssigned != 'All'
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              items: viewModel.availableAssignedPersons.map((a) {
                                return DropdownMenuItem<String>(
                                  value: a,
                                  child: Text(a),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedAssigned = val;
                                  });
                                  viewModel.setSelectedAssigned(val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                AppSearchFilterBar(
                  searchQuery: _searchController.text,
                  onSearchChanged: (q) => setState(() {
                    _searchController.text = q;
                  }),
                  hintText: 'Search calls, mobile, staff...',
                  activeFilterCount:
                      (_selectedStatus != 'All' ? 1 : 0) +
                      (_selectedAssigned != 'All' ? 1 : 0),
                  filterOptions: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Status',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedStatus,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1B243B),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textPrimary,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                              ),
                              items: _allStatuses.map((s) {
                                return DropdownMenuItem(
                                  value: s,
                                  child: Text(s),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedStatus = val;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Assigned',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedAssigned,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1B243B),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textPrimary,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                              ),
                              items: viewModel.availableAssignedPersons.map((
                                a,
                              ) {
                                return DropdownMenuItem(
                                  value: a,
                                  child: Text(a),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedAssigned = val;
                                  });
                                  viewModel.setSelectedAssigned(val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),

              // Table or cards list grouped by status
              Expanded(
                child: filteredCalls.isEmpty
                    ? _buildEmptyState()
                    : (isDesktop
                        ? _buildDesktopTable(
                            context,
                            viewModel,
                            groupedCalls,
                          )
                        : _buildMobileCardsList(
                            context,
                            viewModel,
                            groupedCalls,
                          )),
              ),
            ],
          ),
        );
      },
    );
  }

  Map<String, List<CallModel>> _getGroupedCalls(List<CallModel> calls) {
    final List<String> configuredStatuses =
        StatusManagementService.getStatuses('calls');
    final Map<String, List<CallModel>> grouped = {};

    for (final status in configuredStatuses) {
      grouped[status] = [];
    }

    for (final call in calls) {
      final statusName = call.status.trim();
      final existingKey = grouped.keys.firstWhere(
        (k) => k.toLowerCase() == statusName.toLowerCase(),
        orElse: () => '',
      );

      if (existingKey.isNotEmpty) {
        grouped[existingKey]!.add(call);
      } else {
        if (!grouped.containsKey(statusName)) {
          grouped[statusName] = [];
        }
        grouped[statusName]!.add(call);
      }
    }

    grouped.removeWhere((key, list) => list.isEmpty);
    return grouped;
  }

  Widget _buildStatusSectionHeader(String status, int count) {
    final Color color = _getStatusColor(status);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14, bottom: 8, left: 4, right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count ${count == 1 ? 'Call' : 'Calls'}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase().trim();
    if (s == 'laptop' || s == 'desktop') return const Color(0xFFEF4444); // Red
    if (s == 'ready return' || s == 'ready-return') return const Color(0xFFCA8A04); // Dull Yellow
    if (s == 'ready') return const Color(0xFFEAB308); // Yellow
    if (s.contains('hold')) return const Color(0xFF06B6D4); // Cyan
    if (s.contains('complete') || s.contains('pre complete') || s.contains('pre-complete')) {
      return const Color(0xFF10B981); // Green
    }
    if (s.contains('cancel') || s.contains('reject')) return const Color(0xFFEF4444);
    if (s.contains('pending')) return const Color(0xFFF97316);
    return const Color(0xFF6366F1);
  }

  Widget _buildEmptyState() {
    return AppEmptyState(
      icon: Icons.phone_callback_rounded,
      title: 'No Calls Found',
      message: 'No support calls match your search or filter criteria.',
      actionLabel: 'Log New Call',
      onAction: () => _showAddEditDialog(context),
    );
  }

  Widget _buildDesktopTable(
    BuildContext context,
    CallsViewModel viewModel,
    Map<String, List<CallModel>> groupedCalls,
  ) {
    final double totalWidth =
        _dateWidth +
        _nameWidth +
        _mobileWidth +
        _queryWidth +
        _assignedWidth;

    return Container(
      width: double.infinity,
      decoration: AppTheme.glassCardDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: 12,
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double tableWidth = constraints.maxWidth > totalWidth
              ? constraints.maxWidth
              : totalWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  // Table Headers (Status column removed - grouped under status headers)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildResizableHeader(
                          'Date',
                          _dateWidth,
                          (delta) => _updateColumnWidth(
                            'date',
                            (_dateWidth + delta).clamp(80.0, 200.0),
                          ),
                        ),
                        _buildResizableHeader(
                          'Customer Name',
                          _nameWidth,
                          (delta) => _updateColumnWidth(
                            'name',
                            (_nameWidth + delta).clamp(120.0, 400.0),
                          ),
                        ),
                        _buildResizableHeader(
                          'Mobile',
                          _mobileWidth,
                          (delta) => _updateColumnWidth(
                            'mobile',
                            (_mobileWidth + delta).clamp(100.0, 300.0),
                          ),
                        ),
                        _buildResizableHeader(
                          'Query',
                          _queryWidth,
                          (delta) => _updateColumnWidth(
                            'query',
                            (_queryWidth + delta).clamp(120.0, 500.0),
                          ),
                        ),
                        _buildResizableHeader(
                          'Assigned To',
                          _assignedWidth,
                          (delta) => _updateColumnWidth(
                            'assigned',
                            (_assignedWidth + delta).clamp(120.0, 400.0),
                          ),
                          onTapDown: (details) => _showAssignedFilterMenu(
                            context,
                            viewModel,
                            details.globalPosition,
                          ),
                          isFilterActive: _selectedAssigned != 'All',
                        ),
                      ],
                    ),
                  ),
                  // Scrollable Body grouped by Status
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in groupedCalls.entries) ...[
                            _buildStatusSectionHeader(entry.key, entry.value.length),
                            for (final call in entry.value) ...[
                              _buildDesktopTableRow(context, viewModel, call),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopTableRow(
    BuildContext context,
    CallsViewModel viewModel,
    CallModel call,
  ) {
    final formattedDate = DateFormat('dd/MM/yy').format(call.date);
    return InkWell(
      onTap: () => _showDetailPopup(context, call, viewModel),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: _dateWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(formattedDate),
            ),
            Container(
              width: _nameWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                call.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              width: _mobileWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(call.mobileNo ?? '-'),
            ),
            Container(
              width: _queryWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                call.query ?? '-',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: _assignedWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                call.assignedTo.trim().isEmpty ? 'Unassigned' : call.assignedTo,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignedFilterMenu(
    BuildContext context,
    CallsViewModel viewModel,
    Offset globalPosition,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xFF131A2E),
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: viewModel.availableAssignedPersons.map((person) {
        final isSelected = person == _selectedAssigned;
        return PopupMenuItem<String>(
          value: person,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.person_outline_rounded,
                size: 16,
                color: isSelected ? AppTheme.primaryLight : AppTheme.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                person,
                style: TextStyle(
                  color: isSelected ? AppTheme.primaryLight : AppTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );

    if (selected != null) {
      setState(() {
        _selectedAssigned = selected;
      });
      viewModel.setSelectedAssigned(selected);
    }
  }

  Widget _buildResizableHeader(
    String label,
    double currentWidth,
    ValueChanged<double> onResize, {
    void Function(TapDownDetails)? onTapDown,
    bool isFilterActive = false,
  }) {
    return Container(
      width: currentWidth,
      padding: const EdgeInsets.only(left: 16, right: 2, top: 12, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTapDown: onTapDown,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isFilterActive
                            ? AppTheme.primaryLight
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onTapDown != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 18,
                      color: isFilterActive
                          ? AppTheme.primaryLight
                          : AppTheme.textMuted,
                    ),
                  ],
                ],
              ),
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
              child: Container(
                width: 12,
                height: 20,
                alignment: Alignment.center,
                child: Container(
                  width: 1.5,
                  height: 14,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCardsList(
    BuildContext context,
    CallsViewModel viewModel,
    Map<String, List<CallModel>> groupedCalls,
  ) {
    return RefreshIndicator(
      color: AppTheme.primaryLight,
      backgroundColor: const Color(0xFF131A2E),
      onRefresh: () async {
        final localDb = context.read<ShopRepository>().localDb;
        await SupabaseSyncService.instance.syncAllTablesFromCloud(localDb);
        if (context.mounted) viewModel.loadCalls();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in groupedCalls.entries) ...[
              _buildStatusSectionHeader(entry.key, entry.value.length),
              for (final call in entry.value) ...[
                _buildMobileCallCard(context, viewModel, call),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCallCard(
    BuildContext context,
    CallsViewModel viewModel,
    CallModel call,
  ) {
    final formattedDate = DateFormat('dd MMM yyyy').format(call.date);
    final metadata = <Widget>[];

    if (call.mobileNo != null &&
        call.mobileNo!.trim().isNotEmpty &&
        call.mobileNo != 'N/A') {
      metadata.add(
        Row(
          children: [
            const Icon(
              Icons.phone_rounded,
              size: 13,
              color: AppTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              call.mobileNo!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (call.query != null &&
        call.query!.trim().isNotEmpty &&
        call.query != 'N/A') {
      if (metadata.isNotEmpty) metadata.add(const SizedBox(height: 4));
      metadata.add(
        Text(
          call.query!,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (metadata.isNotEmpty) metadata.add(const SizedBox(height: 6));
    metadata.add(
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            formattedDate,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );

    return AppListCard(
      title: call.name,
      statusBadge: _buildStatusChip(call.status),
      metadataRows: metadata,
      onTap: () => _showDetailPopup(context, call, viewModel),
      onEdit: () => _showAddEditDialog(context, existingCall: call),
      onDelete: () => _confirmDeleteCall(context, viewModel, call.id),
    );
  }



  void _confirmDeleteCall(
    BuildContext context,
    CallsViewModel viewModel,
    int id,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirm Delete',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to delete this call record?',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              viewModel.deleteCall(id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color chipColor;
    switch (status.toLowerCase()) {
      case 'complete':
        chipColor = AppTheme.success;
        break;
      case 'pre-complete':
        chipColor = const Color(0xFF2196F3);
        break;
      case 'pending payment':
        chipColor = const Color(0xFFFF9800);
        break;
      case 'pending':
        chipColor = AppTheme.warning;
        break;
      default:
        chipColor = AppTheme.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: chipColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: chipColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildFloatingPaginationIsland({
    required int currentPage,
    required int totalPages,
    required int itemsPerPage,
    required ValueChanged<int> onItemsPerPageChanged,
    required VoidCallback onPreviousPage,
    required VoidCallback onNextPage,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xE60F1524),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<int>(
            initialValue: itemsPerPage,
            tooltip: 'Rows per page',
            color: const Color(0xFF0F1524),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            onSelected: onItemsPerPageChanged,
            child: Row(
              children: [
                Text(
                  '$itemsPerPage',
                  style: const TextStyle(
                    color: AppTheme.primaryLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: AppTheme.textMuted,
                  size: 14,
                ),
              ],
            ),
            itemBuilder: (context) => [20, 50, 100].map((val) {
              return PopupMenuItem<int>(
                value: val,
                child: Text(
                  '$val rows',
                  style: TextStyle(
                    color: val == itemsPerPage
                        ? AppTheme.primaryLight
                        : AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: val == itemsPerPage
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 4),
          Container(
            height: 12,
            width: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: currentPage > 1 ? onPreviousPage : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            iconSize: 16,
            color: AppTheme.primaryLight,
            disabledColor: AppTheme.textMuted.withValues(alpha: 0.3),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              '$currentPage/$totalPages',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: currentPage < totalPages ? onNextPage : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            iconSize: 16,
            color: AppTheme.primaryLight,
            disabledColor: AppTheme.textMuted.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  // Opens the resizable detail popup for a call entry
  void _showDetailPopup(
    BuildContext context,
    CallModel call,
    CallsViewModel viewModel,
  ) {
    final repo = context.read<ShopRepository>();
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(call.date);

    ResizableDetailPopup.show(
      context: context,
      repository: repo,
      title: call.name,
      subtitle: 'Logged on $formattedDate',
      contentBuilder: (ctx, scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScaledInfoRow(
              label: 'Customer Name',
              value: call.name,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Mobile Number',
              value: call.mobileNo ?? 'N/A',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Address',
              value: call.address ?? 'N/A',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Query / Problem',
              value: call.query ?? 'N/A',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Assigned To',
              value: call.assignedTo,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Estimate Amount',
              value: call.estimate ?? 'N/A',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Status',
              value: call.status,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Notes',
              value: call.notes ?? 'N/A',
              scaleFactor: scale,
            ),
            if (call.photoList.isNotEmpty)
              PhotoGallerySection(photoUrls: call.photoList),
            SizedBox(height: 12 * scale),
            Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
            SizedBox(height: 12 * scale),
            // Action buttons
            Wrap(
              spacing: 8 * scale,
              runSpacing: 8 * scale,
              children: [
                ScaledActionButton(
                  icon: Icons.phone,
                  label: 'Call',
                  scaleFactor: scale,
                  onTap: () => _launchPhone(call.mobileNo ?? ''),
                ),
                ScaledActionButton(
                  iconWidget: WhatsAppIcon(size: 32 * scale),
                  label: 'WhatsApp',
                  scaleFactor: scale,
                  onTap: () => _launchWhatsApp(call),
                ),
                ScaledActionButton(
                  icon: Icons.copy,
                  label: 'Duplicate',
                  scaleFactor: scale,
                  onTap: () {
                    Navigator.pop(ctx);
                    _duplicateCall(context, call);
                  },
                ),
                ScaledActionButton(
                  icon: Icons.sell,
                  label: 'Convert to Sale',
                  scaleFactor: scale,
                  onTap: () => _convertToSale(ctx, call),
                ),
                ScaledActionButton(
                  icon: Icons.build,
                  label: 'Enter in Inward',
                  scaleFactor: scale,
                  onTap: () => _enterInModule(ctx, 'inward', call),
                ),
                ScaledActionButton(
                  icon: Icons.request_page,
                  label: 'Enter in Request',
                  scaleFactor: scale,
                  onTap: () => _enterInModule(ctx, 'request', call),
                ),
                ScaledActionButton(
                  icon: Icons.shopping_cart,
                  label: 'Enter in Purchase',
                  scaleFactor: scale,
                  onTap: () => _enterInModule(ctx, 'purchase', call),
                ),
              ],
            ),
          ],
        );
      },
      actionsBuilder: (ctx, scale) {
        final canEdit = UserPermissionService.canPerformModuleAction('calls', 'canEdit');
        final canDelete = UserPermissionService.canPerformModuleAction('calls', 'canDelete');

        return Row(
          children: [
            if (canEdit)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAddEditDialog(context, existingCall: call);
                  },
                  icon: Icon(Icons.edit_rounded, size: 16 * scale),
                  label: Text('Edit', style: TextStyle(fontSize: 13 * scale)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryLight,
                    side: BorderSide(
                      color: AppTheme.primaryLight.withValues(alpha: 0.3),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 10 * scale),
                  ),
                ),
              ),
            if (canEdit && canDelete) SizedBox(width: 12 * scale),
            if (canDelete)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    _deleteCall(context, viewModel, call.id);
                  },
                  icon: Icon(Icons.delete_rounded, size: 16 * scale),
                  label: Text('Delete', style: TextStyle(fontSize: 13 * scale)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: BorderSide(
                      color: AppTheme.danger.withValues(alpha: 0.3),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 10 * scale),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showAddEditDialog(BuildContext context, {CallModel? existingCall}) {
    final isEdit = existingCall != null;
    final actionKey = isEdit ? 'canEdit' : 'canAdd';
    if (!UserPermissionService.canPerformModuleAction('calls', actionKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEdit
                ? 'Access Denied: You do not have permission to edit Calls.'
                : 'Access Denied: You do not have permission to log new Calls.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CallFormDialog(existingCall: existingCall),
    );
  }

  void _deleteCall(
    BuildContext context,
    CallsViewModel viewModel,
    int id,
  ) async {
    if (!UserPermissionService.canPerformModuleAction('calls', 'canDelete')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to delete Calls.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131A2E),
        title: const Text(
          'Delete Call',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to delete this call record?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await viewModel.deleteCall(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call deleted successfully')),
        );
      }
    }
  }

  void _launchPhone(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _launchWhatsApp(CallModel call) {
    final mobileNo = call.mobileNo;
    if (mobileNo == null || mobileNo.trim().isEmpty) return;
    final message =
        'Hello ${call.name},\n\nGreetings from *Perfect Solution*!\n\nWe received your enquiry regarding "${call.query ?? 'your requirement'}". Our team will assist you shortly.\n\nThank you!\n~ Perfect Solution, Noida';
    WhatsAppService.launch(mobileNo: mobileNo, message: message);
  }

  void _duplicateCall(BuildContext context, CallModel call) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CallFormDialog(
        existingCall: null,
        prefillName: call.name,
        prefillMobile: call.mobileNo,
        prefillAddress: call.address,
        prefillQuery: call.query,
        prefillAssigned: call.assignedTo,
        prefillEstimate: call.estimate,
        prefillNotes: call.notes,
      ),
    );
  }

  void _enterInModule(BuildContext context, String module, CallModel call) {
    final navVM = context.read<NavigationViewModel>();
    Navigator.pop(context);

    if (module == 'purchase') {
      navVM.setIndex(
        NavigationViewModel.purchase,
        prefillData: {
          'target': 'purchase',
          'purchasedFrom': call.name,
          'mobileNo': call.mobileNo,
        },
      );
    } else if (module == 'request') {
      navVM.setIndex(
        NavigationViewModel.request,
        prefillData: {
          'target': 'request',
          'customerName': call.name,
          'mobileNo': call.mobileNo,
        },
      );
    } else if (module == 'inward') {
      navVM.setIndex(
        NavigationViewModel.inward,
        prefillData: {
          'target': 'inward',
          'name': call.name,
          'mobileNo': call.mobileNo,
        },
      );
    }
  }

  void _convertToSale(BuildContext context, CallModel call) {
    final navVM = context.read<NavigationViewModel>();
    Navigator.pop(context);
    navVM.setIndex(
      NavigationViewModel.sales,
      prefillData: {
        'target': 'sales',
        'customerName': call.name,
        'customerNumber': call.mobileNo,
        'itemName': 'Call log conversion - ${call.name}',
      },
    );
  }
}

// ==========================================================
// FORM DIALOG IMPLEMENTATION
// ==========================================================

class _CallFormDialog extends StatefulWidget {
  final CallModel? existingCall;
  final String? prefillName;
  final String? prefillMobile;
  final String? prefillAddress;
  final String? prefillQuery;
  final String? prefillAssigned;
  final String? prefillEstimate;
  final String? prefillNotes;

  const _CallFormDialog({
    this.existingCall,
    this.prefillName,
    this.prefillMobile,
    this.prefillAddress,
    this.prefillQuery,
    this.prefillAssigned,
    this.prefillEstimate,
    this.prefillNotes,
  });

  @override
  State<_CallFormDialog> createState() => _CallFormDialogState();
}

class _CallFormDialogState extends State<_CallFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _callDate;
  late final TextEditingController _nameController;
  late TextEditingController _mobileController;
  late TextEditingController _addressController;
  late TextEditingController _queryController;
  late TextEditingController _assignedController;
  late TextEditingController _estimateController;
  late TextEditingController _notesController;
  late String _status;
  String? _photoUrl;

  final List<String> _staffOptions = [
    'sale.perfectsolutionnoida@gmail.com',
    'mohankumarmishra28@gmail.com',
    'ashimkumar0006@gmail.com',
    'Office',
  ];

  // ignore: unused_field
  static const List<String> _statusOptions = [
    'Pending',
    'Pre-complete',
    'Pending payment',
    'Complete',
  ];

  @override
  void initState() {
    super.initState();
    final call = widget.existingCall;
    _callDate = call?.date ?? DateTime.now();
    _nameController = TextEditingController(
      text: call?.name ?? widget.prefillName ?? '',
    );
    _mobileController = TextEditingController(
      text: call?.mobileNo ?? widget.prefillMobile ?? '',
    );
    _addressController = TextEditingController(
      text: call?.address ?? widget.prefillAddress ?? '',
    );
    _queryController = TextEditingController(
      text: call?.query ?? widget.prefillQuery ?? '',
    );
    _assignedController = TextEditingController(
      text: (call?.assignedTo.isNotEmpty ?? false)
          ? call!.assignedTo
          : (widget.prefillAssigned ?? _staffOptions.first),
    );
    _estimateController = TextEditingController(
      text: call?.estimate ?? widget.prefillEstimate ?? '',
    );
    _notesController = TextEditingController(
      text: call?.notes ?? widget.prefillNotes ?? '',
    );
    _photoUrl = call?.photo;
    _status =
        call?.status ??
        StatusManagementService.getDefaultStatus('calls');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _queryController.dispose();
    _assignedController.dispose();
    _estimateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.existingCall != null;
    final bool isMobile = MediaQuery.of(context).size.width < 700;

    final bool isDateVis = UserPermissionService.isFieldVisible('calls', 'date');
    final bool isDateMod = UserPermissionService.canModifyField('calls', 'date', isEdit: isEdit);

    final bool isNameVis = UserPermissionService.isFieldVisible('calls', 'name');
    final bool isNameMod = UserPermissionService.canModifyField('calls', 'name', isEdit: isEdit);

    final bool isMobileVis = UserPermissionService.isFieldVisible('calls', 'mobileNo');
    final bool isMobileMod = UserPermissionService.canModifyField('calls', 'mobileNo', isEdit: isEdit);

    final bool isAddressVis = UserPermissionService.isFieldVisible('calls', 'address');
    final bool isAddressMod = UserPermissionService.canModifyField('calls', 'address', isEdit: isEdit);

    final bool isQueryVis = UserPermissionService.isFieldVisible('calls', 'query');
    final bool isQueryMod = UserPermissionService.canModifyField('calls', 'query', isEdit: isEdit);

    final bool isAssignedVis = UserPermissionService.isFieldVisible('calls', 'assignedTo');
    final bool isAssignedMod = UserPermissionService.canModifyField('calls', 'assignedTo', isEdit: isEdit);

    final bool isEstimateVis = UserPermissionService.isFieldVisible('calls', 'estimate');
    final bool isEstimateMod = UserPermissionService.canModifyField('calls', 'estimate', isEdit: isEdit);

    final bool isStatusVis = UserPermissionService.isFieldVisible('calls', 'status');
    final bool isStatusMod = UserPermissionService.canModifyField('calls', 'status', isEdit: isEdit);

    final bool isNotesVis = UserPermissionService.isFieldVisible('calls', 'notes');
    final bool isNotesMod = UserPermissionService.canModifyField('calls', 'notes', isEdit: isEdit);

    final formContent = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDateVis) ...[
            DateTimePickerField(
              label: 'Call Date & Time',
              selectedDateTime: _callDate,
              onDateTimeChanged: (dt) => setState(() => _callDate = dt),
              isVisible: isDateVis,
              canEdit: isDateMod,
            ),
            const SizedBox(height: 12),
          ],
          if (isNameVis) ...[
            TextFormField(
              controller: _nameController,
              readOnly: !isNameMod,
              enabled: isNameMod,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _buildInputDecoration('Customer Name *'),
              validator: (val) => (val == null || val.trim().isEmpty)
                  ? 'Please enter customer name'
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (isMobileVis) ...[
            TextFormField(
              controller: _mobileController,
              readOnly: !isMobileMod,
              enabled: isMobileMod,
              style: const TextStyle(color: AppTheme.textPrimary),
              keyboardType: TextInputType.phone,
              decoration: _buildInputDecoration('Mobile Number'),
            ),
            const SizedBox(height: 16),
          ],
          if (isAddressVis) ...[
            TextFormField(
              controller: _addressController,
              readOnly: !isAddressMod,
              enabled: isAddressMod,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _buildInputDecoration('Address'),
            ),
            const SizedBox(height: 16),
          ],
          if (isQueryVis) ...[
            TextFormField(
              controller: _queryController,
              readOnly: !isQueryMod,
              enabled: isQueryMod,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _buildInputDecoration('Query / Problem Details'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
          ],
          if (isAssignedVis) ...[
            DropdownButtonFormField<String>(
              initialValue: _staffOptions.contains(_assignedController.text)
                  ? _assignedController.text
                  : _staffOptions.first,
              dropdownColor: const Color(0xFF131A2E),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _buildInputDecoration('Assigned To'),
              onChanged: isAssignedMod
                  ? (val) {
                      if (val != null) {
                        setState(() {
                          _assignedController.text = val;
                        });
                      }
                    }
                  : null,
              items: _staffOptions.map((staff) {
                return DropdownMenuItem<String>(value: staff, child: Text(staff));
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              if (isEstimateVis)
                Expanded(
                  child: TextFormField(
                    controller: _estimateController,
                    readOnly: !isEstimateMod,
                    enabled: isEstimateMod,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: _buildInputDecoration('Estimate Amount'),
                  ),
                ),
              if (isEstimateVis && isStatusVis) const SizedBox(width: 16),
              if (isStatusVis)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    dropdownColor: const Color(0xFF131A2E),
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: _buildInputDecoration('Status'),
                    onChanged: isStatusMod
                        ? (val) {
                            if (val != null) {
                              setState(() {
                                _status = val;
                              });
                            }
                          }
                        : null,
                    items:
                        (() {
                          final list =
                              UserPermissionService.getAllowedSelectableStatuses(
                            'calls',
                          );
                          final List<String> selectableList = List.from(list);
                          if (_status.isNotEmpty && !selectableList.any((s) => s.toLowerCase() == _status.toLowerCase())) {
                            selectableList.insert(0, _status);
                          }
                          return selectableList;
                        })().map((st) {
                          return DropdownMenuItem<String>(
                            value: st,
                            child: Text(st),
                          );
                        }).toList(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (isNotesVis) ...[
            TextFormField(
              controller: _notesController,
              readOnly: !isNotesMod,
              enabled: isNotesMod,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _buildInputDecoration('Notes'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
          ],
          PhotoAttachmentWidget(
            initialPhotoUrl: _photoUrl,
            label: 'Enquiry / Product Screenshot or Photo(s)',
            onPhotoChanged: (urls) {
              _photoUrl = urls;
            },
          ),
        ],
      ),
    );

    if (isMobile) {
      return Dialog.fullscreen(
        backgroundColor: const Color(0xFF0F1322),
        child: Scaffold(
          backgroundColor: const Color(0xFF0F1322),
          appBar: AppBar(
            backgroundColor: const Color(0xFF131A2E),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: AppTheme.textPrimary,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              isEdit ? 'Edit Call Record' : 'Log New Call',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => _saveForm(context),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    color: AppTheme.primaryLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: formContent,
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF131A2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      title: Text(
        isEdit ? 'Edit Call Record' : 'Log New Call',
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      content: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(child: formContent),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => _saveForm(context),
          child: Text(isEdit ? 'Save Changes' : 'Log Call'),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppTheme.primaryLight),
        borderRadius: BorderRadius.circular(8),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppTheme.danger),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppTheme.danger),
        borderRadius: BorderRadius.circular(8),
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.01),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  void _saveForm(BuildContext context) async {
    if (_formKey.currentState?.validate() ?? false) {
      final viewModel = context.read<CallsViewModel>();

      final int callId = widget.existingCall?.id ?? viewModel.getNextCallId();

      final newCall = CallModel(
        id: callId,
        date: _callDate,
        name: _nameController.text.trim(),
        mobileNo: _mobileController.text.trim().isNotEmpty
            ? _mobileController.text.trim()
            : null,
        address: _addressController.text.trim().isNotEmpty
            ? _addressController.text.trim()
            : null,
        query: _queryController.text.trim().isNotEmpty
            ? _queryController.text.trim()
            : null,
        assignedTo: _assignedController.text.trim(),
        estimate: _estimateController.text.trim().isNotEmpty
            ? _estimateController.text.trim()
            : null,
        status: _status,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        photo: _photoUrl,
      );

      await viewModel.saveCall(newCall);

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingCall != null
                  ? 'Call record updated'
                  : 'Call logged successfully',
            ),
          ),
        );
      }
    }
  }
}

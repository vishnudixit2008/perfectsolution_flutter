import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../data/models/customer_profile.dart';
import '../../../../data/models/request_order.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/customer_directory_service.dart';
import '../../../../data/services/dealer_inquiry_service.dart';
import '../../../../data/services/dealer_recommendation_service.dart';
import '../../../../data/services/fcm_push_sender_service.dart';
import '../../../../data/services/item_category_detector.dart';
import '../../../../data/services/smart_search_utils.dart';
import '../../../../data/services/supabase_sync_service.dart';
import '../../../../data/services/ui_preferences_service.dart';
import '../../../../data/services/user_permission_service.dart';
import '../../../../data/services/whatsapp_service.dart';
import '../../../../ui/core/app_theme.dart';
import '../../../../ui/core/motion/motion.dart';
import '../../../navigation/navigation_view_model.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_floating_action_button.dart';
import '../../../shared/components/app_header_sync_button.dart';
import '../../../shared/components/app_list_card.dart';
import '../../../shared/components/app_page_header.dart';
import '../../../shared/components/app_search_filter_bar.dart';
import '../../../shared/components/app_status_chip.dart';
import '../../../shared/components/app_status_section_header.dart';
import '../../../shared/components/customer_lookup_banner.dart';
import '../../../shared/date_time_picker_field.dart';
import '../../../shared/dialogs/customer_history_dialog.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../../../shared/resizable_detail_popup.dart';
import '../../../shared/status_management_dialog.dart';
import '../../../shared/whatsapp_icon.dart';
import '../view_models/requests_view_model.dart';
import 'dealer_inquiry_view.dart';
import 'runner_tasks_view.dart';

class RequestsView extends StatefulWidget {
  const RequestsView({super.key});

  /// Opens the detail dialog for a request record from anywhere in the app.
  static void showDetailDialog(
    BuildContext context,
    RequestOrder req, {
    RequestsViewModel? viewModel,
  }) {
    final vm = viewModel ?? context.read<RequestsViewModel>();
    _RequestsViewState._showDetailDialog(context, req, vm);
  }

  /// Opens the runner assignment dialog for a request from anywhere in the app.
  static void showAssignRunnerDialog(
    BuildContext context,
    RequestOrder req,
    RequestsViewModel viewModel, {
    String? preselectedDealer,
    String? preselectedBuilding,
    String? preselectedShopNo,
  }) {
    _RequestsViewState._showAssignRunnerDialog(
      context,
      req,
      viewModel,
      preselectedDealer: preselectedDealer,
      preselectedBuilding: preselectedBuilding,
      preselectedShopNo: preselectedShopNo,
    );
  }

  @override
  State<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends State<RequestsView> {
  final TextEditingController _searchController = TextEditingController();

  // Table columns widths
  // ignore: unused_field
  double _idWidth = 120.0;
  double _dateWidth = 120.0;
  double _nameWidth = 180.0;
  // ignore: unused_field
  double _mobileWidth = 130.0;
  double _itemWidth = 200.0;
  double _amountWidth = 120.0;
  // ignore: unused_field
  double _statusWidth = 140.0;

  void _loadSavedColumnWidths() {
    _idWidth = UiPreferencesService.getColumnWidth('requests', 'id') ?? 120.0;
    _dateWidth = UiPreferencesService.getColumnWidth('requests', 'date') ?? 120.0;
    _nameWidth = UiPreferencesService.getColumnWidth('requests', 'name') ?? 180.0;
    _mobileWidth = UiPreferencesService.getColumnWidth('requests', 'mobile') ?? 130.0;
    _itemWidth = UiPreferencesService.getColumnWidth('requests', 'item') ?? 200.0;
    _amountWidth = UiPreferencesService.getColumnWidth('requests', 'amount') ?? 120.0;
    _statusWidth = UiPreferencesService.getColumnWidth('requests', 'status') ?? 140.0;
  }

  void _updateColumnWidth(String columnKey, double newWidth) {
    setState(() {
      switch (columnKey) {
        case 'id':
          _idWidth = newWidth;
          break;
        case 'date':
          _dateWidth = newWidth;
          break;
        case 'name':
          _nameWidth = newWidth;
          break;
        case 'mobile':
          _mobileWidth = newWidth;
          break;
        case 'item':
          _itemWidth = newWidth;
          break;
        case 'amount':
          _amountWidth = newWidth;
          break;
        case 'status':
          _statusWidth = newWidth;
          break;
      }
    });
    UiPreferencesService.setColumnWidth('requests', columnKey, newWidth);
  }

  @override
  void initState() {
    super.initState();
    StatusManagementService.clearCache();
    _loadSavedColumnWidths();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RequestsViewModel>().loadRequests();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handlePrefillData(
    BuildContext context,
    Map<String, dynamic> prefill,
    NavigationViewModel navVM,
  ) {
    navVM.clearPrefillData();
    final String name = prefill['customerName'] ?? prefill['name'] ?? '';
    final String mobile = prefill['mobileNo'] ?? prefill['customerNumber'] ?? '';
    final String item = prefill['item'] ?? prefill['devices'] ?? '';
    final double amount = prefill['totalAmount'] ?? prefill['amount'] ?? 0.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAddEditDialog(
        context,
        prefillName: name,
        prefillMobile: mobile,
        prefillItem: item,
        prefillAmount: amount,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefill = context.select<NavigationViewModel, Map<String, dynamic>?>(
      (vm) => vm.pendingPrefillData,
    );
    if (prefill != null && prefill['target'] == 'request') {
      _handlePrefillData(context, prefill, context.read<NavigationViewModel>());
    }

    final canAccessRunnerMode = UserPermissionService.canPerformModuleAction('requests', 'canAccessRunnerMode');

    return Consumer<RequestsViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading && viewModel.requests.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ShimmerSkeleton.card(height: 80),
                const SizedBox(height: 10),
                ShimmerSkeleton.card(height: 80),
                const SizedBox(height: 10),
                ShimmerSkeleton.card(height: 80),
              ],
            ),
          );
        }

        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isDesktop = screenWidth >= 800;

        // Filtering
        final query = _searchController.text.trim();
        final filtered = viewModel.requests.where((r) {
          if (!UserPermissionService.isStatusVisible('requests', r.status)) {
            return false;
          }
          if (query.isEmpty) return true;
          final combined =
              '${r.id} ${r.customerName} ${r.item} ${r.estimate ?? ""} ${r.mobileNo ?? ""} ${r.status} ${r.dealerName ?? ""} ${r.assignedRunnerName ?? ""} ${r.targetBuilding ?? ""} ${r.targetShopNo ?? ""}';
          return SmartSearchUtils.matchesQuery(combined, query);
        }).toList();

        // Sort by date descending (newest requests first), tie-break with updatedAt and ID descending
        filtered.sort((a, b) {
          final dateComp = b.date.compareTo(a.date);
          if (dateComp != 0) return dateComp;
          final updateComp = b.updatedAt.compareTo(a.updatedAt);
          if (updateComp != 0) return updateComp;
          return b.id.compareTo(a.id);
        });
        final groupedRequests = _getGroupedRequests(filtered);

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: (!isDesktop && UserPermissionService.canPerformModuleAction('requests', 'canAdd'))
              ? AppFloatingActionButton(
                  onPressed: () => _showAddEditDialog(context),
                  tooltip: 'Add Request',
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: 'Requests',
                actions: [
                  if (canAccessRunnerMode)
                    BouncyPressable(
                      scaleFactor: 0.94,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RunnerTasksView(),
                          ),
                        );
                      },
                      child: Container(
                        height: 32,
                        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 10 : 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(Icons.directions_walk_rounded, size: 16, color: Color(0xFF60A5FA)),
                            if (isDesktop) ...[
                              const SizedBox(width: 6),
                              const Text(
                                'Runner Mode',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF60A5FA),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (isDesktop && UserPermissionService.canPerformModuleAction('requests', 'canAdd'))
                    AppHeaderActionButton(
                      label: 'New Request',
                      icon: Icons.add_rounded,
                      onPressed: () => _showAddEditDialog(context),
                    ),
                  if (!isDesktop)
                    AppHeaderSyncButton(
                      onSynced: () => context.read<RequestsViewModel>().loadRequests(),
                    ),
                  BouncyPressable(
                    scaleFactor: 0.94,
                    onTap: () {
                      StatusManagementDialog.show(
                        context,
                        moduleKey: 'requests',
                        moduleTitle: 'Request',
                        onStatusesUpdated: () {
                          StatusManagementService.invalidateCache('requests');
                          context.read<RequestsViewModel>().loadRequests();
                          setState(() {});
                        },
                      );
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.low_priority_rounded,
                        color: AppTheme.primaryLight,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),

              // Search Bar
              if (isDesktop)
                AppAnimatedSearchBar(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  onClear: () => setState(() {}),
                  hintText: 'Search request ID, customer, item, dealer, runner, building...',
                  margin: const EdgeInsets.only(bottom: 10),
                )
              else
                AppSearchFilterBar(
                  searchQuery: _searchController.text,
                  onSearchChanged: (q) => setState(() => _searchController.text = q),
                  hintText: 'Search request, customer, item, dealer...',
                ),

              const SizedBox(height: 12),

              // Table / Cards list grouped by 5-stage status
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : (isDesktop
                        ? _buildDesktopTable(context, viewModel, groupedRequests)
                        : _buildMobileCardsList(context, viewModel, groupedRequests)),
              ),
            ],
          ),
        );
      },
    );
  }

  Map<String, List<RequestOrder>> _getGroupedRequests(List<RequestOrder> requests) {
    final List<String> configuredStatuses = StatusManagementService.getStatuses('requests');
    final Map<String, List<RequestOrder>> grouped = {};

    // Strictly initialize ONLY with configured statuses from Status Manager, preserving exact order
    for (final status in configuredStatuses) {
      grouped[status] = [];
    }

    // Assign requests strictly to configured status groups
    for (final req in requests) {
      final statusName = req.status.trim();
      String existingKey = configuredStatuses.firstWhere(
        (k) => k.trim().toLowerCase() == statusName.toLowerCase(),
        orElse: () => '',
      );

      // Handle common aliases if not found directly
      if (existingKey.isEmpty) {
        if (statusName.toLowerCase() == 'completed' || statusName.toLowerCase() == 'complete') {
          existingKey = configuredStatuses.firstWhere(
            (k) => k.trim().toLowerCase() == 'complete' || k.trim().toLowerCase() == 'completed',
            orElse: () => '',
          );
        } else if (statusName.toLowerCase() == 'inquiry sent' || statusName.toLowerCase() == 'inquiry' || statusName.toLowerCase() == 'pending') {
          existingKey = configuredStatuses.firstWhere(
            (k) => k.trim().toLowerCase() == 'pending' || k.trim().toLowerCase() == 'inquiry sent',
            orElse: () => '',
          );
        } else if (statusName.toLowerCase() == 'collected' || statusName.toLowerCase() == 'received') {
          existingKey = configuredStatuses.firstWhere(
            (k) => k.trim().toLowerCase() == 'received' || k.trim().toLowerCase() == 'collected',
            orElse: () => '',
          );
        }
      }

      if (existingKey.isNotEmpty) {
        grouped[existingKey]!.add(req);
      } else {
        final defaultStatus = StatusManagementService.getDefaultStatus('requests');
        final fallbackKey = configuredStatuses.firstWhere(
          (k) => k.trim().toLowerCase() == defaultStatus.trim().toLowerCase(),
          orElse: () => configuredStatuses.isNotEmpty ? configuredStatuses.first : '',
        );
        if (fallbackKey.isNotEmpty) {
          grouped[fallbackKey]!.add(req);
        } else {
          final sKey = statusName.isNotEmpty ? statusName : 'Pending';
          grouped.putIfAbsent(sKey, () => []).add(req);
        }
      }
    }

    for (final list in grouped.values) {
      list.sort((a, b) {
        final dateComp = b.date.compareTo(a.date);
        if (dateComp != 0) return dateComp;
        final updateComp = b.updatedAt.compareTo(a.updatedAt);
        if (updateComp != 0) return updateComp;
        return b.id.compareTo(a.id);
      });
    }

    // Only keep status groups that have entries
    grouped.removeWhere((key, list) => list.isEmpty);
    return grouped;
  }

  Color _getStatusColor(String status) {
    return StatusManagementService.getStatusColor('requests', status);
  }

  Widget _buildStatusSectionHeader(String status, int count) {
    return AppStatusSectionHeader(
      title: status,
      count: count,
      singularLabel: 'Request',
      pluralLabel: 'Requests',
      color: _getStatusColor(status),
    );
  }
  Widget _buildEmptyState() {
    return AppEmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'No Part Requests Found',
      message: 'No procurement records match your search criteria.',
      actionLabel: 'Add Order Request',
      onAction: () => _showAddEditDialog(context),
    );
  }

  Widget _buildDesktopTable(
    BuildContext context,
    RequestsViewModel viewModel,
    Map<String, List<RequestOrder>> groupedRequests,
  ) {
    final listEntries = <_RequestListItem>[];
    for (final entry in groupedRequests.entries) {
      listEntries.add(_RequestListItem.header(entry.key, entry.value.length));
      for (final req in entry.value) {
        listEntries.add(_RequestListItem.card(req));
      }
    }

    return Container(
      width: double.infinity,
      decoration: AppTheme.glassCardDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: 12,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header Row
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Row(
              children: [
                if (UserPermissionService.isFieldVisible('requests', 'date'))
                  _buildResizableHeader(
                    'Date',
                    _dateWidth,
                    (delta) => _updateColumnWidth(
                      'date',
                      (_dateWidth + delta).clamp(80.0, 200.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('requests', 'customerName'))
                  _buildResizableHeader(
                    'Customer Name',
                    _nameWidth,
                    (delta) => _updateColumnWidth(
                      'name',
                      (_nameWidth + delta).clamp(100.0, 300.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('requests', 'item'))
                  _buildResizableHeader(
                    'Requested Item',
                    _itemWidth,
                    (delta) => _updateColumnWidth(
                      'item',
                      (_itemWidth + delta).clamp(120.0, 400.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('requests', 'totalAmount'))
                  _buildResizableHeader(
                    'Total Price',
                    _amountWidth,
                    (delta) => _updateColumnWidth(
                      'amount',
                      (_amountWidth + delta).clamp(80.0, 250.0),
                    ),
                  ),
              ],
            ),
          ),

          // Scrollable Body grouped by Status (Virtualized ListView.builder)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: listEntries.length,
              itemBuilder: (context, index) {
                final item = listEntries[index];
                if (item.statusHeader != null) {
                  return _buildStatusSectionHeader(
                    item.statusHeader!,
                    item.statusCount!,
                  );
                }
                return _buildDesktopTableRow(context, viewModel, item.request!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTableRow(
    BuildContext context,
    RequestsViewModel viewModel,
    RequestOrder req,
  ) {
    final formattedDate = DateFormat('dd/MM/yy').format(req.date);
    return InkWell(
      onTap: () => _showDetailDialog(context, req, viewModel),
      hoverColor: Colors.white.withValues(alpha: 0.03),
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
            if (UserPermissionService.isFieldVisible('requests', 'date'))
              Container(
                width: _dateWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  formattedDate,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            if (UserPermissionService.isFieldVisible('requests', 'customerName'))
              Container(
                width: _nameWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  req.customerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (UserPermissionService.isFieldVisible('requests', 'item'))
              Container(
                width: _itemWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      req.item,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (req.assignedRunnerName != null)
                      Text(
                        'Runner: ${req.assignedRunnerName} • ${req.targetBuilding ?? 'Market'}',
                        style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            if (UserPermissionService.isFieldVisible('requests', 'totalAmount'))
              Container(
                width: _amountWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  req.totalAmount > 0
                      ? '₹${req.totalAmount.toStringAsFixed(0)}'
                      : '-',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryLight,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResizableHeader(
    String label,
    double currentWidth,
    ValueChanged<double> onResize,
  ) {
    return Container(
      width: currentWidth,
      padding: const EdgeInsets.only(left: 16, right: 2, top: 12, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

  Widget _buildStatusChip(String status) {
    final chipColor = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: chipColor.withValues(alpha: 0.3), width: 1),
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

  Widget _buildMobileCardsList(
    BuildContext context,
    RequestsViewModel viewModel,
    Map<String, List<RequestOrder>> groupedRequests,
  ) {
    final listEntries = <_RequestListItem>[];
    for (final entry in groupedRequests.entries) {
      listEntries.add(_RequestListItem.header(entry.key, entry.value.length));
      for (final req in entry.value) {
        listEntries.add(_RequestListItem.card(req));
      }
    }

    return RefreshIndicator(
      color: AppTheme.primaryLight,
      backgroundColor: const Color(0xFF131A2E),
      onRefresh: () async {
        final localDb = context.read<ShopRepository>().localDb;
        await SupabaseSyncService.instance.manualSync(localDb, forceFullDownload: false);
        if (context.mounted) viewModel.loadRequests();
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 152),
        itemCount: listEntries.length,
        itemBuilder: (context, index) {
          final item = listEntries[index];
          if (item.statusHeader != null) {
            return _buildStatusSectionHeader(item.statusHeader!, item.statusCount!);
          }
          return _buildMobileRequestCard(context, viewModel, item.request!, itemIndex: index);
        },
      ),
    );
  }

  Widget _buildMobileRequestCard(
    BuildContext context,
    RequestsViewModel viewModel,
    RequestOrder req, {
    int itemIndex = 0,
  }) {
    final metadata = <Widget>[];

    if (req.mobileNo != null &&
        req.mobileNo!.trim().isNotEmpty &&
        req.mobileNo != 'N/A') {
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
              req.mobileNo!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (req.item.isNotEmpty) {
      if (metadata.isNotEmpty) metadata.add(const SizedBox(height: 4));
      metadata.add(
        Text(
          'Item: ${req.item}',
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
            'Advance: ₹${req.advance.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            'Total: ₹${req.totalAmount.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryLight,
            ),
          ),
        ],
      ),
    );

    final canEdit = UserPermissionService.canPerformModuleAction('requests', 'canEdit');
    final canDelete = UserPermissionService.canPerformModuleAction('requests', 'canDelete');

    return AppListCard(
      index: itemIndex,
      title: req.customerName,
      statusBadge: _buildStatusChip(req.status),
      metadataRows: metadata,
      onTap: () => _showDetailDialog(context, req, viewModel),
      onEdit: canEdit ? () => _showAddEditDialog(context, existingRequest: req) : null,
      onDelete: canDelete ? () => _confirmDelete(context, req.id, viewModel) : null,
    );
  }

  static void _confirmDelete(
    BuildContext context,
    String id,
    RequestsViewModel viewModel,
  ) {
    if (!UserPermissionService.canPerformModuleAction('requests', 'canDelete')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to delete Customer Requests.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Special Request?'),
          content: const Text(
            'Are you sure you want to permanently delete this special request record? This action cannot be undone.',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await viewModel.deleteRequest(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Request deleted successfully.'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  static void _showDetailDialog(
    BuildContext context,
    RequestOrder req,
    RequestsViewModel viewModel,
  ) {
    final repo = context.read<ShopRepository>();
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(req.date);

    final canApproveInquiry = UserPermissionService.canPerformModuleAction('requests', 'canApproveInquiry');
    final canSendDealerBroadcast = UserPermissionService.canPerformModuleAction('requests', 'canSendDealerBroadcast');
    final canAssignRunner = UserPermissionService.canPerformModuleAction('requests', 'canAssignRunner');
    final canCheckInAndConvert = UserPermissionService.canPerformModuleAction('requests', 'canCheckInAndConvert');

    ResizableDetailPopup.show(
      context: context,
      repository: repo,
      title: 'Request #${req.id}',
      subtitle: 'Logged on $formattedDate',
      contentBuilder: (ctx, scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (UserPermissionService.isFieldVisible('requests', 'customerName') && req.customerName.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Customer Name',
                value: req.customerName,
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (UserPermissionService.isFieldVisible('requests', 'mobileNo') && req.mobileNo != null && req.mobileNo!.trim().isNotEmpty && req.mobileNo != 'N/A')
              ScaledInfoRow(
                label: 'Mobile Number',
                value: req.mobileNo!,
                onValueTap: UserPermissionService.canViewCustomerHistory('requests')
                    ? () => CustomerHistoryDialog.show(
                        context,
                        phone: req.mobileNo,
                        moduleKey: 'requests',
                      )
                    : null,
                valueTooltip: UserPermissionService.canViewCustomerHistory('requests')
                    ? 'View customer history for ${req.mobileNo}'
                    : null,
                trailing: InlineCallButton(
                  phone: req.mobileNo!,
                  scaleFactor: scale,
                ),
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (UserPermissionService.isFieldVisible('requests', 'item') && req.item.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Requested Item',
                value: req.item,
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (UserPermissionService.isFieldVisible('requests', 'advance') && req.advance > 0)
              ScaledInfoRow(
                label: 'Advance Paid',
                value: '₹${req.advance.toStringAsFixed(2)}',
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (UserPermissionService.isFieldVisible('requests', 'totalAmount') && req.totalAmount > 0)
              ScaledInfoRow(
                label: 'Total Estimated Price',
                value: '₹${req.totalAmount.toStringAsFixed(2)}',
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (UserPermissionService.isFieldVisible('requests', 'dealerName') && req.dealerName != null && req.dealerName!.trim().isNotEmpty && req.dealerName != 'N/A')
              ScaledInfoRow(
                label: 'Dealer Name / Vendor',
                value: req.dealerName!,
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (req.targetBuilding != null && req.targetBuilding!.isNotEmpty)
              ScaledInfoRow(
                label: 'Building & Floor',
                value: '${req.targetBuilding} ${req.targetShopNo != null ? '(${req.targetShopNo})' : ''}',
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (req.assignedRunnerName != null)
              ScaledInfoRow(
                label: 'Assigned Runner',
                value: req.assignedRunnerName!,
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (req.actualPurchaseCost != null)
              ScaledInfoRow(
                label: 'Actual Cost Paid',
                value: '₹${req.actualPurchaseCost!.toStringAsFixed(2)}',
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (UserPermissionService.isFieldVisible('requests', 'status'))
              ScaledInfoRow(
                label: 'Status',
                value: req.status,
                valueWidget: AppStatusChip(
                  status: req.status,
                  moduleKey: 'requests',
                  scaleFactor: scale,
                ),
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (UserPermissionService.isFieldVisible('requests', 'estimate') && req.estimate != null && req.estimate!.trim().isNotEmpty && req.estimate != 'N/A')
              ScaledInfoRow(
                label: 'Notes',
                value: req.estimate!,
                scaleFactor: scale,
                labelWidth: 175,
              ),
            if (UserPermissionService.isFieldVisible('requests', 'photo') && req.photoList.isNotEmpty) ...[
              SizedBox(height: 10 * scale),
              Text('Part Reference Photos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12 * scale)),
              const SizedBox(height: 6),
              PhotoGallerySection(photoUrls: req.photoList),
            ],

            if (req.billPhotoList.isNotEmpty) ...[
              SizedBox(height: 10 * scale),
              Text('Runner Market Bill Receipt', style: TextStyle(color: const Color(0xFF34D399), fontSize: 12 * scale, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              PhotoGallerySection(photoUrls: req.billPhotoList),
            ],

            SizedBox(height: 14 * scale),
            _DealerInquiriesTrackerSection(requestId: req.id, scaleFactor: scale),
            SizedBox(height: 14 * scale),
            Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
            SizedBox(height: 12 * scale),

            Builder(builder: (context) {
              final canWhatsApp = UserPermissionService.canPerformModuleAction('requests', 'canSendWhatsapp');
              final canDuplicate = UserPermissionService.canPerformModuleAction('requests', 'canDuplicate');
              final canConvertSale = UserPermissionService.canPerformModuleAction('requests', 'canConvertToSale');
              final canTransferInward = UserPermissionService.canPerformModuleAction('requests', 'canTransferInward');
              final canTransferReplacement = UserPermissionService.canPerformModuleAction('requests', 'canTransferReplacement');
              final canTransferPurchase = UserPermissionService.canPerformModuleAction('requests', 'canTransferPurchase');

              return Wrap(
                spacing: 8 * scale,
                runSpacing: 8 * scale,
                children: [
                  if (canSendDealerBroadcast)
                    ScaledActionButton(
                      icon: Icons.campaign_rounded,
                      label: 'Dealer Inquiries',
                      color: const Color(0xFFF59E0B),
                      scaleFactor: scale,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showBroadcastDialog(context, req);
                      },
                    ),
                  if (req.status == RequestOrder.statusInquirySent && canApproveInquiry)
                    ScaledActionButton(
                      icon: Icons.thumb_up_alt_rounded,
                      label: 'Customer Approved',
                      color: const Color(0xFF38BDF8),
                      scaleFactor: scale,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await viewModel.updateStatus(req.id, RequestOrder.statusCustomerApproved);
                      },
                    ),
                  if (canAssignRunner)
                    ScaledActionButton(
                      icon: Icons.directions_walk_rounded,
                      label: 'Assign Runner',
                      color: const Color(0xFFA78BFA),
                      scaleFactor: scale,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showAssignRunnerDialog(context, req, viewModel);
                      },
                    ),
                  if ((req.status == RequestOrder.statusCollected || req.status == RequestOrder.statusCompleted) && canCheckInAndConvert)
                    ScaledActionButton(
                      icon: Icons.shopping_bag_rounded,
                      label: 'Convert to Purchase',
                      color: const Color(0xFF10B981),
                      scaleFactor: scale,
                      onTap: () async {
                        Navigator.pop(ctx);
                        final purchase = await viewModel.convertToPurchase(req);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Converted to Purchase #${purchase.id}!'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        }
                      },
                    ),
                  if (canWhatsApp)
                    ScaledActionButton(
                      iconWidget: WhatsAppIcon(size: 18 * scale, color: const Color(0xFF25D366)),
                      color: const Color(0xFF25D366),
                      label: 'WhatsApp',
                      scaleFactor: scale,
                      onTap: () => _launchWhatsApp(req),
                    ),
                  if (canDuplicate)
                    ScaledActionButton(
                      icon: Icons.copy,
                      label: 'Duplicate',
                      scaleFactor: scale,
                      onTap: () {
                        Navigator.pop(ctx);
                        _duplicate(context, req);
                      },
                    ),
                  if (canConvertSale)
                    ScaledActionButton(
                      icon: Icons.sell,
                      label: 'Convert to Sale',
                      scaleFactor: scale,
                      onTap: () => _convertToSale(ctx, req),
                    ),
                  if (canTransferInward)
                    ScaledActionButton(
                      icon: Icons.build,
                      label: 'Enter in Inward',
                      scaleFactor: scale,
                      onTap: () => _enterInModule(ctx, 'inward', req),
                    ),
                  if (canTransferReplacement)
                    ScaledActionButton(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Enter in Replacement',
                      scaleFactor: scale,
                      onTap: () => _enterInModule(ctx, 'replacement', req),
                    ),
                  if (canTransferPurchase)
                    ScaledActionButton(
                      icon: Icons.shopping_cart,
                      label: 'Enter in Purchase',
                      scaleFactor: scale,
                      onTap: () => _enterInModule(ctx, 'purchase', req),
                    ),
                ],
              );
            }),
          ],
        );
      },
      actionsBuilder: (ctx, scale) {
        final canEdit = UserPermissionService.canPerformModuleAction('requests', 'canEdit');
        final canDelete = UserPermissionService.canPerformModuleAction('requests', 'canDelete');
        if (!canEdit && !canDelete) return const SizedBox.shrink();

        return Row(
          children: [
            if (canEdit)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAddEditDialog(context, existingRequest: req);
                  },
                  icon: Icon(Icons.edit_rounded, size: 16 * scale),
                  label: Text('Edit Request', style: TextStyle(fontSize: 13 * scale)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryLight,
                    side: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
                    padding: EdgeInsets.symmetric(vertical: 10 * scale),
                  ),
                ),
              ),
            if (canEdit && canDelete) SizedBox(width: 12 * scale),
            if (canDelete)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmDelete(context, req.id, viewModel);
                  },
                  icon: Icon(Icons.delete_rounded, size: 16 * scale),
                  label: Text('Delete', style: TextStyle(fontSize: 13 * scale)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.3)),
                    padding: EdgeInsets.symmetric(vertical: 10 * scale),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static void _showAssignRunnerDialog(
    BuildContext context,
    RequestOrder req,
    RequestsViewModel viewModel, {
    String? preselectedDealer,
    String? preselectedBuilding,
    String? preselectedShopNo,
  }) {
    final allUsers = UserPermissionService.getAllUsers();
    final allDealers = context.read<ShopRepository>().getDealers();

    // Sort users so Market Runners appear at the top
    final runnersFirst = [...allUsers]..sort((a, b) {
        final aIs = a.isRunner || a.role.toLowerCase() == 'runner';
        final bIs = b.isRunner || b.role.toLowerCase() == 'runner';
        if (aIs && !bIs) return -1;
        if (!aIs && bIs) return 1;
        return a.name.compareTo(b.name);
      });

    // Default to 'Pick Up' if dealer is pre-selected, otherwise determine by existing data
    bool isPickup = (preselectedDealer != null && preselectedDealer.trim().isNotEmpty) ||
        (req.dealerName != null && req.dealerName!.trim().isNotEmpty);

    String selectedRunnerEmail = '';
    String selectedRunnerName = '';
    bool isCustomRunner = runnersFirst.isEmpty;

    if (runnersFirst.isNotEmpty) {
      // Try to find currently assigned runner or fallback to first runner/user
      final existingMatch = runnersFirst.where((u) =>
          ((req.assignedRunnerId?.isNotEmpty ?? false) && u.email == req.assignedRunnerId) ||
          ((req.assignedRunnerName?.isNotEmpty ?? false) && u.name == req.assignedRunnerName)).firstOrNull;

      final defaultUser = existingMatch ?? runnersFirst.first;
      selectedRunnerEmail = defaultUser.email;
      selectedRunnerName = defaultUser.name;
    }

    final customRunnerCtrl = TextEditingController(
      text: (req.assignedRunnerName?.isNotEmpty ?? false) ? req.assignedRunnerName! : '',
    );
    String dealerName = preselectedDealer ?? (req.dealerName ?? '');
    String building = preselectedBuilding ?? (req.targetBuilding ?? 'Meghdoot Building');
    String shopNo = preselectedShopNo ?? (req.targetShopNo ?? '');

    final buildingCtrl = TextEditingController(text: building);
    final shopNoCtrl = TextEditingController(text: shopNo);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF0F1524),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white12),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFA78BFA).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_walk_rounded, color: Color(0xFFA78BFA), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Assign Task to Runner',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item & Photo preview strip
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131A2E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (req.photoList.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                req.photoList.first,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  width: 48,
                                  height: 48,
                                  color: Colors.white10,
                                  child: const Icon(Icons.broken_image_rounded, size: 20, color: Colors.white38),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                req.item,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              if (req.estimate != null && req.estimate!.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Specs: ${req.estimate}',
                                  style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 11),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                'Customer: ${req.customerName}',
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Mode Selector: Find in Market vs Shop Pickup
                  const Text('Task Type', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF131A2E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setDlgState(() => isPickup = false),
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !isPickup ? const Color(0xFF3B82F6) : Colors.transparent,
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_rounded, size: 15, color: !isPickup ? Colors.white : AppTheme.textMuted),
                                  const SizedBox(width: 5),
                                  Text(
                                    '🔍 Find in Market',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: !isPickup ? FontWeight.bold : FontWeight.normal,
                                      color: !isPickup ? Colors.white : AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setDlgState(() => isPickup = true),
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isPickup ? const Color(0xFF10B981) : Colors.transparent,
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.storefront_rounded, size: 15, color: isPickup ? Colors.white : AppTheme.textMuted),
                                  const SizedBox(width: 5),
                                  Text(
                                    '📦 Shop Pickup',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isPickup ? FontWeight.bold : FontWeight.normal,
                                      color: isPickup ? Colors.white : AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Select Runner Staff
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Select Runner Staff *', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                      if (runnersFirst.isNotEmpty)
                        GestureDetector(
                          onTap: () => setDlgState(() => isCustomRunner = !isCustomRunner),
                          child: Text(
                            isCustomRunner ? 'Choose from Team' : '+ Custom Name',
                            style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (!isCustomRunner && runnersFirst.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedRunnerEmail.isNotEmpty ? selectedRunnerEmail : runnersFirst.first.email,
                      dropdownColor: const Color(0xFF131A2E),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.person_rounded, size: 18, color: Color(0xFFA78BFA)),
                      ),
                      items: runnersFirst.map((u) {
                        final isRunner = u.isRunner || u.role.toLowerCase() == 'runner';
                        return DropdownMenuItem(
                          value: u.email,
                          child: Row(
                            children: [
                              Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isRunner ? const Color(0xFFA78BFA).withValues(alpha: 0.2) : Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isRunner ? '🏃 Runner' : u.role,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isRunner ? const Color(0xFFA78BFA) : AppTheme.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDlgState(() {
                            selectedRunnerEmail = val;
                            selectedRunnerName = runnersFirst.firstWhere((u) => u.email == val).name;
                          });
                        }
                      },
                    ),
                  ] else ...[
                    TextFormField(
                      controller: customRunnerCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Runner Name',
                        hintText: 'Enter runner name or phone',
                        isDense: true,
                        prefixIcon: Icon(Icons.person_outline_rounded, size: 18, color: Color(0xFFA78BFA)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // If Shop Pickup: Dealer Autocomplete
                  if (isPickup) ...[
                    Autocomplete<String>(
                      initialValue: TextEditingValue(text: dealerName),
                      optionsBuilder: (textVal) {
                        if (textVal.text.isEmpty) return allDealers.map((d) => d.name);
                        return allDealers
                            .where((d) => d.name.toLowerCase().contains(textVal.text.toLowerCase()))
                            .map((d) => d.name);
                      },
                      onSelected: (val) {
                        final d = allDealers.where((e) => e.name == val).firstOrNull;
                        setDlgState(() {
                          dealerName = val;
                          if (d != null) {
                            final bName = d.buildingName?.trim() ?? '';
                            final addr = d.address.trim();
                            buildingCtrl.text = bName.isNotEmpty ? bName : addr;
                            shopNoCtrl.text = d.shopNo?.trim() ?? '';
                          }
                        });
                      },
                      fieldViewBuilder: (ctx, controller, focus, onSub) {
                        controller.addListener(() => dealerName = controller.text);
                        return TextFormField(
                          controller: controller,
                          focusNode: focus,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Dealer',
                            hintText: 'e.g. Pro Lab, Caviar Technologies',
                            isDense: true,
                            prefixIcon: Icon(Icons.storefront_rounded, size: 18, color: Color(0xFF10B981)),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Building & Shop No
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: buildingCtrl,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: isPickup ? 'Building / Address' : 'Market Area / Building',
                            hintText: 'e.g. Meghdoot Building',
                            isDense: true,
                            prefixIcon: const Icon(Icons.location_city_rounded, size: 18),
                          ),
                        ),
                      ),
                      if (isPickup) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: shopNoCtrl,
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Shop / Floor',
                              hintText: 'e.g. 204',
                              isDense: true,
                              prefixIcon: Icon(Icons.room_rounded, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final runnerNameToSave = isCustomRunner
                    ? customRunnerCtrl.text.trim()
                    : selectedRunnerName;
                final runnerIdToSave = isCustomRunner ? '' : selectedRunnerEmail;

                if (runnerNameToSave.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please specify a runner name')),
                  );
                  return;
                }

                final finalBuilding = buildingCtrl.text.trim();
                final finalShopNo = shopNoCtrl.text.trim();

                Navigator.pop(ctx);
                await viewModel.assignRunner(
                  requestId: req.id,
                  runnerId: runnerIdToSave,
                  runnerName: runnerNameToSave,
                  dealerName: isPickup ? dealerName.trim() : null,
                  building: finalBuilding,
                  shopNo: isPickup ? (finalShopNo.isNotEmpty ? finalShopNo : null) : null,
                );

                // Build updated RequestOrder instance for instant FCM push notification
                final updatedReq = req.copyWith(
                  status: RequestOrder.statusRunnerAssigned,
                  assignedRunnerId: runnerIdToSave,
                  assignedRunnerName: runnerNameToSave,
                  dealerName: isPickup ? dealerName.trim() : null,
                  targetBuilding: finalBuilding,
                  targetShopNo: isPickup ? (finalShopNo.isNotEmpty ? finalShopNo : null) : null,
                );

                // Send FCM push to runner's device(s)
                unawaited(FcmPushSenderService.instance.sendRunnerTaskPush(
                  request: updatedReq,
                  runnerIdentifier: runnerIdToSave.isNotEmpty ? runnerIdToSave : runnerNameToSave,
                ));

                if (context.mounted) {
                  final actionLabel = isPickup ? 'pickup at $dealerName' : 'finding in market';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Assigned #${req.id} to $runnerNameToSave for $actionLabel! Push sent 📲'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA78BFA),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Dispatch Task'),
            ),
          ],
        ),
      ),
    );
  }

  static void _showBroadcastDialog(BuildContext context, RequestOrder req) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DealerInquiryView(request: req),
      ),
    );
  }

  static Future<void> _showAddEditDialog(
    BuildContext context, {
    RequestOrder? existingRequest,
    String? prefillName,
    String? prefillMobile,
    String? prefillItem,
    double? prefillAmount,
    String? prefillDealer,
    String? prefillStatus,
    String? prefillEstimate,
  }) async {
    final isEdit = existingRequest != null;
    final actionKey = isEdit ? 'canEdit' : 'canAdd';
    if (!UserPermissionService.canPerformModuleAction('requests', actionKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEdit ? 'Access Denied: You do not have permission to edit Requests.' : 'Access Denied: You do not have permission to create Requests.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final createdOrder = await showAppModalDialog<RequestOrder?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RequestFormDialog(
        existingRequest: existingRequest,
        prefillName: prefillName,
        prefillMobile: prefillMobile,
        prefillItem: prefillItem,
        prefillAmount: prefillAmount,
        prefillDealer: prefillDealer,
        prefillStatus: prefillStatus,
        prefillEstimate: prefillEstimate,
      ),
    );

    if (createdOrder != null && context.mounted && !isEdit) {
      _showBroadcastDialog(context, createdOrder);
    }
  }

  static void _launchWhatsApp(RequestOrder r) {
    final mobileNo = r.mobileNo;
    if (mobileNo == null || mobileNo.trim().isEmpty) return;
    final message = "Hello ${r.customerName}, We have updated your request item ${r.item} status to ${r.status}. Perfect Solution";
    WhatsAppService.launch(mobileNo: mobileNo, message: message);
  }

  static void _duplicate(BuildContext context, RequestOrder r) async {
    final createdOrder = await showDialog<RequestOrder?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RequestFormDialog(
        prefillName: r.customerName,
        prefillMobile: r.mobileNo,
        prefillItem: r.item,
        prefillAmount: r.totalAmount,
        prefillDealer: r.dealerName,
        prefillStatus: r.status,
        prefillEstimate: r.estimate,
      ),
    );

    if (createdOrder != null && context.mounted) {
      _showBroadcastDialog(context, createdOrder);
    }
  }

  static void _convertToSale(BuildContext context, RequestOrder r) {
    final navVM = context.read<NavigationViewModel>();
    navVM.setIndex(
      NavigationViewModel.sales,
      prefillData: {
        'target': 'sales',
        'customerName': r.customerName,
        'customerNumber': r.mobileNo,
        'advance': r.advance,
        'itemName': r.item,
        'amount': r.totalAmount > 0 ? r.totalAmount : r.advance,
      },
    );
  }

  static void _enterInModule(BuildContext context, String target, RequestOrder r) {
    final navVM = context.read<NavigationViewModel>();
    int index = target == 'inward'
        ? NavigationViewModel.inward
        : (target == 'replacement'
              ? NavigationViewModel.replacement
              : NavigationViewModel.purchase);
    navVM.setIndex(
      index,
      prefillData: {
        'target': target,
        'name': r.customerName,
        'customerName': r.customerName,
        'purchasedFrom': r.dealerName ?? r.customerName,
        'mobileNo': r.mobileNo,
        'devices': r.item,
        'item': 'Special Request item: ${r.item}',
      },
    );
  }
}

class _RequestFormDialog extends StatefulWidget {
  final RequestOrder? existingRequest;
  final String? prefillName;
  final String? prefillMobile;
  final String? prefillItem;
  final double? prefillAmount;
  final String? prefillDealer;
  final String? prefillStatus;
  final String? prefillEstimate;

  const _RequestFormDialog({
    this.existingRequest,
    this.prefillName,
    this.prefillMobile,
    this.prefillItem,
    this.prefillAmount,
    this.prefillDealer,
    this.prefillStatus,
    this.prefillEstimate,
  });

  @override
  State<_RequestFormDialog> createState() => _RequestFormDialogState();
}

class _RequestFormDialogState extends State<_RequestFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _requestDate;
  late final TextEditingController _nameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _itemController;
  late final TextEditingController _advanceController;
  late final TextEditingController _totalAmountController;
  late final TextEditingController _dealerController;
  late final TextEditingController _estimateController;
  late String _status;
  String? _photoUrl;
  bool _isPhotoUploading = false;

  CustomerProfile? _matchedCustomerProfile;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRequest;

    _requestDate = r?.date ?? DateTime.now();

    _nameController = TextEditingController(
      text: r?.customerName ?? widget.prefillName ?? '',
    );
    _mobileController = TextEditingController(
      text: r?.mobileNo ?? widget.prefillMobile ?? '',
    );
    _matchedCustomerProfile =
        CustomerDirectoryService.instance.lookupCustomer(_mobileController.text);
    _mobileController.addListener(_onMobileChanged);
    _itemController = TextEditingController(
      text: r?.item ?? widget.prefillItem ?? '',
    );
    _advanceController = TextEditingController(
      text: (r != null && r.advance > 0)
          ? r.advance.toStringAsFixed(0)
          : '',
    );
    _totalAmountController = TextEditingController(
      text: (r != null && r.totalAmount > 0)
          ? r.totalAmount.toStringAsFixed(0)
          : ((widget.prefillAmount != null && widget.prefillAmount! > 0)
              ? widget.prefillAmount!.toStringAsFixed(0)
              : ''),
    );
    _dealerController = TextEditingController(
      text: r?.dealerName ?? widget.prefillDealer ?? '',
    );
    _estimateController = TextEditingController(
      text: r?.estimate ?? widget.prefillEstimate ?? '',
    );
    _photoUrl = r?.photo;
    _status =
        r?.status ??
        widget.prefillStatus ??
        StatusManagementService.getDefaultStatus('requests');
  }

  void _onMobileChanged() {
    final text = _mobileController.text.trim();
    final profile = CustomerDirectoryService.instance.lookupCustomer(text);
    if (profile != _matchedCustomerProfile) {
      setState(() {
        _matchedCustomerProfile = profile;
      });
      if (profile != null && _nameController.text.trim().isEmpty) {
        _nameController.text = profile.displayName;
      }
    }
  }

  @override
  void dispose() {
    _mobileController.removeListener(_onMobileChanged);
    _nameController.dispose();
    _mobileController.dispose();
    _itemController.dispose();
    _advanceController.dispose();
    _totalAmountController.dispose();
    _dealerController.dispose();
    _estimateController.dispose();
    super.dispose();
  }

  void _saveForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isPhotoUploading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⏳ Photo is still uploading. Please wait a moment before saving.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final viewModel = context.read<RequestsViewModel>();
    final isEdit = widget.existingRequest != null;
    final String id = widget.existingRequest?.id ?? viewModel.getNextId();

    final advance = double.tryParse(_advanceController.text.trim()) ?? 0.0;
    final total = double.tryParse(_totalAmountController.text.trim()) ?? 0.0;

    final order = RequestOrder(
      id: id,
      date: _requestDate,
      customerName: _nameController.text.trim(),
      mobileNo: _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
      item: _itemController.text.trim(),
      advance: advance,
      totalAmount: total,
      dealerName: _dealerController.text.trim().isEmpty ? null : _dealerController.text.trim(),
      status: _status,
      estimate: _estimateController.text.trim().isEmpty ? null : _estimateController.text.trim(),
      photo: _photoUrl,
      assignedRunnerId: widget.existingRequest?.assignedRunnerId,
      assignedRunnerName: widget.existingRequest?.assignedRunnerName,
      targetBuilding: widget.existingRequest?.targetBuilding,
      targetShopNo: widget.existingRequest?.targetShopNo,
      actualPurchaseCost: widget.existingRequest?.actualPurchaseCost,
      billPhoto: widget.existingRequest?.billPhoto,
      collectedAt: widget.existingRequest?.collectedAt,
    );

    await viewModel.saveRequest(order);

    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, isEdit ? null : order);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isEdit ? 'Request updated successfully' : 'Request created successfully',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingRequest != null;
    final isMobile = MediaQuery.of(context).size.width < 700;
    final dealers = context.read<ShopRepository>().getDealers();

    final bool isDateVis = UserPermissionService.isFieldVisible('requests', 'date');
    final bool isDateMod = UserPermissionService.canModifyField('requests', 'date', isEdit: isEdit);

    final bool isNameVis = UserPermissionService.isFieldVisible('requests', 'customerName');
    final bool isNameMod = UserPermissionService.canModifyField('requests', 'customerName', isEdit: isEdit);

    final bool isMobileVis = UserPermissionService.isFieldVisible('requests', 'mobileNo');
    final bool isMobileMod = UserPermissionService.canModifyField('requests', 'mobileNo', isEdit: isEdit);

    final bool isItemVis = UserPermissionService.isFieldVisible('requests', 'item');
    final bool isItemMod = UserPermissionService.canModifyField('requests', 'item', isEdit: isEdit);

    final bool isAdvanceVis = UserPermissionService.isFieldVisible('requests', 'advance');
    final bool isAdvanceMod = UserPermissionService.canModifyField('requests', 'advance', isEdit: isEdit);

    final bool isTotalVis = UserPermissionService.isFieldVisible('requests', 'totalAmount');
    final bool isTotalMod = UserPermissionService.canModifyField('requests', 'totalAmount', isEdit: isEdit);

    final bool isDealerVis = UserPermissionService.isFieldVisible('requests', 'dealerName');
    final bool isDealerMod = UserPermissionService.canModifyField('requests', 'dealerName', isEdit: isEdit);

    final bool isStatusVis = UserPermissionService.isFieldVisible('requests', 'status');
    final bool isStatusMod = UserPermissionService.canModifyField('requests', 'status', isEdit: isEdit);

    final bool isEstimateVis = UserPermissionService.isFieldVisible('requests', 'estimate');
    final bool isEstimateMod = UserPermissionService.canModifyField('requests', 'estimate', isEdit: isEdit);

    final bool isPhotoVis = UserPermissionService.isFieldVisible('requests', 'photo');
    final bool isPhotoMod = UserPermissionService.canModifyField('requests', 'photo', isEdit: isEdit);

    final Widget formContent = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDateVis) ...[
            DateTimePickerField(
              label: 'Pre-Order Date & Time',
              selectedDateTime: _requestDate,
              onDateTimeChanged: (dt) => setState(() => _requestDate = dt),
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
              decoration: InputDecoration(
                labelText: 'Customer Name *',
                suffixIcon: (_matchedCustomerProfile != null &&
                        _matchedCustomerProfile!.events.isNotEmpty)
                    ? CustomerHistoryBadge(
                        profile: _matchedCustomerProfile,
                        moduleKey: 'requests',
                      )
                    : null,
              ),
              validator: (val) => val == null || val.trim().isEmpty
                  ? 'Please enter customer name'
                  : null,
            ),
            const SizedBox(height: 12),
          ],

          if (isMobileVis) ...[
            TextFormField(
              controller: _mobileController,
              readOnly: !isMobileMod,
              enabled: isMobileMod,
              decoration: const InputDecoration(
                labelText: 'Mobile Number',
                hintText: '10 digits',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
          ],

          if (isItemVis) ...[
            TextFormField(
              controller: _itemController,
              readOnly: !isItemMod,
              enabled: isItemMod,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Requested Item *',
                hintText: 'e.g. ASUS Zephyrus G14 Battery',
              ),
              validator: (val) => val == null || val.trim().isEmpty
                  ? 'Please enter item name'
                  : null,
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _itemController,
              builder: (context, value, _) {
                final text = value.text.trim();
                if (text.length < 3) return const SizedBox.shrink();
                final classification = ItemCategoryDetector.classify(text);
                final repo = context.read<ShopRepository>();
                final dealers = repo.getDealers();
                final orders = repo.getPurchaseOrders();
                final matched = DealerRecommendationService.getRecommendations(
                  itemText: text,
                  allDealers: dealers,
                  purchaseOrders: orders,
                  getPurchaseItems: (id) => repo.getPurchaseOrderItems(id),
                );

                return Padding(
                  padding: const EdgeInsets.only(top: 6.0, bottom: 4.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF22D3EE).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, size: 15, color: Color(0xFF22D3EE)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            classification.summary,
                            style: const TextStyle(
                              color: Color(0xFF22D3EE),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (matched.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '⚡ ${matched.length} Frequent Dealers',
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              if (isAdvanceVis)
                Expanded(
                  child: TextFormField(
                    controller: _advanceController,
                    readOnly: !isAdvanceMod,
                    enabled: isAdvanceMod,
                    decoration: const InputDecoration(
                      labelText: 'Advance Paid (₹)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              if (isAdvanceVis && isTotalVis) const SizedBox(width: 12),
              if (isTotalVis)
                Expanded(
                  child: TextFormField(
                    controller: _totalAmountController,
                    readOnly: !isTotalMod,
                    enabled: isTotalMod,
                    decoration: const InputDecoration(
                      labelText: 'Total Amount (₹)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (isMobile) ...[
            if (isDealerVis)
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _dealerController.text),
                optionsBuilder: (textVal) {
                  if (textVal.text.isEmpty) return dealers.map((d) => d.name);
                  return dealers.where((d) => d.name.toLowerCase().contains(textVal.text.toLowerCase())).map((d) => d.name);
                },
                onSelected: (val) => _dealerController.text = val,
                fieldViewBuilder: (ctx, controller, focus, onSub) {
                  controller.addListener(() => _dealerController.text = controller.text);
                  return TextFormField(
                    controller: controller,
                    focusNode: focus,
                    readOnly: !isDealerMod,
                    enabled: isDealerMod,
                    decoration: const InputDecoration(
                      labelText: 'Dealer Name / Sourced Vendor',
                    ),
                  );
                },
              ),
            if (isDealerVis && isStatusVis) const SizedBox(height: 12),
            if (isStatusVis)
              Builder(
                builder: (context) {
                  final list = UserPermissionService.getAllowedSelectableStatuses('requests');
                  final List<String> selectableList = List.from(list);
                  if (_status.isNotEmpty && !selectableList.any((e) => e.trim().toLowerCase() == _status.trim().toLowerCase())) {
                    if ((_status.toLowerCase() == 'complete' || _status.toLowerCase() == 'completed') &&
                        selectableList.any((e) => e.toLowerCase() == 'complete' || e.toLowerCase() == 'completed')) {
                      _status = selectableList.firstWhere((e) => e.toLowerCase() == 'complete' || e.toLowerCase() == 'completed');
                    } else {
                      selectableList.add(_status);
                    }
                  }
                  final match = selectableList.firstWhere(
                    (s) => s.trim().toLowerCase() == _status.trim().toLowerCase() ||
                           ((s.trim().toLowerCase() == 'complete' || s.trim().toLowerCase() == 'completed') &&
                            (_status.trim().toLowerCase() == 'complete' || _status.trim().toLowerCase() == 'completed')),
                    orElse: () => selectableList.isNotEmpty ? selectableList.first : 'Pending',
                  );
                  final effectiveStatus = match;
                  return DropdownButtonFormField<String>(
                    initialValue: effectiveStatus.isNotEmpty ? effectiveStatus : (selectableList.isNotEmpty ? selectableList.first : null),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Status'),
                    dropdownColor: const Color(0xFF131A2E),
                    onChanged: isStatusMod
                        ? (val) {
                            if (val != null) setState(() => _status = val);
                          }
                        : null,
                    items: selectableList.map((st) {
                      return DropdownMenuItem(
                        value: st,
                        child: Text(
                          st,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ] else
            Row(
              children: [
                if (isDealerVis)
                  Expanded(
                    child: Autocomplete<String>(
                      initialValue: TextEditingValue(text: _dealerController.text),
                      optionsBuilder: (textVal) {
                        if (textVal.text.isEmpty) return dealers.map((d) => d.name);
                        return dealers.where((d) => d.name.toLowerCase().contains(textVal.text.toLowerCase())).map((d) => d.name);
                      },
                      onSelected: (val) => _dealerController.text = val,
                      fieldViewBuilder: (ctx, controller, focus, onSub) {
                        controller.addListener(() => _dealerController.text = controller.text);
                        return TextFormField(
                          controller: controller,
                          focusNode: focus,
                          readOnly: !isDealerMod,
                          enabled: isDealerMod,
                          decoration: const InputDecoration(
                            labelText: 'Dealer Name / Sourced Vendor',
                          ),
                        );
                      },
                    ),
                  ),
                if (isDealerVis && isStatusVis) const SizedBox(width: 12),
                if (isStatusVis)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final list = UserPermissionService.getAllowedSelectableStatuses('requests');
                        final List<String> selectableList = List.from(list);
                        if (_status.isNotEmpty && !selectableList.any((e) => e.trim().toLowerCase() == _status.trim().toLowerCase())) {
                          if ((_status.toLowerCase() == 'complete' || _status.toLowerCase() == 'completed') &&
                              selectableList.any((e) => e.toLowerCase() == 'complete' || e.toLowerCase() == 'completed')) {
                            _status = selectableList.firstWhere((e) => e.toLowerCase() == 'complete' || e.toLowerCase() == 'completed');
                          } else {
                            selectableList.add(_status);
                          }
                        }
                        final match = selectableList.firstWhere(
                          (s) => s.trim().toLowerCase() == _status.trim().toLowerCase() ||
                                 ((s.trim().toLowerCase() == 'complete' || s.trim().toLowerCase() == 'completed') &&
                                  (_status.trim().toLowerCase() == 'complete' || _status.trim().toLowerCase() == 'completed')),
                          orElse: () => selectableList.isNotEmpty ? selectableList.first : 'Pending',
                        );
                        final effectiveStatus = match;
                        return DropdownButtonFormField<String>(
                          initialValue: effectiveStatus.isNotEmpty ? effectiveStatus : (selectableList.isNotEmpty ? selectableList.first : null),
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Status'),
                          dropdownColor: const Color(0xFF131A2E),
                          onChanged: isStatusMod
                              ? (val) {
                                  if (val != null) setState(() => _status = val);
                                }
                              : null,
                          items: selectableList.map((st) {
                            return DropdownMenuItem(
                              value: st,
                              child: Text(
                                st,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),

          if (isEstimateVis) ...[
            TextFormField(
              controller: _estimateController,
              readOnly: !isEstimateMod,
              enabled: isEstimateMod,
              decoration: const InputDecoration(
                labelText: 'Estimate Details & Private Notes',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
          ],

          if (isPhotoVis)
            PhotoAttachmentWidget(
              category: 'requests',
              initialPhotoUrl: _photoUrl,
              label: 'Sample / Requested Item Photo(s)',
              onUploadingChanged: (uploading) {
                setState(() {
                  _isPhotoUploading = uploading;
                });
              },
              onPhotoChanged: isPhotoMod
                  ? (urls) {
                      _photoUrl = urls;
                    }
                  : null,
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
              isEdit ? 'Edit Request' : 'Add New Request',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: _saveForm,
                child: const Text(
                  'Save Request',
                  style: TextStyle(
                    color: AppTheme.primaryLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
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

    final bool hasHistory = _matchedCustomerProfile != null &&
        _matchedCustomerProfile!.events.isNotEmpty;

    return AlertDialog(
      backgroundColor: const Color(0xFF131A2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      title: Text(
        isEdit ? 'Edit Request' : 'Add New Request',
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      content: Container(
        constraints: BoxConstraints(maxWidth: hasHistory ? 1180 : 500),
        width: MediaQuery.of(context).size.width * 0.92,
        child: hasHistory
            ? SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(child: formContent),
                    ),
                    const VerticalDivider(
                      width: 24,
                      thickness: 1,
                      color: Color(0xFF334155),
                    ),
                    Expanded(
                      flex: 5,
                      child: CustomerHistorySidePanel(
                        profile: _matchedCustomerProfile!,
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(child: formContent),
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
          onPressed: _saveForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save Request'),
        ),
      ],
    );
  }
}

class _RequestListItem {
  final String? statusHeader;
  final int? statusCount;
  final RequestOrder? request;

  _RequestListItem.header(this.statusHeader, this.statusCount) : request = null;
  _RequestListItem.card(this.request)
      : statusHeader = null,
        statusCount = null;
}

class _DealerInquiriesTrackerSection extends StatefulWidget {
  final String requestId;
  final double scaleFactor;

  const _DealerInquiriesTrackerSection({
    required this.requestId,
    this.scaleFactor = 1.0,
  });

  @override
  State<_DealerInquiriesTrackerSection> createState() =>
      _DealerInquiriesTrackerSectionState();
}

class _DealerInquiriesTrackerSectionState
    extends State<_DealerInquiriesTrackerSection> {
  List<DealerInquiryItem> _inquiries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchInquiries();
  }

  Future<void> _fetchInquiries() async {
    final list =
        await DealerInquiryService.getInquiriesForRequest(widget.requestId);
    if (mounted) {
      setState(() {
        _inquiries = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;

    if (_isLoading) {
      return const SizedBox(
        height: 24,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_inquiries.isEmpty) {
      return const SizedBox.shrink();
    }

    final quotesWithPrice = _inquiries
        .where((i) => i.quoteAmount != null && i.quoteAmount! > 0)
        .toList();
    final priceCount = quotesWithPrice.length;
    final hasPrices = priceCount > 0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasPrices
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      padding: EdgeInsets.all(10 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mark_chat_read_rounded,
                  size: 16 * scale, color: const Color(0xFF22D3EE)),
              SizedBox(width: 8 * scale),
              Text(
                'Dealer WhatsApp Inquiries (${_inquiries.length})',
                style: TextStyle(
                  color: const Color(0xFF22D3EE),
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5 * scale,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: _fetchInquiries,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded,
                          size: 13 * scale, color: AppTheme.textMuted),
                      SizedBox(width: 4 * scale),
                      Text(
                        'Refresh',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11 * scale,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8 * scale),

          // ── Beautiful Quotes Button with number of prices arrived directly on button ──
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showQuotesModal(context),
              borderRadius: BorderRadius.circular(10),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: hasPrices
                        ? [
                            const Color(0xFF064E3B).withValues(alpha: 0.7),
                            const Color(0xFF065F46).withValues(alpha: 0.4),
                          ]
                        : [
                            const Color(0xFF1E293B).withValues(alpha: 0.6),
                            const Color(0xFF0F172A).withValues(alpha: 0.8),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasPrices
                        ? const Color(0xFF10B981).withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1),
                    width: 1.2,
                  ),
                  boxShadow: hasPrices
                      ? [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: 12 * scale,
                  vertical: 10 * scale,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(7 * scale),
                      decoration: BoxDecoration(
                        color: hasPrices
                            ? const Color(0xFF10B981).withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasPrices
                            ? Icons.price_check_rounded
                            : Icons.hourglass_top_rounded,
                        color: hasPrices
                            ? const Color(0xFF34D399)
                            : AppTheme.textMuted,
                        size: 18 * scale,
                      ),
                    ),
                    SizedBox(width: 10 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasPrices ? 'Dealer Price Quotes' : 'Awaiting Dealer Quotes',
                            style: TextStyle(
                              color: hasPrices ? Colors.white : AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5 * scale,
                            ),
                          ),
                          SizedBox(height: 2 * scale),
                          Text(
                            hasPrices
                                ? 'Tap to view received dealer prices'
                                : '${_inquiries.length} ${_inquiries.length == 1 ? "inquiry" : "inquiries"} sent • Waiting for replies',
                            style: TextStyle(
                              color: hasPrices ? const Color(0xFF6EE7B7) : AppTheme.textMuted,
                              fontSize: 11 * scale,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8 * scale),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10 * scale,
                        vertical: 5 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: hasPrices
                            ? const Color(0xFF10B981)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: hasPrices
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasPrices) ...[
                            Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 12 * scale),
                            SizedBox(width: 4 * scale),
                          ],
                          Text(
                            '$priceCount ${priceCount == 1 ? "Price" : "Prices"} Arrived',
                            style: TextStyle(
                              color: hasPrices ? Colors.white : AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11 * scale,
                            ),
                          ),
                          SizedBox(width: 4 * scale),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: hasPrices ? Colors.white70 : AppTheme.textMuted,
                            size: 9 * scale,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuotesModal(BuildContext context) {
    final quotesWithPrice = _inquiries
        .where((i) => i.quoteAmount != null && i.quoteAmount! > 0)
        .toList()
      ..sort((a, b) => a.quoteAmount!.compareTo(b.quoteAmount!));
    final pendingQuotes = _inquiries
        .where((i) => i.quoteAmount == null || i.quoteAmount! <= 0)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF131A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.price_check_rounded,
                            color: Color(0xFF34D399), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Dealer Price Quotes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              '${quotesWithPrice.length} of ${_inquiries.length} dealers quoted a price',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: AppTheme.textMuted),
                        onPressed: () => Navigator.pop(ctx),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(
                      color: Colors.white.withValues(alpha: 0.08), height: 1),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (quotesWithPrice.isNotEmpty) ...[
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  color: Color(0xFF34D399), size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'ARRIVED PRICES (${quotesWithPrice.length}) - BEST RATE FIRST',
                                style: const TextStyle(
                                  color: Color(0xFF34D399),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10.5,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final inq in quotesWithPrice) ...[
                            _buildQuoteDetailCard(inq),
                            const SizedBox(height: 8),
                          ],
                        ],
                        if (pendingQuotes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.schedule_rounded,
                                  color: Colors.amber, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'AWAITING REPLIES (${pendingQuotes.length})',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10.5,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final inq in pendingQuotes) ...[
                            _buildPendingInquiryCard(inq),
                            const SizedBox(height: 6),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuoteDetailCard(DealerInquiryItem inq) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inq.dealerName,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    if (inq.dealerPhone.isNotEmpty)
                      Text(
                        inq.dealerPhone,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '₹${inq.quoteAmount!.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFF34D399),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (inq.quoteNotes != null && inq.quoteNotes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                inq.quoteNotes!,
                style: const TextStyle(
                  color: Color(0xFFFBBF24),
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (inq.dealerPhone.isNotEmpty) ...[
                InkWell(
                  onTap: () {
                    final clean =
                        inq.dealerPhone.replaceAll(RegExp(r'[^0-9+]'), '');
                    launchUrl(Uri.parse('tel:$clean'));
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppTheme.primaryLight.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.call_rounded,
                            size: 12, color: AppTheme.primaryLight),
                        SizedBox(width: 4),
                        Text(
                          'Call',
                          style: TextStyle(
                            color: AppTheme.primaryLight,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    String clean =
                        inq.dealerPhone.replaceAll(RegExp(r'[^0-9]'), '');
                    if (clean.length == 10) clean = '91$clean';
                    launchUrl(
                      Uri.parse('https://wa.me/$clean'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF25D366).withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_rounded,
                            size: 12, color: Color(0xFF25D366)),
                        SizedBox(width: 4),
                        Text(
                          'WhatsApp',
                          style: TextStyle(
                            color: Color(0xFF25D366),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingInquiryCard(DealerInquiryItem inq) {
    final isSent = inq.status == 'sent';
    final isSending = inq.status == 'sending';
    final isFailed = inq.status == 'failed';

    final statusColor = isSent
        ? const Color(0xFF10B981)
        : (isSending
            ? const Color(0xFFF59E0B)
            : (isFailed ? Colors.redAccent : Colors.white54));

    final statusText = isSent
        ? 'Sent'
        : (isSending
            ? 'Sending...'
            : (isFailed ? 'Failed' : 'Queued'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inq.dealerName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                Text(
                  inq.dealerPhone,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


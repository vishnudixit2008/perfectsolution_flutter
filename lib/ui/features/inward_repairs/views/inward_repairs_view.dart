import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../data/models/inward_repair.dart';
import '../../../../data/models/inward_estimate_item.dart';
import '../../../../data/models/pricelist_item.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/supabase_sync_service.dart';
import '../../../../data/services/ui_preferences_service.dart';
import '../../../../data/services/whatsapp_service.dart';
import '../../../../ui/core/app_theme.dart';
import '../../../navigation/navigation_view_model.dart';
import '../../../shared/components/app_page_header.dart';
import '../../../shared/components/app_list_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_floating_action_button.dart';
import '../../../shared/components/app_search_filter_bar.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../../../shared/resizable_detail_popup.dart';
import '../../../shared/status_management_dialog.dart';

import '../../../shared/whatsapp_icon.dart';
import '../../../../data/services/user_permission_service.dart';
import '../../pricelist/view_models/pricelist_view_model.dart';
import '../../sales/view_models/sales_view_model.dart';
import '../view_models/inward_repairs_view_model.dart';

class InwardRepairsView extends StatefulWidget {
  const InwardRepairsView({super.key});

  @override
  State<InwardRepairsView> createState() => _InwardRepairsViewState();
}

class _InwardRepairsViewState extends State<InwardRepairsView> {
  final TextEditingController _searchController = TextEditingController();

  // Table columns widths
  double _jobNoWidth = 100.0;
  double _dateWidth = 120.0;
  double _nameWidth = 200.0;
  double _mobileWidth = 150.0;
  double _devicesWidth = 250.0;
  double _statusWidth = 140.0;

  void _loadSavedColumnWidths() {
    _jobNoWidth =
        UiPreferencesService.getColumnWidth('inward', 'jobNo') ?? 100.0;
    _dateWidth = UiPreferencesService.getColumnWidth('inward', 'date') ?? 120.0;
    _nameWidth = UiPreferencesService.getColumnWidth('inward', 'name') ?? 200.0;
    _mobileWidth =
        UiPreferencesService.getColumnWidth('inward', 'mobile') ?? 150.0;
    _devicesWidth =
        UiPreferencesService.getColumnWidth('inward', 'devices') ?? 250.0;
    _statusWidth =
        UiPreferencesService.getColumnWidth('inward', 'status') ?? 140.0;
  }

  void _updateColumnWidth(String columnKey, double newWidth) {
    setState(() {
      switch (columnKey) {
        case 'jobNo':
          _jobNoWidth = newWidth;
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
        case 'devices':
          _devicesWidth = newWidth;
          break;
        case 'status':
          _statusWidth = newWidth;
          break;
      }
    });
    UiPreferencesService.setColumnWidth('inward', columnKey, newWidth);
  }

  // Pagination states
  int _currentPage = 1;
  final int _itemsPerPage = 20;

  @override
  void initState() {
    super.initState();
    _loadSavedColumnWidths();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InwardRepairsViewModel>().loadRepairs();
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
    final String name = prefill['name'] ?? prefill['customerName'] ?? '';
    final String mobile =
        prefill['mobileNo'] ?? prefill['customerNumber'] ?? '';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAddEditDialog(context, prefillName: name, prefillMobile: mobile);
    });
  }

  @override
  Widget build(BuildContext context) {
    final navVM = context.watch<NavigationViewModel>();
    final prefill = navVM.pendingPrefillData;
    if (prefill != null && prefill['target'] == 'inward') {
      _handlePrefillData(context, prefill, navVM);
    }

    return Consumer<InwardRepairsViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading && viewModel.repairs.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isDesktop = screenWidth >= 800;

        // Filtering
        final query = _searchController.text.trim().toLowerCase();
        final filteredRepairs = viewModel.repairs.where((r) {
          if (query.isEmpty) return true;
          final jobMatch = r.jobNo.toString().contains(query);
          final nameMatch = r.name.toLowerCase().contains(query);
          final deviceMatch = r.devices.toLowerCase().contains(query);
          final mobileMatch =
              r.mobileNo?.toLowerCase().contains(query) ?? false;
          final statusMatch = r.status.toLowerCase().contains(query);
          return jobMatch ||
              nameMatch ||
              deviceMatch ||
              mobileMatch ||
              statusMatch;
        }).toList();

        // Sort by jobNo descending (newest repairs first)
        filteredRepairs.sort((a, b) => b.jobNo.compareTo(a.jobNo));

        // Group entries by Status (Status on top, entries belonging to that status below)
        final groupedRepairs = _getGroupedRepairs(filteredRepairs);

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: UserPermissionService.canPerformModuleAction('inward', 'canAdd')
              ? AppFloatingActionButton(
                  onPressed: () => _showAddEditDialog(context),
                  tooltip: 'Add Inward Repair',
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: 'Inward Repairs',
                subtitle: 'Jobsheets & Repair Tracking',
                actions: [
                  IconButton(
                    onPressed: () {
                      StatusManagementDialog.show(
                        context,
                        moduleKey: 'inward',
                        moduleTitle: 'Inward Repair',
                        onStatusesUpdated: () {
                          StatusManagementService.invalidateCache('inward');
                          context.read<InwardRepairsViewModel>().loadRepairs();
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

              // Search Bar
              if (isDesktop)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by job no, customer, device, status...',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppTheme.textMuted,
                        size: 20,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                size: 18,
                                color: AppTheme.textMuted,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                )
              else
                AppSearchFilterBar(
                  searchQuery: _searchController.text,
                  onSearchChanged: (q) => setState(() {
                    _searchController.text = q;
                    _currentPage = 1;
                  }),
                  hintText: 'Search job no, customer, device...',
                ),
              const SizedBox(height: 12),

              // Table / Cards list grouped by status
              Expanded(
                child: filteredRepairs.isEmpty
                    ? _buildEmptyState()
                    : (isDesktop
                        ? _buildDesktopTable(
                            context,
                            viewModel,
                            groupedRepairs,
                          )
                        : _buildMobileCardsList(
                            context,
                            viewModel,
                            groupedRepairs,
                          )),
              ),
            ],
          ),
        );
      },
    );
  }

  Map<String, List<InwardRepair>> _getGroupedRepairs(
    List<InwardRepair> repairs,
  ) {
    final List<String> configuredStatuses =
        StatusManagementService.getStatuses('inward');
    final Map<String, List<InwardRepair>> grouped = {};

    // Preserve configured status order
    for (final status in configuredStatuses) {
      grouped[status] = [];
    }

    // Assign repairs to status groups
    for (final repair in repairs) {
      final statusName = repair.status.trim();
      final existingKey = grouped.keys.firstWhere(
        (k) => k.toLowerCase() == statusName.toLowerCase(),
        orElse: () => '',
      );

      if (existingKey.isNotEmpty) {
        grouped[existingKey]!.add(repair);
      } else {
        if (!grouped.containsKey(statusName)) {
          grouped[statusName] = [];
        }
        grouped[statusName]!.add(repair);
      }
    }

    // Only keep status groups that have entries
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
              '$count ${count == 1 ? 'Job' : 'Jobs'}',
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
      icon: Icons.build_circle_outlined,
      title: 'No Inward Repairs Found',
      message: 'No jobsheet records match your search query.',
      actionLabel: 'Add Inward Repair',
      onAction: () => _showAddEditDialog(context),
    );
  }

  Widget _buildDesktopTable(
    BuildContext context,
    InwardRepairsViewModel viewModel,
    Map<String, List<InwardRepair>> groupedRepairs,
  ) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.glassCardDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: 12,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header Row (Status column removed - grouped under status headers)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
            ),
            child: Row(
              children: [
                _buildResizableHeader(
                  'Job No',
                  _jobNoWidth,
                  (delta) => _updateColumnWidth(
                    'jobNo',
                    (_jobNoWidth + delta).clamp(60.0, 200.0),
                  ),
                ),
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
                  'Devices / Model',
                  _devicesWidth,
                  (delta) => _updateColumnWidth(
                    'devices',
                    (_devicesWidth + delta).clamp(150.0, 500.0),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Body with Status Headers on Top and Entries Below Each Status
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in groupedRepairs.entries) ...[
                    _buildStatusSectionHeader(entry.key, entry.value.length),
                    for (final repair in entry.value) ...[
                      _buildDesktopTableRow(context, viewModel, repair),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTableRow(
    BuildContext context,
    InwardRepairsViewModel viewModel,
    InwardRepair repair,
  ) {
    final formattedDate = DateFormat('dd/MM/yy').format(repair.date);
    return InkWell(
      onTap: () => _showDetailDialog(context, repair, viewModel),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.04),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: _jobNoWidth,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Text(
                '#${repair.jobNo}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryLight,
                ),
              ),
            ),
            Container(
              width: _dateWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(formattedDate),
            ),
            Container(
              width: _nameWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                repair.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: _mobileWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(repair.mobileNo ?? '-'),
            ),
            Container(
              width: _devicesWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                repair.devices,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
                  color: Colors.white.withOpacity(0.12),
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
    InwardRepairsViewModel viewModel,
    Map<String, List<InwardRepair>> groupedRepairs,
  ) {
    return RefreshIndicator(
      color: AppTheme.primaryLight,
      backgroundColor: const Color(0xFF131A2E),
      onRefresh: () async {
        final localDb = context.read<ShopRepository>().localDb;
        await SupabaseSyncService.instance.syncAllTablesFromCloud(localDb);
        if (context.mounted) viewModel.loadRepairs();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in groupedRepairs.entries) ...[
              _buildStatusSectionHeader(entry.key, entry.value.length),
              for (final repair in entry.value) ...[
                _buildMobileRepairCard(context, viewModel, repair),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileRepairCard(
    BuildContext context,
    InwardRepairsViewModel viewModel,
    InwardRepair repair,
  ) {
    final formattedDate = DateFormat('dd MMM yyyy').format(repair.date);
    final metadata = <Widget>[];

    if (repair.mobileNo != null &&
        repair.mobileNo!.trim().isNotEmpty &&
        repair.mobileNo != 'N/A') {
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
              repair.mobileNo!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (repair.query != null &&
        repair.query!.trim().isNotEmpty &&
        repair.query != 'N/A') {
      if (metadata.isNotEmpty) metadata.add(const SizedBox(height: 4));
      metadata.add(
        Text(
          'Problem: ${repair.query!}',
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final estItems = viewModel.getEstimateItems(repair.jobNo);
    if (estItems.isNotEmpty) {
      final double estTotal = estItems.fold(
        0.0,
        (sum, item) => sum + item.totalAmount,
      );
      if (metadata.isNotEmpty) metadata.add(const SizedBox(height: 4));
      metadata.add(
        Row(
          children: [
            const Icon(
              Icons.receipt_rounded,
              size: 12,
              color: AppTheme.primaryLight,
            ),
            const SizedBox(width: 4),
            Text(
              'Estimate: ${estItems.length} item(s) • ₹${estTotal.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryLight,
              ),
            ),
          ],
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
      title: '#${repair.jobNo} • ${repair.devices}',
      subtitle: 'Customer: ${repair.name}',
      statusBadge: _buildStatusChip(repair.status),
      metadataRows: metadata,
      onTap: () => _showDetailDialog(context, repair, viewModel),
      onEdit: () => _showAddEditDialog(context, existingRepair: repair),
      onDelete: () => _confirmDelete(context, repair.jobNo, viewModel),
    );
  }

  Widget _buildStatusChip(String status) {
    Color chipColor = AppTheme.warning;
    if (status.toLowerCase().contains('complete')) {
      chipColor = AppTheme.success;
    } else if (status.toLowerCase().contains('cancel')) {
      chipColor = AppTheme.danger;
    } else if (status.toLowerCase().contains('diagnos') ||
        status.toLowerCase().contains('work')) {
      chipColor = AppTheme.primaryLight;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: chipColor.withOpacity(0.3), width: 1),
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

  void _confirmDelete(
    BuildContext context,
    int jobNo,
    InwardRepairsViewModel viewModel,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Inward Repair Record?'),
          content: Text(
            'Are you sure you want to permanently delete job #$jobNo? This action cannot be undone.',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await viewModel.deleteRepair(jobNo);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Job #$jobNo deleted successfully.'),
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

  void _showDetailDialog(
    BuildContext context,
    InwardRepair repair,
    InwardRepairsViewModel viewModel,
  ) {
    final repo = context.read<ShopRepository>();
    final formattedDate = DateFormat(
      'dd MMM yyyy, hh:mm a',
    ).format(repair.date);

    ResizableDetailPopup.show(
      context: context,
      repository: repo,
      title: 'Job #${repair.jobNo}',
      subtitle: 'Logged on $formattedDate',
      contentBuilder: (ctx, scale) {
        final currentVM = ctx.watch<InwardRepairsViewModel>();
        final items = currentVM.getEstimateItems(repair.jobNo);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScaledInfoRow(
              label: 'Customer Name',
              value: repair.name,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Mobile Number',
              value: repair.mobileNo ?? 'N/A',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Devices / Model',
              value: repair.devices,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Problem Reported',
              value: repair.query ?? 'N/A',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Purchased From',
              value: repair.purchasedFrom ?? 'N/A',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Notes / Diagnostics',
              value: repair.notes ?? 'N/A',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Status',
              value: repair.status,
              scaleFactor: scale,
            ),
            if (items.isNotEmpty) ...[
              SizedBox(height: 8 * scale),
              Text(
                'Estimate Line Items (${items.length})',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13 * scale,
                ),
              ),
              SizedBox(height: 6 * scale),
              ...items.map(
                (it) => Container(
                  margin: EdgeInsets.only(bottom: 4 * scale),
                  padding: EdgeInsets.symmetric(
                    horizontal: 10 * scale,
                    vertical: 6 * scale,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        it.itemName ?? it.itemDescription ?? 'Item',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${it.quantity} x ₹${it.unitPrice.toStringAsFixed(0)} = ₹${it.totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: AppTheme.primaryLight,
                          fontSize: 12 * scale,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (repair.photoList.isNotEmpty)
              PhotoGallerySection(photoUrls: repair.photoList),
            SizedBox(height: 12 * scale),
            Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
            SizedBox(height: 12 * scale),
            Wrap(
              spacing: 8 * scale,
              runSpacing: 8 * scale,
              children: [
                ScaledActionButton(
                  icon: Icons.phone,
                  label: 'Call',
                  scaleFactor: scale,
                  onTap: () => _launchPhone(repair.mobileNo ?? ''),
                ),
                ScaledActionButton(
                  iconWidget: WhatsAppIcon(size: 18 * scale),
                  label: 'WhatsApp',
                  scaleFactor: scale,
                  onTap: () => _launchWhatsApp(repair),
                ),
                ScaledActionButton(
                  icon: Icons.copy,
                  label: 'Duplicate',
                  scaleFactor: scale,
                  onTap: () {
                    Navigator.pop(ctx);
                    _duplicateInward(context, repair, viewModel);
                  },
                ),
                ScaledActionButton(
                  icon: Icons.sell,
                  label: 'Convert to Sale',
                  scaleFactor: scale,
                  onTap: () => _convertToSale(ctx, repair, viewModel),
                ),
                ScaledActionButton(
                  icon: Icons.request_page,
                  label: 'Enter in Request',
                  scaleFactor: scale,
                  onTap: () =>
                      _enterInModule(ctx, 'request', repair, viewModel),
                ),
                ScaledActionButton(
                  icon: Icons.shopping_cart,
                  label: 'Enter in Purchase',
                  scaleFactor: scale,
                  onTap: () =>
                      _enterInModule(ctx, 'purchase', repair, viewModel),
                ),
              ],
            ),
          ],
        );
      },
      actionsBuilder: (ctx, scale) {
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAddEditDialog(context, existingRepair: repair);
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
            SizedBox(width: 12 * scale),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, repair.jobNo, viewModel);
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

  void _showAddEditDialog(
    BuildContext context, {
    InwardRepair? existingRepair,
    String? prefillName,
    String? prefillMobile,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InwardRepairFormDialog(
        existingRepair: existingRepair,
        prefillName: prefillName,
        prefillMobile: prefillMobile,
      ),
    );
  }

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
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
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
              side: BorderSide(color: Colors.white.withOpacity(0.08)),
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
          Container(height: 12, width: 1, color: Colors.white.withOpacity(0.1)),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: currentPage > 1 ? onPreviousPage : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            iconSize: 16,
            color: AppTheme.primaryLight,
            disabledColor: AppTheme.textMuted.withOpacity(0.3),
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
            disabledColor: AppTheme.textMuted.withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  void _launchPhone(String number) async {
    if (number.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _launchWhatsApp(InwardRepair r) {
    final mobileNo = r.mobileNo;
    if (mobileNo == null || mobileNo.trim().isEmpty) return;
    final message =
        "Hello ${r.name}, We have received your ${r.devices}, Job no. of your device is ${r.jobNo} our team is thoroughly working to diagnose and resolve the problem. We will provide you with a timely update once the issue has been addressed. Thank you for your cooperation. Perfect Solution";
    WhatsAppService.launch(mobileNo: mobileNo, message: message);
  }

  void _duplicateInward(
    BuildContext context,
    InwardRepair repair,
    InwardRepairsViewModel viewModel,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InwardRepairFormDialog(
        prefillName: repair.name,
        prefillMobile: repair.mobileNo,
        prefillDevices: repair.devices,
        prefillQuery: repair.query,
        prefillPurchasedFrom: repair.purchasedFrom,
        prefillNotes: repair.notes,
        prefillStatus: repair.status,
      ),
    );
  }

  void _convertToSale(
    BuildContext context,
    InwardRepair repair,
    InwardRepairsViewModel viewModel,
  ) {
    final navVM = context.read<NavigationViewModel>();

    // Fetch estimate line items and services for this inward repair job
    final estimateItems = viewModel.getEstimateItems(repair.jobNo);
    final double estTotal = estimateItems.fold(
      0.0,
      (sum, item) => sum + item.totalAmount,
    );

    final List<Map<String, dynamic>> itemsList = estimateItems.map((est) {
      double price = 0.0;
      if (est.lineType == 'Service') {
        price = est.servicePrice > 0
            ? est.servicePrice
            : (est.unitPrice > 0
                  ? est.unitPrice
                  : (est.totalAmount > 0
                        ? est.totalAmount /
                              (est.quantity > 0 ? est.quantity : 1)
                        : 0.0));
      } else {
        price = est.unitPrice > 0
            ? est.unitPrice
            : (est.servicePrice > 0
                  ? est.servicePrice
                  : (est.totalAmount > 0
                        ? est.totalAmount /
                              (est.quantity > 0 ? est.quantity : 1)
                        : 0.0));
      }

      String desc = est.itemName != null && est.itemName!.trim().isNotEmpty
          ? est.itemName!
          : (est.itemDescription != null &&
                    est.itemDescription!.trim().isNotEmpty
                ? est.itemDescription!
                : (est.notes != null && est.notes!.trim().isNotEmpty
                      ? est.notes!
                      : '${est.lineType} Repair Service (${repair.devices})'));

      return {
        'itemId': est.itemId,
        'lineType': est.lineType,
        'itemDescription': desc,
        'quantity': est.quantity > 0 ? est.quantity : 1,
        'itemPrice': price,
        'totalAmount': est.totalAmount > 0
            ? est.totalAmount
            : ((est.quantity > 0 ? est.quantity : 1) * price),
      };
    }).toList();

    // 1. Automatically close the inward detail popup/sheet
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {}

    // 2. Navigate to Sales page with prefilled customer details, items, prices, and total
    navVM.setIndex(
      NavigationViewModel.sales,
      prefillData: {
        'target': 'sales',
        'customerName': repair.name,
        'customerNumber': repair.mobileNo,
        'itemName': 'Inward repair job #${repair.jobNo} - ${repair.devices}',
        'estimateItems': itemsList,
        'totalAmount': estTotal,
      },
    );
  }

  void _enterInModule(
    BuildContext context,
    String target,
    InwardRepair repair,
    InwardRepairsViewModel viewModel,
  ) {
    final navVM = context.read<NavigationViewModel>();
    int index = target == 'request'
        ? NavigationViewModel.request
        : NavigationViewModel.purchase;
    navVM.setIndex(
      index,
      prefillData: {
        'target': target,
        'customerName': repair.name,
        'purchasedFrom': repair.name,
        'mobileNo': repair.mobileNo,
        'item': '${repair.devices} - repair job #${repair.jobNo}',
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.primaryLight, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// ADD/EDIT FORM DIALOG IMPLEMENTATION
// ==========================================================
class _InwardRepairFormDialog extends StatefulWidget {
  final InwardRepair? existingRepair;
  final String? prefillName;
  final String? prefillMobile;
  final String? prefillDevices;
  final String? prefillQuery;
  final String? prefillPurchasedFrom;
  final String? prefillNotes;
  final String? prefillStatus;
  final List<InwardEstimateItem>? prefillEstimates;

  const _InwardRepairFormDialog({
    this.existingRepair,
    this.prefillName,
    this.prefillMobile,
    this.prefillDevices,
    this.prefillQuery,
    this.prefillPurchasedFrom,
    this.prefillNotes,
    this.prefillStatus,
    this.prefillEstimates,
  });

  @override
  State<_InwardRepairFormDialog> createState() =>
      _InwardRepairFormDialogState();
}

class _InwardRepairFormDialogState extends State<_InwardRepairFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _devicesController;
  late final TextEditingController _queryController;
  late final TextEditingController _purchasedFromController;
  late final TextEditingController _notesController;
  late String _status;
  late DateTime? _completionDate;
  String? _photoUrl;

  List<InwardEstimateItem> _estimates = [];

  // Controllers for adding estimate item
  final _estItemNameController = TextEditingController();
  final _estPriceController = TextEditingController();
  final _estQtyController = TextEditingController();
  TextEditingController? _activeAutocompleteController;
  String _estType = 'Product'; // Product, Service

  @override
  void initState() {
    super.initState();
    final r = widget.existingRepair;

    _nameController = TextEditingController(
      text: r?.name ?? widget.prefillName ?? '',
    );
    _mobileController = TextEditingController(
      text: r?.mobileNo ?? widget.prefillMobile ?? '',
    );
    _devicesController = TextEditingController(
      text: r?.devices ?? widget.prefillDevices ?? '',
    );
    _queryController = TextEditingController(
      text: r?.query ?? widget.prefillQuery ?? '',
    );
    _purchasedFromController = TextEditingController(
      text: r?.purchasedFrom ?? widget.prefillPurchasedFrom ?? '',
    );
    _notesController = TextEditingController(
      text: r?.notes ?? widget.prefillNotes ?? '',
    );
    _photoUrl = r?.photo;
    final inwardStatuses = StatusManagementService.getStatuses('inward');
    _status =
        r?.status ??
        widget.prefillStatus ??
        (inwardStatuses.isNotEmpty ? inwardStatuses.first : 'Pending');
    _completionDate = r?.completionDate;

    if (r != null) {
      _estimates = context.read<InwardRepairsViewModel>().getEstimateItems(
        r.jobNo,
      );
    } else if (widget.prefillEstimates != null) {
      _estimates = List.from(widget.prefillEstimates!);
    }

    // Ensure pricelist and sales services are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PricelistViewModel>().loadItems();
      context.read<SalesViewModel>().loadSavedServices();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _devicesController.dispose();
    _queryController.dispose();
    _purchasedFromController.dispose();
    _notesController.dispose();
    _estItemNameController.dispose();
    _estPriceController.dispose();
    _estQtyController.dispose();
    super.dispose();
  }

  void _addEstimateItem() {
    final String name =
        (_activeAutocompleteController?.text.trim().isNotEmpty ?? false)
        ? _activeAutocompleteController!.text.trim()
        : _estItemNameController.text.trim();
    final price = double.tryParse(_estPriceController.text) ?? 0.0;
    final qty = int.tryParse(_estQtyController.text) ?? 1;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an item name')),
      );
      return;
    }

    final int jobNo = widget.existingRepair?.jobNo ?? 0;
    final double total = price * qty;

    final newItem = InwardEstimateItem(
      lineId:
          'est_${DateTime.now().microsecondsSinceEpoch}_${_estimates.length}',
      jobNo: jobNo,
      lineType: _estType,
      itemName: name,
      quantity: qty,
      unitPrice: _estType == 'Product' ? price : 0.0,
      servicePrice: _estType == 'Service' ? price : 0.0,
      totalAmount: total,
    );

    if (_estType == 'Service') {
      context.read<ShopRepository>().saveCustomServiceName(name);
      context.read<SalesViewModel>().loadSavedServices();
    }

    setState(() {
      _estimates.add(newItem);
      _estItemNameController.clear();
      _estPriceController.clear();
      _estQtyController.clear();
      if (_activeAutocompleteController != null) {
        _activeAutocompleteController!.text = '';
      }
    });
  }

  void _saveForm() async {
    if (!_formKey.currentState!.validate()) return;

    final pendingName =
        (_activeAutocompleteController?.text.trim().isNotEmpty ?? false)
        ? _activeAutocompleteController!.text.trim()
        : _estItemNameController.text.trim();
    if (pendingName.isNotEmpty) {
      _addEstimateItem();
    }

    final viewModel = context.read<InwardRepairsViewModel>();
    final int jobNo = widget.existingRepair?.jobNo ?? viewModel.getNextJobNo();
    final DateTime date = widget.existingRepair?.date ?? DateTime.now();

    final repair = InwardRepair(
      jobNo: jobNo,
      date: date,
      name: _nameController.text.trim(),
      mobileNo: _mobileController.text.trim().isEmpty
          ? null
          : _mobileController.text.trim(),
      devices: _devicesController.text.trim(),
      query: _queryController.text.trim().isEmpty
          ? null
          : _queryController.text.trim(),
      purchasedFrom: _purchasedFromController.text.trim().isEmpty
          ? null
          : _purchasedFromController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      status: _status,
      completionDate: _status.toLowerCase().contains('complete')
          ? (_completionDate ?? DateTime.now())
          : null,
      photo: _photoUrl,
    );

    final List<InwardEstimateItem> finalEstimates = _estimates.map((item) {
      return InwardEstimateItem(
        lineId: item.lineId,
        jobNo: jobNo,
        lineType: item.lineType,
        itemId: item.itemId,
        itemName: item.itemName,
        itemDescription: item.itemDescription,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        servicePrice: item.servicePrice,
        totalAmount: item.totalAmount,
        notes: item.notes,
      );
    }).toList();

    await viewModel.saveRepair(repair, finalEstimates);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existingRepair == null
                ? 'Inward repair created successfully'
                : 'Repair job updated successfully',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.existingRepair != null;
    final viewModel = context.watch<InwardRepairsViewModel>();

    final bool isMobile = MediaQuery.of(context).size.width < 700;
    final formContent = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Job Number: ',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              Text(
                isEdit
                    ? 'Job No. ${widget.existingRepair?.jobNo}'
                    : 'Job No. ${viewModel.getNextJobNo()}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Customer Name *'),
            validator: (val) => val == null || val.trim().isEmpty
                ? 'Please enter customer name'
                : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _mobileController,
            decoration: const InputDecoration(
              labelText: 'Mobile Number',
              hintText: '10 digits',
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _devicesController,
            decoration: const InputDecoration(
              labelText: 'Devices / Model / Serial *',
              hintText: 'e.g. DELL Inspiron 15, HP G5',
            ),
            validator: (val) => val == null || val.trim().isEmpty
                ? 'Please enter device details'
                : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _queryController,
            decoration: const InputDecoration(
              labelText: 'Fault / Issue Reported',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _purchasedFromController,
                  decoration: const InputDecoration(
                    labelText: 'Purchased From',
                    hintText: 'Store / Vendor',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Repair Status'),
                  dropdownColor: const Color(0xFF131A2E),
                  items:
                      (() {
                        final list = StatusManagementService.getStatuses(
                          'inward',
                        );
                        if (!list.contains(_status)) {
                          list.add(_status);
                        }
                        return list;
                      })().map((st) {
                        return DropdownMenuItem(value: st, child: Text(st));
                      }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _status = val;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Internal Diagnostic Notes',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),

          PhotoAttachmentWidget(
            initialPhotoUrl: _photoUrl,
            label: 'Device Condition / Proof Photo(s)',
            onPhotoChanged: (urls) {
              setState(() {
                _photoUrl = urls;
              });
            },
          ),

          const SizedBox(height: 24),
          const SizedBox(height: 24),
          const Text(
            'Estimate',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),

          // Add estimate item inline form
          Builder(
            builder: (context) {
              final catalogItems = context.watch<PricelistViewModel>().items;
              final savedServices = context
                  .watch<SalesViewModel>()
                  .savedServices;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _estType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      dropdownColor: const Color(0xFF131A2E),
                      items: ['Product', 'Service'].map((t) {
                        return DropdownMenuItem(value: t, child: Text(t));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _estType = val;
                            _estItemNameController.clear();
                            _estPriceController.clear();
                            _activeAutocompleteController?.clear();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: _estType == 'Product'
                        ? Autocomplete<PricelistItem>(
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text.isEmpty) {
                                    return catalogItems.take(10);
                                  }
                                  final query = textEditingValue.text
                                      .toLowerCase();
                                  return catalogItems.where(
                                    (item) =>
                                        item.itemName.toLowerCase().contains(
                                          query,
                                        ) ||
                                        (item.category?.toLowerCase().contains(
                                              query,
                                            ) ??
                                            false),
                                  );
                                },
                            displayStringForOption: (PricelistItem item) =>
                                item.itemName,
                            onSelected: (PricelistItem selection) {
                              _estItemNameController.text = selection.itemName;
                              _estPriceController.text = selection.price
                                  .toStringAsFixed(0);
                            },
                            fieldViewBuilder:
                                (
                                  context,
                                  textEditingController,
                                  focusNode,
                                  onFieldSubmitted,
                                ) {
                                  _activeAutocompleteController =
                                      textEditingController;
                                  textEditingController.addListener(() {
                                    _estItemNameController.text =
                                        textEditingController.text;
                                  });
                                  return TextFormField(
                                    controller: textEditingController,
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Product Name (from Pricelist)',
                                      hintText: 'Search product...',
                                    ),
                                  );
                                },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  color: const Color(0xFF131A2E),
                                  elevation: 4.0,
                                  child: Container(
                                    width: 320,
                                    constraints: const BoxConstraints(
                                      maxHeight: 200,
                                    ),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (context, index) {
                                        final item = options.elementAt(index);
                                        return ListTile(
                                          dense: true,
                                          title: Text(
                                            item.itemName,
                                            style: const TextStyle(
                                              color: AppTheme.textPrimary,
                                              fontSize: 13,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '₹${item.price.toStringAsFixed(0)} • Stock: ${item.stockQty}',
                                            style: const TextStyle(
                                              color: AppTheme.textMuted,
                                              fontSize: 11,
                                            ),
                                          ),
                                          onTap: () => onSelected(item),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : Autocomplete<String>(
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                                  final allServices = <String>{
                                    ...savedServices,
                                    ...catalogItems
                                        .where(
                                          (i) =>
                                              (i.category?.toLowerCase() ??
                                                  '') ==
                                              'service',
                                        )
                                        .map((i) => i.itemName),
                                  }.toList();
                                  if (textEditingValue.text.isEmpty) {
                                    return allServices;
                                  }
                                  final query = textEditingValue.text
                                      .toLowerCase();
                                  return allServices.where(
                                    (s) => s.toLowerCase().contains(query),
                                  );
                                },
                            onSelected: (String selection) {
                              _estItemNameController.text = selection;
                            },
                            fieldViewBuilder:
                                (
                                  context,
                                  textEditingController,
                                  focusNode,
                                  onFieldSubmitted,
                                ) {
                                  _activeAutocompleteController =
                                      textEditingController;
                                  textEditingController.addListener(() {
                                    _estItemNameController.text =
                                        textEditingController.text;
                                  });
                                  return TextFormField(
                                    controller: textEditingController,
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(
                                      labelText: 'Service Name',
                                      hintText: 'OS Install, Screen Repair...',
                                    ),
                                  );
                                },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  color: const Color(0xFF131A2E),
                                  elevation: 4.0,
                                  child: Container(
                                    width: 320,
                                    constraints: const BoxConstraints(
                                      maxHeight: 200,
                                    ),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (context, index) {
                                        final s = options.elementAt(index);
                                        return ListTile(
                                          dense: true,
                                          title: Text(
                                            s,
                                            style: const TextStyle(
                                              color: AppTheme.textPrimary,
                                              fontSize: 13,
                                            ),
                                          ),
                                          onTap: () => onSelected(s),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _estPriceController,
                      decoration: const InputDecoration(labelText: 'Price (₹)'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _estQtyController,
                      decoration: const InputDecoration(labelText: 'Qty'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addEstimateItem,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    child: const Icon(Icons.add),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Added estimate items list
          if (_estimates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No estimate items added to this job.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
            )
          else
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.01),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _estimates.length,
                itemBuilder: (context, index) {
                  final item = _estimates[index];
                  final price = item.lineType == 'Service'
                      ? item.servicePrice
                      : item.unitPrice;
                  return ListTile(
                    title: Text(
                      item.itemName ?? '',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${item.lineType} | ₹$price x ${item.quantity}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₹${item.totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppTheme.danger,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _estimates.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
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
              isEdit
                  ? 'Edit Repair #${widget.existingRepair?.jobNo}'
                  : 'Add New Inward Repair Job',
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
                  'Save Job',
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

    return AlertDialog(
      title: Text(
        isEdit
            ? 'Edit Inward Repair Job #${widget.existingRepair?.jobNo}'
            : 'Add New Inward Repair Job',
      ),
      content: Container(
        constraints: const BoxConstraints(maxWidth: 650),
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(child: formContent),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _saveForm, child: const Text('Save Job')),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../../../shared/date_time_picker_field.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/replacement.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/supabase_sync_service.dart';
import '../../../../data/services/ui_preferences_service.dart';
import '../../../../data/services/whatsapp_service.dart';
import '../../../../ui/core/app_theme.dart';
import '../../../../ui/core/motion/motion.dart';
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
import '../view_models/replacements_view_model.dart';

class ReplacementsView extends StatefulWidget {
  const ReplacementsView({super.key});

  @override
  State<ReplacementsView> createState() => _ReplacementsViewState();
}

class _ReplacementsViewState extends State<ReplacementsView> {
  final TextEditingController _searchController = TextEditingController();

  // Table columns widths
  double _jobNoWidth = 100.0;
  double _dateWidth = 120.0;
  double _nameWidth = 200.0;
  double _mobileWidth = 150.0;
  double _itemWidth = 250.0;
  // ignore: unused_field
  double _statusWidth = 140.0;

  void _loadSavedColumnWidths() {
    _jobNoWidth =
        UiPreferencesService.getColumnWidth('replacement', 'jobNo') ?? 100.0;
    _dateWidth =
        UiPreferencesService.getColumnWidth('replacement', 'date') ?? 120.0;
    _nameWidth =
        UiPreferencesService.getColumnWidth('replacement', 'name') ?? 200.0;
    _mobileWidth =
        UiPreferencesService.getColumnWidth('replacement', 'mobile') ?? 150.0;
    _itemWidth =
        UiPreferencesService.getColumnWidth('replacement', 'item') ?? 250.0;
    _statusWidth =
        UiPreferencesService.getColumnWidth('replacement', 'status') ?? 140.0;
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
        case 'item':
          _itemWidth = newWidth;
          break;
        case 'status':
          _statusWidth = newWidth;
          break;
      }
    });
    UiPreferencesService.setColumnWidth('replacement', columnKey, newWidth);
  }

  @override
  void initState() {
    super.initState();
    _loadSavedColumnWidths();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReplacementsViewModel>().loadReplacements();
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
    if (prefill != null && prefill['target'] == 'replacement') {
      _handlePrefillData(context, prefill, navVM);
    }

    return Consumer<ReplacementsViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading && viewModel.replacements.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ShimmerSkeleton.card(height: 80),
                const SizedBox(height: 10),
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
        final query = _searchController.text.trim().toLowerCase();
        final filtered = viewModel.replacements.where((r) {
          if (!UserPermissionService.isEntryVisible(
            moduleKey: 'replacements',
            status: r.status,
            assignedTo: r.assignedTo,
          )) {
            return false;
          }
          if (query.isEmpty) return true;
          final jobMatch = r.jobNo.toLowerCase().contains(query);
          final nameMatch = r.name.toLowerCase().contains(query);
          final itemMatch = r.item.toLowerCase().contains(query);
          final mobileMatch =
              r.mobileNo?.toLowerCase().contains(query) ?? false;
          final statusMatch = r.status.toLowerCase().contains(query);
          return jobMatch ||
              nameMatch ||
              itemMatch ||
              mobileMatch ||
              statusMatch;
        }).toList();

        // Sort by date descending (newest replacements first)
        filtered.sort((a, b) => b.date.compareTo(a.date));

        final groupedReplacements = _getGroupedReplacements(filtered);

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: (!isDesktop && UserPermissionService.canPerformModuleAction('replacements', 'canAdd'))
              ? AppFloatingActionButton(
                  onPressed: () => _showAddEditDialog(context),
                  tooltip: 'Add Replacement',
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: 'Replacements',
                subtitle: 'Warranty & Parts Replacement Tracker',
                actions: [
                  if (isDesktop && UserPermissionService.canPerformModuleAction('replacements', 'canAdd'))
                    AppHeaderActionButton(
                      label: 'New Replacement',
                      icon: Icons.add_rounded,
                      onPressed: () => _showAddEditDialog(context),
                    ),
                  if (!isDesktop)
                    AppHeaderSyncButton(
                      onSynced: () => context.read<ReplacementsViewModel>().loadReplacements(),
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () {
                      StatusManagementDialog.show(
                        context,
                        moduleKey: 'replacements',
                        moduleTitle: 'Replacement',
                        onStatusesUpdated: () {
                          StatusManagementService.invalidateCache(
                            'replacements',
                          );
                          context
                              .read<ReplacementsViewModel>()
                              .loadReplacements();
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
                AppAnimatedSearchBar(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  onClear: () => setState(() {}),
                  hintText: 'Search job no, name, item, mobile, status...',
                  margin: const EdgeInsets.only(bottom: 10),
                )
              else
                AppSearchFilterBar(
                  searchQuery: _searchController.text,
                  onSearchChanged: (q) => setState(() {
                    _searchController.text = q;
                  }),
                  hintText: 'Search job no, name, item...',
                ),
              const SizedBox(height: 12),

              // Table / Cards list grouped by status
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : (isDesktop
                        ? _buildDesktopTable(
                            context,
                            viewModel,
                            groupedReplacements,
                          )
                        : _buildMobileCardsList(
                            context,
                            viewModel,
                            groupedReplacements,
                          )),
              ),
            ],
          ),
        );
      },
    );
  }

  Map<String, List<Replacement>> _getGroupedReplacements(
    List<Replacement> replacements,
  ) {
    final List<String> configuredStatuses =
        StatusManagementService.getStatuses('replacements');
    final Map<String, List<Replacement>> grouped = {};

    for (final status in configuredStatuses) {
      grouped[status] = [];
    }

    for (final repl in replacements) {
      final statusName = repl.status.trim();
      final existingKey = configuredStatuses.firstWhere(
        (k) => k.trim().toLowerCase() == statusName.toLowerCase(),
        orElse: () => '',
      );

      if (existingKey.isNotEmpty) {
        grouped[existingKey]!.add(repl);
      } else {
        final defaultStatus = StatusManagementService.getDefaultStatus('replacements');
        final fallbackKey = configuredStatuses.firstWhere(
          (k) => k.trim().toLowerCase() == defaultStatus.trim().toLowerCase(),
          orElse: () => configuredStatuses.isNotEmpty ? configuredStatuses.first : '',
        );
        if (fallbackKey.isNotEmpty) {
          grouped[fallbackKey]!.add(repl);
        }
      }
    }

    for (final list in grouped.values) {
      list.sort((a, b) {
        final dateComp = b.date.compareTo(a.date);
        if (dateComp != 0) return dateComp;
        return b.jobNo.compareTo(a.jobNo);
      });
    }

    grouped.removeWhere((key, list) => list.isEmpty);
    return grouped;
  }

  Widget _buildStatusSectionHeader(String status, int count) {
    final Color color = _getStatusColor(status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: color.withValues(alpha: 0.38),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: color,
                  shadows: [
                    Shadow(color: color, offset: const Offset(0.12, 0)),
                    Shadow(color: color, offset: const Offset(-0.12, 0)),
                  ],
                ),
              ),
              if (status.trim().toLowerCase() != 'complete' &&
                  status.trim().toLowerCase() != 'completed' &&
                  status.trim().toLowerCase() != 'confirmed') ...[
                const SizedBox(width: 7),
                Text(
                  '·',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '$count ${count == 1 ? 'Replacement' : 'Replacements'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                    shadows: [
                      Shadow(color: color, offset: const Offset(0.12, 0)),
                      Shadow(color: color, offset: const Offset(-0.12, 0)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    return StatusManagementService.getStatusColor('replacements', status);
  }

  Widget _buildEmptyState() {
    return AppEmptyState(
      icon: Icons.published_with_changes_rounded,
      title: 'No Replacements Found',
      message: 'No replacement records match your search query.',
      actionLabel: 'Add Replacement',
      onAction: () => _showAddEditDialog(context),
    );
  }

  Widget _buildDesktopTable(
    BuildContext context,
    ReplacementsViewModel viewModel,
    Map<String, List<Replacement>> groupedReplacements,
  ) {
    final listEntries = <_ReplacementListItem>[];
    for (final entry in groupedReplacements.entries) {
      listEntries.add(_ReplacementListItem.header(entry.key, entry.value.length));
      for (final repl in entry.value) {
        listEntries.add(_ReplacementListItem.card(repl));
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
                if (UserPermissionService.isFieldVisible('replacements', 'jobNo'))
                  _buildResizableHeader(
                    'Job No',
                    _jobNoWidth,
                    (delta) => _updateColumnWidth(
                      'jobNo',
                      (_jobNoWidth + delta).clamp(60.0, 200.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('replacements', 'date'))
                  _buildResizableHeader(
                    'Date',
                    _dateWidth,
                    (delta) => _updateColumnWidth(
                      'date',
                      (_dateWidth + delta).clamp(80.0, 200.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('replacements', 'name'))
                  _buildResizableHeader(
                    'Customer Name',
                    _nameWidth,
                    (delta) => _updateColumnWidth(
                      'name',
                      (_nameWidth + delta).clamp(120.0, 400.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('replacements', 'mobileNo'))
                  _buildResizableHeader(
                    'Mobile',
                    _mobileWidth,
                    (delta) => _updateColumnWidth(
                      'mobile',
                      (_mobileWidth + delta).clamp(100.0, 300.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('replacements', 'item'))
                  _buildResizableHeader(
                    'Replacement Item',
                    _itemWidth,
                    (delta) => _updateColumnWidth(
                      'item',
                      (_itemWidth + delta).clamp(150.0, 500.0),
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
                return _buildDesktopTableRow(context, viewModel, item.replacement!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTableRow(
    BuildContext context,
    ReplacementsViewModel viewModel,
    Replacement repl,
  ) {
    final formattedDate = DateFormat('dd/MM/yy').format(repl.date);
    return InkWell(
      onTap: () => _showDetailDialog(context, repl, viewModel),
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
            if (UserPermissionService.isFieldVisible('replacements', 'jobNo'))
              Container(
                width: _jobNoWidth,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Text(
                  repl.jobNo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryLight,
                  ),
                ),
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'date'))
              Container(
                width: _dateWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(formattedDate),
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'name'))
              Container(
                width: _nameWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  repl.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'mobileNo'))
              Container(
                width: _mobileWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(repl.mobileNo ?? '-'),
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'item'))
              Container(
                width: _itemWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  repl.item,
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
    ReplacementsViewModel viewModel,
    Map<String, List<Replacement>> groupedReplacements,
  ) {
    final listEntries = <_ReplacementListItem>[];
    for (final entry in groupedReplacements.entries) {
      listEntries.add(_ReplacementListItem.header(entry.key, entry.value.length));
      for (final repl in entry.value) {
        listEntries.add(_ReplacementListItem.card(repl));
      }
    }

    return RefreshIndicator(
      color: AppTheme.primaryLight,
      backgroundColor: const Color(0xFF131A2E),
      onRefresh: () async {
        final localDb = context.read<ShopRepository>().localDb;
        await SupabaseSyncService.instance.syncAllTablesFromCloud(localDb);
        if (context.mounted) viewModel.loadReplacements();
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: listEntries.length,
        itemBuilder: (context, index) {
          final item = listEntries[index];
          if (item.statusHeader != null) {
            return _buildStatusSectionHeader(item.statusHeader!, item.statusCount!);
          }
          return _buildMobileReplacementCard(context, viewModel, item.replacement!, itemIndex: index);
        },
      ),
    );
  }

  Widget _buildMobileReplacementCard(
    BuildContext context,
    ReplacementsViewModel viewModel,
    Replacement repl, {
    int itemIndex = 0,
  }) {
    final formattedDate = DateFormat('dd MMM yyyy').format(repl.date);
    final metadata = <Widget>[];

    if (repl.mobileNo != null &&
        repl.mobileNo!.trim().isNotEmpty &&
        repl.mobileNo != 'N/A') {
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
              repl.mobileNo!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
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

    final canEdit = UserPermissionService.canPerformModuleAction('replacements', 'canEdit');
    final canDelete = UserPermissionService.canPerformModuleAction('replacements', 'canDelete');

    return AppListCard(
      index: itemIndex,
      title: '#${repl.jobNo} • ${repl.item}',
      subtitle: 'Customer: ${repl.name}',
      statusBadge: _buildStatusChip(repl.status),
      metadataRows: metadata,
      onTap: () => _showDetailDialog(context, repl, viewModel),
      onEdit: canEdit ? () => _showAddEditDialog(context, existingReplacement: repl) : null,
      onDelete: canDelete ? () => _confirmDelete(context, repl.jobNo, viewModel) : null,
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

  void _confirmDelete(
    BuildContext context,
    String jobNo,
    ReplacementsViewModel viewModel,
  ) {
    if (!UserPermissionService.canPerformModuleAction('replacements', 'canDelete')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to delete Replacement records.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Replacement Record?'),
          content: Text(
            'Are you sure you want to permanently delete replacement job $jobNo? This action cannot be undone.',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await viewModel.deleteReplacement(jobNo);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Job $jobNo deleted successfully.'),
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
    Replacement repl,
    ReplacementsViewModel viewModel,
  ) {
    final repo = context.read<ShopRepository>();
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(repl.date);
    final depDate = repl.depositDate != null
        ? DateFormat('dd MMM yyyy').format(repl.depositDate!)
        : 'N/A';
    final recDate = repl.receiveDate != null
        ? DateFormat('dd MMM yyyy').format(repl.receiveDate!)
        : 'N/A';

    ResizableDetailPopup.show(
      context: context,
      repository: repo,
      title: 'Replacement ${repl.jobNo}',
      subtitle: 'Logged on $formattedDate',
      contentBuilder: (ctx, scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (UserPermissionService.isFieldVisible('replacements', 'name') && repl.name.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Customer Name',
                value: repl.name,
                scaleFactor: scale,
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'mobileNo') && repl.mobileNo != null && repl.mobileNo!.trim().isNotEmpty && repl.mobileNo != 'N/A')
              ScaledInfoRow(
                label: 'Mobile Number',
                value: repl.mobileNo!,
                trailing: InlineCallButton(
                  phone: repl.mobileNo!,
                  scaleFactor: scale,
                ),
                scaleFactor: scale,
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'item') && repl.item.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Replacement Item',
                value: repl.item,
                scaleFactor: scale,
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'assignedTo') && repl.assignedTo != null && repl.assignedTo!.trim().isNotEmpty && repl.assignedTo != 'N/A')
              ScaledInfoRow(
                label: 'Assigned To',
                value: UserPermissionService.formatStaffName(repl.assignedTo),
                scaleFactor: scale,
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'depositDate') && repl.depositDate != null)
              ScaledInfoRow(
                label: 'Deposit Date',
                value: depDate,
                scaleFactor: scale,
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'receiveDate') && repl.receiveDate != null)
              ScaledInfoRow(
                label: 'Receive Date',
                value: recDate,
                scaleFactor: scale,
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'status'))
              ScaledInfoRow(
                label: 'Status',
                value: repl.status,
                scaleFactor: scale,
              ),
            if (UserPermissionService.isFieldVisible('replacements', 'photo') && repl.photoList.isNotEmpty)
              PhotoGallerySection(photoUrls: repl.photoList),
            SizedBox(height: 12 * scale),
            Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
            SizedBox(height: 12 * scale),
            Builder(builder: (context) {
              final canWhatsApp = UserPermissionService.canPerformModuleAction('replacements', 'canSendWhatsapp');
              final canDuplicate = UserPermissionService.canPerformModuleAction('replacements', 'canDuplicate');
              final canConvertSale = UserPermissionService.canPerformModuleAction('replacements', 'canConvertToSale');
              final canTransferInward = UserPermissionService.canPerformModuleAction('replacements', 'canTransferInward');
              final canTransferRequest = UserPermissionService.canPerformModuleAction('replacements', 'canTransferRequest');
              final canTransferPurchase = UserPermissionService.canPerformModuleAction('replacements', 'canTransferPurchase');
              if (!canWhatsApp && !canDuplicate && !canConvertSale && !canTransferInward && !canTransferRequest && !canTransferPurchase) {
                return const SizedBox.shrink();
              }
              return Wrap(
                spacing: 8 * scale,
                runSpacing: 8 * scale,
                children: [
                  if (canWhatsApp)
                    ScaledActionButton(
                      iconWidget: WhatsAppIcon(size: 18 * scale, color: const Color(0xFF25D366)),
                      color: const Color(0xFF25D366),
                      label: 'WhatsApp',
                      scaleFactor: scale,
                      onTap: () => _launchWhatsApp(repl),
                    ),
                  if (canDuplicate)
                    ScaledActionButton(
                      icon: Icons.copy,
                      label: 'Duplicate',
                      scaleFactor: scale,
                      onTap: () {
                        Navigator.pop(ctx);
                        _duplicate(context, repl);
                      },
                    ),
                  if (canConvertSale)
                    ScaledActionButton(
                      icon: Icons.sell,
                      label: 'Convert to Sale',
                      scaleFactor: scale,
                      onTap: () => _convertToSale(ctx, repl),
                    ),
                  if (canTransferInward)
                    ScaledActionButton(
                      icon: Icons.build,
                      label: 'Enter in Inward',
                      scaleFactor: scale,
                      onTap: () => _enterInModule(ctx, 'inward', repl),
                    ),
                  if (canTransferRequest)
                    ScaledActionButton(
                      icon: Icons.request_page,
                      label: 'Enter in Request',
                      scaleFactor: scale,
                      onTap: () => _enterInModule(ctx, 'request', repl),
                    ),
                  if (canTransferPurchase)
                    ScaledActionButton(
                      icon: Icons.shopping_cart,
                      label: 'Enter in Purchase',
                      scaleFactor: scale,
                      onTap: () => _enterInModule(ctx, 'purchase', repl),
                    ),
                ],
              );
            }),
          ],
        );
      },
      actionsBuilder: (ctx, scale) {
        final canEdit = UserPermissionService.canPerformModuleAction('replacements', 'canEdit');
        final canDelete = UserPermissionService.canPerformModuleAction('replacements', 'canDelete');
        if (!canEdit && !canDelete) return const SizedBox.shrink();

        return Row(
          children: [
            if (canEdit)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAddEditDialog(context, existingReplacement: repl);
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
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmDelete(context, repl.jobNo, viewModel);
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
    Replacement? existingReplacement,
    String? prefillName,
    String? prefillMobile,
  }) {
    final isEdit = existingReplacement != null;
    final actionKey = isEdit ? 'canEdit' : 'canAdd';
    if (!UserPermissionService.canPerformModuleAction('replacements', actionKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEdit
                ? 'Access Denied: You do not have permission to edit Replacement records.'
                : 'Access Denied: You do not have permission to create new Replacement records.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    showAppModalDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReplacementFormDialog(
        existingReplacement: existingReplacement,
        prefillName: prefillName,
        prefillMobile: prefillMobile,
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

  static void launchWhatsAppForReplacement(Replacement r) {
    final mobileNo = r.mobileNo;
    if (mobileNo == null || mobileNo.trim().isEmpty) return;
    final message = '''Hello ${r.name},

We have received your item ${r.item} for replacement under Job No. ${r.jobNo}. Our team is processing your request and we will provide you with a timely update once it is processed.

Thank you for your cooperation.

Perfect Solution''';
    WhatsAppService.launch(mobileNo: mobileNo, message: message);
  }

  void _launchWhatsApp(Replacement r) => launchWhatsAppForReplacement(r);

  void _duplicate(BuildContext context, Replacement r) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReplacementFormDialog(
        prefillName: r.name,
        prefillMobile: r.mobileNo,
        prefillItem: r.item,
        prefillAssignedTo: r.assignedTo,
        prefillStatus: r.status,
      ),
    );
  }

  void _convertToSale(BuildContext context, Replacement r) {
    final navVM = context.read<NavigationViewModel>();
    navVM.setIndex(
      NavigationViewModel.sales,
      prefillData: {
        'target': 'sales',
        'customerName': r.name,
        'customerNumber': r.mobileNo,
        'itemName': 'Replacement item conversion: ${r.item} (${r.jobNo})',
        'amount': 0.0,
      },
    );
  }

  void _enterInModule(BuildContext context, String target, Replacement r) {
    final navVM = context.read<NavigationViewModel>();
    int index = target == 'inward'
        ? NavigationViewModel.inward
        : (target == 'request'
              ? NavigationViewModel.request
              : NavigationViewModel.purchase);
    navVM.setIndex(
      index,
      prefillData: {
        'target': target,
        'name': r.name,
        'customerName': r.name,
        'purchasedFrom': r.name,
        'mobileNo': r.mobileNo,
        'devices': r.item,
        'item': 'Replacement job ${r.jobNo} - ${r.item}',
      },
    );
  }
}

// ignore: unused_element
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

class _ReplacementFormDialog extends StatefulWidget {
  final Replacement? existingReplacement;
  final String? prefillName;
  final String? prefillMobile;
  final String? prefillItem;
  final String? prefillAssignedTo;
  final String? prefillStatus;

  const _ReplacementFormDialog({
    this.existingReplacement,
    this.prefillName,
    this.prefillMobile,
    this.prefillItem,
    this.prefillAssignedTo,
    this.prefillStatus,
  });

  @override
  State<_ReplacementFormDialog> createState() => _ReplacementFormDialogState();
}

class _ReplacementFormDialogState extends State<_ReplacementFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _recordDate;
  late TextEditingController _nameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _itemController;
  late final TextEditingController _assignedToController;
  late String _status;

  DateTime? _depositDate;
  DateTime? _receiveDate;
  String? _photoUrl;
  bool _isPhotoUploading = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existingReplacement;

    _recordDate = r?.date ?? DateTime.now();
    _nameController = TextEditingController(
      text: r?.name ?? widget.prefillName ?? '',
    );
    _mobileController = TextEditingController(
      text: r?.mobileNo ?? widget.prefillMobile ?? '',
    );
    _itemController = TextEditingController(
      text: r?.item ?? widget.prefillItem ?? '',
    );
    _assignedToController = TextEditingController(
      text: r?.assignedTo ?? widget.prefillAssignedTo ?? '',
    );
    _status =
        r?.status ??
        widget.prefillStatus ??
        StatusManagementService.getDefaultStatus('replacements');
    _depositDate = r?.depositDate;
    _receiveDate = r?.receiveDate;
    _photoUrl = r?.photo;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _itemController.dispose();
    _assignedToController.dispose();
    super.dispose();
  }

  void _saveForm() async {
    if (!_formKey.currentState!.validate()) return;

    // Guard: wait for photo upload to complete before saving
    if (_isPhotoUploading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⏳ Photo is still uploading to Google Drive. Please wait a moment before saving.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final viewModel = context.read<ReplacementsViewModel>();
    final String jobNo =
        widget.existingReplacement?.jobNo ?? viewModel.getNextJobNo();

    final r = Replacement(
      jobNo: jobNo,
      date: _recordDate,
      name: _nameController.text.trim(),
      mobileNo: _mobileController.text.trim().isEmpty
          ? null
          : _mobileController.text.trim(),
      item: _itemController.text.trim(),
      assignedTo: _assignedToController.text.trim().isEmpty
          ? null
          : _assignedToController.text.trim(),
      depositDate: _depositDate,
      receiveDate:
          _status.toLowerCase().contains('complete') ||
              _status.toLowerCase().contains('recieved')
          ? (_receiveDate ?? DateTime.now())
          : _receiveDate,
      status: _status,
      photo: _photoUrl,
    );

    final bool isNewEntry = widget.existingReplacement == null;
    await viewModel.saveReplacement(r);

    // Auto-trigger WhatsApp message if adding new replacement entry as sale.perfectsolutionnoida@gmail.com
    if (isNewEntry) {
      final currentUserEmail =
          UserPermissionService.getCurrentUser().email.trim().toLowerCase();
      if (currentUserEmail == 'sale.perfectsolutionnoida@gmail.com') {
        _ReplacementsViewState.launchWhatsAppForReplacement(r);
      }
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNewEntry
                ? 'Replacement created successfully'
                : 'Replacement updated successfully',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _selectDate(BuildContext context, bool isDeposit) async {
    final initial = (isDeposit ? _depositDate : _receiveDate) ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: Color(0xFF131A2E),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isDeposit) {
          _depositDate = picked;
        } else {
          _receiveDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.existingReplacement != null;
    final bool isMobile = MediaQuery.of(context).size.width < 700;
    final viewModel = context.watch<ReplacementsViewModel>();

    final bool isDateVis = UserPermissionService.isFieldVisible('replacements', 'date');
    final bool isDateMod = UserPermissionService.canModifyField('replacements', 'date', isEdit: isEdit);

    final bool isNameVis = UserPermissionService.isFieldVisible('replacements', 'name');
    final bool isNameMod = UserPermissionService.canModifyField('replacements', 'name', isEdit: isEdit);

    final bool isMobileVis = UserPermissionService.isFieldVisible('replacements', 'mobileNo');
    final bool isMobileMod = UserPermissionService.canModifyField('replacements', 'mobileNo', isEdit: isEdit);

    final bool isItemVis = UserPermissionService.isFieldVisible('replacements', 'item');
    final bool isItemMod = UserPermissionService.canModifyField('replacements', 'item', isEdit: isEdit);

    final bool isAssignedVis = UserPermissionService.isFieldVisible('replacements', 'assignedTo');
    final bool isAssignedMod = UserPermissionService.canModifyField('replacements', 'assignedTo', isEdit: isEdit);

    final bool isStatusVis = UserPermissionService.isFieldVisible('replacements', 'status');
    final bool isStatusMod = UserPermissionService.canModifyField('replacements', 'status', isEdit: isEdit);

    final bool isJobNoVis = UserPermissionService.isFieldVisible('replacements', 'jobNo');
    final bool isDepositDateVis = UserPermissionService.isFieldVisible('replacements', 'depositDate');
    final bool isDepositDateMod = UserPermissionService.canModifyField('replacements', 'depositDate', isEdit: isEdit);
    final bool isReceiveDateVis = UserPermissionService.isFieldVisible('replacements', 'receiveDate');
    final bool isReceiveDateMod = UserPermissionService.canModifyField('replacements', 'receiveDate', isEdit: isEdit);
    final bool isPhotoVis = UserPermissionService.isFieldVisible('replacements', 'photo');
    final bool isPhotoMod = UserPermissionService.canModifyField('replacements', 'photo', isEdit: isEdit);

    final Widget formContent = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isJobNoVis)
            Row(
              children: [
                const Text(
                  'Job Number: ',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                Text(
                  isEdit
                      ? widget.existingReplacement!.jobNo
                      : viewModel.getNextJobNo(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryLight,
                  ),
                ),
              ],
            ),
          if (isDateVis) ...[
            const SizedBox(height: 12),
            DateTimePickerField(
              label: 'Record Date & Time',
              selectedDateTime: _recordDate,
              onDateTimeChanged: (dt) => setState(() => _recordDate = dt),
              isVisible: isDateVis,
              canEdit: isDateMod,
            ),
          ],
          const SizedBox(height: 16),

          if (isNameVis) ...[
            TextFormField(
              controller: _nameController,
              readOnly: !isNameMod,
              enabled: isNameMod,
              decoration: const InputDecoration(labelText: 'Customer Name *'),
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
              decoration: const InputDecoration(
                labelText: 'Replacement Item *',
                hintText: 'e.g. Logitech G102, Crucial 8GB DDR4 RAM',
              ),
              validator: (val) => val == null || val.trim().isEmpty
                  ? 'Please enter replacement item name'
                  : null,
            ),
            const SizedBox(height: 12),
          ],

          if (isAssignedVis) ...[
            TextFormField(
              controller: _assignedToController,
              readOnly: !isAssignedMod,
              enabled: isAssignedMod,
              decoration: const InputDecoration(
                labelText: 'Assigned To / Technician',
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (isPhotoVis) ...[
            PhotoAttachmentWidget(
              initialPhotoUrl: _photoUrl,
              label: 'Replacement Item Photo / Receipt (Google Drive Link)',
              onUploadingChanged: (uploading) {
                setState(() {
                  _isPhotoUploading = uploading;
                });
              },
              onPhotoChanged: isPhotoMod
                  ? (url) {
                      _photoUrl = url;
                    }
                  : null,
            ),
            const SizedBox(height: 12),
          ],

          if (isStatusVis) ...[
            Builder(
              builder: (context) {
                final list = UserPermissionService.getAllowedSelectableStatuses('replacements');
                final List<String> selectableList = List.from(list);
                final match = selectableList.firstWhere(
                  (s) => s.trim().toLowerCase() == _status.trim().toLowerCase(),
                  orElse: () => selectableList.isNotEmpty ? selectableList.first : 'Pending',
                );
                final effectiveStatus = match;
                return DropdownButtonFormField<String>(
                  value: effectiveStatus.isNotEmpty ? effectiveStatus : (selectableList.isNotEmpty ? selectableList.first : null),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Replacement Status'),
                  dropdownColor: const Color(0xFF131A2E),
                  onChanged: isStatusMod
                      ? (val) {
                          if (val != null) {
                            setState(() {
                              _status = val;
                            });
                          }
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
            const SizedBox(height: 12),
          ],

          // Deposit Date Picker
          if (isDepositDateVis) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _depositDate == null
                        ? 'Deposit Date: Not set'
                        : 'Deposit Date: ${DateFormat('dd/MM/yyyy').format(_depositDate!)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (isDepositDateMod)
                  OutlinedButton(
                    onPressed: () => _selectDate(context, true),
                    child: const Text('Set Deposit'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Receive Date Picker
          if (isReceiveDateVis) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _receiveDate == null
                        ? 'Receive Date: Not set'
                        : 'Receive Date: ${DateFormat('dd/MM/yyyy').format(_receiveDate!)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (isReceiveDateMod)
                  OutlinedButton(
                    onPressed: () => _selectDate(context, false),
                    child: const Text('Set Receive'),
                  ),
              ],
            ),
          ],
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
                  ? 'Edit Replacement #${widget.existingReplacement?.jobNo}'
                  : 'Add New Replacement Job',
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
      backgroundColor: const Color(0xFF131A2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      title: Text(
        isEdit
            ? 'Edit Replacement #${widget.existingReplacement?.jobNo}'
            : 'Add New Replacement Job',
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      content: Container(
        constraints: const BoxConstraints(maxWidth: 500),
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
          onPressed: _saveForm,
          child: const Text('Save Replacement'),
        ),
      ],
    );
  }
}

class _ReplacementListItem {
  final String? statusHeader;
  final int? statusCount;
  final Replacement? replacement;

  _ReplacementListItem.header(this.statusHeader, this.statusCount) : replacement = null;
  _ReplacementListItem.card(this.replacement)
      : statusHeader = null,
        statusCount = null;
}

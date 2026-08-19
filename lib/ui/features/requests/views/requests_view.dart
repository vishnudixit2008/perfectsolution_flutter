import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/models/request_order.dart';
import '../../../../data/repositories/shop_repository.dart';
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
import '../../../shared/date_time_picker_field.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../../../shared/resizable_detail_popup.dart';
import '../../../shared/status_management_dialog.dart';
import '../../../shared/whatsapp_icon.dart';
import '../view_models/requests_view_model.dart';
import 'runner_tasks_view.dart';

class RequestsView extends StatefulWidget {
  const RequestsView({super.key});

  @override
  State<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends State<RequestsView> {
  final TextEditingController _searchController = TextEditingController();

  // Table columns widths
  double _idWidth = 120.0;
  double _dateWidth = 120.0;
  double _nameWidth = 180.0;
  double _mobileWidth = 130.0;
  double _itemWidth = 200.0;
  double _amountWidth = 120.0;

  void _loadSavedColumnWidths() {
    _idWidth = UiPreferencesService.getColumnWidth('requests', 'id') ?? 120.0;
    _dateWidth = UiPreferencesService.getColumnWidth('requests', 'date') ?? 120.0;
    _nameWidth = UiPreferencesService.getColumnWidth('requests', 'name') ?? 180.0;
    _mobileWidth = UiPreferencesService.getColumnWidth('requests', 'mobile') ?? 130.0;
    _itemWidth = UiPreferencesService.getColumnWidth('requests', 'item') ?? 200.0;
    _amountWidth = UiPreferencesService.getColumnWidth('requests', 'amount') ?? 120.0;
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
      }
    });
    UiPreferencesService.setColumnWidth('requests', columnKey, newWidth);
  }

  @override
  void initState() {
    super.initState();
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
    final navVM = context.watch<NavigationViewModel>();
    final prefill = navVM.pendingPrefillData;
    if (prefill != null && prefill['target'] == 'request') {
      _handlePrefillData(context, prefill, navVM);
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
        final bool isDesktop = screenWidth >= 850;

        // Filtering
        final query = _searchController.text.trim().toLowerCase();
        final filtered = viewModel.requests.where((r) {
          if (!UserPermissionService.isStatusVisible('requests', r.status)) {
            return false;
          }
          if (query.isEmpty) return true;
          final idMatch = r.id.toLowerCase().contains(query);
          final nameMatch = r.customerName.toLowerCase().contains(query);
          final itemMatch = r.item.toLowerCase().contains(query);
          final mobileMatch = r.mobileNo?.toLowerCase().contains(query) ?? false;
          final statusMatch = r.status.toLowerCase().contains(query);
          final dealerMatch = r.dealerName?.toLowerCase().contains(query) ?? false;
          final runnerMatch = r.assignedRunnerName?.toLowerCase().contains(query) ?? false;
          final bldgMatch = r.targetBuilding?.toLowerCase().contains(query) ?? false;
          return idMatch || nameMatch || itemMatch || mobileMatch || statusMatch || dealerMatch || runnerMatch || bldgMatch;
        }).toList();

        filtered.sort((a, b) => b.date.compareTo(a.date));
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
                title: 'Requests & Sourcing',
                subtitle: 'Parts Procurement, Dealer Sourcing & Market Runner Dispatch',
                actions: [
                  if (canAccessRunnerMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                backgroundColor: const Color(0xFF0A0E1A),
                                appBar: AppBar(
                                  backgroundColor: const Color(0xFF0F1524),
                                  title: const Text('Market Runner Mode'),
                                ),
                                body: const RunnerTasksView(),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.directions_walk_rounded, size: 18),
                        label: const Text('Runner Mode'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () {
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
                    icon: const Icon(
                      Icons.low_priority_rounded,
                      color: AppTheme.primaryLight,
                      size: 20,
                    ),
                    tooltip: 'Manage & Reorder Statuses',
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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

    // Standard 5-stage order defaults
    final defaultWorkflow = RequestOrder.allStatuses;
    for (final s in defaultWorkflow) {
      grouped[s] = [];
    }
    for (final s in configuredStatuses) {
      if (!grouped.containsKey(s)) {
        grouped[s] = [];
      }
    }

    for (final req in requests) {
      final statusName = req.status.trim();
      final existingKey = grouped.keys.firstWhere(
        (k) => k.toLowerCase() == statusName.toLowerCase(),
        orElse: () => '',
      );

      if (existingKey.isNotEmpty) {
        grouped[existingKey]!.add(req);
      } else {
        grouped.putIfAbsent(statusName, () => []).add(req);
      }
    }

    grouped.removeWhere((key, list) => list.isEmpty);
    return grouped;
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase().trim();
    if (s.contains('inquiry')) return const Color(0xFFFBBF24); // Amber
    if (s.contains('approved')) return const Color(0xFF38BDF8); // Sky Blue
    if (s.contains('runner') || s.contains('assigned')) return const Color(0xFFA78BFA); // Indigo
    if (s.contains('collected') || s.contains('received')) return const Color(0xFF34D399); // Emerald
    if (s.contains('complete')) return const Color(0xFF94A3B8); // Slate
    if (s.contains('cancel') || s.contains('reject')) return const Color(0xFFEF4444);
    return const Color(0xFF818CF8);
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
              '$count ${count == 1 ? 'Request' : 'Requests'}',
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
                _buildResizableHeader('Req ID', _idWidth, (delta) => _updateColumnWidth('id', (_idWidth + delta).clamp(80.0, 200.0))),
                _buildResizableHeader('Date', _dateWidth, (delta) => _updateColumnWidth('date', (_dateWidth + delta).clamp(80.0, 200.0))),
                _buildResizableHeader('Customer Name', _nameWidth, (delta) => _updateColumnWidth('name', (_nameWidth + delta).clamp(100.0, 300.0))),
                _buildResizableHeader('Mobile', _mobileWidth, (delta) => _updateColumnWidth('mobile', (_mobileWidth + delta).clamp(100.0, 250.0))),
                _buildResizableHeader('Requested Item', _itemWidth, (delta) => _updateColumnWidth('item', (_itemWidth + delta).clamp(120.0, 400.0))),
                _buildResizableHeader('Estimated Price', _amountWidth, (delta) => _updateColumnWidth('amount', (_amountWidth + delta).clamp(80.0, 250.0))),
              ],
            ),
          ),

          // Scrollable Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in groupedRequests.entries) ...[
                    _buildStatusSectionHeader(entry.key, entry.value.length),
                    for (final req in entry.value) ...[
                      _buildDesktopTableRow(context, viewModel, req),
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
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: _idWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                '#${req.id}',
                style: const TextStyle(color: AppTheme.primaryLight, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            Container(
              width: _dateWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                formattedDate,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
            Container(
              width: _nameWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
            Container(
              width: _mobileWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                req.mobileNo ?? '—',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: _itemWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
            Container(
              width: _amountWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '₹${req.totalAmount.toStringAsFixed(0)}',
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

  Widget _buildMobileCardsList(
    BuildContext context,
    RequestsViewModel viewModel,
    Map<String, List<RequestOrder>> groupedRequests,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80, top: 4),
      physics: const BouncingScrollPhysics(),
      itemCount: groupedRequests.entries.length,
      itemBuilder: (context, sectionIndex) {
        final entry = groupedRequests.entries.elementAt(sectionIndex);
        final status = entry.key;
        final requests = entry.value;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusSectionHeader(status, requests.length),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              itemCount: requests.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (ctx, index) {
                final req = requests[index];
                final formattedDate = DateFormat('dd/MM/yy hh:mm a').format(req.date);

                final List<Widget> metadata = [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 14, color: AppTheme.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          req.item,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        formattedDate,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  if (req.assignedRunnerName != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.directions_walk_rounded, size: 14, color: Color(0xFFA78BFA)),
                        const SizedBox(width: 6),
                        Text(
                          'Runner: ${req.assignedRunnerName} (${req.targetBuilding ?? 'Market'})',
                          style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Advance: ₹${req.advance.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      Text(
                        'Est: ₹${req.totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                      ),
                    ],
                  ),
                ];

                return AppListCard(
                  title: req.customerName,
                  statusBadge: _buildStatusChip(req.status),
                  metadataRows: metadata,
                  onTap: () => _showDetailDialog(context, req, viewModel),
                  onEdit: () => _showAddEditDialog(context, existingRequest: req),
                  onDelete: () => _confirmDelete(context, req.id, viewModel),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showDetailDialog(
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
      title: 'Procurement Request #${req.id}',
      subtitle: 'Logged on $formattedDate',
      contentBuilder: (ctx, scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScaledInfoRow(label: 'Customer Name', value: req.customerName, scaleFactor: scale),
            ScaledInfoRow(label: 'Mobile Number', value: req.mobileNo ?? 'N/A', scaleFactor: scale),
            ScaledInfoRow(label: 'Requested Item', value: req.item, scaleFactor: scale),
            ScaledInfoRow(label: 'Status', value: req.status, scaleFactor: scale),
            ScaledInfoRow(label: 'Advance Paid', value: '₹${req.advance.toStringAsFixed(2)}', scaleFactor: scale),
            ScaledInfoRow(label: 'Total Estimate', value: '₹${req.totalAmount.toStringAsFixed(2)}', scaleFactor: scale),
            if (req.dealerName != null && req.dealerName!.isNotEmpty)
              ScaledInfoRow(label: 'Target Dealer', value: req.dealerName!, scaleFactor: scale),
            if (req.targetBuilding != null && req.targetBuilding!.isNotEmpty)
              ScaledInfoRow(
                label: 'Building & Floor',
                value: '${req.targetBuilding} ${req.targetShopNo != null ? '(${req.targetShopNo})' : ''}',
                scaleFactor: scale,
              ),
            if (req.assignedRunnerName != null)
              ScaledInfoRow(label: 'Assigned Runner', value: req.assignedRunnerName!, scaleFactor: scale),
            if (req.actualPurchaseCost != null)
              ScaledInfoRow(label: 'Actual Cost Paid', value: '₹${req.actualPurchaseCost!.toStringAsFixed(2)}', scaleFactor: scale),
            if (req.estimate != null && req.estimate!.isNotEmpty)
              ScaledInfoRow(label: 'Internal Notes', value: req.estimate!, scaleFactor: scale),

            if (req.photoList.isNotEmpty) ...[
              SizedBox(height: 10 * scale),
              Text('Part Reference Photos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12 * scale)),
              const SizedBox(height: 6),
              PhotoGallerySection(photoUrls: req.photoList),
            ],

            if (req.billPhotoList.isNotEmpty) ...[
              SizedBox(height: 10 * scale),
              Text('Runner Market Bill Receipt', style: TextStyle(color: Color(0xFF34D399), fontSize: 12 * scale, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              PhotoGallerySection(photoUrls: req.billPhotoList),
            ],

            SizedBox(height: 14 * scale),
            Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
            SizedBox(height: 12 * scale),

            // Action Pills Grid
            Wrap(
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
                ScaledActionButton(
                  icon: Icons.phone_rounded,
                  label: 'Call Customer',
                  color: const Color(0xFF10B981),
                  scaleFactor: scale,
                  onTap: () => _launchPhone(req.mobileNo ?? ''),
                ),
                ScaledActionButton(
                  iconWidget: WhatsAppIcon(size: 32 * scale),
                  label: 'WhatsApp Customer',
                  scaleFactor: scale,
                  onTap: () => _launchWhatsApp(req),
                ),
                ScaledActionButton(
                  icon: Icons.point_of_sale_rounded,
                  label: 'Convert to POS Sale',
                  scaleFactor: scale,
                  onTap: () => _convertToSale(ctx, req),
                ),
              ],
            ),
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

  void _showAssignRunnerDialog(
    BuildContext context,
    RequestOrder req,
    RequestsViewModel viewModel,
  ) {
    final allUsers = UserPermissionService.getAllUsers();
    final allDealers = context.read<ShopRepository>().getDealers();

    String selectedRunnerEmail = allUsers.isNotEmpty ? allUsers.first.email : '';
    String selectedRunnerName = allUsers.isNotEmpty ? allUsers.first.name : '';
    String dealerName = req.dealerName ?? '';
    String building = req.targetBuilding ?? 'Meghdoot Building';
    String shopNo = req.targetShopNo ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF0F1524),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
          title: Row(
            children: [
              const Icon(Icons.directions_walk_rounded, color: Color(0xFFA78BFA)),
              const SizedBox(width: 10),
              const Text('Assign Task to Runner', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Item: ${req.item}', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),

                // Select Runner Staff
                const Text('Select Runner Staff *', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: selectedRunnerEmail,
                  dropdownColor: const Color(0xFF131A2E),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  items: allUsers.map((u) => DropdownMenuItem(value: u.email, child: Text('${u.name} (${u.role})'))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDlgState(() {
                        selectedRunnerEmail = val;
                        selectedRunnerName = allUsers.firstWhere((u) => u.email == val).name;
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Target Dealer
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: dealerName),
                  optionsBuilder: (textVal) {
                    if (textVal.text.isEmpty) return allDealers.map((d) => d.name);
                    return allDealers.where((d) => d.name.toLowerCase().contains(textVal.text.toLowerCase())).map((d) => d.name);
                  },
                  onSelected: (val) {
                    final d = allDealers.where((e) => e.name == val).firstOrNull;
                    setDlgState(() {
                      dealerName = val;
                      if (d?.buildingName != null) building = d!.buildingName!;
                      if (d?.shopNo != null) shopNo = d!.shopNo!;
                    });
                  },
                  fieldViewBuilder: (ctx, controller, focus, onSub) {
                    controller.addListener(() => dealerName = controller.text);
                    return TextFormField(
                      controller: controller,
                      focusNode: focus,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Shortlisted Dealer / Shop',
                        hintText: 'e.g. Pro Lab, Caviar Technologies',
                        prefixIcon: Icon(Icons.storefront_rounded, size: 18),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Building & Shop No
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: building,
                        onChanged: (v) => building = v,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Building Name',
                          hintText: 'e.g. Siddharth Bldg',
                          prefixIcon: Icon(Icons.location_city_rounded, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: shopNo,
                        onChanged: (v) => shopNo = v,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Shop / Floor',
                          hintText: 'e.g. 204',
                          prefixIcon: Icon(Icons.room_rounded, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await viewModel.assignRunner(
                  requestId: req.id,
                  runnerId: selectedRunnerEmail,
                  runnerName: selectedRunnerName,
                  dealerName: dealerName,
                  building: building,
                  shopNo: shopNo,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Assigned #${req.id} to $selectedRunnerName!'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA78BFA)),
              child: const Text('Assign Task'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBroadcastDialog(BuildContext context, RequestOrder req) {
    final dealers = context.read<ShopRepository>().getDealers();
    final withMobile = dealers.where((d) => d.mobileNo != null && d.mobileNo!.trim().isNotEmpty).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1524),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white12)),
        title: Row(
          children: [
            const Icon(Icons.campaign_rounded, color: Color(0xFFF59E0B)),
            const SizedBox(width: 10),
            const Text('Dispatch Dealer Inquiries', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Inquire stock & price for "${req.item}" across market vendors:', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 12),
              SizedBox(
                height: 300,
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: withMobile.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (context, idx) {
                    final d = withMobile[idx];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('${d.buildingName ?? 'Nehru Place'} • ${d.category ?? 'General'}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                      trailing: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Color(0xFF22D3EE), size: 18),
                        tooltip: 'Send WhatsApp Inquiry',
                        onPressed: () {
                          String phone = d.mobileNo!.replaceAll(RegExp(r'[^0-9]'), '');
                          if (phone.length == 10) phone = '91$phone';
                          final msg = Uri.encodeComponent(
                            'Hi ${d.name}, Perfect Solution inquiry: Do you have "${req.item}" in stock? Please share availability and best price rate.',
                          );
                          launchUrl(Uri.parse('https://wa.me/$phone?text=$msg'), mode: LaunchMode.externalApplication);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, String id, RequestsViewModel viewModel) {
    if (!UserPermissionService.canPerformModuleAction('requests', 'canDelete')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access Denied: You do not have permission to delete Requests.'), backgroundColor: AppTheme.danger),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Special Request?'),
        content: const Text('Are you sure you want to permanently delete this special request record?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await viewModel.deleteRequest(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request deleted successfully.'), backgroundColor: AppTheme.success));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddEditDialog(
    BuildContext context, {
    RequestOrder? existingRequest,
    String? prefillName,
    String? prefillMobile,
    String? prefillItem,
    double? prefillAmount,
  }) {
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

    showAppModalDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RequestFormDialog(
        existingRequest: existingRequest,
        prefillName: prefillName,
        prefillMobile: prefillMobile,
        prefillItem: prefillItem,
        prefillAmount: prefillAmount,
      ),
    );
  }

  void _launchPhone(String number) async {
    if (number.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _launchWhatsApp(RequestOrder r) {
    final mobileNo = r.mobileNo;
    if (mobileNo == null || mobileNo.trim().isEmpty) return;
    final message = "Hello ${r.customerName}, We have updated your request item ${r.item} status to ${r.status}. Perfect Solution";
    WhatsAppService.launch(mobileNo: mobileNo, message: message);
  }

  void _convertToSale(BuildContext context, RequestOrder r) {
    final navVM = context.read<NavigationViewModel>();
    navVM.setIndex(
      NavigationViewModel.sales,
      prefillData: {
        'target': 'sales',
        'customerName': r.customerName,
        'customerNumber': r.mobileNo,
        'advance': r.advance,
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

  const _RequestFormDialog({
    this.existingRequest,
    this.prefillName,
    this.prefillMobile,
    this.prefillItem,
    this.prefillAmount,
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

  @override
  void initState() {
    super.initState();
    final r = widget.existingRequest;
    _requestDate = r?.date ?? DateTime.now();
    _nameController = TextEditingController(text: r?.customerName ?? widget.prefillName ?? '');
    _mobileController = TextEditingController(text: r?.mobileNo ?? widget.prefillMobile ?? '');
    _itemController = TextEditingController(text: r?.item ?? widget.prefillItem ?? '');
    _advanceController = TextEditingController(text: (r != null && r.advance > 0) ? r.advance.toStringAsFixed(0) : '');
    _totalAmountController = TextEditingController(
      text: (r != null && r.totalAmount > 0) ? r.totalAmount.toStringAsFixed(0) : ((widget.prefillAmount != null && widget.prefillAmount! > 0) ? widget.prefillAmount!.toStringAsFixed(0) : ''),
    );
    _dealerController = TextEditingController(text: r?.dealerName ?? '');
    _estimateController = TextEditingController(text: r?.estimate ?? '');
    _photoUrl = r?.photo;
    _status = r?.status ?? RequestOrder.statusInquirySent;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _itemController.dispose();
    _advanceController.dispose();
    _totalAmountController.dispose();
    _dealerController.dispose();
    _estimateController.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    final viewModel = context.read<RequestsViewModel>();
    final isEdit = widget.existingRequest != null;

    final advance = double.tryParse(_advanceController.text.trim()) ?? 0.0;
    final total = double.tryParse(_totalAmountController.text.trim()) ?? 0.0;

    final order = RequestOrder(
      id: isEdit ? widget.existingRequest!.id : viewModel.getNextId(),
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
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEdit ? 'Request updated successfully' : 'Request created successfully'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingRequest != null;
    final dealers = context.read<ShopRepository>().getDealers();

    return Dialog(
      backgroundColor: const Color(0xFF0F1524),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white10)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.inventory_2_rounded, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  isEdit ? 'Edit Part Request' : 'New Part Request',
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary)),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Colors.white10),
            const SizedBox(height: 16),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      DateTimePickerField(
                        label: 'Request Date *',
                        selectedDateTime: _requestDate,
                        onDateTimeChanged: (d) => setState(() => _requestDate = d),
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(labelText: 'Customer Name *', prefixIcon: Icon(Icons.person_outline_rounded, size: 20)),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Enter customer name' : null,
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(labelText: 'Mobile Number', prefixIcon: Icon(Icons.phone_android_rounded, size: 20)),
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _itemController,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(labelText: 'Requested Item / Part *', prefixIcon: Icon(Icons.laptop_chromebook_rounded, size: 20)),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Enter requested item details' : null,
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _advanceController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              decoration: const InputDecoration(labelText: 'Advance Paid (₹)', prefixIcon: Icon(Icons.payments_outlined, size: 20)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _totalAmountController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              decoration: const InputDecoration(labelText: 'Estimated Total (₹)', prefixIcon: Icon(Icons.receipt_outlined, size: 20)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Dealer Autocomplete
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
                            style: const TextStyle(color: AppTheme.textPrimary),
                            decoration: const InputDecoration(labelText: 'Dealer / Vendor Sourced', prefixIcon: Icon(Icons.storefront_rounded, size: 20)),
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // Status Picker
                      DropdownButtonFormField<String>(
                        value: _status,
                        dropdownColor: const Color(0xFF131A2E),
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(labelText: 'Procurement Status', prefixIcon: Icon(Icons.flag_outlined, size: 20)),
                        items: RequestOrder.allStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _status = val);
                        },
                      ),
                      const SizedBox(height: 14),

                      PhotoAttachmentWidget(
                        initialPhotoUrl: _photoUrl,
                        onPhotoChanged: (url) => setState(() => _photoUrl = url),
                        label: 'Attach Part Photos (Zoom / Comparison)',
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _estimateController,
                        maxLines: 2,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(labelText: 'Internal Notes', prefixIcon: Icon(Icons.notes_rounded, size: 20)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(isEdit ? 'Save Changes' : 'Create Request'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

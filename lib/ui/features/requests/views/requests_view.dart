import 'package:flutter/material.dart';
import '../../../shared/date_time_picker_field.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../data/models/request_order.dart';
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
import '../../../shared/components/app_header_sync_button.dart';
import '../../../shared/components/app_search_filter_bar.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../../../shared/resizable_detail_popup.dart';
import '../../../shared/status_management_dialog.dart';
import '../../../shared/whatsapp_icon.dart';
import '../../../../data/services/user_permission_service.dart';
import '../view_models/requests_view_model.dart';

class RequestsView extends StatefulWidget {
  const RequestsView({super.key});

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
  double _mobileWidth = 130.0;
  double _itemWidth = 200.0;
  double _amountWidth = 120.0;
  // ignore: unused_field
  double _statusWidth = 120.0;

  void _loadSavedColumnWidths() {
    _idWidth = UiPreferencesService.getColumnWidth('requests', 'id') ?? 120.0;
    _dateWidth =
        UiPreferencesService.getColumnWidth('requests', 'date') ?? 120.0;
    _nameWidth =
        UiPreferencesService.getColumnWidth('requests', 'name') ?? 180.0;
    _mobileWidth =
        UiPreferencesService.getColumnWidth('requests', 'mobile') ?? 130.0;
    _itemWidth =
        UiPreferencesService.getColumnWidth('requests', 'item') ?? 200.0;
    _amountWidth =
        UiPreferencesService.getColumnWidth('requests', 'amount') ?? 120.0;
    _statusWidth =
        UiPreferencesService.getColumnWidth('requests', 'status') ?? 120.0;
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
    final String mobile =
        prefill['mobileNo'] ?? prefill['customerNumber'] ?? '';
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

    return Consumer<RequestsViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading && viewModel.requests.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
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
          final mobileMatch =
              r.mobileNo?.toLowerCase().contains(query) ?? false;
          final statusMatch = r.status.toLowerCase().contains(query);
          final dealerMatch =
              r.dealerName?.toLowerCase().contains(query) ?? false;
          return idMatch ||
              nameMatch ||
              itemMatch ||
              mobileMatch ||
              statusMatch ||
              dealerMatch;
        }).toList();

        // Sort by date descending (newest requests first)
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
                title: 'Requests',
                subtitle: 'Special Parts & Customer Pre-orders',
                actions: [
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
                      hintText: 'Search ID, customer, item, dealer, status...',
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
                              icon: const Icon(Icons.clear_rounded, size: 18),
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
                  }),
                  hintText: 'Search request ID, customer, item...',
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
                            groupedRequests,
                          )
                        : _buildMobileCardsList(
                            context,
                            viewModel,
                            groupedRequests,
                          )),
              ),
            ],
          ),
        );
      },
    );
  }

  Map<String, List<RequestOrder>> _getGroupedRequests(
    List<RequestOrder> requests,
  ) {
    final List<String> configuredStatuses =
        StatusManagementService.getStatuses('requests');
    final Map<String, List<RequestOrder>> grouped = {};

    for (final status in configuredStatuses) {
      grouped[status] = [];
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
        if (!grouped.containsKey(statusName)) {
          grouped[statusName] = [];
        }
        grouped[statusName]!.add(req);
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
      icon: Icons.inventory_2_outlined,
      title: 'No Part Requests Found',
      message: 'No order request records match your search criteria.',
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
                    (_nameWidth + delta).clamp(100.0, 300.0),
                  ),
                ),
                _buildResizableHeader(
                  'Mobile',
                  _mobileWidth,
                  (delta) => _updateColumnWidth(
                    'mobile',
                    (_mobileWidth + delta).clamp(100.0, 250.0),
                  ),
                ),
                _buildResizableHeader(
                  'Requested Item',
                  _itemWidth,
                  (delta) => _updateColumnWidth(
                    'item',
                    (_itemWidth + delta).clamp(120.0, 400.0),
                  ),
                ),
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

          // Scrollable Body grouped by Status
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
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
              width: _dateWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(formattedDate),
            ),
            Container(
              width: _nameWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                req.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: _mobileWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(req.mobileNo ?? '-'),
            ),
            Container(
              width: _itemWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                req.item,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: _amountWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                req.totalAmount > 0
                    ? '₹${req.totalAmount.toStringAsFixed(0)}'
                    : '-',
                style: const TextStyle(fontWeight: FontWeight.w600),
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

  Widget _buildStatusChip(String status) {
    Color chipColor = AppTheme.warning;
    final lower = status.toLowerCase();
    if (lower.contains('complete')) {
      chipColor = AppTheme.success;
    } else if (lower.contains('received')) {
      chipColor = AppTheme.primaryLight;
    } else if (lower.contains('pending')) {
      chipColor = AppTheme.warning;
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

  Widget _buildMobileCardsList(
    BuildContext context,
    RequestsViewModel viewModel,
    Map<String, List<RequestOrder>> groupedRequests,
  ) {
    return RefreshIndicator(
      color: AppTheme.primaryLight,
      backgroundColor: const Color(0xFF131A2E),
      onRefresh: () async {
        final localDb = context.read<ShopRepository>().localDb;
        await SupabaseSyncService.instance.syncAllTablesFromCloud(localDb);
        if (context.mounted) viewModel.loadRequests();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in groupedRequests.entries) ...[
              _buildStatusSectionHeader(entry.key, entry.value.length),
              for (final req in entry.value) ...[
                _buildMobileRequestCard(context, viewModel, req),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileRequestCard(
    BuildContext context,
    RequestsViewModel viewModel,
    RequestOrder req,
  ) {
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

    return AppListCard(
      title: req.customerName,
      statusBadge: _buildStatusChip(req.status),
      metadataRows: metadata,
      onTap: () => _showDetailDialog(context, req, viewModel),
      onEdit: () => _showAddEditDialog(context, existingRequest: req),
      onDelete: () => _confirmDelete(context, req.id, viewModel),
    );
  }

  void _confirmDelete(
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

  void _showDetailDialog(
    BuildContext context,
    RequestOrder req,
    RequestsViewModel viewModel,
  ) {
    final repo = context.read<ShopRepository>();
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(req.date);

    ResizableDetailPopup.show(
      context: context,
      repository: repo,
      title: 'Request Details',
      subtitle: 'Logged on $formattedDate',
      contentBuilder: (ctx, scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScaledInfoRow(
              label: 'Request ID',
              value: req.id,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Customer Name',
              value: req.customerName,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Mobile Number',
              value: req.mobileNo ?? 'N/A',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Requested Item',
              value: req.item,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Advance Paid',
              value: '₹${req.advance.toStringAsFixed(2)}',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Total Estimated Price',
              value: '₹${req.totalAmount.toStringAsFixed(2)}',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Dealer Name / Vendor',
              value: req.dealerName ?? 'N/A',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Status',
              value: req.status,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Notes',
              value: req.estimate ?? 'N/A',
              scaleFactor: scale,
            ),
            if (req.photoList.isNotEmpty)
              PhotoGallerySection(photoUrls: req.photoList),
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
                  onTap: () => _launchPhone(req.mobileNo ?? ''),
                ),
                ScaledActionButton(
                  iconWidget: WhatsAppIcon(size: 32 * scale),
                  label: 'WhatsApp',
                  scaleFactor: scale,
                  onTap: () => _launchWhatsApp(req),
                ),
                ScaledActionButton(
                  icon: Icons.copy,
                  label: 'Duplicate',
                  scaleFactor: scale,
                  onTap: () {
                    Navigator.pop(ctx);
                    _duplicate(context, req);
                  },
                ),
                ScaledActionButton(
                  icon: Icons.sell,
                  label: 'Convert to Sale',
                  scaleFactor: scale,
                  onTap: () => _convertToSale(ctx, req),
                ),
                ScaledActionButton(
                  icon: Icons.build,
                  label: 'Enter in Inward',
                  scaleFactor: scale,
                  onTap: () => _enterInModule(ctx, 'inward', req),
                ),
                ScaledActionButton(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Enter in Replacement',
                  scaleFactor: scale,
                  onTap: () => _enterInModule(ctx, 'replacement', req),
                ),
                ScaledActionButton(
                  icon: Icons.shopping_cart,
                  label: 'Enter in Purchase',
                  scaleFactor: scale,
                  onTap: () => _enterInModule(ctx, 'purchase', req),
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
                    _confirmDelete(context, req.id, viewModel);
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
          content: Text(
            isEdit
                ? 'Access Denied: You do not have permission to edit Customer Requests.'
                : 'Access Denied: You do not have permission to create new Customer Requests.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    showDialog(
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

  void _launchPhone(String number) async {
    if (number.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _launchWhatsApp(RequestOrder r) {
    final mobileNo = r.mobileNo;
    if (mobileNo == null || mobileNo.trim().isEmpty) return;
    final message =
        "Hello ${r.customerName}, We have updated your request item ${r.item} status to ${r.status}. Perfect Solution";
    WhatsAppService.launch(mobileNo: mobileNo, message: message);
  }

  void _duplicate(BuildContext context, RequestOrder r) {
    showDialog(
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

  void _enterInModule(BuildContext context, String target, RequestOrder r) {
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

// ==========================================================
// ADD/EDIT FORM DIALOG IMPLEMENTATION
// ==========================================================
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

    final viewModel = context.read<RequestsViewModel>();
    final String id = widget.existingRequest?.id ?? viewModel.getNextId();

    final r = RequestOrder(
      id: id,
      date: _requestDate,
      customerName: _nameController.text.trim(),
      mobileNo: _mobileController.text.trim().isEmpty
          ? null
          : _mobileController.text.trim(),
      item: _itemController.text.trim(),
      advance: double.tryParse(_advanceController.text.trim()) ?? 0.0,
      totalAmount: double.tryParse(_totalAmountController.text.trim()) ?? 0.0,
      dealerName: _dealerController.text.trim().isEmpty
          ? null
          : _dealerController.text.trim(),
      status: _status,
      estimate: _estimateController.text.trim().isEmpty
          ? null
          : _estimateController.text.trim(),
      photo: _photoUrl,
    );

    await viewModel.saveRequest(r);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existingRequest == null
                ? 'Request created successfully'
                : 'Request updated successfully',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.existingRequest != null;
    final bool isMobile = MediaQuery.of(context).size.width < 700;

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
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Requested Item *',
                hintText: 'e.g. ASUS Zephyrus G14 Battery',
              ),
              validator: (val) => val == null || val.trim().isEmpty
                  ? 'Please enter item name'
                  : null,
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
                      labelText: 'Total Estimate Price (₹)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              if (isDealerVis)
                Expanded(
                  child: TextFormField(
                    controller: _dealerController,
                    readOnly: !isDealerMod,
                    enabled: isDealerMod,
                    decoration: const InputDecoration(
                      labelText: 'Dealer Name / Source Vendor',
                    ),
                  ),
                ),
              if (isDealerVis && isStatusVis) const SizedBox(width: 12),
              if (isStatusVis)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    dropdownColor: const Color(0xFF131A2E),
                    onChanged: isStatusMod
                        ? (val) {
                            if (val != null) setState(() => _status = val);
                          }
                        : null,
                    items:
                        (() {
                          final list =
                              UserPermissionService.getAllowedSelectableStatuses(
                            'requests',
                          );
                          final List<String> selectableList = List.from(list);
                          if (_status.isNotEmpty && !selectableList.any((s) => s.toLowerCase() == _status.toLowerCase())) {
                            selectableList.insert(0, _status);
                          }
                          return selectableList;
                        })().map((st) {
                          return DropdownMenuItem(value: st, child: Text(st));
                        }).toList(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _estimateController,
            decoration: const InputDecoration(
              labelText: 'Estimate Details & Private Notes',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 12),

          PhotoAttachmentWidget(
            initialPhotoUrl: _photoUrl,
            label: 'Sample / Requested Item Photo(s)',
            onUploadingChanged: (uploading) {
              setState(() {
                _isPhotoUploading = uploading;
              });
            },
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
        ElevatedButton(onPressed: _saveForm, child: const Text('Save Request')),
      ],
    );
  }
}

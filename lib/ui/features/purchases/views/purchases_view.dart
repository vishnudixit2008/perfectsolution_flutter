import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/purchase_order.dart';
import '../../../../data/models/purchase_order_item.dart';
import '../../../../data/models/pricelist_item.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/supabase_sync_service.dart';
import '../../../../data/services/ui_preferences_service.dart';
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
import '../../../shared/components/app_pagination_bar.dart';

import '../../pricelist/view_models/pricelist_view_model.dart';
import '../../pricelist/views/pricelist_view.dart';
import '../view_models/purchases_view_model.dart';
import '../../../../data/services/user_permission_service.dart';

class PurchasesView extends StatefulWidget {
  const PurchasesView({super.key});

  @override
  State<PurchasesView> createState() => _PurchasesViewState();
}

class _PurchasesViewState extends State<PurchasesView> {
  final TextEditingController _searchController = TextEditingController();

  // Table columns widths
  // ignore: unused_field
  double _idWidth = 120.0;
  double _dateWidth = 120.0;
  double _vendorWidth = 220.0;
  double _amountWidth = 150.0;
  // ignore: unused_field
  double _statusWidth = 140.0;

  void _loadSavedColumnWidths() {
    _idWidth = UiPreferencesService.getColumnWidth('purchases', 'id') ?? 120.0;
    _dateWidth =
        UiPreferencesService.getColumnWidth('purchases', 'date') ?? 120.0;
    _vendorWidth =
        UiPreferencesService.getColumnWidth('purchases', 'vendor') ?? 220.0;
    _amountWidth =
        UiPreferencesService.getColumnWidth('purchases', 'amount') ?? 150.0;
    _statusWidth =
        UiPreferencesService.getColumnWidth('purchases', 'status') ?? 140.0;
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
        case 'vendor':
          _vendorWidth = newWidth;
          break;
        case 'amount':
          _amountWidth = newWidth;
          break;
        case 'status':
          _statusWidth = newWidth;
          break;
      }
    });
    UiPreferencesService.setColumnWidth('purchases', columnKey, newWidth);
  }

  // Pagination states
  int _currentPage = 1;
  int _itemsPerPage = 20;

  @override
  void initState() {
    super.initState();
    _loadSavedColumnWidths();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PurchasesViewModel>().loadPurchases();
      context.read<PricelistViewModel>().loadItems();
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
    final String vendor = prefill['purchasedFrom'] ?? '';
    final String item = prefill['item'] ?? '';
    final double amount = prefill['totalAmount'] ?? prefill['amount'] ?? 0.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAddEditDialog(
        context,
        prefillVendor: vendor,
        prefillItem: item,
        prefillAmount: amount,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final navVM = context.watch<NavigationViewModel>();
    final prefill = navVM.pendingPrefillData;
    if (prefill != null && prefill['target'] == 'purchase') {
      _handlePrefillData(context, prefill, navVM);
    }

    return Consumer<PurchasesViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading && viewModel.purchases.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isDesktop = screenWidth >= 800;

        // Filtering
        final query = _searchController.text.trim().toLowerCase();
        final filtered = viewModel.purchases.where((p) {
          if (!UserPermissionService.isStatusVisible('purchases', p.status)) {
            return false;
          }
          if (query.isEmpty) return true;
          final idMatch = p.id.toLowerCase().contains(query);
          final vendorMatch = p.purchasedFrom.toLowerCase().contains(query);
          final statusMatch = p.status.toLowerCase().contains(query);
          final notesMatch = p.notes?.toLowerCase().contains(query) ?? false;
          return idMatch || vendorMatch || statusMatch || notesMatch;
        }).toList();

        // Sort by date descending (newest purchases first)
        filtered.sort((a, b) => b.date.compareTo(a.date));

        final int totalPages = (filtered.length / _itemsPerPage).ceil();
        final int currentPage = _currentPage.clamp(
          1,
          totalPages > 0 ? totalPages : 1,
        );
        final int startIndex = (currentPage - 1) * _itemsPerPage;
        final int endIndex = (startIndex + _itemsPerPage).clamp(
          0,
          filtered.length,
        );
        final pagedPurchases = filtered.isEmpty
            ? <PurchaseOrder>[]
            : filtered.sublist(startIndex, endIndex);

        final groupedPurchases = _getGroupedPurchases(pagedPurchases);

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton:
              (!isDesktop &&
                      UserPermissionService.canPerformModuleAction(
                        'purchases',
                        'canAdd',
                      ))
                  ? AppFloatingActionButton(
                      onPressed: () => _showAddEditDialog(context),
                      tooltip: 'Add Purchase',
                    )
                  : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: 'Purchases',
                subtitle: 'Vendor Procurement & Stock Inwarding',
                actions: [
                  if (isDesktop && UserPermissionService.canPerformModuleAction('purchases', 'canAdd'))
                    AppHeaderActionButton(
                      label: 'New Purchase',
                      icon: Icons.add_rounded,
                      onPressed: () => _showAddEditDialog(context),
                    ),
                  if (!isDesktop)
                    AppHeaderSyncButton(
                      onSynced: () => context.read<PurchasesViewModel>().loadPurchases(),
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () {
                      StatusManagementDialog.show(
                        context,
                        moduleKey: 'purchases',
                        moduleTitle: 'Purchase',
                        onStatusesUpdated: () {
                          StatusManagementService.invalidateCache('purchases');
                          context.read<PurchasesViewModel>().loadPurchases();
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
                      hintText: 'Search ID, vendor, status, notes...',
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
                    _currentPage = 1;
                  }),
                  hintText: 'Search purchase ID, vendor...',
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
                              groupedPurchases,
                              currentPage,
                              totalPages,
                            )
                          : Stack(
                              children: [
                                Positioned.fill(
                                  child: _buildMobileCardsList(
                                    context,
                                    viewModel,
                                    groupedPurchases,
                                  ),
                                ),
                                if (totalPages > 1)
                                  Positioned(
                                    bottom: 12,
                                    left: 8,
                                    child: _buildFloatingPaginationIsland(
                                        currentPage: currentPage,
                                        totalPages: totalPages,
                                        itemsPerPage: _itemsPerPage,
                                        onItemsPerPageChanged: (val) {
                                          setState(() {
                                            _itemsPerPage = val;
                                            _currentPage = 1;
                                          });
                                        },
                                        onPreviousPage: () {
                                          if (_currentPage > 1) {
                                            setState(() {
                                              _currentPage--;
                                            });
                                          }
                                        },
                                        onNextPage: () {
                                          if (_currentPage < totalPages) {
                                            setState(() {
                                              _currentPage++;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                              ],
                            )),
              ),
            ],
          ),
        );
      },
    );
  }

  Map<String, List<PurchaseOrder>> _getGroupedPurchases(
    List<PurchaseOrder> purchases,
  ) {
    final List<String> configuredStatuses = StatusManagementService.getStatuses(
      'purchases',
    );
    final Map<String, List<PurchaseOrder>> grouped = {};

    for (final status in configuredStatuses) {
      grouped[status] = [];
    }

    for (final pur in purchases) {
      final statusName = pur.status.trim();
      final existingKey = grouped.keys.firstWhere(
        (k) => k.toLowerCase() == statusName.toLowerCase(),
        orElse: () => '',
      );

      if (existingKey.isNotEmpty) {
        grouped[existingKey]!.add(pur);
      } else {
        if (!grouped.containsKey(statusName)) {
          grouped[statusName] = [];
        }
        grouped[statusName]!.add(pur);
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
              '$count ${count == 1 ? 'Purchase' : 'Purchases'}',
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
    if (s == 'ready return' || s == 'ready-return') {
      return const Color(0xFFCA8A04); // Dull Yellow
    }
    if (s == 'ready') return const Color(0xFFEAB308); // Yellow
    if (s.contains('hold')) return const Color(0xFF06B6D4); // Cyan
    if (s.contains('complete') ||
        s.contains('pre complete') ||
        s.contains('pre-complete')) {
      return const Color(0xFF10B981); // Green
    }
    if (s.contains('cancel') || s.contains('reject')) {
      return const Color(0xFFEF4444);
    }
    if (s.contains('pending')) return const Color(0xFFF97316);
    return const Color(0xFF6366F1);
  }

  Widget _buildEmptyState() {
    return AppEmptyState(
      icon: Icons.shopping_bag_outlined,
      title: 'No Purchases Found',
      message: 'No purchase order records match your search criteria.',
      actionLabel: 'Add Purchase',
      onAction: () => _showAddEditDialog(context),
    );
  }

  Widget _buildDesktopTable(
    BuildContext context,
    PurchasesViewModel viewModel,
    Map<String, List<PurchaseOrder>> groupedPurchases,
    int currentPage,
    int totalPages,
  ) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
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
                        'Purchased From (Vendor)',
                        _vendorWidth,
                        (delta) => _updateColumnWidth(
                          'vendor',
                          (_vendorWidth + delta).clamp(120.0, 450.0),
                        ),
                      ),
                      _buildResizableHeader(
                        'Total Amount',
                        _amountWidth,
                        (delta) => _updateColumnWidth(
                          'amount',
                          (_amountWidth + delta).clamp(100.0, 300.0),
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable Body grouped by Status
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in groupedPurchases.entries) ...[
                          _buildStatusSectionHeader(
                            entry.key,
                            entry.value.length,
                          ),
                          for (final pur in entry.value) ...[
                            _buildDesktopTableRow(context, viewModel, pur),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: AppPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            itemsPerPage: _itemsPerPage,
            onItemsPerPageChanged: (val) => setState(() {
              _itemsPerPage = val;
              _currentPage = 1;
            }),
            onPreviousPage: () => setState(() => _currentPage--),
            onNextPage: () => setState(() => _currentPage++),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopTableRow(
    BuildContext context,
    PurchasesViewModel viewModel,
    PurchaseOrder pur,
  ) {
    final formattedDate = DateFormat('dd/MM/yy').format(pur.date);
    return InkWell(
      onTap: () => _showDetailDialog(context, pur, viewModel),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.04)),
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
              width: _vendorWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                pur.purchasedFrom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: _amountWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '₹${pur.totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
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
    PurchasesViewModel viewModel,
    Map<String, List<PurchaseOrder>> groupedPurchases,
  ) {
    return RefreshIndicator(
      color: AppTheme.primaryLight,
      backgroundColor: const Color(0xFF131A2E),
      onRefresh: () async {
        final localDb = context.read<ShopRepository>().localDb;
        await SupabaseSyncService.instance.syncAllTablesFromCloud(localDb);
        if (context.mounted) viewModel.loadPurchases();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in groupedPurchases.entries) ...[
              _buildStatusSectionHeader(entry.key, entry.value.length),
              for (final pur in entry.value) ...[
                _buildMobilePurchaseCard(context, viewModel, pur),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobilePurchaseCard(
    BuildContext context,
    PurchasesViewModel viewModel,
    PurchaseOrder pur,
  ) {
    final formattedDate = DateFormat('dd MMM yyyy').format(pur.date);
    final metadata = <Widget>[];

    metadata.add(
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Total Amount: ₹${pur.totalAmount.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.success,
            ),
          ),
          Text(
            formattedDate,
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );

    return AppListCard(
      title: 'Vendor: ${pur.purchasedFrom}',
      subtitle: 'Order ID: ${pur.id}',
      statusBadge: _buildStatusChip(pur.status),
      metadataRows: metadata,
      onTap: () => _showDetailDialog(context, pur, viewModel),
      onEdit: () => _showAddEditDialog(context, existingPurchase: pur),
      onDelete: () => _confirmDelete(context, pur.id, viewModel),
    );
  }

  Widget _buildStatusChip(String status) {
    Color chipColor = AppTheme.warning;
    final lower = status.toLowerCase();
    if (lower.contains('confirm')) {
      chipColor = AppTheme.success;
    } else {
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

  // ignore: unused_element
  void _confirmStockIn(
    BuildContext context,
    String id,
    PurchasesViewModel viewModel,
  ) async {
    final success = await viewModel.confirmPurchase(id);
    if (context.mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Stock-in confirmed! Pricelist quantities have been updated.',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error confirming stock-in.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _confirmDelete(
    BuildContext context,
    String id,
    PurchasesViewModel viewModel,
  ) {
    if (!UserPermissionService.canPerformModuleAction('purchases', 'canDelete')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to delete Purchase Orders.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Purchase Record?'),
          content: const Text(
            'Are you sure you want to permanently delete this purchase record? If it was confirmed, stock quantities will NOT be automatically reverted. Action cannot be undone.',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await viewModel.deletePurchase(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Purchase record deleted successfully.'),
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
    PurchaseOrder pur,
    PurchasesViewModel viewModel,
  ) {
    final repo = context.read<ShopRepository>();
    final items = viewModel.getPurchaseItems(pur.id);
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(pur.date);

    ResizableDetailPopup.show(
      context: context,
      repository: repo,
      title: 'Purchase Details',
      subtitle: 'Logged on $formattedDate',
      contentBuilder: (ctx, scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScaledInfoRow(
              label: 'Purchase ID',
              value: pur.id,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Purchased From (Vendor)',
              value: pur.purchasedFrom,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Total Purchase Amount',
              value: '₹${pur.totalAmount.toStringAsFixed(2)}',
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Status',
              value: pur.status,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Notes',
              value: pur.notes ?? 'N/A',
              scaleFactor: scale,
            ),
            if (items.isNotEmpty) ...[
              SizedBox(height: 8 * scale),
              Text(
                'Line Items (${items.length})',
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
                        (it.itemName != null && it.itemName!.isNotEmpty)
                            ? it.itemName!
                            : (it.customItemName != null && it.customItemName!.isNotEmpty)
                                ? it.customItemName!
                                : 'Purchase Item (${it.lineId})',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${it.quantity} x ₹${it.unitPrice.toStringAsFixed(0)} = ₹${it.amount.toStringAsFixed(2)}',
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
            if (pur.photoList.isNotEmpty)
              PhotoGallerySection(photoUrls: pur.photoList),
            SizedBox(height: 12 * scale),
            Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
            SizedBox(height: 12 * scale),
            Wrap(
              spacing: 8 * scale,
              runSpacing: 8 * scale,
              children: [
                if (pur.status == 'PENDING') ...[
                  ScaledActionButton(
                    icon: Icons.check_circle,
                    label: 'Confirm Stock In',
                    scaleFactor: scale,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await viewModel.confirmPurchase(pur.id);
                      if (context.mounted) {
                        context.read<PricelistViewModel>().loadItems();
                      }
                    },
                  ),
                ] else ...[
                  ScaledActionButton(
                    icon: Icons.undo,
                    label: 'Revert to Pending',
                    scaleFactor: scale,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await viewModel.revertPurchaseToPending(pur.id);
                      if (context.mounted) {
                        context.read<PricelistViewModel>().loadItems();
                      }
                    },
                  ),
                ],
                ScaledActionButton(
                  icon: Icons.copy,
                  label: 'Duplicate',
                  scaleFactor: scale,
                  onTap: () {
                    Navigator.pop(ctx);
                    _duplicate(context, pur, viewModel);
                  },
                ),
                ScaledActionButton(
                  icon: Icons.sell,
                  label: 'Convert to Sale',
                  scaleFactor: scale,
                  onTap: () => _convertToSale(ctx, pur, viewModel),
                ),
              ],
            ),
          ],
        );
      },
      actionsBuilder: (ctx, scale) {
        final canEdit = UserPermissionService.canPerformModuleAction('purchases', 'canEdit');
        final canDelete = UserPermissionService.canPerformModuleAction('purchases', 'canDelete');
        if (!canEdit && !canDelete) return const SizedBox.shrink();

        return Row(
          children: [
            if (canEdit)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAddEditDialog(context, existingPurchase: pur);
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
                    _confirmDelete(context, pur.id, viewModel);
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
    PurchaseOrder? existingPurchase,
    String? prefillVendor,
    String? prefillItem,
    double? prefillAmount,
  }) {
    final isEdit = existingPurchase != null;
    final actionKey = isEdit ? 'canEdit' : 'canAdd';
    if (!UserPermissionService.canPerformModuleAction('purchases', actionKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEdit
                ? 'Access Denied: You do not have permission to edit Purchase Orders.'
                : 'Access Denied: You do not have permission to record new Purchases.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PurchaseFormDialog(
        existingPurchase: existingPurchase,
        prefillVendor: prefillVendor,
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

  void _duplicate(
    BuildContext context,
    PurchaseOrder pur,
    PurchasesViewModel viewModel,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PurchaseFormDialog(
        prefillVendor: pur.purchasedFrom,
        prefillNotes: pur.notes,
      ),
    );
  }

  void _convertToSale(
    BuildContext context,
    PurchaseOrder pur,
    PurchasesViewModel viewModel,
  ) {
    final navVM = context.read<NavigationViewModel>();
    navVM.setIndex(
      NavigationViewModel.sales,
      prefillData: {
        'target': 'sales',
        'customerName': pur.purchasedFrom,
        'itemName': 'Purchase inventory sale conversion: ${pur.id}',
        'amount': pur.totalAmount,
      },
    );
  }
}

// ==========================================================
// ADD/EDIT FORM DIALOG IMPLEMENTATION
// ==========================================================
class _PurchaseFormDialog extends StatefulWidget {
  final PurchaseOrder? existingPurchase;
  final String? prefillVendor;
  final String? prefillItem;
  final double? prefillAmount;
  final String? prefillNotes;
  final List<PurchaseOrderItem>? prefillItems;

  const _PurchaseFormDialog({
    this.existingPurchase,
    this.prefillVendor,
    this.prefillItem,
    this.prefillAmount,
    this.prefillNotes,
    // ignore: unused_element_parameter
    this.prefillItems,
  });

  @override
  State<_PurchaseFormDialog> createState() => _PurchaseFormDialogState();
}

class _PurchaseFormDialogState extends State<_PurchaseFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _vendorController;
  late final TextEditingController _notesController;
  late String _status;
  String? _photoUrl;

  List<PurchaseOrderItem> _items = [];

  // Controllers for adding item
  PricelistItem? _selectedCatalogItem;
  final _searchItemController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = widget.existingPurchase;

    _vendorController = TextEditingController(
      text: p?.purchasedFrom ?? widget.prefillVendor ?? '',
    );
    _notesController = TextEditingController(
      text: p?.notes ?? widget.prefillNotes ?? '',
    );
    _photoUrl = p?.photo;
    final purchasesStatuses = StatusManagementService.getStatuses('purchases');
    _status =
        p?.status ??
        (purchasesStatuses.isNotEmpty ? purchasesStatuses.first : 'Pending');

    if (p != null) {
      _items = context.read<PurchasesViewModel>().getPurchaseItems(p.id);
    } else if (widget.prefillItems != null) {
      _items = List.from(widget.prefillItems!);
    } else if (widget.prefillItem != null && widget.prefillItem!.isNotEmpty) {
      _items.add(
        PurchaseOrderItem(
          lineId: 'line_${DateTime.now().millisecondsSinceEpoch}',
          purchaseId: '',
          customItemName: widget.prefillItem,
          quantity: 1,
          unitPrice: widget.prefillAmount ?? 0.0,
          amount: widget.prefillAmount ?? 0.0,
        ),
      );
    }
  }

  @override
  void dispose() {
    _vendorController.dispose();
    _notesController.dispose();
    _searchItemController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  double get _calculatedTotal =>
      _items.fold(0.0, (sum, item) => sum + item.amount);

  void _addItem() async {
    final qty = int.tryParse(_qtyController.text) ?? 1;
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final textVal = _searchItemController.text.trim();

    PricelistItem? targetItem = _selectedCatalogItem;

    if (targetItem == null && textVal.isNotEmpty) {
      final pricelistVM = context.read<PricelistViewModel>();
      final existingMatches = pricelistVM.items.where(
        (i) => i.itemName.trim().toLowerCase() == textVal.toLowerCase(),
      );

      if (existingMatches.isNotEmpty) {
        targetItem = existingMatches.first;
      } else {
        // Create new item in pricelist!
        final newPricelistItem = PricelistItem(
          id: pricelistVM.getNextId(),
          itemName: textVal,
          price: price,
          stockQty: 0,
          openingStock: 0,
          category: 'General',
        );

        await pricelistVM.addItem(newPricelistItem);
        targetItem = newPricelistItem;
      }
    }

    if (targetItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or type an item name')),
      );
      return;
    }

    final unitCost = price > 0.0 ? price : targetItem.price;

    final newItem = PurchaseOrderItem(
      lineId: 'line_${DateTime.now().millisecondsSinceEpoch}',
      purchaseId: '',
      itemId: targetItem.id,
      itemName: targetItem.itemName,
      quantity: qty,
      unitPrice: unitCost,
      amount: qty * unitCost,
    );

    setState(() {
      _items.add(newItem);
      _selectedCatalogItem = null;
      _searchItemController.clear();
      _priceController.clear();
      _qtyController.clear();
    });
  }

  void _saveForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item')),
      );
      return;
    }

    final viewModel = context.read<PurchasesViewModel>();
    final String id = widget.existingPurchase?.id ?? viewModel.getNextId();
    final DateTime date = widget.existingPurchase?.date ?? DateTime.now();

    final order = PurchaseOrder(
      id: id,
      date: date,
      purchasedFrom: _vendorController.text.trim(),
      totalAmount: _calculatedTotal,
      status: _status,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      photo: _photoUrl,
    );

    final List<PurchaseOrderItem> finalItems = _items.map((item) {
      return item.copyWith(purchaseId: id);
    }).toList();

    await viewModel.savePurchase(order, finalItems);

    if (mounted) {
      context.read<PricelistViewModel>().loadItems();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existingPurchase == null
                ? 'Purchase order logged successfully'
                : 'Purchase order updated successfully',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.existingPurchase != null;
    final bool isMobile = MediaQuery.of(context).size.width < 700;
    final catalogItems = context.watch<PricelistViewModel>().items;

    final bool isPurchasedFromVis = UserPermissionService.isFieldVisible('purchases', 'purchasedFrom');
    final bool isPurchasedFromMod = UserPermissionService.canModifyField('purchases', 'purchasedFrom', isEdit: isEdit);

    final bool isStatusVis = UserPermissionService.isFieldVisible('purchases', 'status');
    final bool isStatusMod = UserPermissionService.canModifyField('purchases', 'status', isEdit: isEdit);

    final bool isNotesVis = UserPermissionService.isFieldVisible('purchases', 'notes');
    final bool isNotesMod = UserPermissionService.canModifyField('purchases', 'notes', isEdit: isEdit);

    final Widget formContent = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPurchasedFromVis) ...[
            TextFormField(
              controller: _vendorController,
              readOnly: !isPurchasedFromMod,
              enabled: isPurchasedFromMod,
              decoration: const InputDecoration(
                labelText: 'Purchased From (Vendor / Dealer Name) *',
              ),
              validator: (val) => val == null || val.trim().isEmpty
                  ? 'Please enter vendor name'
                  : null,
            ),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              if (isStatusVis)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Order Status'),
                    dropdownColor: const Color(0xFF131A2E),
                    onChanged: isStatusMod ? (val) {
                      if (val != null) setState(() => _status = val);
                    } : null,
                    items:
                        (() {
                          final list =
                              UserPermissionService.getAllowedSelectableStatuses(
                            'purchases',
                          );
                          if (!list.contains(_status)) {
                            list.add(_status);
                          }
                          return list;
                        })().map((st) {
                          return DropdownMenuItem(value: st, child: Text(st));
                        }).toList(),
                  ),
                ),
              if (isStatusVis) const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Total: ₹${_calculatedTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (isNotesVis) ...[
            TextFormField(
              controller: _notesController,
              readOnly: !isNotesMod,
              enabled: isNotesMod,
              decoration: const InputDecoration(labelText: 'Private Notes'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
          ],

          PhotoAttachmentWidget(
            initialPhotoUrl: _photoUrl,
            label: 'Vendor Bill / Purchase Invoice Photo(s)',
            onPhotoChanged: (urls) {
              _photoUrl = urls;
            },
          ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Items Stock-In Builder',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          RawAutocomplete<PricelistItem>(
            textEditingController: _searchItemController,
            focusNode: FocusNode(),
            optionsBuilder: (TextEditingValue textEditingValue) {
              final query = textEditingValue.text.toLowerCase().trim();
              if (query.isEmpty) {
                return catalogItems;
              }
              final matches = catalogItems.where((item) {
                final nameMatch = item.itemName.toLowerCase().contains(query);
                final catMatch = item.category?.toLowerCase().contains(query) ?? false;
                return nameMatch || catMatch;
              }).toList();

              if (matches.isEmpty) {
                return [
                  PricelistItem(
                    id: -1,
                    itemName: textEditingValue.text.trim(),
                    category: '',
                    price: 0,
                    stockQty: 0,
                    openingStock: 0,
                  ),
                ];
              }

              return matches;
            },
            displayStringForOption: (PricelistItem option) => option.itemName,
            onSelected: (PricelistItem selection) {
              if (selection.id == -1) return;
              setState(() {
                _selectedCatalogItem = selection;
                _priceController.text = selection.price > 0 ? selection.price.toStringAsFixed(0) : '';
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search or enter item name...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 18),
                  suffixIcon: controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted, size: 18),
                          onPressed: () {
                            controller.clear();
                            setState(() {
                              _selectedCatalogItem = null;
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.02),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              final query = _searchItemController.text.trim();
              final realOptions = options.where((opt) => opt.id != -1).toList();
              final hasExactMatch = realOptions.any(
                (opt) => opt.itemName.toLowerCase() == query.toLowerCase(),
              );

              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: const Color(0xFF131A2E),
                  elevation: 4.0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.8,
                    constraints: const BoxConstraints(
                      maxWidth: 450,
                      maxHeight: 260,
                    ),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        if (query.isNotEmpty && !hasExactMatch) ...[
                          ListTile(
                            dense: true,
                            tileColor: AppTheme.primary.withValues(alpha: 0.15),
                            leading: const Icon(
                              Icons.add_circle_outline_rounded,
                              color: AppTheme.primaryLight,
                              size: 20,
                            ),
                            title: Text(
                              'Add "$query" to Pricelist Catalog',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryLight,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: const Text(
                              'Open Add Product window and pre-fill details',
                              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                            onTap: () async {
                              FocusScope.of(context).unfocus();
                              final pricelistVM = context.read<PricelistViewModel>();
                              final newItem = await showAddEditPricelistItemDialog(
                                context,
                                pricelistVM,
                                initialName: query,
                              );
                              if (newItem != null) {
                                setState(() {
                                  _selectedCatalogItem = newItem;
                                  _searchItemController.text = newItem.itemName;
                                  _priceController.text = newItem.price > 0
                                      ? newItem.price.toStringAsFixed(0)
                                      : '';
                                });
                              }
                            },
                          ),
                          const Divider(color: Colors.white10, height: 1),
                        ],
                        ...realOptions.map((PricelistItem option) {
                          final bool isLowStock = option.stockQty <= option.openingStock;
                          return ListTile(
                            dense: true,
                            title: Text(
                              option.itemName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              'Category: ${option.category ?? "General"}  |  Stock: ${option.stockQty} left',
                              style: TextStyle(
                                fontSize: 11,
                                color: isLowStock ? AppTheme.danger : AppTheme.textMuted,
                              ),
                            ),
                            trailing: Text(
                              '₹${option.price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            onTap: () {
                              onSelected(option);
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _priceController,
                  decoration: InputDecoration(
                    labelText: 'Cost Price (₹)',
                    hintText: _selectedCatalogItem != null
                        ? _selectedCatalogItem!.price.toStringAsFixed(0)
                        : '0.00',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _qtyController,
                  decoration: const InputDecoration(
                    labelText: 'Qty',
                    hintText: '1',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _addItem,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Item'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Added items list
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No items added yet.',
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
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final String name =
                      item.itemName ?? item.customItemName ?? 'Product';
                  return ListTile(
                    title: Text(name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '₹${item.unitPrice} x ${item.quantity}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₹${item.amount.toStringAsFixed(2)}',
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
                              _items.removeAt(index);
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
              isEdit ? 'Edit Purchase Order' : 'Add Vendor Purchase',
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
                  'Save Purchase',
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
        isEdit ? 'Edit Purchase Order' : 'Add Vendor Purchase (Stock-In)',
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      content: Container(
        constraints: const BoxConstraints(maxWidth: 650),
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
          child: const Text('Save Purchase'),
        ),
      ],
    );
  }
}

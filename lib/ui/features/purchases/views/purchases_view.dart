import 'package:flutter/material.dart';
import '../../../shared/date_time_picker_field.dart';
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
import '../../../shared/components/app_animated_search_bar.dart';
import '../../../shared/components/app_keyboard_autocomplete.dart';
import '../../../shared/components/app_status_section_header.dart';
import '../../../shared/components/app_status_chip.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../../../shared/resizable_detail_popup.dart';
import '../../../shared/status_management_dialog.dart';

import '../../pricelist/view_models/pricelist_view_model.dart';
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
  double _itemsWidth = 280.0;
  double _amountWidth = 150.0;
  // ignore: unused_field
  double _statusWidth = 140.0;

  void _loadSavedColumnWidths() {
    _idWidth = UiPreferencesService.getColumnWidth('purchases', 'id') ?? 120.0;
    _dateWidth =
        UiPreferencesService.getColumnWidth('purchases', 'date') ?? 120.0;
    _vendorWidth =
        UiPreferencesService.getColumnWidth('purchases', 'vendor') ?? 220.0;
    _itemsWidth =
        UiPreferencesService.getColumnWidth('purchases', 'items') ?? 280.0;
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
        case 'items':
          _itemsWidth = newWidth;
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

        final groupedPurchases = _getGroupedPurchases(filtered);

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
                AppAnimatedSearchBar(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  onClear: () => setState(() {}),
                  hintText: 'Search ID, vendor, status, notes...',
                  margin: const EdgeInsets.only(bottom: 10),
                )
              else
                AppSearchFilterBar(
                  searchQuery: _searchController.text,
                  onSearchChanged: (q) => setState(() {
                    _searchController.text = q;
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
                            )
                          : _buildMobileCardsList(
                              context,
                              viewModel,
                              groupedPurchases,
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
      final existingKey = configuredStatuses.firstWhere(
        (k) => k.trim().toLowerCase() == statusName.toLowerCase(),
        orElse: () => '',
      );

      if (existingKey.isNotEmpty) {
        grouped[existingKey]!.add(pur);
      } else {
        final defaultStatus = StatusManagementService.getDefaultStatus('purchases');
        final fallbackKey = configuredStatuses.firstWhere(
          (k) => k.trim().toLowerCase() == defaultStatus.trim().toLowerCase(),
          orElse: () => configuredStatuses.isNotEmpty ? configuredStatuses.first : '',
        );
        if (fallbackKey.isNotEmpty) {
          grouped[fallbackKey]!.add(pur);
        }
      }
    }

    for (final list in grouped.values) {
      list.sort((a, b) {
        final dateComp = b.date.compareTo(a.date);
        if (dateComp != 0) return dateComp;
        return b.id.compareTo(a.id);
      });
    }

    grouped.removeWhere((key, list) => list.isEmpty);
    return grouped;
  }

  Widget _buildStatusSectionHeader(String status, int count) {
    return AppStatusSectionHeader(
      title: status,
      count: count,
      singularLabel: 'Purchase',
      pluralLabel: 'Purchases',
      color: _getStatusColor(status),
    );
  }

  Color _getStatusColor(String status) {
    return StatusManagementService.getStatusColor('purchases', status);
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
  ) {
    final listEntries = <_PurchaseListItem>[];
    for (final entry in groupedPurchases.entries) {
      listEntries.add(_PurchaseListItem.header(entry.key, entry.value.length));
      for (final pur in entry.value) {
        listEntries.add(_PurchaseListItem.card(pur));
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
                if (UserPermissionService.isFieldVisible('purchases', 'date'))
                  _buildResizableHeader(
                    'Date',
                    _dateWidth,
                    (delta) => _updateColumnWidth(
                      'date',
                      (_dateWidth + delta).clamp(80.0, 200.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('purchases', 'purchasedFrom'))
                  _buildResizableHeader(
                    'Purchased From (Vendor)',
                    _vendorWidth,
                    (delta) => _updateColumnWidth(
                      'vendor',
                      (_vendorWidth + delta).clamp(120.0, 450.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('purchases', 'stockInItems'))
                  _buildResizableHeader(
                    'Items',
                    _itemsWidth,
                    (delta) => _updateColumnWidth(
                      'items',
                      (_itemsWidth + delta).clamp(150.0, 600.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('purchases', 'totalAmount'))
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
                return _buildDesktopTableRow(context, viewModel, item.purchase!);
              },
            ),
          ),
        ],
      ),
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
            if (UserPermissionService.isFieldVisible('purchases', 'date'))
              Container(
                width: _dateWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(formattedDate),
              ),
            if (UserPermissionService.isFieldVisible('purchases', 'purchasedFrom'))
              Container(
                width: _vendorWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  pur.purchasedFrom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (UserPermissionService.isFieldVisible('purchases', 'stockInItems'))
              Container(
                width: _itemsWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                alignment: Alignment.centerLeft,
                child: Builder(
                  builder: (context) {
                    final items = viewModel.getPurchaseItems(pur.id);
                    final String itemsSummary = items.isNotEmpty
                        ? items
                            .map((i) =>
                                '${i.itemName ?? i.customItemName ?? "Item"} (${i.quantity})')
                            .join(', ')
                        : '-';

                    return Text(
                      itemsSummary,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
            if (UserPermissionService.isFieldVisible('purchases', 'totalAmount'))
              Container(
                width: _amountWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    final listEntries = <_PurchaseListItem>[];
    for (final entry in groupedPurchases.entries) {
      listEntries.add(_PurchaseListItem.header(entry.key, entry.value.length));
      for (final pur in entry.value) {
        listEntries.add(_PurchaseListItem.card(pur));
      }
    }

    return RefreshIndicator(
      color: AppTheme.primaryLight,
      backgroundColor: const Color(0xFF131A2E),
      onRefresh: () async {
        final localDb = context.read<ShopRepository>().localDb;
        await SupabaseSyncService.instance.syncAllTablesFromCloud(localDb);
        if (context.mounted) viewModel.loadPurchases();
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
          return _buildMobilePurchaseCard(context, viewModel, item.purchase!, itemIndex: index);
        },
      ),
    );
  }

  Widget _buildMobilePurchaseCard(
    BuildContext context,
    PurchasesViewModel viewModel,
    PurchaseOrder pur, {
    int itemIndex = 0,
  }) {
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

    if (UserPermissionService.isFieldVisible('purchases', 'stockInItems')) {
      final items = viewModel.getPurchaseItems(pur.id);
      if (items.isNotEmpty) {
        final itemsSummary = items
            .map((i) =>
                '${i.itemName ?? i.customItemName ?? "Item"} (${i.quantity})')
            .join(', ');
        metadata.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Items: $itemsSummary',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }

    final canEdit = UserPermissionService.canPerformModuleAction('purchases', 'canEdit');
    final canDelete = UserPermissionService.canPerformModuleAction('purchases', 'canDelete');

    return AppListCard(
      index: itemIndex,
      title: 'Vendor: ${pur.purchasedFrom}',
      subtitle: 'Order ID: ${pur.id}',
      statusBadge: _buildStatusChip(pur.status),
      metadataRows: metadata,
      onTap: () => _showDetailDialog(context, pur, viewModel),
      onEdit: canEdit ? () => _showAddEditDialog(context, existingPurchase: pur) : null,
      onDelete: canDelete ? () => _confirmDelete(context, pur.id, viewModel) : null,
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
            if (UserPermissionService.isFieldVisible('purchases', 'purchasedFrom') && pur.purchasedFrom.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Purchased From (Vendor)',
                value: pur.purchasedFrom,
                scaleFactor: scale,
                labelWidth: 195,
              ),
            if (UserPermissionService.isFieldVisible('purchases', 'totalAmount') && pur.totalAmount > 0)
              ScaledInfoRow(
                label: 'Total Purchase Amount',
                value: '₹${pur.totalAmount.toStringAsFixed(2)}',
                scaleFactor: scale,
                labelWidth: 195,
              ),
            if (UserPermissionService.isFieldVisible('purchases', 'status'))
              ScaledInfoRow(
                label: 'Status',
                value: pur.status,
                valueWidget: AppStatusChip(
                  status: pur.status,
                  moduleKey: 'purchases',
                  scaleFactor: scale,
                ),
                scaleFactor: scale,
                labelWidth: 195,
              ),
            if (UserPermissionService.isFieldVisible('purchases', 'notes') && pur.notes != null && pur.notes!.trim().isNotEmpty && pur.notes != 'N/A')
              ScaledInfoRow(
                label: 'Notes',
                value: pur.notes!,
                scaleFactor: scale,
                labelWidth: 195,
              ),
            if (UserPermissionService.isFieldVisible('purchases', 'stockInItems') && items.isNotEmpty) ...[
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
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          (it.itemName != null && it.itemName!.isNotEmpty)
                              ? it.itemName!
                              : (it.customItemName != null && it.customItemName!.isNotEmpty)
                                  ? it.customItemName!
                                  : 'Purchase Item (${it.lineId})',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12.5 * scale,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Text(
                        '${it.quantity} x ₹${it.unitPrice.toStringAsFixed(0)} = ₹${it.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: AppTheme.primaryLight,
                          fontSize: 12.5 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (UserPermissionService.isFieldVisible('purchases', 'photo') && pur.photoList.isNotEmpty)
              PhotoGallerySection(photoUrls: pur.photoList),
            if (UserPermissionService.canPerformModuleAction('purchases', 'canDuplicate') ||
                UserPermissionService.canPerformModuleAction('purchases', 'canConvertToSale')) ...[
              SizedBox(height: 12 * scale),
              Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
              SizedBox(height: 12 * scale),
              Wrap(
                spacing: 8 * scale,
                runSpacing: 8 * scale,
                children: [
                  if (UserPermissionService.canPerformModuleAction('purchases', 'canDuplicate'))
                    ScaledActionButton(
                      icon: Icons.copy,
                      label: 'Duplicate',
                      scaleFactor: scale,
                      onTap: () {
                        Navigator.pop(ctx);
                        _duplicate(context, pur, viewModel);
                      },
                    ),
                  if (UserPermissionService.canPerformModuleAction('purchases', 'canConvertToSale'))
                    ScaledActionButton(
                      icon: Icons.sell,
                      label: 'Convert to Sale',
                      scaleFactor: scale,
                      onTap: () => _convertToSale(ctx, pur, viewModel),
                    ),
                ],
              ),
            ],
          ],
        );
      },
      actionsBuilder: (ctx, scale) {
        final canManageStatus = UserPermissionService.canPerformModuleAction('purchases', 'canManageStatus');
        final canEdit = UserPermissionService.canPerformModuleAction('purchases', 'canEdit');
        final canDelete = UserPermissionService.canPerformModuleAction('purchases', 'canDelete');
        final isConfirmed = pur.status.toUpperCase() == 'CONFIRMED';

        if (!canManageStatus && !canEdit && !canDelete) return const SizedBox.shrink();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canManageStatus) ...[
              if (!isConfirmed)
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await viewModel.confirmPurchase(pur.id);
                    if (context.mounted) {
                      context.read<PricelistViewModel>().loadItems();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Purchase order ${pur.id} confirmed and stocked in.',
                          ),
                          backgroundColor: AppTheme.success,
                        ),
                      );
                    }
                  },
                  icon: Icon(Icons.check_circle_rounded, size: 18 * scale),
                  label: Text(
                    'Confirm & Stock In',
                    style: TextStyle(
                      fontSize: 13.5 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12 * scale),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await viewModel.revertPurchaseToPending(pur.id);
                    if (context.mounted) {
                      context.read<PricelistViewModel>().loadItems();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Purchase order ${pur.id} reverted to pending.',
                          ),
                          backgroundColor: AppTheme.warning,
                        ),
                      );
                    }
                  },
                  icon: Icon(Icons.history_rounded, size: 18 * scale),
                  label: Text(
                    'Revert to Pending',
                    style: TextStyle(
                      fontSize: 13.5 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.warning.withValues(alpha: 0.15),
                    foregroundColor: AppTheme.warning,
                    side: BorderSide(
                      color: AppTheme.warning.withValues(alpha: 0.4),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 12 * scale),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              if (canEdit || canDelete) SizedBox(height: 10 * scale),
            ],
            if (canEdit || canDelete)
              Row(
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
    final purchaseItems = viewModel.getPurchaseItems(pur.id);

    if (purchaseItems.isNotEmpty) {
      final itemsList = purchaseItems.map((item) {
        return {
          'itemId': item.itemId,
          'lineType': 'Product',
          'itemDescription': item.itemName ?? item.customItemName ?? 'Product',
          'quantity': item.quantity,
          'itemPrice': item.unitPrice,
          'totalAmount': item.amount,
        };
      }).toList();

      navVM.setIndex(
        NavigationViewModel.sales,
        prefillData: {
          'target': 'sales',
          'customerName': pur.purchasedFrom,
          'estimateItems': itemsList,
          'totalAmount': pur.totalAmount,
        },
      );
    } else {
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

  late DateTime _purchaseDate;

  late final TextEditingController _vendorController;
  late final TextEditingController _notesController;
  late String _status;
  String? _photoUrl;
  bool _isPhotoUploading = false;

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

    _purchaseDate = p?.date ?? DateTime.now();

    _vendorController = TextEditingController(
      text: p?.purchasedFrom ?? widget.prefillVendor ?? '',
    );
    _notesController = TextEditingController(
      text: p?.notes ?? widget.prefillNotes ?? '',
    );
    _photoUrl = p?.photo;
    _status =
        p?.status ??
        StatusManagementService.getDefaultStatus('purchases');

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

  void _editItemDialog(int index) {
    final item = _items[index];
    final editNameController = TextEditingController(
      text: item.itemName ?? item.customItemName ?? '',
    );
    final editPriceController = TextEditingController(
      text: item.unitPrice.toStringAsFixed(0),
    );
    final editQtyController = TextEditingController(
      text: item.quantity.toString(),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131A2E),
          title: const Text('Edit Purchase Item', style: TextStyle(color: AppTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: editNameController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Item Name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: editPriceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(labelText: 'Cost Price (₹)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: editQtyController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(labelText: 'Quantity'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = editNameController.text.trim();
                final newPrice = double.tryParse(editPriceController.text.trim()) ?? item.unitPrice;
                final newQty = int.tryParse(editQtyController.text.trim()) ?? item.quantity;

                if (newName.isNotEmpty && newQty > 0) {
                  final pricelistVM = context.read<PricelistViewModel>();
                  final match = pricelistVM.items
                      .where((p) => p.itemName.trim().toLowerCase() == newName.toLowerCase())
                      .firstOrNull;
                  setState(() {
                    _items[index] = item.copyWith(
                      itemId: match?.id ?? item.itemId,
                      itemName: newName,
                      customItemName: newName,
                      unitPrice: newPrice,
                      quantity: newQty,
                      amount: newQty * newPrice,
                    );
                  });
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
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
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item')),
      );
      return;
    }

    final viewModel = context.read<PurchasesViewModel>();
    final String id = widget.existingPurchase?.id ?? viewModel.getNextId();

    final order = PurchaseOrder(
      id: id,
      date: _purchaseDate,
      purchasedFrom: _vendorController.text.trim(),
      totalAmount: _calculatedTotal,
      status: _status,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      photo: _photoUrl,
    );

    final catalog = context.read<PricelistViewModel>().items;
    final List<PurchaseOrderItem> finalItems = _items.map((item) {
      int? resolvedId = item.itemId;
      if (resolvedId == null) {
        final target = (item.itemName ?? item.customItemName ?? '').trim().toLowerCase();
        if (target.isNotEmpty) {
          final match = catalog
              .where((p) => p.itemName.trim().toLowerCase() == target)
              .firstOrNull;
          if (match != null) {
            resolvedId = match.id;
          }
        }
      }
      return item.copyWith(
        purchaseId: id,
        itemId: resolvedId,
      );
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

    final bool isDateVis = UserPermissionService.isFieldVisible('purchases', 'date');
    final bool isDateMod = UserPermissionService.canModifyField('purchases', 'date', isEdit: isEdit);

    final bool isPurchasedFromVis = UserPermissionService.isFieldVisible('purchases', 'purchasedFrom');
    final bool isPurchasedFromMod = UserPermissionService.canModifyField('purchases', 'purchasedFrom', isEdit: isEdit);

    final bool isStatusVis = UserPermissionService.isFieldVisible('purchases', 'status');
    final bool isStatusMod = UserPermissionService.canModifyField('purchases', 'status', isEdit: isEdit);

    final bool isNotesVis = UserPermissionService.isFieldVisible('purchases', 'notes');
    final bool isNotesMod = UserPermissionService.canModifyField('purchases', 'notes', isEdit: isEdit);

    final bool isTotalVis = UserPermissionService.isFieldVisible('purchases', 'totalAmount');
    final bool isPhotoVis = UserPermissionService.isFieldVisible('purchases', 'photo');
    final bool isPhotoMod = UserPermissionService.canModifyField('purchases', 'photo', isEdit: isEdit);

    final bool isStockInItemsVis = UserPermissionService.isFieldVisible('purchases', 'stockInItems');
    final bool isStockInItemsMod = UserPermissionService.canModifyField('purchases', 'stockInItems', isEdit: isEdit);

    final Widget formContent = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDateVis) ...[
            DateTimePickerField(
              label: 'Purchase Date & Time',
              selectedDateTime: _purchaseDate,
              onDateTimeChanged: (dt) => setState(() => _purchaseDate = dt),
              isVisible: isDateVis,
              canEdit: isDateMod,
            ),
            const SizedBox(height: 12),
          ],
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
                  child: Builder(
                    builder: (context) {
                      final list = UserPermissionService.getAllowedSelectableStatuses('purchases');
                      final List<String> selectableList = List.from(list);
                      final match = selectableList.firstWhere(
                        (s) => s.trim().toLowerCase() == _status.trim().toLowerCase(),
                        orElse: () => selectableList.isNotEmpty ? selectableList.first : 'PENDING',
                      );
                      final effectiveStatus = match;
                      return DropdownButtonFormField<String>(
                        value: effectiveStatus.isNotEmpty ? effectiveStatus : (selectableList.isNotEmpty ? selectableList.first : null),
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Order Status'),
                        dropdownColor: const Color(0xFF131A2E),
                        onChanged: isStatusMod ? (val) {
                          if (val != null) setState(() => _status = val);
                        } : null,
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
              if (isStatusVis && isTotalVis) const SizedBox(width: 12),
              if (isTotalVis)
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

          if (isPhotoVis) ...[
            PhotoAttachmentWidget(
              initialPhotoUrl: _photoUrl,
              label: 'Vendor Bill / Purchase Invoice Photo(s)',
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
            const SizedBox(height: 12),
          ],

          if (isStockInItemsVis) ...[
            const SizedBox(height: 12),
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

            if (isStockInItemsMod) ...[
              AppKeyboardAutocomplete(
                controller: _searchItemController,
                catalogItems: catalogItems,
                hintText: 'Search or enter item name...',
                allowNewItem: true,
                onSelected: (PricelistItem selection) {
                  setState(() {
                    if (selection.id == -1) {
                      _selectedCatalogItem = null;
                      _searchItemController.text = selection.itemName;
                      _priceController.clear();
                    } else {
                      _selectedCatalogItem = selection;
                      _priceController.text =
                          selection.price > 0
                              ? selection.price.toStringAsFixed(0)
                              : '';
                    }
                  });
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
            ],

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
                          if (isStockInItemsMod) ...[
                            IconButton(
                              icon: const Icon(
                                Icons.edit_note_rounded,
                                color: AppTheme.primaryLight,
                                size: 18,
                              ),
                              tooltip: 'Edit item details',
                              onPressed: () => _editItemDialog(index),
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
                        ],
                      ),
                    );
                  },
                ),
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

class _PurchaseListItem {
  final String? statusHeader;
  final int? statusCount;
  final PurchaseOrder? purchase;

  _PurchaseListItem.header(this.statusHeader, this.statusCount) : purchase = null;
  _PurchaseListItem.card(this.purchase)
      : statusHeader = null,
        statusCount = null;
}

import 'package:flutter/material.dart';
import '../../../shared/date_time_picker_field.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shop_management_flutter/ui/core/app_theme.dart';
import 'package:shop_management_flutter/ui/core/motion/motion.dart';
import 'package:shop_management_flutter/data/models/pricelist_item.dart';
import 'package:shop_management_flutter/data/models/sale.dart';
import 'package:shop_management_flutter/data/models/sale_item.dart';
import '../../../../data/services/pdf_invoice_helper.dart';
import '../view_models/sales_view_model.dart';
import '../../dashboard/view_models/recent_sales_view_model.dart';
import '../../pricelist/view_models/pricelist_view_model.dart';

import '../../../navigation/navigation_view_model.dart';
import '../../../shared/components/app_page_header.dart';
import '../../../shared/components/app_list_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_floating_action_button.dart';
import '../../../shared/components/app_header_sync_button.dart';
import '../../../shared/components/app_search_filter_bar.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../../../shared/components/app_keyboard_autocomplete.dart';
import '../../../shared/status_management_dialog.dart';

import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/supabase_sync_service.dart';
import '../../../../data/services/user_permission_service.dart';
import '../../../../data/services/kiosk_broadcast_service.dart';
import '../../../../data/services/ui_preferences_service.dart';

class SalesView extends StatefulWidget {
  const SalesView({super.key});

  @override
  State<SalesView> createState() => _SalesViewState();
}

class _SalesViewState extends State<SalesView> {
  // Navigation sub-state
  bool _showBillingDesk = false;

  // Resizable column widths for Sales Ledger
  double _invoiceColumnWidth = 100.0;
  double _dateColumnWidth = 130.0;
  double _nameColumnWidth = 180.0;
  double _itemsColumnWidth = 250.0;
  double _amountColumnWidth = 120.0;

  // Selection states
  bool _isSelectionMode = false;
  final Set<int> _selectedInvoices = {};

  // Controllers
  final TextEditingController _ledgerSearchController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _advanceController = TextEditingController();

  void _loadSavedColumnWidths() {
    _invoiceColumnWidth =
        UiPreferencesService.getColumnWidth('sales', 'invoice') ?? 100.0;
    _dateColumnWidth =
        UiPreferencesService.getColumnWidth('sales', 'date') ?? 130.0;
    _nameColumnWidth =
        UiPreferencesService.getColumnWidth('sales', 'name') ?? 180.0;
    _itemsColumnWidth =
        UiPreferencesService.getColumnWidth('sales', 'items') ?? 250.0;
    _amountColumnWidth =
        UiPreferencesService.getColumnWidth('sales', 'amount') ?? 120.0;
  }

  void _updateColumnWidth(String columnKey, double newWidth) {
    setState(() {
      switch (columnKey) {
        case 'invoice':
          _invoiceColumnWidth = newWidth;
          break;
        case 'date':
          _dateColumnWidth = newWidth;
          break;
        case 'name':
          _nameColumnWidth = newWidth;
          break;
        case 'items':
          _itemsColumnWidth = newWidth;
          break;
        case 'amount':
          _amountColumnWidth = newWidth;
          break;
      }
    });
    UiPreferencesService.setColumnWidth('sales', columnKey, newWidth);
  }

  @override
  void initState() {
    super.initState();
    _loadSavedColumnWidths();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesViewModel>().loadCatalog();
      context.read<RecentSalesViewModel>().loadSales();
    });
  }

  @override
  void dispose() {
    _ledgerSearchController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _discountController.dispose();
    _advanceController.dispose();
    super.dispose();
  }

  void _clearLocalForm() {
    _customerNameController.clear();
    _customerPhoneController.clear();
    _discountController.clear();
    _advanceController.clear();
  }

  void _handleSalesPrefill(
    BuildContext context,
    Map<String, dynamic> prefill,
    NavigationViewModel navVM,
  ) {
    navVM.clearPrefillData();

    final salesVM = context.read<SalesViewModel>();
    salesVM.clearCart();
    _clearLocalForm();

    final String name = prefill['customerName'] ?? prefill['name'] ?? '';
    final String mobile =
        prefill['customerNumber'] ??
        prefill['mobileNo'] ??
        prefill['mobile'] ??
        '';

    _customerNameController.text = name;
    _customerPhoneController.text = mobile;
    salesVM.setCustomerName(name);
    salesVM.setCustomerNumber(mobile);

    if (prefill['advance'] != null) {
      final double adv = (prefill['advance'] as num).toDouble();
      if (adv > 0) {
        _advanceController.text = adv.toStringAsFixed(2);
        salesVM.setAdvance(adv);
      }
    }

    if (prefill['discount'] != null) {
      final double disc = (prefill['discount'] as num).toDouble();
      if (disc > 0) {
        _discountController.text = disc.toStringAsFixed(2);
        salesVM.setDiscount(disc);
      }
    }

    final List<dynamic>? estItems = prefill['estimateItems'] as List<dynamic>?;
    if (estItems != null && estItems.isNotEmpty) {
      for (final raw in estItems) {
        final item = raw as Map<String, dynamic>;
        salesVM.addSaleItemToCart(
          itemId: (item['itemId'] as num?)?.toInt(),
          lineType: item['lineType'] ?? 'Product',
          itemDescription:
              item['itemDescription'] ?? item['itemName'] ?? 'Estimate Item',
          quantity: (item['quantity'] as num?)?.toInt() ?? 1,
          itemPrice: (item['itemPrice'] as num?)?.toDouble() ?? 0.0,
          customPrice: (item['customPrice'] as num?)?.toDouble(),
          notes: item['notes']?.toString(),
        );
      }
    } else {
      final String? itemName =
          prefill['itemName'] ?? prefill['item'] ?? prefill['devices'];
      final double amount = (prefill['amount'] != null
          ? (prefill['amount'] as num).toDouble()
          : (prefill['totalAmount'] != null
              ? (prefill['totalAmount'] as num).toDouble()
              : 0.0));

      if (itemName != null && itemName.isNotEmpty) {
        salesVM.addCustomServiceToCart(
          itemName,
          amount,
          notes: prefill['notes']?.toString(),
        );
      }
    }

    setState(() {
      _showBillingDesk = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final navViewModel = context.watch<NavigationViewModel>();
    final prefill = navViewModel.pendingPrefillData;
    if (prefill != null && prefill['target'] == 'sales') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleSalesPrefill(context, prefill, navViewModel);
      });
    }

    return Consumer2<SalesViewModel, RecentSalesViewModel>(
      builder: (context, salesCartVM, recentSalesVM, child) {
        return AnimatedSwitcher(
          duration: AppleMotion.isDesktop
              ? const Duration(milliseconds: 240)
              : const Duration(milliseconds: 320),
          reverseDuration: AppleMotion.isDesktop
              ? const Duration(milliseconds: 200)
              : const Duration(milliseconds: 260),
          switchInCurve: AppleMotion.easeOut,
          switchOutCurve: AppleMotion.modalExitCurve,
          transitionBuilder: (child, animation) {
            final isBilling = child.key == const ValueKey('billing_desk');
            final slideOffset = isBilling
                ? Tween<Offset>(
                    begin: const Offset(0.04, 0.0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: AppleMotion.easeOut,
                    ),
                  )
                : Tween<Offset>(
                    begin: const Offset(-0.03, 0.0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: AppleMotion.easeOut,
                    ),
                  );

            final scale = Tween<double>(
              begin: 0.98,
              end: 1.0,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: AppleMotion.easeOut,
              ),
            );

            return SlideTransition(
              position: slideOffset,
              child: FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: scale,
                  child: child,
                ),
              ),
            );
          },
          child: _showBillingDesk
              ? KeyedSubtree(
                  key: const ValueKey('billing_desk'),
                  child: _buildBillingDesk(context, salesCartVM, recentSalesVM),
                )
              : KeyedSubtree(
                  key: const ValueKey('sales_ledger'),
                  child: _buildSalesLedgerScreen(context, recentSalesVM),
                ),
        );
      },
    );
  }

  // ==========================================
  // VIEW SCREEN 1: SALES LEDGER & HISTORY
  // ==========================================
  Widget _buildSalesLedgerScreen(
    BuildContext context,
    RecentSalesViewModel viewModel,
  ) {
    if (viewModel.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 800;

    // Filtered ledger sales list
    final filteredSales = viewModel.sales.where((sale) {
      if (!UserPermissionService.isStatusVisible('sales', sale.orderStatus)) {
        return false;
      }
      final query = _ledgerSearchController.text.trim().toLowerCase();
      if (query.isEmpty) return true;
      final nameMatch =
          sale.customerName?.toLowerCase().contains(query) ?? false;
      final phoneMatch =
          sale.customerNumber?.toLowerCase().contains(query) ?? false;
      final invMatch = sale.invoiceNo.toString().contains(query);
      return nameMatch || phoneMatch || invMatch;
    }).toList();

    // Sort: PENDING first (descending date), Confirmed second (descending date)
    // Sort by status order first, then by date descending
    filteredSales.sort((a, b) {
      final statusCompare = StatusManagementService.compareStatuses(
        'sales',
        a.orderStatus,
        b.orderStatus,
      );
      if (statusCompare != 0) return statusCompare;
      return b.saleDate.compareTo(a.saleDate);
    });

    // Pagination calculations
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isDesktop
          ? null
          : AppFloatingActionButton(
              onPressed: () {
                setState(() {
                  _showBillingDesk = true;
                });
              },
              tooltip: 'Create Invoice',
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: 'Sales Ledger',
            subtitle: 'Ledger & Invoice History',
            actions: [
              if (isDesktop && UserPermissionService.canPerformModuleAction('sales', 'canAdd'))
                AppHeaderActionButton(
                  label: 'New Sale',
                  icon: Icons.add_rounded,
                  onPressed: () {
                    setState(() {
                      _showBillingDesk = true;
                    });
                  },
                ),
              if (!isDesktop)
                AppHeaderSyncButton(
                  onSynced: () => context.read<RecentSalesViewModel>().loadSales(),
                ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () {
                  StatusManagementDialog.show(
                    context,
                    moduleKey: 'sales',
                    moduleTitle: 'Sale',
                    onStatusesUpdated: () {
                      StatusManagementService.invalidateCache('sales');
                      context.read<RecentSalesViewModel>().loadSales();
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
              controller: _ledgerSearchController,
              onChanged: (_) => setState(() {}),
              onClear: () => setState(() {}),
              hintText: 'Search invoice #, customer name, mobile...',
              margin: const EdgeInsets.only(bottom: 10),
            )
          else
            AppSearchFilterBar(
              searchQuery: _ledgerSearchController.text,
              onSearchChanged: (q) => setState(() {
                _ledgerSearchController.text = q;
              }),
              hintText: 'Search invoice #, customer, mobile...',
            ),
          const SizedBox(height: 12),

          // Table / Cards list
          Expanded(
            child: filteredSales.isEmpty
                ? _buildEmptyLedger(context)
                : _buildSalesTableOrCards(
                    context,
                    viewModel,
                    filteredSales,
                    isDesktop,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyLedger(BuildContext context) {
    return AppEmptyState(
      icon: Icons.receipt_long_rounded,
      title: 'No Matching Invoices Found',
      message:
          'No sales records match your current search terms.\nTap below to launch the Billing Desk.',
      actionLabel: 'Create New Invoice',
      onAction: () {
        setState(() {
          _showBillingDesk = true;
        });
      },
    );
  }

  Widget _buildResizeGripSales(ValueChanged<double> onResize) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) {
          onResize(details.delta.dx);
        },
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
    );
  }

  Widget _buildResizableHeaderSales(
    RecentSalesViewModel viewModel,
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
            ),
          ),
          _buildResizeGripSales(onResize),
        ],
      ),
    );
  }

  Widget _buildSaleRow(
    BuildContext context,
    RecentSalesViewModel viewModel,
    Sale sale,
  ) {
    final bool isSelected = _selectedInvoices.contains(sale.invoiceNo);
    final formattedDate = DateFormat('dd/MM/yy hh:mm a').format(sale.saleDate);

    return InkWell(
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedInvoices.remove(sale.invoiceNo);
            } else {
              _selectedInvoices.add(sale.invoiceNo);
            }
          });
        } else {
          _showInvoiceDetailsSheet(context, viewModel, sale);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.05)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.04)),
          ),
        ),
        child: Row(
          children: [
            if (_isSelectionMode)
              Container(
                width: 45,
                padding: const EdgeInsets.only(left: 16),
                alignment: Alignment.centerLeft,
                child: Checkbox(
                  value: isSelected,
                  activeColor: AppTheme.primary,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedInvoices.add(sale.invoiceNo);
                      } else {
                        _selectedInvoices.remove(sale.invoiceNo);
                      }
                    });
                  },
                ),
              ),
            // Invoice # cell
            if (UserPermissionService.isFieldVisible('sales', 'invoiceNo'))
              Container(
                width: _invoiceColumnWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                alignment: Alignment.centerLeft,
                child: Text(
                  '#${sale.invoiceNo}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            // Date cell
            if (UserPermissionService.isFieldVisible('sales', 'date'))
              Container(
                width: _dateColumnWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                alignment: Alignment.centerLeft,
                child: Text(
                  formattedDate,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
            // Customer Name cell
            if (UserPermissionService.isFieldVisible('sales', 'customerName'))
              Container(
                width: _nameColumnWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                alignment: Alignment.centerLeft,
                child: Text(
                  (sale.customerName != null && sale.customerName!.trim().isNotEmpty)
                      ? sale.customerName!
                      : 'Cash / Walk-in',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // Items & Services cell
            Container(
              width: _itemsColumnWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              alignment: Alignment.centerLeft,
              child: Builder(
                builder: (context) {
                  final items = viewModel.getSaleItems(sale.invoiceNo);
                  final String itemsSummary = items.isNotEmpty
                      ? items
                          .map((i) =>
                              '${i.itemDescription ?? i.serviceName ?? "Item"} (${i.quantity})')
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
            // Payment Mode cell
            if (UserPermissionService.isFieldVisible('sales', 'paymentMode'))
              Container(
                width: _amountColumnWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    sale.paymentMode,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            // Net Total cell
            if (UserPermissionService.isFieldVisible('sales', 'totalAmount'))
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₹${sale.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppTheme.primaryLight,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Map<String, List<Sale>> _getGroupedSales(List<Sale> sales) {
    final List<String> configuredStatuses = StatusManagementService.getStatuses('sales');
    final Map<String, List<Sale>> grouped = {};

    for (final status in configuredStatuses) {
      grouped[status] = [];
    }

    for (final sale in sales) {
      final statusName = sale.orderStatus.trim();
      final existingKey = configuredStatuses.firstWhere(
        (k) => k.trim().toLowerCase() == statusName.toLowerCase(),
        orElse: () => '',
      );

      if (existingKey.isNotEmpty) {
        grouped[existingKey]!.add(sale);
      } else if (statusName.toLowerCase() == 'confirmed') {
        // Unify legacy Confirmed into Complete
        final completeKey = configuredStatuses.firstWhere(
          (k) => k.trim().toLowerCase() == 'complete' || k.trim().toLowerCase() == 'completed',
          orElse: () => '',
        );
        if (completeKey.isNotEmpty) {
          grouped[completeKey]!.add(sale);
        } else if (configuredStatuses.isNotEmpty) {
          grouped[configuredStatuses.last]!.add(sale);
        }
      } else {
        // Strictly restrict to configured statuses in Status Manager modal
        final defaultStatus = StatusManagementService.getDefaultStatus('sales');
        final fallbackKey = configuredStatuses.firstWhere(
          (k) => k.trim().toLowerCase() == defaultStatus.trim().toLowerCase(),
          orElse: () => configuredStatuses.isNotEmpty ? configuredStatuses.first : '',
        );
        if (fallbackKey.isNotEmpty) {
          grouped[fallbackKey]!.add(sale);
        }
      }
    }

    for (final list in grouped.values) {
      list.sort((a, b) {
        final dateComp = b.saleDate.compareTo(a.saleDate);
        if (dateComp != 0) return dateComp;
        return b.invoiceNo.compareTo(a.invoiceNo);
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
                  '$count ${count == 1 ? 'Invoice' : 'Invoices'}',
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

  // ignore: unused_element
  void _bulkDeleteSales(BuildContext context, RecentSalesViewModel viewModel) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Bulk Delete Invoices'),
          content: Text(
            'Are you sure you want to delete the ${_selectedInvoices.length} selected invoices? This will delete the sale records permanently and add back any confirmed stock quantities to the catalog.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final List<int> invoicesToDelete = _selectedInvoices.toList();

                // Show loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                );

                try {
                  for (final invoiceNo in invoicesToDelete) {
                    await viewModel.deleteSale(invoiceNo);
                  }
                  setState(() {
                    _selectedInvoices.clear();
                    _isSelectionMode = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Successfully deleted ${invoicesToDelete.length} invoices.',
                      ),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting invoices: $e'),
                      backgroundColor: AppTheme.danger,
                    ),
                  );
                } finally {
                  // Hide loading indicator
                  Navigator.pop(context);
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

  Widget _buildSalesTableOrCards(
    BuildContext context,
    RecentSalesViewModel viewModel,
    List<Sale> sales,
    bool isDesktop,
  ) {
    final groupedSales = _getGroupedSales(sales);

    if (isDesktop) {
      return Container(
        width: double.infinity,
        decoration: AppTheme.glassCardDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: 12,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Custom Header Row
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: Row(
                children: [
                  if (_isSelectionMode)
                    Container(
                      width: 45,
                      padding: const EdgeInsets.only(left: 16),
                      alignment: Alignment.centerLeft,
                      child: Checkbox(
                        value:
                            sales.isNotEmpty &&
                            sales.every(
                              (sale) =>
                                  _selectedInvoices.contains(sale.invoiceNo),
                            ),
                        activeColor: AppTheme.primary,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedInvoices.addAll(
                                sales.map((sale) => sale.invoiceNo),
                              );
                            } else {
                              _selectedInvoices.removeAll(
                                sales.map((sale) => sale.invoiceNo),
                              );
                            }
                          });
                        },
                      ),
                    ),
                  if (UserPermissionService.isFieldVisible('sales', 'invoiceNo'))
                    _buildResizableHeaderSales(
                      viewModel,
                      'Invoice #',
                      _invoiceColumnWidth,
                      (delta) => _updateColumnWidth(
                        'invoice',
                        (_invoiceColumnWidth + delta).clamp(60.0, 200.0),
                      ),
                    ),
                  if (UserPermissionService.isFieldVisible('sales', 'date'))
                    _buildResizableHeaderSales(
                      viewModel,
                      'Date & Time',
                      _dateColumnWidth,
                      (delta) => _updateColumnWidth(
                        'date',
                        (_dateColumnWidth + delta).clamp(100.0, 300.0),
                      ),
                    ),
                  if (UserPermissionService.isFieldVisible('sales', 'customerName'))
                    _buildResizableHeaderSales(
                      viewModel,
                      'Customer',
                      _nameColumnWidth,
                      (delta) => _updateColumnWidth(
                        'name',
                        (_nameColumnWidth + delta).clamp(100.0, 400.0),
                      ),
                    ),
                  _buildResizableHeaderSales(
                    viewModel,
                    'Items / Services',
                    _itemsColumnWidth,
                    (delta) => _updateColumnWidth(
                      'items',
                      (_itemsColumnWidth + delta).clamp(150.0, 600.0),
                    ),
                  ),
                  if (UserPermissionService.isFieldVisible('sales', 'paymentMode'))
                    _buildResizableHeaderSales(
                      viewModel,
                      'Payment Mode',
                      _amountColumnWidth,
                      (delta) => _updateColumnWidth(
                        'amount',
                        (_amountColumnWidth + delta).clamp(80.0, 250.0),
                      ),
                    ),
                  if (UserPermissionService.isFieldVisible('sales', 'totalAmount'))
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: const Text(
                          'Net Total',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Scrollable Body Rows grouped by Status (Virtualized ListView.builder)
            Expanded(
              child: () {
                final listEntries = <_SaleListItem>[];
                for (final entry in groupedSales.entries) {
                  listEntries.add(_SaleListItem.header(entry.key, entry.value.length));
                  for (final sale in entry.value) {
                    listEntries.add(_SaleListItem.sale(sale));
                  }
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: listEntries.length,
                  itemBuilder: (context, index) {
                    final item = listEntries[index];
                    if (item.statusHeader != null) {
                      return _buildStatusSectionHeader(item.statusHeader!, item.statusCount!);
                    }
                    return _buildSaleRow(context, viewModel, item.sale!);
                  },
                );
              }(),
            ),
          ],
        ),
      );
    } else {
      final listEntries = <_SaleListItem>[];
      for (final entry in groupedSales.entries) {
        listEntries.add(_SaleListItem.header(entry.key, entry.value.length));
        for (final sale in entry.value) {
          listEntries.add(_SaleListItem.sale(sale));
        }
      }

      return RefreshIndicator(
        color: AppTheme.primaryLight,
        backgroundColor: const Color(0xFF131A2E),
        onRefresh: () async {
          final localDb = context.read<ShopRepository>().localDb;
          await SupabaseSyncService.instance.syncAllTablesFromCloud(localDb);
          if (context.mounted) viewModel.loadSales();
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
            return _buildMobileSaleCard(context, viewModel, item.sale!, itemIndex: index);
          },
        ),
      );
    }
  }

  Widget _buildMobileSaleCard(
    BuildContext context,
    RecentSalesViewModel viewModel,
    Sale sale, {
    int itemIndex = 0,
  }) {
    final items = viewModel.getSaleItems(sale.invoiceNo);
    final String itemsSummary = items.isNotEmpty
        ? items
            .map((i) =>
                '${i.itemDescription ?? "Item"} (${i.quantity})')
            .join(', ')
        : 'No items recorded';

    final String customerTitle = sale.customerName?.isNotEmpty == true
        ? sale.customerName!
        : 'Walk-in Customer';

    return AppListCard(
      index: itemIndex,
      title: customerTitle,
      subtitle: 'Invoice #${sale.invoiceNo} • ${sale.paymentMode}',
      metadataRows: [
        if (sale.customerNumber != null &&
            sale.customerNumber!.trim().isNotEmpty &&
            sale.customerNumber != 'N/A')
          Row(
            children: [
              const Icon(
                Icons.phone_rounded,
                size: 12,
                color: AppTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                sale.customerNumber!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 12,
              color: AppTheme.primaryLight,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                itemsSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total: ₹${sale.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.success,
              ),
            ),
            Text(
              DateFormat('dd MMM yyyy, hh:mm a').format(sale.saleDate),
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ],
      onTap: () => _showInvoiceDetailsSheet(context, viewModel, sale),
      onEdit: UserPermissionService.canPerformModuleAction('sales', 'canEdit')
          ? () => _startEditingSaleInBillingDesk(context, sale)
          : null,
      onDelete: UserPermissionService.canPerformModuleAction('sales', 'canDelete')
          ? () => _confirmDeleteInvoice(context, viewModel, sale.invoiceNo)
          : null,
    );
  }

  void _confirmDeleteInvoice(
    BuildContext context,
    RecentSalesViewModel viewModel,
    int invoiceNo, {
    VoidCallback? onDeleted,
  }) {
    if (!UserPermissionService.canPerformModuleAction('sales', 'canDelete')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to delete/void Sales Invoices.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirm Delete Invoice',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete Invoice #$invoiceNo? Stock will be restored.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
            onPressed: () async {
              Navigator.pop(context);
              await viewModel.deleteSale(invoiceNo);
              if (onDeleted != null) {
                onDeleted();
              }
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

  Color _getStatusColor(String status) {
    return StatusManagementService.getStatusColor('sales', status);
  }

  Widget _buildStatusChip(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }


  // ==========================================
  // VIEW SCREEN 2: BILLING DESK (POS CART)
  // ==========================================
  Widget _buildBillingDesk(
    BuildContext context,
    SalesViewModel cartVM,
    RecentSalesViewModel recentVM,
  ) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPageHeader(
          title: cartVM.isEditing
              ? 'Edit Invoice #${cartVM.editingInvoiceNo}'
              : 'Create Invoice',
          subtitle: cartVM.isEditing
              ? 'Update line items, rates, customer info, or order status.'
              : 'Search catalog, override prices, and confirm checkout.',
          onBack: () {
            cartVM.clearCart();
            _clearLocalForm();
            setState(() {
              _showBillingDesk = false;
            });
          },
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                final wasEditing = cartVM.isEditing;
                cartVM.clearCart();
                _clearLocalForm();
                if (wasEditing) {
                  setState(() {
                    _showBillingDesk = false;
                  });
                }
              },
              icon: Icon(
                cartVM.isEditing ? Icons.close_rounded : Icons.refresh_rounded,
                size: 16,
              ),
              label: Text(cartVM.isEditing ? 'Cancel Edit' : 'Reset Desk'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ],
        ),

        // Billing content
        Expanded(
          child: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildCartSection(context, cartVM),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 2,
                      child: _buildCheckoutSection(context, cartVM, recentVM),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 84),
                  child: Column(
                    children: [
                      _buildCartSection(context, cartVM, height: 450),
                      const SizedBox(height: 16),
                      _buildCheckoutSection(context, cartVM, recentVM),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCartSection(
    BuildContext context,
    SalesViewModel viewModel, {
    double? height,
  }) {
    return StaggeredSlideFade(
      index: 0,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.glassCardDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Invoice Number Header
            Row(
              children: [
                const Icon(
                  Icons.receipt_rounded,
                  color: AppTheme.primaryLight,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Invoice #${viewModel.currentOrNextInvoiceNo}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryLight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final bool isMobile = MediaQuery.of(context).size.width < 600;

                final productSearchField = AppKeyboardAutocomplete(
                  catalogItems: viewModel.catalogItems,
                  isMobile: isMobile,
                  hintText: 'Search products by name or category...',
                  clearOnSelect: true,
                  autoFocusAfterSelect: true,
                  onSelected: (PricelistItem selection) {
                    viewModel.addProductToCart(selection);
                  },
                );

                final addServiceBtn = BouncyPressable(
                  scaleFactor: 0.94,
                  onTap: () => _showAddServiceDialog(context, viewModel),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.secondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.build_rounded, size: 16, color: AppTheme.secondary),
                        SizedBox(width: 8),
                        Text(
                          'Add Service',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                if (isMobile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      productSearchField,
                      const SizedBox(height: 10),
                      addServiceBtn,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: productSearchField),
                    const SizedBox(width: 12),
                    addServiceBtn,
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white10, height: 20),

            // Cart list
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: AppleMotion.easeOut,
                switchOutCurve: AppleMotion.modalExitCurve,
                child: viewModel.cartItems.isEmpty
                    ? Center(
                        key: const ValueKey('cart_empty'),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart_outlined,
                              size: 48,
                              color: AppTheme.textMuted.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Billing Desk Cart is Empty',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Use the suggestions box above or add repair services.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey('cart_list'),
                        itemCount: viewModel.cartItems.length,
                        itemBuilder: (context, index) {
                          final item = viewModel.cartItems[index];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.015),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top Row: Icon + Description + Total + Delete
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: item.lineType == 'Product'
                                            ? AppTheme.primary.withValues(alpha: 0.12)
                                            : AppTheme.secondary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(
                                        item.lineType == 'Product'
                                            ? Icons.inventory_2_rounded
                                            : Icons.handyman_rounded,
                                        color: item.lineType == 'Product'
                                            ? AppTheme.primaryLight
                                            : AppTheme.secondary,
                                        size: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.itemDescription ?? 'Line Item',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimary,
                                              fontSize: 13,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            item.lineType,
                                            style: const TextStyle(
                                              color: AppTheme.textMuted,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    RollingNumberTicker(
                                      value: item.totalAmount,
                                      prefix: '₹',
                                      decimalDigits: 2,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    BouncyPressable(
                                      scaleFactor: 0.82,
                                      onTap: () {
                                        HapticFeedback.mediumImpact();
                                        viewModel.removeCartItem(item.id);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.danger.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 16,
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  key: Key('notes_${item.id}'),
                                  initialValue: item.notes ?? '',
                                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                                  decoration: InputDecoration(
                                    hintText: 'Add item description / details for invoice...',
                                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    filled: true,
                                    fillColor: Colors.black.withValues(alpha: 0.15),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(color: AppTheme.primaryLight),
                                    ),
                                  ),
                                  onChanged: (val) {
                                    viewModel.updateItemNotes(item.id, val.trim().isEmpty ? null : val.trim());
                                  },
                                ),
                                const SizedBox(height: 8),
                                const Divider(color: Colors.white10, height: 1),
                                const SizedBox(height: 8),

                                // Bottom Row: Unit Price Controls + Quantity Selector
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '₹${item.activePrice.toStringAsFixed(0)} / unit',
                                          style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (UserPermissionService.canPerformModuleAction('sales', 'canOverridePrice'))
                                          BouncyPressable(
                                            scaleFactor: 0.85,
                                            onTap: () => _showPriceOverrideDialog(
                                              context,
                                              viewModel,
                                              item,
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.only(left: 6),
                                              child: Icon(
                                                Icons.edit_note_rounded,
                                                size: 18,
                                                color: AppTheme.primaryLight,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        BouncyPressable(
                                          scaleFactor: 0.82,
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            viewModel.updateItemQuantity(
                                              item.id,
                                              item.quantity - 1,
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.06),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.remove_rounded,
                                              size: 14,
                                              color: AppTheme.textMuted,
                                            ),
                                          ),
                                        ),
                                        AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 160),
                                          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                          child: Padding(
                                            key: ValueKey('qty_${item.id}_${item.quantity}'),
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            child: Text(
                                              '${item.quantity}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        BouncyPressable(
                                          scaleFactor: 0.82,
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            viewModel.updateItemQuantity(
                                              item.id,
                                              item.quantity + 1,
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary.withValues(alpha: 0.2),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.add_rounded,
                                              size: 14,
                                              color: AppTheme.primaryLight,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutSection(
    BuildContext context,
    SalesViewModel cartVM,
    RecentSalesViewModel recentVM,
  ) {
    final bool isEdit = cartVM.isEditing;
    final bool isDateVis = UserPermissionService.isFieldVisible('sales', 'date');
    final bool isDateMod = UserPermissionService.canModifyField('sales', 'date', isEdit: isEdit);

    return StaggeredSlideFade(
      index: 1,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.glassCardDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.assignment_turned_in_rounded,
                        color: AppTheme.primaryLight,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Checkout Summary',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.primaryLight.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.tag_rounded,
                          size: 13,
                          color: AppTheme.primaryLight,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Invoice #${cartVM.currentOrNextInvoiceNo}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (isDateVis) ...[
                DateTimePickerField(
                  label: 'Invoice Date & Time',
                  selectedDateTime: cartVM.selectedSaleDate,
                  onDateTimeChanged: (dt) => cartVM.setSelectedSaleDate(dt),
                  isVisible: isDateVis,
                  canEdit: isDateMod,
                ),
                const SizedBox(height: 16),
              ],

              const Text(
                'Customer Information',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _customerNameController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  prefixIcon: Icon(Icons.person_outline, size: 18),
                ),
                onChanged: (val) => cartVM.setCustomerName(val),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _customerPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  prefixIcon: Icon(Icons.phone_iphone_rounded, size: 18),
                ),
                keyboardType: TextInputType.phone,
                onChanged: (val) => cartVM.setCustomerNumber(val),
              ),
              const SizedBox(height: 20),

              const Text(
                'Calculations & Adjustments',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _discountController,
                      decoration: const InputDecoration(
                        labelText: 'Discount (₹)',
                        prefixIcon: Icon(Icons.local_offer_outlined, size: 18),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (val) {
                        final discount = double.tryParse(val) ?? 0.0;
                        cartVM.setDiscount(discount);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _advanceController,
                      decoration: const InputDecoration(
                        labelText: 'Advance Paid (₹)',
                        prefixIcon: Icon(Icons.payments_outlined, size: 18),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (val) {
                        final advance = double.tryParse(val) ?? 0.0;
                        cartVM.setAdvance(advance);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Animated Payment Mode Segmented Chips
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment Mode',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final mode in [
                        ('UPI', Icons.qr_code_2_rounded),
                        ('Cash', Icons.payments_rounded),
                        ('Card', Icons.credit_card_rounded),
                      ]) ...[
                        Expanded(
                          child: BouncyPressable(
                            scaleFactor: 0.94,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              cartVM.setPaymentMode(mode.$1);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: AppleMotion.easeOut,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: cartVM.paymentMode == mode.$1
                                    ? AppTheme.primary
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: cartVM.paymentMode == mode.$1
                                      ? AppTheme.primaryLight
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                                boxShadow: cartVM.paymentMode == mode.$1
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.primary.withValues(alpha: 0.4),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    mode.$2,
                                    size: 16,
                                    color: cartVM.paymentMode == mode.$1
                                        ? Colors.white
                                        : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    mode.$1,
                                    style: TextStyle(
                                      color: cartVM.paymentMode == mode.$1
                                          ? Colors.white
                                          : AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (mode != ('Card', Icons.credit_card_rounded))
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ],
              ),
              if (cartVM.isEditing && UserPermissionService.isFieldVisible('sales', 'orderStatus')) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Order Status:',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Builder(
                        builder: (context) {
                          final allowed = UserPermissionService.getAllowedSelectableStatuses('sales');
                          final List<String> selectableList = List.from(allowed);
                          final current = (cartVM.editingOrderStatus ?? StatusManagementService.getDefaultStatus('sales')).trim();
                          final match = selectableList.firstWhere(
                            (s) => s.trim().toLowerCase() == current.toLowerCase() ||
                                   (current.toLowerCase() == 'confirmed' && (s.trim().toLowerCase() == 'complete' || s.trim().toLowerCase() == 'completed')),
                            orElse: () => selectableList.isNotEmpty ? selectableList.first : 'Pending',
                          );
                          final effectiveStatus = match;

                          return DropdownButton<String>(
                            value: effectiveStatus.isNotEmpty ? effectiveStatus : (selectableList.isNotEmpty ? selectableList.first : null),
                            underline: const SizedBox(),
                            dropdownColor: const Color(0xFF131A2E),
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            items: selectableList.map((st) {
                              return DropdownMenuItem<String>(value: st, child: Text(st));
                            }).toList(),
                            onChanged: UserPermissionService.canModifyField('sales', 'orderStatus', isEdit: true)
                                ? (val) {
                                    if (val != null) {
                                      cartVM.setEditingOrderStatus(val);
                                    }
                                  }
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],

              const Divider(color: Colors.white10, height: 28),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Subtotal',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  RollingNumberTicker(
                    value: cartVM.subtotal,
                    prefix: '₹',
                    decimalDigits: 2,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (cartVM.discount > 0) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Discount Applied',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    RollingNumberTicker(
                      value: cartVM.discount,
                      prefix: '- ₹',
                      decimalDigits: 2,
                      style: const TextStyle(
                        color: AppTheme.danger,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              if (cartVM.advance > 0) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Advance Paid',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    RollingNumberTicker(
                      value: cartVM.advance,
                      prefix: '- ₹',
                      decimalDigits: 2,
                      style: const TextStyle(
                        color: AppTheme.success,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),

              // Glowing Total Payable Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.18),
                      AppTheme.secondary.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryLight.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOTAL PAYABLE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${cartVM.cartItems.length} item${cartVM.cartItems.length == 1 ? '' : 's'} in cart',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    RollingNumberTicker(
                      value: cartVM.totalAmount,
                      prefix: '₹',
                      decimalDigits: 2,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.success,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Confirm Checkout / Update Invoice
              BouncyPressable(
                scaleFactor: 0.98,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: cartVM.cartItems.isEmpty
                        ? null
                        : () async {
                          final isEditing = cartVM.isEditing;
                          final double checkoutAmount = cartVM.totalAmount;
                          final invoiceNo = await cartVM.checkout();
                          if (!context.mounted) return;
                          if (invoiceNo != null) {
                            _clearLocalForm();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isEditing
                                      ? 'Invoice #$invoiceNo updated successfully.'
                                      : 'Order #$invoiceNo created in PENDING verification.',
                                ),
                                backgroundColor: AppTheme.success,
                              ),
                            );

                            // Reload ledger and return
                            await recentVM.loadSales();
                            if (!context.mounted) return;
                            setState(() {
                              _showBillingDesk = false;
                            });

                            // Show Payment QR Code Popup
                            _showPaymentQrDialog(
                              context,
                              recentVM,
                              invoiceNo,
                              checkoutAmount,
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Checkout failed.'),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                          }
                        },
                    icon: cartVM.isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            isEdit
                                ? Icons.save_rounded
                                : Icons.check_circle_rounded,
                            size: 18,
                          ),
                    label: Text(
                      cartVM.isSaving
                          ? 'Processing...'
                          : (isEdit ? 'Save Changes' : 'Confirm Checkout'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 0.3,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: cartVM.cartItems.isEmpty ? 0 : 4,
                      shadowColor: AppTheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInvoiceDetailsSheet(
    BuildContext context,
    RecentSalesViewModel viewModel,
    Sale sale,
  ) {
    final items = viewModel.getSaleItems(sale.invoiceNo);

    showDialog(
      context: context,
      builder: (context) {
        final normalizedStatus = sale.orderStatus.trim().toLowerCase();
        final bool isComplete = normalizedStatus == 'complete' ||
            normalizedStatus == 'completed' ||
            normalizedStatus == 'confirmed';
        final bool isMobile = MediaQuery.of(context).size.width < 600;

        return Dialog(
          backgroundColor: const Color(0xFF0F1524),
          insetPadding: isMobile
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: isMobile
              ? const RoundedRectangleBorder()
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
          child: Container(
            width: isMobile
                ? double.infinity
                : MediaQuery.of(context).size.width * 0.8,
            height: isMobile
                ? double.infinity
                : MediaQuery.of(context).size.height * 0.8,
            constraints: isMobile
                ? const BoxConstraints()
                : const BoxConstraints(maxWidth: 750, maxHeight: 600),
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.receipt_long_rounded,
                          color: AppTheme.primaryLight,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Invoice #${sale.invoiceNo}',
                          style: TextStyle(
                            fontSize: isMobile ? 18 : 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Scrollable Content Section
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer Details Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'BILLED TO',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  sale.customerName ?? 'Cash / Walk-in',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                if (sale.customerNumber != null &&
                                    sale.customerNumber!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Mob: ${sale.customerNumber}',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'DATE & PAYMENT',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('dd/MM/yy hh:mm a')
                                      .format(sale.saleDate),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Mode: ${sale.paymentMode}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: AppTheme.primaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 24),

                        // Invoice Items Header
                        const Text(
                          'INVOICE ITEMS',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Invoice Items List
                        ...items.map((item) {
                          final String titleText = (item.itemDescription != null &&
                                  item.itemDescription!.trim().isNotEmpty)
                              ? item.itemDescription!
                              : (item.serviceName ?? 'Line Item');
                          final bool hasNotes = item.notes != null &&
                              item.notes!.trim().isNotEmpty &&
                              item.notes!.trim().toLowerCase() !=
                                  titleText.trim().toLowerCase();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.015),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.05),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        titleText,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      if (hasNotes) ...[
                                        const SizedBox(height: 3),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primary.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            item.notes!,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.primaryLight,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        'Qty: ${item.quantity} x ₹${item.activePrice.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '₹${item.totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(color: Colors.white10, height: 24),

                        // Financial Summary Blocks
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Order Status: ',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    _buildStatusChip(sale.orderStatus),
                                  ],
                                ),
                                if (sale.discount > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Discount: -₹${sale.discount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: AppTheme.danger,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                if (sale.advance > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Advance Paid: ₹${sale.advance.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: AppTheme.success,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                if (sale.photoList.isNotEmpty)
                                  PhotoGallerySection(photoUrls: sale.photoList),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'GRAND TOTAL',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₹${sale.totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Action Buttons Block
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isComplete &&
                        UserPermissionService.canPerformModuleAction(
                            'sales', 'canVerifyStock'))
                      ElevatedButton.icon(
                        onPressed: () async {
                          final success = await viewModel.confirmOrder(
                            sale.invoiceNo,
                          );
                          if (success) {
                            if (context.mounted) {
                              context.read<PricelistViewModel>().loadItems();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Invoice #${sale.invoiceNo} marked as complete. Stock levels updated.',
                                  ),
                                  backgroundColor: AppTheme.success,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Mark as Complete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      )
                    else if (isComplete)
                      ElevatedButton.icon(
                        onPressed: () async {
                          final success = await viewModel.setSaleStatusPending(
                            sale.invoiceNo,
                          );
                          if (success) {
                            if (context.mounted) {
                              context.read<PricelistViewModel>().loadItems();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Invoice #${sale.invoiceNo} reverted to pending.',
                                  ),
                                  backgroundColor: AppTheme.warning,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.history_rounded),
                        label: const Text('Revert to Pending'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.warning.withValues(
                            alpha: 0.2,
                          ),
                          foregroundColor: AppTheme.warning,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final canEdit = UserPermissionService.canPerformModuleAction(
                            'sales', 'canEdit');
                        final canDelete =
                            UserPermissionService.canPerformModuleAction(
                                'sales', 'canDelete');
                        final isCompact = constraints.maxWidth < 520;

                        final sendToDisplayBtn = ElevatedButton.icon(
                          onPressed: () async {
                            final activeUpiId = viewModel.getActiveUpiId() ?? 'computer.perfect@ybl';
                            final upiRefName = viewModel.getUpiReferenceName(activeUpiId);

                            final success = await KioskBroadcastService.instance.sendQrToKiosk(
                              amount: sale.totalAmount,
                              invoiceNo: '#${sale.invoiceNo}',
                              customerName: sale.customerName,
                              upiId: activeUpiId,
                              upiName: upiRefName,
                            );

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? 'Broadcasting ₹${sale.totalAmount.toStringAsFixed(0)} QR to Customer Display...'
                                        : 'Failed to broadcast to display.',
                                  ),
                                  backgroundColor: const Color(0xFF0EA5E9),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.cast_rounded, size: 16),
                          label: const Text('Send to QR Display'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.25),
                            foregroundColor: const Color(0xFF38BDF8),
                            side: const BorderSide(color: Color(0xFF0284C7), width: 1.2),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );

                        final editBtn = ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _startEditingSaleInBillingDesk(context, sale);
                          },
                          icon: const Icon(Icons.edit_note_rounded, size: 16),
                          label: const Text('Edit Sale'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );

                        final printBtn = ElevatedButton.icon(
                          onPressed: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Opening invoice in PDF viewer...'),
                                backgroundColor: AppTheme.success,
                                duration: Duration(seconds: 2),
                              ),
                            );
                            final success = await PdfInvoiceHelper.printInvoice(
                              sale: sale,
                              items: items,
                              activeUpiId: viewModel.getActiveUpiId(),
                            );
                            if (!success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not open PDF viewer.'),
                                  backgroundColor: AppTheme.danger,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.print_rounded, size: 16),
                          label: const Text('Print Receipt'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            foregroundColor: AppTheme.textPrimary,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );

                        final deleteBtn = OutlinedButton.icon(
                          onPressed: () => _confirmDeleteInvoice(
                            context,
                            viewModel,
                            sale.invoiceNo,
                            onDeleted: () {
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                          ),
                          icon: const Icon(
                            Icons.delete_forever_rounded,
                            size: 16,
                          ),
                          label: const Text('Delete'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.danger),
                            foregroundColor: AppTheme.danger,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );

                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  if (UserPermissionService.canPerformModuleAction('sales', 'canBroadcastQr')) ...[
                                    Expanded(child: sendToDisplayBtn),
                                    const SizedBox(width: 8),
                                  ],
                                  if (canEdit) ...[ 
                                    Expanded(child: editBtn),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: printBtn),
                                  if (canDelete) ...[ 
                                    const SizedBox(width: 8),
                                    Expanded(child: deleteBtn),
                                  ],
                                ],
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            if (UserPermissionService.canPerformModuleAction('sales', 'canBroadcastQr')) ...[
                              Expanded(child: sendToDisplayBtn),
                              const SizedBox(width: 8),
                            ],
                            if (canEdit) ...[
                              Expanded(child: editBtn),
                              const SizedBox(width: 8),
                            ],
                            Expanded(child: printBtn),
                            if (canDelete) ...[
                              const SizedBox(width: 8),
                              deleteBtn,
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Service Name Autocomplete & Add Service Dialog

  void _showAddServiceDialog(BuildContext context, SalesViewModel viewModel) {
    showAppModalDialog(
      context: context,
      builder: (context) => _AddRepairServiceModal(viewModel: viewModel),
    );
  }

  void _showPriceOverrideDialog(
    BuildContext context,
    SalesViewModel viewModel,
    SaleItem item,
  ) {
    final TextEditingController rateController = TextEditingController(
      text: item.activePrice.toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Override Rate: ${item.itemDescription}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter a custom pricing overrides for this specific line item.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: rateController,
                decoration: const InputDecoration(labelText: 'Custom Rate (₹)'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                autofocus: true,
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
                final double? rate = double.tryParse(rateController.text);
                if (rate != null) {
                  viewModel.updateItemCustomPrice(item.id, rate);
                }
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  void _startEditingSaleInBillingDesk(BuildContext context, Sale sale) {
    if (!UserPermissionService.canPerformModuleAction('sales', 'canEdit')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to edit Sales Invoices.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    final repo = context.read<ShopRepository>();
    final items = repo.localDb.getSaleItems(sale.invoiceNo);
    final cartVM = context.read<SalesViewModel>();

    cartVM.loadSaleForEditing(sale, items);
    _customerNameController.text = sale.customerName ?? '';
    _customerPhoneController.text = sale.customerNumber ?? '';
    _discountController.text =
        sale.discount > 0 ? sale.discount.toStringAsFixed(2) : '';
    _advanceController.text =
        sale.advance > 0 ? sale.advance.toStringAsFixed(2) : '';

    setState(() {
      _showBillingDesk = true;
    });
  }

  void _showPaymentQrDialog(
    BuildContext context,
    RecentSalesViewModel recentVM,
    int invoiceNo,
    double totalAmount,
  ) {
    final activeUpiId = recentVM.getActiveUpiId() ?? 'computer.perfect@ybl';
    final upiRefName = recentVM.getUpiReferenceName(activeUpiId);
    final sale = recentVM.getSaleByInvoiceNo(invoiceNo);
    final items = recentVM.getSaleItems(invoiceNo);

    final upiUri =
        'upi://pay?pa=$activeUpiId&pn=Perfect%20Solution&am=${totalAmount.toStringAsFixed(2)}&cu=INR&tn=Invoice%20%23$invoiceNo';

    showAppModalDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final bool isMobile = MediaQuery.of(context).size.width < 600;

        return Dialog(
          backgroundColor: const Color(0xFF0F1524),
          insetPadding: isMobile
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
          ),
          child: Container(
            width: isMobile ? double.infinity : 440,
            padding: EdgeInsets.all(isMobile ? 18 : 24),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Success Badge with spring pop
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.success,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Invoice #$invoiceNo Saved!',
                    style: AppTypography.title2.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Scan QR code to pay via UPI (GPay, PhonePe, Paytm)',
                    textAlign: TextAlign.center,
                    style: AppTypography.footnote.copyWith(
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Amount Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'AMOUNT TO PAY',
                          style: AppTypography.badge.copyWith(
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        RollingNumberTicker(
                          value: totalAmount,
                          prefix: '₹',
                          decimalDigits: 2,
                          style: AppTypography.currencyLarge.copyWith(
                            fontSize: isMobile ? 24 : 28,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // QR Code Box with glowing halo
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.35),
                          blurRadius: 28,
                          spreadRadius: 3,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: upiUri,
                      version: QrVersions.auto,
                      size: isMobile ? 180 : 210,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0B0F19)),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0B0F19)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Active UPI Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.primaryLight.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.qr_code_2_rounded,
                          size: 14,
                          color: AppTheme.primaryLight,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            upiRefName.isNotEmpty
                                ? '$upiRefName • $activeUpiId'
                                : activeUpiId,
                            style: AppTypography.subhead.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryLight,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BouncyPressable(
                        scaleFactor: 0.96,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final success = await KioskBroadcastService.instance.sendQrToKiosk(
                              amount: totalAmount,
                              invoiceNo: '#$invoiceNo',
                              customerName: sale?.customerName,
                              upiId: activeUpiId,
                              upiName: upiRefName,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? 'Broadcasting ₹${totalAmount.toStringAsFixed(0)} QR to Kiosk Display...'
                                        : 'Failed to broadcast to Kiosk.',
                                  ),
                                  backgroundColor: success ? AppTheme.secondary : AppTheme.danger,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.cast_rounded, size: 18),
                          label: const Text(
                            'Send to QR Display',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.secondary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (sale != null) ...[
                        BouncyPressable(
                          scaleFactor: 0.96,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Opening invoice in PDF viewer...'),
                                  backgroundColor: AppTheme.success,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              await PdfInvoiceHelper.printInvoice(
                                sale: sale,
                                items: items,
                                activeUpiId: activeUpiId,
                              );
                            },
                            icon: const Icon(Icons.print_rounded, size: 18),
                            label: const Text(
                              'Print Receipt',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      BouncyPressable(
                        scaleFactor: 0.96,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text(
                            'Done / Complete',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            foregroundColor: AppTheme.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SaleListItem {
  final String? statusHeader;
  final int? statusCount;
  final Sale? sale;

  _SaleListItem.header(this.statusHeader, this.statusCount) : sale = null;
  _SaleListItem.sale(this.sale) : statusHeader = null, statusCount = null;
}

class _AddRepairServiceModal extends StatefulWidget {
  final SalesViewModel viewModel;

  const _AddRepairServiceModal({required this.viewModel});

  @override
  State<_AddRepairServiceModal> createState() => _AddRepairServiceModalState();
}

class _AddRepairServiceModalState extends State<_AddRepairServiceModal> {
  TextEditingController? _autocompleteController;
  final TextEditingController _nameFallbackController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final FocusNode _priceFocusNode = FocusNode();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameFallbackController.dispose();
    _priceController.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final double price = double.parse(_priceController.text.trim());
      final String serviceName =
          (_autocompleteController?.text.trim().isNotEmpty ?? false)
              ? _autocompleteController!.text.trim()
              : _nameFallbackController.text.trim();
      HapticFeedback.mediumImpact();
      widget.viewModel.addCustomServiceToCart(serviceName, price);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedServices = widget.viewModel.savedServices;
    final catalogItems = widget.viewModel.catalogItems;
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    final allServices = <String>{
      ...savedServices,
      ...catalogItems
          .where((i) => (i.category?.toLowerCase() ?? '') == 'service')
          .map((i) => i.itemName),
    }.toList();

    return Dialog(
      backgroundColor: const Color(0xFF0F1524),
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: AppTheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Container(
        width: isMobile ? double.infinity : 480,
        padding: const EdgeInsets.all(22),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryLight.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.handyman_rounded,
                      color: AppTheme.primaryLight,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Repair Service',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Enter or select a service charge',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BouncyPressable(
                    scaleFactor: 0.88,
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Autocomplete with Inward-matching background & styling
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return allServices;
                  }
                  final query = textEditingValue.text.toLowerCase();
                  return allServices.where(
                    (s) => s.toLowerCase().contains(query),
                  );
                },
                onSelected: (String selection) {
                  _autocompleteController?.text = selection;
                  _priceFocusNode.requestFocus();
                },
                fieldViewBuilder: (
                  context,
                  textEditingController,
                  focusNode,
                  onFieldSubmitted,
                ) {
                  _autocompleteController = textEditingController;
                  return TextFormField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _priceFocusNode.requestFocus(),
                    decoration: InputDecoration(
                      labelText: 'Service Name *',
                      hintText: 'e.g. Display Fitting, Motherboard Repair...',
                      prefixIcon: const Icon(Icons.build_rounded, size: 18),
                      suffixIcon: textEditingController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                textEditingController.clear();
                              },
                            )
                          : null,
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter or select a service name';
                      }
                      return null;
                    },
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      color: const Color(0xFF161C2E),
                      elevation: 8.0,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: isMobile ? MediaQuery.of(context).size.width * 0.85 : 436,
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161C2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
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
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              hoverColor: AppTheme.primary.withValues(alpha: 0.15),
                              onTap: () => onSelected(s),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Fee Field
              TextFormField(
                controller: _priceController,
                focusNode: _priceFocusNode,
                decoration: const InputDecoration(
                  labelText: 'Service Fee (₹) *',
                  hintText: '0.00',
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onFieldSubmitted: (_) => _submit(),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter service fee';
                  }
                  if (double.tryParse(val) == null) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 22),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: BouncyPressable(
                      scaleFactor: 0.96,
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: BouncyPressable(
                      scaleFactor: 0.96,
                      onTap: _submit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary,
                              AppTheme.primary.withValues(alpha: 0.85),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_shopping_cart_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Add to Cart',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
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

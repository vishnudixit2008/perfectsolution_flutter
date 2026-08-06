import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shop_management_flutter/ui/core/app_theme.dart';
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
import '../../../shared/components/app_pagination_bar.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_floating_action_button.dart';
import '../../../shared/components/app_header_sync_button.dart';
import '../../../shared/components/app_search_filter_bar.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../../../shared/status_management_dialog.dart';

import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/supabase_sync_service.dart';
import '../../../../data/services/user_permission_service.dart';

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
  double _nameColumnWidth = 220.0;
  double _numberColumnWidth = 150.0;
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

  @override
  void initState() {
    super.initState();
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
        );
      }
    } else {
      final String? itemName =
          prefill['itemName'] ?? prefill['item'] ?? prefill['devices'];
      final double amount =
          (prefill['amount'] ?? prefill['totalAmount'] ?? 0.0) as double;

      if (itemName != null && itemName.isNotEmpty) {
        salesVM.addCustomServiceToCart(itemName, amount);
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
        if (_showBillingDesk) {
          return _buildBillingDesk(context, salesCartVM, recentSalesVM);
        } else {
          return _buildSalesLedgerScreen(context, recentSalesVM);
        }
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
    final int totalItems = filteredSales.length;
    final int totalPages = (totalItems / viewModel.itemsPerPage).ceil().clamp(
      1,
      99999,
    );
    final int currentPage = viewModel.currentPage.clamp(1, totalPages);

    final int startIndex = (currentPage - 1) * viewModel.itemsPerPage;
    final int endIndex = (startIndex + viewModel.itemsPerPage).clamp(
      0,
      totalItems,
    );
    final pagedSales = filteredSales.sublist(startIndex, endIndex);

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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: TextField(
                controller: _ledgerSearchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search invoice #, customer name, mobile...',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
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
                : Stack(
                    children: [
                      Positioned.fill(
                        child: _buildSalesTableOrCards(
                          context,
                          viewModel,
                          pagedSales,
                          isDesktop,
                        ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: AppPaginationBar(
                          currentPage: currentPage,
                          totalPages: totalPages,
                          itemsPerPage: viewModel.itemsPerPage,
                          onItemsPerPageChanged: (val) =>
                              viewModel.setItemsPerPage(val),
                          onPreviousPage: () => viewModel.previousPage(),
                          onNextPage: () => viewModel.nextPage(totalPages),
                        ),
                      ),
                    ],
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
            Container(
              width: _nameColumnWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              alignment: Alignment.centerLeft,
              child: Text(
                sale.customerName ?? 'Cash / Walk-in',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Customer Phone cell
            Container(
              width: _numberColumnWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              alignment: Alignment.centerLeft,
              child: Text(
                (sale.customerNumber == null || sale.customerNumber!.isEmpty)
                    ? '-'
                    : sale.customerNumber!,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
            // Payment Mode cell
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
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            // Net Total (expanded)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  '₹${sale.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
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
      final existingKey = grouped.keys.firstWhere(
        (k) => k.toLowerCase() == statusName.toLowerCase(),
        orElse: () => '',
      );

      if (existingKey.isNotEmpty) {
        grouped[existingKey]!.add(sale);
      } else {
        if (!grouped.containsKey(statusName)) {
          grouped[statusName] = [];
        }
        grouped[statusName]!.add(sale);
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
              '$count ${count == 1 ? 'Invoice' : 'Invoices'}',
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
                  _buildResizableHeaderSales(
                    viewModel,
                    'Invoice #',
                    _invoiceColumnWidth,
                    (delta) => setState(
                      () => _invoiceColumnWidth = (_invoiceColumnWidth + delta)
                          .clamp(60.0, 200.0),
                    ),
                  ),
                  _buildResizableHeaderSales(
                    viewModel,
                    'Date & Time',
                    _dateColumnWidth,
                    (delta) => setState(
                      () => _dateColumnWidth = (_dateColumnWidth + delta).clamp(
                        100.0,
                        300.0,
                      ),
                    ),
                  ),
                  _buildResizableHeaderSales(
                    viewModel,
                    'Customer',
                    _nameColumnWidth,
                    (delta) => setState(
                      () => _nameColumnWidth = (_nameColumnWidth + delta).clamp(
                        150.0,
                        500.0,
                      ),
                    ),
                  ),
                  _buildResizableHeaderSales(
                    viewModel,
                    'Mobile Details',
                    _numberColumnWidth,
                    (delta) => setState(
                      () => _numberColumnWidth = (_numberColumnWidth + delta)
                          .clamp(100.0, 300.0),
                    ),
                  ),
                  _buildResizableHeaderSales(
                    viewModel,
                    'Payment Mode',
                    _amountColumnWidth,
                    (delta) => setState(
                      () => _amountColumnWidth = (_amountColumnWidth + delta)
                          .clamp(80.0, 250.0),
                    ),
                  ),
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

            // Scrollable Body Rows grouped by Status
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                padding: const EdgeInsets.only(bottom: 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in groupedSales.entries) ...[
                      _buildStatusSectionHeader(entry.key, entry.value.length),
                      for (final sale in entry.value) ...[
                        _buildSaleRow(context, viewModel, sale),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return RefreshIndicator(
        color: AppTheme.primaryLight,
        backgroundColor: const Color(0xFF131A2E),
        onRefresh: () async {
          final localDb = context.read<ShopRepository>().localDb;
          await SupabaseSyncService.instance.syncAllTablesFromCloud(localDb);
          if (context.mounted) viewModel.loadSales();
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            for (final entry in groupedSales.entries) ...[
              _buildStatusSectionHeader(entry.key, entry.value.length),
              for (final sale in entry.value) ...[
                AppListCard(
                  title: 'Invoice #${sale.invoiceNo}',
                  subtitle: sale.customerName?.isNotEmpty == true
                      ? sale.customerName!
                      : 'Walk-in Customer',
                  metadataRows: [
                    if (sale.customerNumber != null &&
                        sale.customerNumber!.trim().isNotEmpty &&
                        sale.customerNumber != 'N/A')
                      Row(
                        children: [
                          const Icon(
                            Icons.phone_rounded,
                            size: 13,
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
                  onDelete: () =>
                      _confirmDeleteInvoice(context, viewModel, sale.invoiceNo),
                ),
              ],
            ],
          ],
        ),
      );
    }
  }

  void _confirmDeleteInvoice(
    BuildContext context,
    RecentSalesViewModel viewModel,
    int invoiceNo,
  ) {
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
    final s = status.toLowerCase().trim();
    if (s == 'laptop' || s == 'desktop') return const Color(0xFFEF4444); // Red
    if (s == 'ready return' || s == 'ready-return') return const Color(0xFFCA8A04); // Dull Yellow
    if (s == 'ready') return const Color(0xFFEAB308); // Yellow
    if (s.contains('hold')) return const Color(0xFF06B6D4); // Cyan
    if (s.contains('complete') || s.contains('pre complete') || s.contains('pre-complete') || s == 'confirmed') {
      return const Color(0xFF10B981); // Green
    }
    if (s.contains('cancel') || s.contains('reject')) return const Color(0xFFEF4444);
    if (s.contains('pending')) return const Color(0xFFF97316);
    return const Color(0xFF6366F1);
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
    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassCardDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keyboard autocomplete product search bar
          Row(
            children: [
              Expanded(
                child: Autocomplete<PricelistItem>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<PricelistItem>.empty();
                    }
                    return viewModel.searchResults;
                  },
                  displayStringForOption: (PricelistItem option) =>
                      option.itemName,
                  onSelected: (PricelistItem selection) {
                    viewModel.addProductToCart(selection);
                  },
                  fieldViewBuilder:
                      (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        // Force suggestions query update on keystroke
                        textEditingController.addListener(() {
                          viewModel.updateSearchQuery(
                            textEditingController.text,
                          );
                        });

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                          child: TextField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText:
                                  'Search products by name or category...',
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: AppTheme.textMuted,
                              ),
                              suffixIcon: textEditingController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear_rounded,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        textEditingController.clear();
                                        viewModel.updateSearchQuery('');
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        );
                      },
                  optionsViewBuilder: (context, onSelected, options) {
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
                          width: MediaQuery.of(context).size.width * 0.85,
                          constraints: const BoxConstraints(
                            maxWidth: 450,
                            maxHeight: 250,
                          ),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            separatorBuilder: (context, index) =>
                                const Divider(color: Colors.white10, height: 1),

                            itemBuilder: (BuildContext context, int index) {
                              final PricelistItem option = options.elementAt(
                                index,
                              );
                              final bool isLowStock =
                                  option.stockQty <= option.openingStock;

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
                                    color: isLowStock
                                        ? AppTheme.danger
                                        : AppTheme.textMuted,
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
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showAddServiceDialog(context, viewModel),
                icon: const Icon(Icons.build_rounded, size: 16),
                label: const Text('Add Service'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary.withOpacity(0.12),
                  foregroundColor: AppTheme.secondary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white10, height: 24),

          // Cart list
          Expanded(
            child: viewModel.cartItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 48,
                          color: AppTheme.textMuted.withOpacity(0.5),
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
                          color: Colors.white.withOpacity(0.01),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.04),
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
                                        ? AppTheme.primary.withOpacity(0.08)
                                        : AppTheme.secondary.withOpacity(0.08),
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
                                Text(
                                  '₹${item.totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: AppTheme.danger,
                                  ),
                                  onPressed: () {
                                    viewModel.removeCartItem(item.id);
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
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
                                fillColor: Colors.black.withOpacity(0.15),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
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
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_note_rounded,
                                        size: 16,
                                        color: AppTheme.primaryLight,
                                      ),
                                      onPressed: () => _showPriceOverrideDialog(
                                        context,
                                        viewModel,
                                        item,
                                      ),
                                      padding: const EdgeInsets.only(left: 4),
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Override Price',
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline_rounded,
                                        size: 18,
                                        color: AppTheme.textMuted,
                                      ),
                                      onPressed: () {
                                        viewModel.updateItemQuantity(
                                          item.id,
                                          item.quantity - 1,
                                        );
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        '${item.quantity}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                        size: 18,
                                        color: AppTheme.primaryLight,
                                      ),
                                      onPressed: () {
                                        viewModel.updateItemQuantity(
                                          item.id,
                                          item.quantity + 1,
                                        );
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
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
        ],
      ),
    );
  }

  Widget _buildCheckoutSection(
    BuildContext context,
    SalesViewModel cartVM,
    RecentSalesViewModel recentVM,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCardDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: 12,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.assignment_turned_in_rounded,
                  color: AppTheme.primaryLight,
                  size: 20,
                ),
                SizedBox(width: 12),
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
            const SizedBox(height: 20),

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

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Payment Mode:',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: DropdownButton<String>(
                    value: cartVM.paymentMode,
                    underline: const SizedBox(),
                    dropdownColor: const Color(0xFF131A2E),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    items: ['UPI', 'Cash', 'Card'].map((mode) {
                      return DropdownMenuItem<String>(
                        value: mode,
                        child: Text(mode),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        cartVM.setPaymentMode(val);
                      }
                    },
                  ),
                ),
              ],
            ),
            if (cartVM.isEditing) ...[
              const SizedBox(height: 12),
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
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: DropdownButton<String>(
                      value: ['Confirmed', 'PENDING'].contains(cartVM.editingOrderStatus)
                          ? cartVM.editingOrderStatus
                          : 'Confirmed',
                      underline: const SizedBox(),
                      dropdownColor: const Color(0xFF131A2E),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Confirmed', child: Text('Confirmed')),
                        DropdownMenuItem(value: 'PENDING', child: Text('PENDING')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          cartVM.setEditingOrderStatus(val);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],

            const Divider(color: Colors.white10, height: 32),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Subtotal',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                Text(
                  '₹${cartVM.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
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
                  Text(
                    '- ₹${cartVM.discount.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppTheme.danger, fontSize: 14),
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
                  Text(
                    '- ₹${cartVM.advance.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppTheme.success, fontSize: 14),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'GRAND TOTAL',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '₹${cartVM.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryLight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Confirm Checkout / Update Invoice
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: cartVM.cartItems.isEmpty
                    ? null
                    : () async {
                        final isEditing = cartVM.isEditing;
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
                        cartVM.isEditing
                            ? Icons.save_rounded
                            : Icons.check_circle_rounded,
                      ),
                label: Text(
                  cartVM.isSaving
                      ? 'Processing...'
                      : (cartVM.isEditing
                          ? 'Update Invoice #${cartVM.editingInvoiceNo}'
                          : 'Confirm Sale (Pending)'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Details Modal Dialog (Bigger in size with actions)
  void _showInvoiceDetailsSheet(
    BuildContext context,
    RecentSalesViewModel viewModel,
    Sale sale,
  ) {
    final items = viewModel.getSaleItems(sale.invoiceNo);

    showDialog(
      context: context,
      builder: (context) {
        final isPending = sale.orderStatus == 'PENDING';
        return Dialog(
          backgroundColor: const Color(0xFF0F1524),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.8,
            constraints: const BoxConstraints(maxWidth: 750, maxHeight: 600),
            padding: const EdgeInsets.all(28),
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
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Invoice #${sale.invoiceNo}',
                          style: const TextStyle(
                            fontSize: 20,
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
                const SizedBox(height: 20),

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
                            fontSize: 15,
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
                              fontSize: 13,
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
                          DateFormat('dd/MM/yy hh:mm a').format(sale.saleDate),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Payment Mode: ${sale.paymentMode}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 32),

                // Invoice Items
                const Text(
                  'INVOICE ITEMS',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.01),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.04),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.itemDescription ?? 'Line Item',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
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
                    },
                  ),
                ),
                const Divider(color: Colors.white10, height: 32),

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
                                fontSize: 13,
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
                              fontSize: 13,
                            ),
                          ),
                        ],
                        if (sale.advance > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Advance Paid: ₹${sale.advance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppTheme.success,
                              fontSize: 13,
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
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                 Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isPending && UserPermissionService.canPerformModuleAction('sales', 'canVerifyStock'))
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
                                    'Invoice #${sale.invoiceNo} confirmed. Stock levels updated.',
                                  ),
                                  backgroundColor: AppTheme.success,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Verify & Deduct Stock'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      )
                    else if (!isPending)
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
                                    'Invoice #${sale.invoiceNo} marked as pending.',
                                  ),
                                  backgroundColor: AppTheme.warning,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.history_rounded),
                        label: const Text('Mark as Pending'),
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
                        final canEdit = UserPermissionService.canPerformModuleAction('sales', 'canEdit');
                        final canDelete = UserPermissionService.canPerformModuleAction('sales', 'canDelete');
                        final isCompact = constraints.maxWidth < 460;

                        final editBtn = ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _startEditingSaleInBillingDesk(context, sale);
                          },
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label: const Text('Edit Sale'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
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
                          icon: const Icon(Icons.print_rounded, size: 18),
                          label: const Text('Print Receipt'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            foregroundColor: AppTheme.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
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
                          ),
                          icon: const Icon(
                            Icons.delete_forever_rounded,
                            size: 18,
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
                                  if (canEdit) ...[
                                    Expanded(child: editBtn),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(child: printBtn),
                                ],
                              ),
                              if (canDelete) ...[
                                const SizedBox(height: 8),
                                SizedBox(width: double.infinity, child: deleteBtn),
                              ],
                            ],
                          );
                        }

                        return Row(
                          children: [
                            if (canEdit) ...[
                              Expanded(child: editBtn),
                              const SizedBox(width: 10),
                            ],
                            Expanded(child: printBtn),
                            if (canDelete) ...[
                              const SizedBox(width: 10),
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

  // Service Name Autocomplete dialog

  void _showAddServiceDialog(BuildContext context, SalesViewModel viewModel) {
    TextEditingController? autocompleteController;
    final TextEditingController priceController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Repair Service'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter details of a custom service charge (e.g. charging port replacement, software reset).',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    final services = viewModel.savedServices;
                    if (textEditingValue.text.isEmpty) {
                      return services;
                    }
                    return services.where((option) {
                      return option.toLowerCase().contains(
                        textEditingValue.text.toLowerCase(),
                      );
                    });
                  },
                  onSelected: (String selection) {
                    if (autocompleteController != null) {
                      autocompleteController!.text = selection;
                    }
                  },
                  fieldViewBuilder:
                      (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        autocompleteController = textEditingController;
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Service Name *',
                            hintText: 'e.g. Display Fitting',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please enter service name';
                            }
                            return null;
                          },
                        );
                      },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: priceController,
                  decoration: const InputDecoration(
                    labelText: 'Service Fee (₹) *',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter price';
                    }
                    if (double.tryParse(val) == null) {
                      return 'Must be a valid number';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final double price = double.parse(priceController.text);
                  final String serviceName =
                      autocompleteController?.text.trim() ?? '';
                  viewModel.addCustomServiceToCart(serviceName, price);
                  Navigator.pop(context);
                }
              },
              child: const Text('Add to Cart'),
            ),
          ],
        );
      },
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
}

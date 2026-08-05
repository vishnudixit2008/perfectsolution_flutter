import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/app_theme.dart';
import '../../pricelist/view_models/pricelist_view_model.dart';
import '../view_models/recent_sales_view_model.dart';
import '../../../../data/models/sale.dart';
import '../../../../data/services/pdf_invoice_helper.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecentSalesViewModel>().loadSales();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RecentSalesViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        final sales = viewModel.sales;
        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isDesktop = screenWidth >= 800;

        // Calculations for KPI cards
        final double todaySalesSum = sales
            .where((s) => _isToday(s.saleDate))
            .fold(0.0, (sum, s) => sum + s.totalAmount);

        final int pendingCount = sales
            .where((s) => s.orderStatus == 'PENDING')
            .length;
        final int confirmedCount = sales
            .where((s) => s.orderStatus == 'Confirmed')
            .length;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dashboard Overview',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monitor daily sales, manage pending orders, and issue customer A5 receipts.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // KPI metrics row
              _buildKpiMetrics(
                context,
                todaySalesSum,
                pendingCount,
                confirmedCount,
                isDesktop,
              ),
              const SizedBox(height: 24),

              // Sales Ledger header
              const Text(
                'Recent Sales & Invoice Ledger',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // Invoice lists
              sales.isEmpty
                  ? _buildEmptyLedger(context)
                  : _buildSalesLedger(context, viewModel, sales, isDesktop),
            ],
          ),
        );
      },
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Widget _buildKpiMetrics(
    BuildContext context,
    double todaySum,
    int pending,
    int confirmed,
    bool isDesktop,
  ) {
    final list = [
      _KpiCard(
        title: 'TODAY\'S TOTAL REVENUE',
        value: '₹${todaySum.toStringAsFixed(2)}',
        icon: Icons.currency_rupee_rounded,
        color: AppTheme.primaryLight,
      ),
      _KpiCard(
        title: 'PENDING VERIFICATIONS',
        value: '$pending orders',
        icon: Icons.pending_actions_rounded,
        color: AppTheme.warning,
      ),
      _KpiCard(
        title: 'COMPLETED TRANSACTIONS',
        value: '$confirmed orders',
        icon: Icons.task_alt_rounded,
        color: AppTheme.success,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: list
            .map(
              (card) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: card,
                ),
              ),
            )
            .toList(),
      );
    } else {
      return Column(
        children: list
            .map(
              (card) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: card,
              ),
            )
            .toList(),
      );
    }
  }

  Widget _buildEmptyLedger(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: AppTheme.glassCardDecoration(
        color: Colors.white.withOpacity(0.01),
        borderRadius: 12,
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 48,
            color: AppTheme.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sales Ledger is Empty',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Invoices will appear here once orders are confirmed in the Billing Desk.',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSalesLedger(
    BuildContext context,
    RecentSalesViewModel viewModel,
    List<Sale> sales,
    bool isDesktop,
  ) {
    if (isDesktop) {
      return Container(
        decoration: AppTheme.glassCardDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: 8,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DataTable(
            horizontalMargin: 16,
            columnSpacing: 20,
            headingRowColor: WidgetStateProperty.all(
              Colors.white.withOpacity(0.04),
            ),
            columns: const [
              DataColumn(
                label: Text(
                  'Invoice #',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Date & Time',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Customer',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Payment',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Net Total',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Status',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Actions',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
            rows: sales.map((sale) {
              final formattedDate = DateFormat(
                'dd/MM/yy hh:mm a',
              ).format(sale.saleDate);

              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      '#${sale.invoiceNo}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataCell(Text(formattedDate)),
                  DataCell(Text(sale.customerName ?? 'Cash / Walk-in')),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        sale.paymentMode,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '₹${sale.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataCell(_buildStatusChip(sale.orderStatus)),
                  DataCell(
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.visibility_rounded,
                            color: AppTheme.primaryLight,
                            size: 18,
                          ),
                          onPressed: () => _showInvoiceDetailsSheet(
                            context,
                            viewModel,
                            sale,
                          ),
                          tooltip: 'View details',
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.print_rounded,
                            color: AppTheme.textSecondary,
                            size: 18,
                          ),
                          onPressed: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Opening invoice in PDF viewer...'),
                                backgroundColor: AppTheme.success,
                                duration: Duration(seconds: 2),
                              ),
                            );
                            final items = viewModel.getSaleItems(
                              sale.invoiceNo,
                            );
                            await PdfInvoiceHelper.printInvoice(
                              sale: sale,
                              items: items,
                              activeUpiId: viewModel.activeUpiId,
                            );
                          },
                          tooltip: 'Print invoice',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      );
    } else {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: sales.length,
        itemBuilder: (context, index) {
          final sale = sales[index];
          final formattedDate = DateFormat(
            'dd/MM/yy hh:mm a',
          ).format(sale.saleDate);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.glassCardDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: 10,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Invoice #${sale.invoiceNo}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    _buildStatusChip(sale.orderStatus),
                  ],
                ),
                const Divider(color: Colors.white10, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sale.customerName ?? 'Cash / Walk-in',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '₹${sale.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.primaryLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          _showInvoiceDetailsSheet(context, viewModel, sale),
                      icon: const Icon(Icons.visibility_rounded, size: 16),
                      label: const Text('View details'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Opening invoice in PDF viewer...'),
                            backgroundColor: AppTheme.success,
                            duration: Duration(seconds: 2),
                          ),
                        );
                        final items = viewModel.getSaleItems(sale.invoiceNo);
                        await PdfInvoiceHelper.printInvoice(
                          sale: sale,
                          items: items,
                          activeUpiId: viewModel.activeUpiId,
                        );
                      },
                      icon: const Icon(Icons.print_rounded, size: 16),
                      label: const Text('Print A5'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Widget _buildStatusChip(String status) {
    final bool isConfirmed = status == 'Confirmed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isConfirmed
            ? AppTheme.success.withOpacity(0.12)
            : AppTheme.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: isConfirmed ? AppTheme.success : AppTheme.warning,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // Show bottom details panel
  void _showInvoiceDetailsSheet(
    BuildContext context,
    RecentSalesViewModel viewModel,
    Sale sale,
  ) {
    final items = viewModel.getSaleItems(sale.invoiceNo);
    final isPending = sale.orderStatus == 'PENDING';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1524),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Invoice Details #${sale.invoiceNo}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
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
              const SizedBox(height: 16),

              // Metadata grid
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sale.customerName ?? 'Cash / Walk-in',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (sale.customerNumber != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          sale.customerNumber!,
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
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd/MM/yy hh:mm a').format(sale.saleDate),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Payment: ${sale.paymentMode}',
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

              const Divider(color: Colors.white10, height: 32),

              // Items table
              const Text(
                'INVOICE ITEMS',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
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
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
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
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Financial Totals block
              const Divider(color: Colors.white10, height: 24),
              if (sale.discount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Discount Applied',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '- ₹${sale.discount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              if (sale.advance > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Advance reference',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '₹${sale.advance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Net Paid Total',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '₹${sale.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
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
                          activeUpiId: viewModel.activeUpiId,
                        );
                      },
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('Print A5 Receipt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.04),
                        foregroundColor: AppTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  if (isPending) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final success = await viewModel.confirmOrder(
                            sale.invoiceNo,
                          );
                          if (success) {
                            // Reload pricelist to reflect inventory subtraction
                            if (context.mounted) {
                              context.read<PricelistViewModel>().loadItems();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Order #${sale.invoiceNo} verified. Stock deducted.',
                                  ),
                                  backgroundColor: AppTheme.success,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Verify & Deduct'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCardDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
        ],
      ),
    );
  }
}

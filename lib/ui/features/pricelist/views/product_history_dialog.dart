import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../data/models/pricelist_item.dart';
import '../../../../data/models/product_history_record.dart';
import '../../../../data/models/sale.dart';
import '../../../../data/models/sale_item.dart';
import '../../../../data/models/purchase_order.dart';
import '../../../../data/models/purchase_order_item.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/pdf_invoice_helper.dart';
import '../../../core/app_theme.dart';
import '../../../shared/components/app_stock_badge.dart';
import '../../../shared/components/app_status_chip.dart';

class ProductHistoryDialog extends StatefulWidget {
  final PricelistItem product;

  const ProductHistoryDialog({
    super.key,
    required this.product,
  });

  static Future<void> show(BuildContext context, PricelistItem product) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => ProductHistoryDialog(product: product),
    );
  }

  @override
  State<ProductHistoryDialog> createState() => _ProductHistoryDialogState();
}

class _ProductHistoryDialogState extends State<ProductHistoryDialog> {
  late List<ProductHistoryRecord> _allHistory;
  String _activeFilter = 'ALL'; // 'ALL', 'SALES', 'PURCHASES'
  final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    final repo = context.read<ShopRepository>();
    _allHistory = repo.getProductHistory(widget.product);
  }

  List<ProductHistoryRecord> get _filteredHistory {
    if (_activeFilter == 'SALES') {
      return _allHistory.where((r) => r.isSale).toList();
    } else if (_activeFilter == 'PURCHASES') {
      return _allHistory.where((r) => r.isPurchase).toList();
    }
    return _allHistory;
  }

  // Summary Metrics
  int get _totalSoldUnits =>
      _allHistory.where((r) => r.isSale).fold(0, (sum, r) => sum + r.quantity);

  double get _totalSalesRevenue => _allHistory
      .where((r) => r.isSale)
      .fold(0.0, (sum, r) => sum + r.totalAmount);

  int get _totalPurchasedUnits => _allHistory
      .where((r) => r.isPurchase)
      .fold(0, (sum, r) => sum + r.quantity);

  double get _totalPurchaseExpense => _allHistory
      .where((r) => r.isPurchase)
      .fold(0.0, (sum, r) => sum + r.totalAmount);

  // Group records by Month Year (e.g. "August 2026")
  Map<String, List<ProductHistoryRecord>> get _groupedHistory {
    final map = <String, List<ProductHistoryRecord>>{};
    for (final record in _filteredHistory) {
      final monthKey = DateFormat('MMMM yyyy').format(record.date);
      map.putIfAbsent(monthKey, () => []).add(record);
    }
    return map;
  }

  void _onRecordTap(ProductHistoryRecord record) {
    if (record.isSale && record.sale != null) {
      _showSaleDetailsModal(context, record.sale!, record.saleItems ?? []);
    } else if (record.isPurchase && record.purchase != null) {
      _showPurchaseDetailsModal(
          context, record.purchase!, record.purchaseItems ?? []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 750;
    final grouped = _groupedHistory;

    return Dialog(
      backgroundColor: const Color(0xFF0F1524),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      child: Container(
        width: isDesktop ? 820 : screenWidth * 0.92,
        height: MediaQuery.of(context).size.height * 0.88,
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 800),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header Bar ────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.history_edu_rounded,
                          color: AppTheme.primaryLight,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.product.itemName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AppStockBadge(stockQty: widget.product.stockQty),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Product Transaction Ledger & Month-wise History',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 16),

            // ── Summary Cards Header ────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Total Sales',
                    value: '$_totalSoldUnits units',
                    subtitle: currencyFormat.format(_totalSalesRevenue),
                    icon: Icons.north_east_rounded,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Total Purchases',
                    value: '$_totalPurchasedUnits units',
                    subtitle: currencyFormat.format(_totalPurchaseExpense),
                    icon: Icons.south_west_rounded,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Current Price',
                    value: currencyFormat.format(widget.product.price),
                    subtitle: 'Category: ${widget.product.category ?? "General"}',
                    icon: Icons.inventory_2_outlined,
                    color: AppTheme.secondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Filter Chips ────────────────────────────────────────────────
            Row(
              children: [
                _buildFilterChip('ALL', 'All Activity (${_allHistory.length})'),
                const SizedBox(width: 8),
                _buildFilterChip('SALES', 'Sales (${_allHistory.where((r) => r.isSale).length})'),
                const SizedBox(width: 8),
                _buildFilterChip('PURCHASES', 'Purchases (${_allHistory.where((r) => r.isPurchase).length})'),
              ],
            ),

            const SizedBox(height: 14),

            // ── History List ────────────────────────────────────────────────
            Expanded(
              child: grouped.isEmpty
                  ? _buildEmptyHistoryState()
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: grouped.keys.length,
                      itemBuilder: (context, index) {
                        final monthKey = grouped.keys.elementAt(index);
                        final records = grouped[monthKey]!;
                        return _buildMonthGroup(monthKey, records);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final bool isSelected = _activeFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _activeFilter = key),
      selectedColor: AppTheme.primary.withOpacity(0.2),
      backgroundColor: Colors.white.withOpacity(0.04),
      side: BorderSide(
        color: isSelected ? AppTheme.primaryLight : Colors.white10,
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? AppTheme.primaryLight : AppTheme.textSecondary,
      ),
    );
  }

  Widget _buildMonthGroup(String monthKey, List<ProductHistoryRecord> records) {
    final int monthSold = records
        .where((r) => r.isSale)
        .fold(0, (sum, r) => sum + r.quantity);
    final double monthSalesRevenue = records
        .where((r) => r.isSale)
        .fold(0.0, (sum, r) => sum + r.totalAmount);

    final int monthPurchased = records
        .where((r) => r.isPurchase)
        .fold(0, (sum, r) => sum + r.quantity);
    final double monthPurchaseCost = records
        .where((r) => r.isPurchase)
        .fold(0.0, (sum, r) => sum + r.totalAmount);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161D2F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      size: 16,
                      color: AppTheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      monthKey,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Sales: $monthSold (${currencyFormat.format(monthSalesRevenue)})  •  Purchases: $monthPurchased (${currencyFormat.format(monthPurchaseCost)})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),

          // Records List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: records.length,
            separatorBuilder: (ctx, idx) =>
                Divider(color: Colors.white.withOpacity(0.04), height: 1),
            itemBuilder: (context, i) {
              final record = records[i];
              return _buildRecordTile(record);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(ProductHistoryRecord record) {
    final formattedTime = DateFormat('dd MMM yyyy, hh:mm a').format(record.date);
    final isSale = record.isSale;
    final themeColor = isSale ? AppTheme.success : Colors.blueAccent;

    return InkWell(
      onTap: () => _onRecordTap(record),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Badge icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isSale ? Icons.north_east_rounded : Icons.south_west_rounded,
                color: themeColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),

            // Party and Ref No
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: themeColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isSale ? 'SALE' : 'PURCHASE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        record.referenceNo,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isSale ? "Customer" : "Vendor"}: ${record.partyName}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    formattedTime,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            // Qty & Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${record.quantity} pcs @ ${currencyFormat.format(record.unitPrice)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  currencyFormat.format(record.totalAmount),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),

            // Closing Stock Column
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryLight.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Closing Stock',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${record.closingStock ?? 0} units',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryLight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Chevron
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHistoryState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 54,
            color: AppTheme.textMuted.withOpacity(0.4),
          ),
          const SizedBox(height: 12),
          const Text(
            'No History Found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No sales or purchase transactions recorded for this product yet.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  // ── Sale Detail Modal ─────────────────────────────────────────────────────
  void _showSaleDetailsModal(
      BuildContext context, Sale sale, List<SaleItem> items) {
    final formattedDate = DateFormat('dd/MM/yy hh:mm a').format(sale.saleDate);

    showDialog(
      context: context,
      builder: (context) {
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
                        const SizedBox(width: 12),
                        AppStatusChip(
                          status: sale.orderStatus,
                          moduleKey: 'sales',
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

                // Details Row
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
                          formattedDate,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Payment Mode: ${sale.paymentMode}',
                          style: const TextStyle(
                            color: AppTheme.primaryLight,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Text(
                  'INVOICE ITEMS',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),

                // Table of items
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: items.length,
                      separatorBuilder: (ctx, idx) => Divider(
                          color: Colors.white.withOpacity(0.04), height: 1),
                      itemBuilder: (context, i) {
                        final item = items[i];
                        final desc = item.itemDescription ??
                            item.serviceName ??
                            'Line Item';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      desc,
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      'Qty: ${item.quantity} × ₹${item.activePrice.toStringAsFixed(2)}',
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
                ),

                const SizedBox(height: 16),

                // Total and Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'GRAND TOTAL',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          currencyFormat.format(sale.totalAmount),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
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
                          activeUpiId: null,
                        );
                      },
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Print Receipt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
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

  // ── Purchase Detail Modal ─────────────────────────────────────────────────
  void _showPurchaseDetailsModal(
      BuildContext context, PurchaseOrder purchase, List<PurchaseOrderItem> items) {
    final formattedDate =
        DateFormat('dd MMM yyyy, hh:mm a').format(purchase.date);

    showDialog(
      context: context,
      builder: (context) {
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
                          Icons.shopping_bag_rounded,
                          color: Colors.blueAccent,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Purchase #${purchase.id}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        AppStatusChip(
                          status: purchase.status,
                          moduleKey: 'purchases',
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

                // Details Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PURCHASED FROM (VENDOR)',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          purchase.purchasedFrom.isNotEmpty
                              ? purchase.purchasedFrom
                              : 'Supplier / Vendor',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'DATE LOGGED',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Text(
                  'PURCHASED ITEMS',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),

                // Items list
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: items.length,
                      separatorBuilder: (ctx, idx) => Divider(
                          color: Colors.white.withOpacity(0.04), height: 1),
                      itemBuilder: (context, i) {
                        final item = items[i];
                        final name =
                            item.itemName ?? item.customItemName ?? 'Product Item';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      'Qty: ${item.quantity} × ₹${item.unitPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '₹${item.amount.toStringAsFixed(2)}',
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
                ),

                const SizedBox(height: 16),

                // Total Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL PURCHASE AMOUNT',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      currencyFormat.format(purchase.totalAmount),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
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
}

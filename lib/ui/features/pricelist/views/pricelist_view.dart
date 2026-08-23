import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shop_management_flutter/ui/core/app_theme.dart';
import 'package:shop_management_flutter/ui/core/motion/motion.dart';
import 'package:shop_management_flutter/data/models/pricelist_item.dart';
import 'package:shop_management_flutter/ui/features/pricelist/view_models/pricelist_view_model.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../../../shared/components/app_page_header.dart';
import '../../../shared/components/app_list_card.dart';
import '../../../shared/components/app_stock_badge.dart';
import '../../../shared/components/app_floating_action_button.dart';
import '../../../shared/components/app_header_sync_button.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_search_filter_bar.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/supabase_sync_service.dart';
import '../../../../data/services/user_permission_service.dart';
import '../../../../data/services/ui_preferences_service.dart';
import 'product_history_dialog.dart';

import '../../../../data/services/pdf_stock_list_helper.dart';

class PricelistView extends StatefulWidget {
  const PricelistView({super.key});

  @override
  State<PricelistView> createState() => _PricelistViewState();
}

class _PricelistViewState extends State<PricelistView> {
  final TextEditingController _searchController = TextEditingController();
  double _nameColumnWidth = 350.0;
  double _priceColumnWidth = 150.0;
  double _stockColumnWidth = 150.0;
  bool _isSelectionMode = false;
  final Set<int> _selectedItemIds = {};

  void _loadSavedColumnWidths() {
    _nameColumnWidth =
        UiPreferencesService.getColumnWidth('pricelist', 'name') ?? 350.0;
    _priceColumnWidth =
        UiPreferencesService.getColumnWidth('pricelist', 'price') ?? 150.0;
    _stockColumnWidth =
        UiPreferencesService.getColumnWidth('pricelist', 'stock') ?? 150.0;
  }

  void _updateColumnWidth(String columnKey, double newWidth) {
    setState(() {
      switch (columnKey) {
        case 'name':
          _nameColumnWidth = newWidth;
          break;
        case 'price':
          _priceColumnWidth = newWidth;
          break;
        case 'stock':
          _stockColumnWidth = newWidth;
          break;
      }
    });
    UiPreferencesService.setColumnWidth('pricelist', columnKey, newWidth);
  }

  @override
  void initState() {
    super.initState();
    _loadSavedColumnWidths();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PricelistViewModel>().loadItems();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PricelistViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading && viewModel.items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ShimmerSkeleton.card(height: 72),
                const SizedBox(height: 10),
                ShimmerSkeleton.card(height: 72),
                const SizedBox(height: 10),
                ShimmerSkeleton.card(height: 72),
                const SizedBox(height: 10),
                ShimmerSkeleton.card(height: 72),
              ],
            ),
          );
        }

        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isDesktop = screenWidth >= 750;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: (!isDesktop && UserPermissionService.canPerformModuleAction('pricelist', 'canAdd'))
              ? AppFloatingActionButton(
                  onPressed: () => _showAddEditItemDialog(context, viewModel),
                  tooltip: 'Add Product',
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: 'Pricelist',
                subtitle: 'Product Catalog & Inventory',
                actions: [
                  if (UserPermissionService.canPerformModuleAction('pricelist', 'canDownloadStockPdf'))
                    AppHeaderActionButton(
                      label: isDesktop ? 'Export Stock PDF' : 'Stock PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      isOutlined: true,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      foregroundColor: AppTheme.textPrimary,
                      borderColor: Colors.white.withValues(alpha: 0.12),
                      onPressed: () async {
                        final items = viewModel.filteredItems.isNotEmpty
                            ? viewModel.filteredItems
                            : viewModel.items;
                        if (items.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No stock items to export.')),
                          );
                          return;
                        }
                        await PdfStockListHelper.generateAndOpenStockListPdf(items);
                      },
                    ),
                  if (isDesktop && UserPermissionService.canPerformModuleAction('pricelist', 'canAdd'))
                    AppHeaderActionButton(
                      label: 'Add Item',
                      icon: Icons.add_rounded,
                      onPressed: () => _showAddEditItemDialog(context, viewModel),
                    ),
                  if (!isDesktop)
                    AppHeaderSyncButton(
                      onSynced: () => context.read<PricelistViewModel>().loadItems(),
                    ),
                ],
              ),

              // Search and Filters Bar
              _buildFiltersBar(context, viewModel, isDesktop),
              const SizedBox(height: 12),

              // Catalog Table / Card list
              Expanded(
                child: viewModel.filteredItems.isEmpty
                    ? _buildEmptyState(context, viewModel)
                    : (isDesktop
                        ? _buildDesktopGrid(context, viewModel)
                        : _buildMobileCardsList(context, viewModel)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFiltersBar(
    BuildContext context,
    PricelistViewModel viewModel,
    bool isDesktop,
  ) {
    final String currentCategory =
        viewModel.selectedCategory ?? 'All Categories';
    final bool hasCategoryFilter = viewModel.selectedCategory != null;

    Widget searchField = AppAnimatedSearchBar(
      controller: _searchController,
      onChanged: viewModel.setSearchQuery,
      onClear: () => viewModel.setSearchQuery(''),
      hintText: 'Search by product name, description, or category...',
    );

    Widget categoryFilterButton = BouncyPressable(
      scaleFactor: 0.98,
      onTap: () => _showSearchableCategoryDialog(context, viewModel),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: hasCategoryFilter
              ? AppTheme.primary.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: hasCategoryFilter
                ? AppTheme.primaryLight.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
          boxShadow: hasCategoryFilter
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.category_outlined,
              size: 16,
              color: hasCategoryFilter
                  ? AppTheme.primaryLight
                  : AppTheme.textMuted.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                currentCategory,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hasCategoryFilter ? FontWeight.w600 : FontWeight.w400,
                  color: hasCategoryFilter
                      ? AppTheme.primaryLight
                      : AppTheme.textPrimary,
                  letterSpacing: -0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasCategoryFilter) ...[
              BouncyPressable(
                scaleFactor: 0.88,
                onTap: () => viewModel.setSelectedCategory(null),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.cancel_rounded,
                    size: 15,
                    color: AppTheme.primaryLight.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: hasCategoryFilter
                  ? AppTheme.primaryLight
                  : AppTheme.textMuted.withValues(alpha: 0.8),
              size: 18,
            ),
          ],
        ),
      ),
    );

    if (isDesktop) {
      return Row(
        children: [
          Expanded(flex: 3, child: searchField),
          const SizedBox(width: 12),
          Expanded(flex: 1, child: categoryFilterButton),
        ],
      );
    } else {
      return AppSearchFilterBar(
        searchQuery: _searchController.text,
        onSearchChanged: (q) {
          _searchController.text = q;
          viewModel.setSearchQuery(q);
        },
        hintText: 'Search products, description, category...',
        activeFilterCount: viewModel.selectedCategory != null ? 1 : 0,
        filterOptions: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Category',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 6),
                  categoryFilterButton,
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  void _showSearchableCategoryDialog(
    BuildContext context,
    PricelistViewModel viewModel,
  ) {
    showAppModalDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final List<String> allCats = viewModel.categories;
            final String currentCategory =
                viewModel.selectedCategory ?? 'All Categories';

            final filteredCats = allCats.where((c) {
              if (searchQuery.trim().isEmpty) return true;
              return c.toLowerCase().contains(searchQuery.trim().toLowerCase());
            }).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF131A2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Row(
                children: [
                  const Icon(
                    Icons.category_outlined,
                    color: AppTheme.primaryLight,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Select Category',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppTheme.textMuted,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                height: 440,
                child: Column(
                  children: [
                    AppAnimatedSearchBar(
                      hintText: 'Search category name...',
                      onChanged: (q) {
                        setDialogState(() {
                          searchQuery = q;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children: [
                          if (searchQuery.trim().isEmpty ||
                              'all categories'.contains(searchQuery.trim().toLowerCase()))
                            _buildCategoryDialogTile(
                              title: 'All Categories',
                              isSelected: currentCategory == 'All Categories',
                              itemCount: viewModel.items.length,
                              onTap: () {
                                viewModel.setSelectedCategory(null);
                                Navigator.pop(context);
                              },
                            ),
                          ...filteredCats.map((cat) {
                            final int count = viewModel.items
                                .where((it) => it.category?.trim().toLowerCase() == cat.trim().toLowerCase())
                                .length;
                            return _buildCategoryDialogTile(
                              title: cat,
                              isSelected: currentCategory == cat,
                              itemCount: count,
                              onTap: () {
                                viewModel.setSelectedCategory(cat);
                                Navigator.pop(context);
                              },
                            );
                          }),
                          if (filteredCats.isEmpty &&
                              !('all categories'.contains(searchQuery.trim().toLowerCase())))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Text(
                                  'No categories found matching "$searchQuery"',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryDialogTile({
    required String title,
    required bool isSelected,
    required int itemCount,
    required VoidCallback onTap,
  }) {
    return BouncyPressable(
      scaleFactor: 0.98,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryLight.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected
                      ? AppTheme.primaryLight
                      : AppTheme.textPrimary,
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryLight.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$itemCount items',
                style: TextStyle(
                  color: isSelected
                      ? AppTheme.primaryLight
                      : AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_rounded,
                color: AppTheme.primaryLight,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, PricelistViewModel viewModel) {
    final canAdd = UserPermissionService.canPerformModuleAction('pricelist', 'canAdd');
    return AppEmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'No Products Found',
      message: 'No catalog items match your search or filter criteria.',
      actionLabel: canAdd ? 'Add Product' : null,
      onAction: canAdd ? () => _showAddEditItemDialog(context, viewModel) : null,
    );
  }

  Widget _buildResizeGrip(ValueChanged<double> onResize) {
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

  Widget _buildResizableHeader(
    PricelistViewModel viewModel,
    String label,
    String column,
    double currentWidth,
    ValueChanged<double> onResize,
  ) {
    final bool isSorted = viewModel.sortColumn == column;
    return Container(
      width: currentWidth,
      padding: const EdgeInsets.only(left: 16, right: 2, top: 12, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => viewModel.toggleSort(column),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSorted
                          ? AppTheme.primaryLight
                          : AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (isSorted) ...[
                    const SizedBox(width: 4),
                    Icon(
                      viewModel.sortAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 14,
                      color: AppTheme.primaryLight,
                    ),
                  ],
                ],
              ),
            ),
          ),
          _buildResizeGrip(onResize),
        ],
      ),
    );
  }

  Widget _buildItemRow(
    BuildContext context,
    PricelistViewModel viewModel,
    PricelistItem item,
  ) {
    final bool isSelected = _selectedItemIds.contains(item.id);
    return InkWell(
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedItemIds.remove(item.id);
            } else {
              _selectedItemIds.add(item.id);
            }
          });
        } else {
          _showDetailPopup(context, item, viewModel);
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
                        _selectedItemIds.add(item.id);
                      } else {
                        _selectedItemIds.remove(item.id);
                      }
                    });
                  },
                ),
              ),
            // Product Name cell
            if (UserPermissionService.isFieldVisible('pricelist', 'itemName'))
              Container(
                width: _nameColumnWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                alignment: Alignment.centerLeft,
                child: Text(
                  item.itemName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // Cash Price cell
            if (UserPermissionService.isFieldVisible('pricelist', 'price'))
              Container(
                width: _priceColumnWidth,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                alignment: Alignment.centerLeft,
                child: Text(
                  '₹${item.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
            // Stock Qty cell (expanded to fill remaining space)
            if (UserPermissionService.isFieldVisible('pricelist', 'stockQty'))
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${item.stockQty} units',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppTheme.primaryLight,
                      ),
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

  Widget _buildCategorySectionHeader(String category, [int totalQty = 0]) {
    const Color color = AppTheme.primaryLight;
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
            color: AppTheme.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.38),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: color,
                  shadows: [
                    Shadow(color: color, offset: Offset(0.12, 0)),
                    Shadow(color: color, offset: Offset(-0.12, 0)),
                  ],
                ),
              ),
              if (totalQty > 0) ...[
                const SizedBox(width: 7),
                const Text(
                  '·',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '$totalQty ${totalQty == 1 ? 'unit' : 'units'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                    shadows: [
                      Shadow(color: color, offset: Offset(0.12, 0)),
                      Shadow(color: color, offset: Offset(-0.12, 0)),
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

  Widget _buildDesktopGrid(BuildContext context, PricelistViewModel viewModel) {
    final items = viewModel.pagedItems;

    // Group items by category
    final Map<String, List<PricelistItem>> groupedItems = {};
    for (var item in items) {
      final String cat =
          (item.category == null || item.category!.trim().isEmpty)
          ? 'General'
          : item.category!.trim();
      if (!groupedItems.containsKey(cat)) {
        groupedItems[cat] = [];
      }
      groupedItems[cat]!.add(item);
    }

    final listEntries = <_PricelistListItem>[];
    groupedItems.forEach((category, categoryItems) {
      final int totalQty =
          categoryItems.fold(0, (sum, item) => sum + item.stockQty);
      listEntries.add(_PricelistListItem.header(category, totalQty));
      for (var item in categoryItems) {
        listEntries.add(_PricelistListItem.item(item));
      }
    });

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
                          items.isNotEmpty &&
                          items.every(
                            (item) => _selectedItemIds.contains(item.id),
                          ),
                      activeColor: AppTheme.primary,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedItemIds.addAll(
                              items.map((item) => item.id),
                            );
                          } else {
                            _selectedItemIds.removeAll(
                              items.map((item) => item.id),
                            );
                          }
                        });
                      },
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('pricelist', 'itemName'))
                  _buildResizableHeader(
                    viewModel,
                    'Product Name',
                    'itemName',
                    _nameColumnWidth,
                    (delta) => _updateColumnWidth(
                      'name',
                      (_nameColumnWidth + delta).clamp(150.0, 800.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('pricelist', 'price'))
                  _buildResizableHeader(
                    viewModel,
                    'Cash Price',
                    'price',
                    _priceColumnWidth,
                    (delta) => _updateColumnWidth(
                      'price',
                      (_priceColumnWidth + delta).clamp(100.0, 400.0),
                    ),
                  ),
                if (UserPermissionService.isFieldVisible('pricelist', 'stockQty'))
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.only(left: 16),
                      alignment: Alignment.centerLeft,
                      child: _buildResizableHeader(
                        viewModel,
                        'Stock Qty',
                        'stockQty',
                        _stockColumnWidth,
                        (delta) => _updateColumnWidth(
                          'stock',
                          (_stockColumnWidth + delta).clamp(100.0, 400.0),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Scrollable Body Rows (Virtualized ListView.builder)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: listEntries.length,
              itemBuilder: (context, index) {
                final entry = listEntries[index];
                if (entry.categoryHeader != null) {
                  return _buildCategorySectionHeader(
                    entry.categoryHeader!,
                    entry.categoryCount ?? 0,
                  );
                }
                return _buildItemRow(context, viewModel, entry.item!);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  void _bulkDeleteItems(BuildContext context, PricelistViewModel viewModel) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Bulk Delete'),
          content: Text(
            'Are you sure you want to delete the ${_selectedItemIds.length} selected items?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final List<int> idsToDelete = _selectedItemIds.toList();

                // Show loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                );

                try {
                  for (final id in idsToDelete) {
                    await viewModel.deleteItem(id);
                  }
                  setState(() {
                    _selectedItemIds.clear();
                    _isSelectionMode = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Successfully deleted ${idsToDelete.length} items.',
                      ),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting items: $e'),
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

  // ignore: unused_element
  Widget _buildSortHeader(
    PricelistViewModel viewModel,
    String label,
    String column,
  ) {
    final bool isSorted = viewModel.sortColumn == column;
    return InkWell(
      onTap: () => viewModel.toggleSort(column),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSorted ? AppTheme.primaryLight : AppTheme.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (isSorted) ...[
            const SizedBox(width: 4),
            Icon(
              viewModel.sortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 14,
              color: AppTheme.primaryLight,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileCardsList(
    BuildContext context,
    PricelistViewModel viewModel,
  ) {
    final items = viewModel.pagedItems;
    final Map<String, List<PricelistItem>> categoryGroups = {};
    for (final item in items) {
      final cat = (item.category != null && item.category!.trim().isNotEmpty)
          ? item.category!.trim()
          : 'General';
      categoryGroups.putIfAbsent(cat, () => []).add(item);
    }

    final listEntries = <_PricelistListItem>[];
    categoryGroups.forEach((category, categoryItems) {
      final int totalQty =
          categoryItems.fold(0, (sum, item) => sum + item.stockQty);
      listEntries.add(_PricelistListItem.header(category, totalQty));
      for (final item in categoryItems) {
        listEntries.add(_PricelistListItem.item(item));
      }
    });

    return RefreshIndicator(
      color: AppTheme.primaryLight,
      backgroundColor: const Color(0xFF131A2E),
      onRefresh: () async {
        final localDb = context.read<ShopRepository>().localDb;
        await SupabaseSyncService.instance.syncAllTablesFromCloud(localDb);
        if (context.mounted) viewModel.loadItems();
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: listEntries.length,
        itemBuilder: (context, index) {
          final entry = listEntries[index];
          if (entry.categoryHeader != null) {
            return _buildCategorySectionHeader(
              entry.categoryHeader!,
              entry.categoryCount ?? 0,
            );
          }
          return _buildMobileCardItem(context, viewModel, entry.item!, itemIndex: index);
        },
      ),
    );
  }

  Widget _buildMobileCardItem(
    BuildContext context,
    PricelistViewModel viewModel,
    PricelistItem item, {
    int itemIndex = 0,
  }) {
    final bool isSelected = _selectedItemIds.contains(item.id);
    final metadata = <Widget>[];

    metadata.add(
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '₹${item.price.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryLight,
            ),
          ),
          AppStockBadge(stockQty: item.stockQty),
        ],
      ),
    );

    if (item.itemDescription != null &&
        item.itemDescription!.trim().isNotEmpty) {
      metadata.add(const SizedBox(height: 6));
      metadata.add(
        Text(
          item.itemDescription!,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (item.photoList.isNotEmpty) {
      metadata.add(const SizedBox(height: 6));
      metadata.add(PhotoGallerySection(photoUrls: item.photoList));
    }

    return AppListCard(
      index: itemIndex,
      title: item.itemName,
      metadataRows: metadata,
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedItemIds.remove(item.id);
            } else {
              _selectedItemIds.add(item.id);
            }
          });
        } else {
          _showDetailPopup(context, item, viewModel);
        }
      },
      onEdit: UserPermissionService.canPerformModuleAction('pricelist', 'canEdit')
          ? () => _showAddEditItemDialog(
              context,
              viewModel,
              existingItem: item,
            )
          : null,
      onDelete: UserPermissionService.canPerformModuleAction('pricelist', 'canDelete')
          ? () => _confirmDeleteItem(context, viewModel, item)
          : null,
    );
  }


  void _showDetailPopup(
    BuildContext context,
    PricelistItem item,
    PricelistViewModel viewModel,
  ) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    showDialog(
      context: context,
      builder: (context) {
        final double screenWidth = MediaQuery.of(context).size.width;
        final double screenHeight = MediaQuery.of(context).size.height;
        final bool isMobile = screenWidth < 600;

        return Dialog(
          backgroundColor: const Color(0xFF0F1524),
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 24,
            vertical: isMobile ? 16 : 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          child: Container(
            width: isMobile ? screenWidth * 0.95 : screenWidth * 0.85,
            height: isMobile ? screenHeight * 0.85 : screenHeight * 0.8,
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
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
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.inventory_2_rounded,
                            color: AppTheme.primaryLight,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Product Details',
                          style: TextStyle(
                            fontSize: 18,
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
                const SizedBox(height: 16),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 16),

                // Main Info Body
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title & Category
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.itemName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  if (item.category != null &&
                                      item.category!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        item.category!,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryLight,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            AppStockBadge(stockQty: item.stockQty),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Price & Stock Row
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'SELLING PRICE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textMuted,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    currencyFormat.format(item.price),
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.success,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'AVAILABLE STOCK',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textMuted,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${item.stockQty} units',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        if (item.itemDescription != null &&
                            item.itemDescription!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'DESCRIPTION / SPECIFICATIONS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withOpacity(0.04)),
                            ),
                            child: Text(
                              item.itemDescription!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],

                        if (item.photoList.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'ATTACHED PHOTOS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          PhotoGallerySection(photoUrls: item.photoList),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 16),

                // Action Buttons Footer
                Builder(
                  builder: (context) {
                    final canViewHistory = UserPermissionService.canPerformModuleAction('pricelist', 'canViewHistory');
                    final canEdit = UserPermissionService.canPerformModuleAction('pricelist', 'canEdit');
                    final canDelete = UserPermissionService.canPerformModuleAction('pricelist', 'canDelete');

                    return Column(
                      children: [
                        if (canViewHistory) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                ProductHistoryDialog.show(context, item);
                              },
                              icon: const Icon(Icons.history_edu_rounded, size: 18),
                              label: const Text('View Sales & Purchase History'),
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
                        if (canEdit || canDelete)
                          Row(
                            children: [
                              if (canEdit)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _showAddEditItemDialog(
                                        context,
                                        viewModel,
                                        existingItem: item,
                                      );
                                    },
                                    icon: const Icon(Icons.edit_rounded, size: 18),
                                    label: const Text('Edit Product'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      side: const BorderSide(color: AppTheme.primaryLight),
                                      foregroundColor: AppTheme.primaryLight,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              if (canEdit && canDelete) const SizedBox(width: 12),
                              if (canDelete)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _confirmDeleteItem(context, viewModel, item);
                                    },
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                    label: const Text('Delete Product'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      side: const BorderSide(color: AppTheme.danger),
                                      foregroundColor: AppTheme.danger,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteItem(
    BuildContext context,
    PricelistViewModel viewModel,
    PricelistItem item,
  ) {
    if (!UserPermissionService.canPerformModuleAction('pricelist', 'canDelete')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access Denied: You do not have permission to delete Catalog Items.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
              const SizedBox(width: 12),
              const Text('Delete Product?'),
            ],
          ),
          content: Text(
            'Are you sure you want to permanently delete "${item.itemName}"? This action cannot be undone.',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                viewModel.deleteItem(item.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('"${item.itemName}" deleted successfully.'),
                    backgroundColor: AppTheme.success,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showAddEditItemDialog(
    BuildContext context,
    PricelistViewModel viewModel, {
    PricelistItem? existingItem,
  }) {
    final isEdit = existingItem != null;
    final actionKey = isEdit ? 'canEdit' : 'canAdd';
    if (!UserPermissionService.canPerformModuleAction('pricelist', actionKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEdit
                ? 'Access Denied: You do not have permission to edit Catalog Items.'
                : 'Access Denied: You do not have permission to add new Catalog Items.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    final canDelete = UserPermissionService.canPerformModuleAction('pricelist', 'canDelete');
    showAddEditPricelistItemDialog(
      context,
      viewModel,
      existingItem: existingItem,
      onDeleteRequested: existingItem != null && canDelete
          ? () => _confirmDeleteItem(context, viewModel, existingItem)
          : null,
    );
  }
}

Future<PricelistItem?> showAddEditPricelistItemDialog(
  BuildContext context,
  PricelistViewModel viewModel, {
  PricelistItem? existingItem,
  String? initialName,
  VoidCallback? onDeleteRequested,
}) async {
  final bool isEdit = existingItem != null;
  final int itemId = isEdit ? existingItem.id : viewModel.getNextId();

  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(
    text: existingItem?.itemName ?? initialName ?? '',
  );
  final descController = TextEditingController(
    text: existingItem?.itemDescription ?? '',
  );
  // Category is now a searchable dropdown — store selected value as state
  String? selectedCategory = existingItem?.category?.trim().isEmpty == false
      ? existingItem!.category!.trim()
      : null;
  final priceController = TextEditingController(
    text: existingItem?.price.toString() ?? '',
  );
  final stockController = TextEditingController(
    text: existingItem?.stockQty.toString() ?? '0',
  );
  String? photoUrl = existingItem?.photo;
  bool isPhotoUploading = false;

  return showAppModalDialog<PricelistItem>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final bool isMobile = MediaQuery.of(context).size.width < 700;

      return StatefulBuilder(
        builder: (context, setDialogState) {
          void saveItem() {
            if (formKey.currentState!.validate()) {
              // Guard: wait for photo upload to complete before saving
              if (isPhotoUploading) {
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

              final item = PricelistItem(
                id: itemId,
                itemName: nameController.text.trim(),
                category: (selectedCategory == null || selectedCategory!.trim().isEmpty)
                    ? 'General'
                    : selectedCategory!.trim(),
                price: double.tryParse(priceController.text) ?? 0.0,
                stockQty: int.tryParse(stockController.text) ?? 0,
                openingStock: existingItem?.openingStock ?? 0,
                itemDescription: descController.text.trim().isEmpty
                    ? null
                    : descController.text.trim(),
                photo: photoUrl,
              );

              if (isEdit) {
                viewModel.updateItem(item);
              } else {
                viewModel.addItem(item);
              }

              Navigator.pop(context, item);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isEdit
                        ? '"${item.itemName}" updated successfully.'
                        : '"${item.itemName}" added to catalog.',
                  ),
                  backgroundColor: AppTheme.success,
                ),
              );
            }
          }

          final bool isItemVis = UserPermissionService.isFieldVisible('pricelist', 'itemName');
          final bool isItemMod = UserPermissionService.canModifyField('pricelist', 'itemName', isEdit: isEdit);

          final bool isCatVis = UserPermissionService.isFieldVisible('pricelist', 'category');
          final bool isCatMod = UserPermissionService.canModifyField('pricelist', 'category', isEdit: isEdit);

          final bool isPriceVis = UserPermissionService.isFieldVisible('pricelist', 'price');
          final bool isPriceMod = UserPermissionService.canModifyField('pricelist', 'price', isEdit: isEdit);

          final bool isStockQtyVis = UserPermissionService.isFieldVisible('pricelist', 'stockQty');
          final bool isStockQtyMod = UserPermissionService.canModifyField('pricelist', 'stockQty', isEdit: isEdit);

          final bool isDescVis = UserPermissionService.isFieldVisible('pricelist', 'itemDescription');
          final bool isDescMod = UserPermissionService.canModifyField('pricelist', 'itemDescription', isEdit: isEdit);

          final bool isPhotoVis = UserPermissionService.isFieldVisible('pricelist', 'photo');
          final bool isPhotoMod = UserPermissionService.canModifyField('pricelist', 'photo', isEdit: isEdit);

          final Widget formContent = Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isItemVis) ...[
                  TextFormField(
                    controller: nameController,
                    readOnly: !isItemMod,
                    enabled: isItemMod,
                    decoration: const InputDecoration(
                      labelText: 'Product Name *',
                      hintText: 'e.g. MOUSE WIRELESS IVOOMI',
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter product name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                if (isCatVis) ...[
                  AbsorbPointer(
                    absorbing: !isCatMod,
                    child: _CategoryDropdown(
                      categories: viewModel.categories,
                      selectedCategory: selectedCategory,
                      onChanged: (val) => setDialogState(() => selectedCategory = val),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                Row(
                  children: [
                    if (isPriceVis)
                      Expanded(
                        child: TextFormField(
                          controller: priceController,
                          readOnly: !isPriceMod,
                          enabled: isPriceMod,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Base Price (₹) *',
                            hintText: 'e.g. 350',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Enter price';
                            }
                            if (double.tryParse(val.trim()) == null) {
                              return 'Invalid price';
                            }
                            return null;
                          },
                        ),
                      ),
                    if (isPriceVis && isStockQtyVis) const SizedBox(width: 12),
                    if (isStockQtyVis)
                      Expanded(
                        child: TextFormField(
                          controller: stockController,
                          readOnly: !isStockQtyMod,
                          enabled: isStockQtyMod,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Stock Qty',
                            hintText: 'e.g. 10',
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                if (isDescVis) ...[
                  TextFormField(
                    controller: descController,
                    readOnly: !isDescMod,
                    enabled: isDescMod,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Optional item description...',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Photo attachment widget
                if (isPhotoVis)
                  PhotoAttachmentWidget(
                    initialPhotoUrl: photoUrl,
                    onUploadingChanged: (uploading) {
                      setDialogState(() {
                        isPhotoUploading = uploading;
                      });
                    },
                    onPhotoChanged: isPhotoMod
                        ? (url) {
                            setDialogState(() {
                              photoUrl = url;
                            });
                          }
                        : null,
                    label: 'Product Image',
                  ),
              ],
            ),
          );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                backgroundColor: const Color(0xFF131A2E),
                appBar: AppBar(
                  backgroundColor: const Color(0xFF0F1524),
                  title: Text(
                    isEdit ? 'Edit Product' : 'Add New Product to Catalog',
                  ),
                  actions: [
                    TextButton(
                      onPressed: saveItem,
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          color: AppTheme.primaryLight,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: formContent,
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
                  ? 'Edit Product Catalog Details'
                  : 'Add New Product to Catalog',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            content: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              width: MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(child: formContent),
            ),
            actions: [
              if (isEdit)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    if (onDeleteRequested != null) {
                      onDeleteRequested();
                    }
                  },
                  icon: const Icon(
                    Icons.delete_forever_rounded,
                    color: AppTheme.danger,
                    size: 18,
                  ),
                  label: const Text(
                    'Delete Product',
                    style: TextStyle(color: AppTheme.danger),
                  ),
                ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              ElevatedButton(onPressed: saveItem, child: const Text('Save')),
            ],
          );
        },
      );
    },
  );
}

  // ignore: unused_element
  Widget _buildFloatingPaginationIsland({
    required BuildContext context,
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
            itemBuilder: (context) => [20, 50, 100, 200].map((val) {
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
// ─────────────────────────────────────────────────────────────────────────────
// Searchable Category Dropdown Widget (used in Add/Edit Pricelist Item Dialog)
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryDropdown extends StatefulWidget {
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onChanged;

  const _CategoryDropdown({
    required this.categories,
    required this.selectedCategory,
    required this.onChanged,
  });

  @override
  State<_CategoryDropdown> createState() => _CategoryDropdownState();
}

class _CategoryDropdownState extends State<_CategoryDropdown> {
  late TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.selectedCategory ?? '');
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _CategoryDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCategory != widget.selectedCategory) {
      if (_textController.text != (widget.selectedCategory ?? '')) {
        _textController.text = widget.selectedCategory ?? '';
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _openOverlay();
    } else {
      // Delay removal so item taps register first
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focusNode.hasFocus) {
          _removeOverlay();
        }
      });
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
  }

  void _openOverlay() {
    if (_isOpen) {
      _overlayEntry?.markNeedsBuild();
      return;
    }
    _overlayEntry = _buildOverlay();
    Overlay.of(context).insert(_overlayEntry!);
    _isOpen = true;
  }

  void _selectCategory(String? value) {
    _removeOverlay();
    _focusNode.unfocus();
    if (value != null) {
      _textController.text = value;
    }
    widget.onChanged(value);
  }

  Future<void> _addNewCategory() async {
    _removeOverlay();
    _focusNode.unfocus();
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        title: const Text(
          'Add New Category',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: 'Category Name',
            hintText: 'e.g. MOUSE, KEYBOARD, ADAPTOR',
            labelStyle: const TextStyle(color: AppTheme.textSecondary),
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppTheme.textMuted.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primaryLight),
            ),
          ),
          onSubmitted: (_) {
            final val = nameCtrl.text.trim();
            if (val.isNotEmpty) Navigator.pop(ctx, val);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryLight),
            onPressed: () {
              final val = nameCtrl.text.trim();
              if (val.isNotEmpty) Navigator.pop(ctx, val);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final newCat = result.toUpperCase();
      _textController.text = newCat;
      widget.onChanged(newCat);
    }
  }

  OverlayEntry _buildOverlay() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (_) => StatefulBuilder(
        builder: (ctx, setOverlayState) {
          final query = _textController.text.trim().toLowerCase();
          final filtered = widget.categories
              .where((c) => c.toLowerCase().contains(query))
              .toList();

          return Positioned(
            width: size.width,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, size.height + 4),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.cardBg,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'No matching category',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ...filtered.map((cat) {
                        final isSelected = widget.selectedCategory == cat;
                        return InkWell(
                          onTap: () => _selectCategory(cat),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            color: isSelected
                                ? AppTheme.primaryLight.withOpacity(0.12)
                                : Colors.transparent,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    cat,
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppTheme.primaryLight
                                          : AppTheme.textPrimary,
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: AppTheme.primaryLight,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const Divider(height: 1, color: Colors.white10),
                      InkWell(
                        onTap: _addNewCategory,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.add_circle_outline,
                                size: 16,
                                color: AppTheme.success,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '+ Add New Category',
                                style: TextStyle(
                                  color: AppTheme.success,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _textController,
        focusNode: _focusNode,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: 'Select Category',
          hintText: 'Type to search category...',
          hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          suffixIcon: _textController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
                  onPressed: () {
                    _textController.clear();
                    widget.onChanged(null);
                    if (_isOpen) {
                      _overlayEntry?.markNeedsBuild();
                    }
                  },
                )
              : const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
        ),
        onChanged: (val) {
          if (!_isOpen) {
            _openOverlay();
          } else {
            _overlayEntry?.markNeedsBuild();
          }
          final match = widget.categories.firstWhere(
            (c) => c.toLowerCase() == val.trim().toLowerCase(),
            orElse: () => val.trim().toUpperCase(),
          );
          widget.onChanged(match.isNotEmpty ? match : null);
        },
      ),
    );
  }
}

class _PricelistListItem {
  final String? categoryHeader;
  final int? categoryCount;
  final PricelistItem? item;

  _PricelistListItem.header(this.categoryHeader, [this.categoryCount = 0])
      : item = null;
  _PricelistListItem.item(this.item)
      : categoryHeader = null,
        categoryCount = null;
}

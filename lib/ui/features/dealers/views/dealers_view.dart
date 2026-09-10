import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/models/dealer.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/ui_preferences_service.dart';
import '../../../../ui/core/app_theme.dart';
import '../../../shared/components/app_animated_search_bar.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_floating_action_button.dart';
import '../../../shared/components/app_header_sync_button.dart';
import '../../../shared/components/app_list_card.dart';
import '../../../shared/components/app_page_header.dart';
import '../../../shared/components/app_search_filter_bar.dart';
import '../../../shared/resizable_detail_popup.dart';
import '../view_models/dealers_view_model.dart';

class DealersView extends StatefulWidget {
  const DealersView({super.key});

  @override
  State<DealersView> createState() => _DealersViewState();
}

class _DealersViewState extends State<DealersView> {
  final TextEditingController _searchController = TextEditingController();

  // Column Widths for Table (Category column removed - grouped under category headers)
  double _nameWidth = 240.0;
  double _contactWidth = 180.0;
  double _mobileWidth = 160.0;
  double _buildingWidth = 240.0;
  double _productsWidth = 300.0;

  void _loadSavedColumnWidths() {
    _nameWidth = UiPreferencesService.getColumnWidth('dealers', 'name') ?? 240.0;
    _contactWidth = UiPreferencesService.getColumnWidth('dealers', 'contact') ?? 180.0;
    _mobileWidth = UiPreferencesService.getColumnWidth('dealers', 'mobile') ?? 160.0;
    _buildingWidth = UiPreferencesService.getColumnWidth('dealers', 'building') ?? 240.0;
    _productsWidth = UiPreferencesService.getColumnWidth('dealers', 'products') ?? 300.0;
  }

  void _updateColumnWidth(String columnKey, double newWidth) {
    setState(() {
      switch (columnKey) {
        case 'name':
          _nameWidth = newWidth;
          break;
        case 'contact':
          _contactWidth = newWidth;
          break;
        case 'mobile':
          _mobileWidth = newWidth;
          break;
        case 'building':
          _buildingWidth = newWidth;
          break;
        case 'products':
          _productsWidth = newWidth;
          break;
      }
    });
    UiPreferencesService.setColumnWidth('dealers', columnKey, newWidth);
  }

  static const List<String> knownBuildings = [
    'Meghdoot Building',
    'Vishal Bhawan',
    'Manjusha Building',
    'Siddharth Building',
    'Raja House',
    'Skylark Building',
    'Deepak Building',
    'Deepali Building',
    'Sahyog Building',
    'Saraswati House',
    'Ansal Tower',
    'Kundan House',
    'Bajaj House',
    'Shakuntla Building',
    'Madhuban Building',
    'Bhandari House',
    'Red Rose Building (KBC)',
    'Blue Sapphire',
    'Harsh Bhawan',
    'Hemkunt Tower',
    'Chiranjiv Tower',
    'Devika Tower',
    'Pragati Tower',
    'Paras Cinema Complex',
    'Khushal House',
    'Sector 10, Noida',
    'Sector 65, Noida',
  ];

  static const List<String> defaultCategories = [
    'Distributor',
    'Laptop Accessories',
    'Motherboards',
    'Cables',
    'Printers & Parts',
    'Macbook & Apple',
    'Chip-Level Repairs',
    'Service Center',
    'Service Center (Noida)',
    'General',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedColumnWidths();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DealersViewModel>().loadDealers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getCategoryColor(String category) {
    final c = category.toLowerCase().trim();
    if (c.contains('distributor')) return const Color(0xFF818CF8); // Indigo
    if (c.contains('laptop') || c.contains('accessories')) return const Color(0xFF38BDF8); // Sky Blue
    if (c.contains('chip') || c.contains('repair')) return const Color(0xFFFBBF24); // Amber
    if (c.contains('motherboard')) return const Color(0xFFA78BFA); // Violet
    if (c.contains('cable')) return const Color(0xFF34D399); // Emerald
    if (c.contains('printer')) return const Color(0xFFF472B6); // Pink
    if (c.contains('service')) return const Color(0xFF60A5FA); // Blue
    if (c.contains('apple') || c.contains('mac')) return const Color(0xFFCBD5E1); // Slate
    return const Color(0xFF94A3B8); // Muted grey
  }

  Future<void> _launchMaps(Dealer dealer) async {
    String url = dealer.googleMapsUrl ?? '';
    if (url.isEmpty) {
      final query = dealer.buildingName != null && dealer.buildingName!.isNotEmpty
          ? '${dealer.buildingName}, Nehru Place, New Delhi'
          : '${dealer.address}, New Delhi';
      url = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';
    }
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open map for ${dealer.name}')),
        );
      }
    }
  }

  Future<void> _launchCall(String? mobileNo) async {
    if (mobileNo == null || mobileNo.trim().isEmpty) return;
    final uri = Uri.parse('tel:${mobileNo.trim()}');
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not initiate call to $mobileNo')),
        );
      }
    }
  }

  Future<void> _launchWhatsApp(Dealer dealer) async {
    if (dealer.mobileNo == null || dealer.mobileNo!.trim().isEmpty) return;
    String phone = dealer.mobileNo!.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length == 10) {
      phone = '91$phone';
    }
    final msg = Uri.encodeComponent(
      'Hi ${dealer.name}, this is Perfect Solution. We are inquiring about item stock & availability.',
    );
    final url = 'https://wa.me/$phone?text=$msg';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open WhatsApp for ${dealer.name}')),
        );
      }
    }
  }

  Map<String, List<Dealer>> _getGroupedDealers(List<Dealer> dealers) {
    final Map<String, List<Dealer>> map = {};
    for (final d in dealers) {
      final cat = (d.category == null || d.category!.trim().isEmpty)
          ? 'General'
          : d.category!.trim();
      map.putIfAbsent(cat, () => []).add(d);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DealersViewModel>(
      builder: (context, viewModel, child) {
        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isDesktop = screenWidth >= 800;
        final filtered = viewModel.filteredDealers;
        final categories = viewModel.categories;
        final groupedDealers = _getGroupedDealers(filtered);

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: !isDesktop
              ? AppFloatingActionButton(
                  onPressed: () => _showAddEditDialog(context),
                  tooltip: 'Add Dealer',
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: 'Dealers Directory',
                subtitle: 'Vendor Registry, Market Sourcing & Direct Contacts',
                actions: [
                  if (isDesktop)
                    AppHeaderActionButton(
                      label: 'New Dealer',
                      icon: Icons.add_business_rounded,
                      onPressed: () => _showAddEditDialog(context),
                    ),
                  if (!isDesktop)
                    AppHeaderSyncButton(
                      onSynced: () => context.read<DealersViewModel>().loadDealers(),
                    ),
                ],
              ),

              // Search & Filter Bar
              if (isDesktop)
                AppAnimatedSearchBar(
                  controller: _searchController,
                  onChanged: (q) => viewModel.setSearchQuery(q),
                  onClear: () => viewModel.setSearchQuery(''),
                  hintText: 'Search dealer name, building, products, mobile...',
                  margin: const EdgeInsets.only(bottom: 8),
                )
              else
                AppSearchFilterBar(
                  searchQuery: _searchController.text,
                  onSearchChanged: (q) {
                    _searchController.text = q;
                    viewModel.setSearchQuery(q);
                  },
                  hintText: 'Search dealer, building, product...',
                ),

              const SizedBox(height: 8),

              // Category Filter Pills
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: categories.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final cat = categories[idx];
                    final isSelected = viewModel.selectedCategory == cat;
                    final catColor = cat == 'All' ? AppTheme.primaryLight : _getCategoryColor(cat);

                    return FilterChip(
                      selected: isSelected,
                      label: Text(cat),
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                      ),
                      backgroundColor: const Color(0xFF131A2E),
                      selectedColor: isSelected ? AppTheme.primary : const Color(0xFF131A2E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? AppTheme.primaryLight : catColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      onSelected: (_) => viewModel.setCategory(cat),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Results Count Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Text(
                      '${filtered.length} ${filtered.length == 1 ? 'Dealer' : 'Dealers'} Found',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (viewModel.selectedCategory != 'All') ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getCategoryColor(viewModel.selectedCategory).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _getCategoryColor(viewModel.selectedCategory).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          viewModel.selectedCategory,
                          style: TextStyle(
                            color: _getCategoryColor(viewModel.selectedCategory),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 6),

              // Content Area
              Expanded(
                child: filtered.isEmpty
                    ? const AppEmptyState(
                        icon: Icons.storefront_rounded,
                        title: 'No Dealers Found',
                        message: 'Try changing your search keywords or category filter.',
                      )
                    : (isDesktop
                        ? _buildDesktopTable(context, viewModel, groupedDealers)
                        : _buildMobileCardsList(context, viewModel, filtered)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategorySectionHeader(String category, int count) {
    final Color color = _getCategoryColor(category);
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
            category.toUpperCase(),
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
              '$count ${count == 1 ? 'Dealer' : 'Dealers'}',
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

  Widget _buildDesktopTable(
    BuildContext context,
    DealersViewModel viewModel,
    Map<String, List<Dealer>> groupedDealers,
  ) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.glassCardDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: 12,
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double totalWidth = _nameWidth +
              _contactWidth +
              _mobileWidth +
              _buildingWidth +
              _productsWidth;
          final double tableWidth = totalWidth > constraints.maxWidth ? totalWidth : constraints.maxWidth;
          final double extraWidth = constraints.maxWidth > totalWidth ? (constraints.maxWidth - totalWidth) : 0.0;
          final double effectiveProductsWidth = _productsWidth + extraWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  // Table Header Row (Category column removed - grouped under status headers)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildResizableHeader(
                          'Dealer Name',
                          _nameWidth,
                          (delta) => _updateColumnWidth('name', (_nameWidth + delta).clamp(150.0, 450.0)),
                        ),
                        _buildResizableHeader(
                          'Contact Person',
                          _contactWidth,
                          (delta) => _updateColumnWidth('contact', (_contactWidth + delta).clamp(120.0, 350.0)),
                        ),
                        _buildResizableHeader(
                          'Mobile No.',
                          _mobileWidth,
                          (delta) => _updateColumnWidth('mobile', (_mobileWidth + delta).clamp(110.0, 300.0)),
                        ),
                        _buildResizableHeader(
                          'Building / Location',
                          _buildingWidth,
                          (delta) => _updateColumnWidth('building', (_buildingWidth + delta).clamp(150.0, 450.0)),
                        ),
                        _buildResizableHeader(
                          'Products & Spares',
                          effectiveProductsWidth,
                          (delta) => _updateColumnWidth('products', (_productsWidth + delta).clamp(180.0, 600.0)),
                        ),
                      ],
                    ),
                  ),

                  // Scrollable Body with Category Headers
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 24),
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in groupedDealers.entries) ...[
                            _buildCategorySectionHeader(entry.key, entry.value.length),
                            for (final dealer in entry.value) ...[
                              _buildDesktopTableRow(context, viewModel, dealer, effectiveProductsWidth),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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

  Widget _buildDesktopTableRow(
    BuildContext context,
    DealersViewModel viewModel,
    Dealer dealer,
    double productsColWidth,
  ) {
    final hasMobile = dealer.mobileNo != null && dealer.mobileNo!.trim().isNotEmpty;

    return InkWell(
      onTap: () => _showDetailDialog(context, dealer, viewModel),
      hoverColor: Colors.white.withValues(alpha: 0.03),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
        ),
        child: Row(
          children: [
            // Dealer Name
            Container(
              width: _nameWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                dealer.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Contact Person
            Container(
              width: _contactWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                (dealer.contactPerson != null && dealer.contactPerson!.trim().isNotEmpty)
                    ? dealer.contactPerson!
                    : '—',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Mobile No.
            Container(
              width: _mobileWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                (dealer.mobileNo != null && dealer.mobileNo!.trim().isNotEmpty)
                    ? dealer.mobileNo!
                    : '—',
                style: TextStyle(
                  color: hasMobile ? AppTheme.primaryLight : AppTheme.textSecondary,
                  fontWeight: hasMobile ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Building / Location
            Container(
              width: _buildingWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dealer.buildingName ?? 'Nehru Place',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (dealer.shopNo != null && dealer.shopNo!.trim().isNotEmpty)
                    Text(
                      dealer.shopNo!,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Products & Spares
            Container(
              width: productsColWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                (dealer.products != null && dealer.products!.trim().isNotEmpty)
                    ? dealer.products!
                    : '—',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCardsList(
    BuildContext context,
    DealersViewModel viewModel,
    List<Dealer> dealers,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 80, top: 4),
      physics: const BouncingScrollPhysics(),
      itemCount: dealers.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final dealer = dealers[index];
        final catColor = _getCategoryColor(dealer.category ?? 'General');

        final List<Widget> metadata = [
          if (dealer.contactPerson != null && dealer.contactPerson!.trim().isNotEmpty)
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 14, color: AppTheme.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Contact: ${dealer.contactPerson}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          if (dealer.mobileNo != null && dealer.mobileNo!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.phone_android_rounded, size: 14, color: AppTheme.primaryLight),
                const SizedBox(width: 6),
                Text(
                  dealer.mobileNo!,
                  style: const TextStyle(
                    color: AppTheme.primaryLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: Colors.redAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${dealer.buildingName ?? 'Nehru Place'} ${dealer.shopNo != null && dealer.shopNo!.trim().isNotEmpty ? '(${dealer.shopNo})' : ''}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (dealer.products != null && dealer.products!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.inventory_2_outlined, size: 14, color: Colors.amberAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dealer.products!,
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ];

        return AppListCard(
          index: index,
          title: dealer.name,
          statusBadge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: catColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              dealer.category ?? 'General',
              style: TextStyle(
                color: catColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          metadataRows: metadata,
          onTap: () => _showDetailDialog(context, dealer, viewModel),
          onEdit: () => _showAddEditDialog(context, existingDealer: dealer),
          onDelete: () => _confirmDelete(context, viewModel, dealer),
        );
      },
    );
  }

  void _showDetailDialog(BuildContext context, Dealer dealer, DealersViewModel viewModel) {
    final repo = context.read<ShopRepository>();
    final hasMobile = dealer.mobileNo != null && dealer.mobileNo!.trim().isNotEmpty;

    ResizableDetailPopup.show(
      context: context,
      repository: repo,
      title: dealer.name,
      subtitle: '${dealer.category ?? 'General'} • ${dealer.buildingName ?? 'Nehru Place'}',
      contentBuilder: (ctx, scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScaledInfoRow(
              label: 'Dealer Name',
              value: dealer.name,
              scaleFactor: scale,
            ),
            ScaledInfoRow(
              label: 'Category',
              value: dealer.category ?? 'General',
              scaleFactor: scale,
            ),
            if (dealer.contactPerson != null && dealer.contactPerson!.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Contact Person',
                value: dealer.contactPerson!,
                scaleFactor: scale,
              ),
            if (dealer.mobileNo != null && dealer.mobileNo!.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Mobile Number',
                value: dealer.mobileNo!,
                scaleFactor: scale,
              ),
            if (dealer.alternateMobile != null && dealer.alternateMobile!.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Alternate Mobile',
                value: dealer.alternateMobile!,
                scaleFactor: scale,
              ),
            if (dealer.buildingName != null && dealer.buildingName!.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Building / Area',
                value: dealer.buildingName!,
                scaleFactor: scale,
              ),
            if (dealer.shopNo != null && dealer.shopNo!.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Shop / Floor No.',
                value: dealer.shopNo!,
                scaleFactor: scale,
              ),
            ScaledInfoRow(
              label: 'Full Address',
              value: dealer.address,
              scaleFactor: scale,
            ),
            if (dealer.products != null && dealer.products!.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Products & Spares',
                value: dealer.products!,
                scaleFactor: scale,
              ),
            if (dealer.notes != null && dealer.notes!.trim().isNotEmpty)
              ScaledInfoRow(
                label: 'Internal Notes',
                value: dealer.notes!,
                scaleFactor: scale,
              ),
          ],
        );
      },
      actionsBuilder: (ctx, scale) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ScaledActionButton(
              icon: Icons.directions_rounded,
              label: 'Directions',
              color: const Color(0xFF3B82F6),
              onTap: () => _launchMaps(dealer),
              scaleFactor: scale,
            ),
            if (hasMobile)
              ScaledActionButton(
                icon: Icons.phone_rounded,
                label: 'Call',
                color: const Color(0xFF10B981),
                onTap: () => _launchCall(dealer.mobileNo),
                scaleFactor: scale,
              ),
            if (hasMobile)
              ScaledActionButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'WhatsApp',
                color: const Color(0xFF14B8A6),
                onTap: () => _launchWhatsApp(dealer),
                scaleFactor: scale,
              ),
            ScaledActionButton(
              icon: Icons.edit_outlined,
              label: 'Edit',
              color: AppTheme.primaryLight,
              onTap: () {
                Navigator.pop(ctx);
                _showAddEditDialog(context, existingDealer: dealer);
              },
              scaleFactor: scale,
            ),
            ScaledActionButton(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: AppTheme.danger,
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, viewModel, dealer);
              },
              scaleFactor: scale,
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, DealersViewModel viewModel, Dealer dealer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Dealer?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Are you sure you want to delete "${dealer.name}" from the directory?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await viewModel.deleteDealer(dealer.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Deleted "${dealer.name}"')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddEditDialog(BuildContext context, {Dealer? existingDealer}) {
    showDialog(
      context: context,
      builder: (ctx) => DealerAddEditDialog(existingDealer: existingDealer),
    );
  }
}

class DealerAddEditDialog extends StatefulWidget {
  final Dealer? existingDealer;

  const DealerAddEditDialog({super.key, this.existingDealer});

  @override
  State<DealerAddEditDialog> createState() => _DealerAddEditDialogState();
}

class _DealerAddEditDialogState extends State<DealerAddEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _contactPersonController;
  late TextEditingController _mobileController;
  late TextEditingController _buildingController;
  late TextEditingController _shopNoController;
  late TextEditingController _fullAddressController;
  late TextEditingController _categoryController;
  late TextEditingController _productsController;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    final d = widget.existingDealer;
    _nameController = TextEditingController(text: d?.name ?? '');
    _contactPersonController = TextEditingController(text: d?.contactPerson ?? '');
    _mobileController = TextEditingController(text: d?.mobileNo ?? '');
    _buildingController = TextEditingController(text: d?.buildingName ?? 'Meghdoot Building');
    _shopNoController = TextEditingController(text: d?.shopNo ?? '');
    _fullAddressController = TextEditingController(
      text: d?.address ?? 'Meghdoot Building, Nehru Place, New Delhi - 110019',
    );
    _categoryController = TextEditingController(text: d?.category ?? 'General');
    _productsController = TextEditingController(text: d?.products ?? '');
    _notesController = TextEditingController(text: d?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactPersonController.dispose();
    _mobileController.dispose();
    _buildingController.dispose();
    _shopNoController.dispose();
    _fullAddressController.dispose();
    _categoryController.dispose();
    _productsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _updateSuggestedAddress() {
    if (widget.existingDealer != null) return; // Keep existing address as-is on edit unless modified
    final shopNo = _shopNoController.text.trim();
    final building = _buildingController.text.trim();
    final city = building.toLowerCase().contains('noida') ? 'Noida' : 'New Delhi';

    final parts = <String>[];
    if (shopNo.isNotEmpty) parts.add(shopNo);
    if (building.isNotEmpty && building != 'Nehru Place') parts.add(building);
    if (city == 'New Delhi') {
      parts.add('Nehru Place, New Delhi - 110019');
    } else {
      parts.add('Noida, Uttar Pradesh');
    }
    _fullAddressController.text = parts.join(', ');
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final contactPerson = _contactPersonController.text.trim();
    final mobileNo = _mobileController.text.trim();
    final building = _buildingController.text.trim();
    final shopNo = _shopNoController.text.trim();
    final fullAddress = _fullAddressController.text.trim();
    final category = _categoryController.text.trim();
    final products = _productsController.text.trim();
    final notes = _notesController.text.trim();

    final city = (building.toLowerCase().contains('noida') || fullAddress.toLowerCase().contains('noida'))
        ? 'Noida'
        : 'New Delhi';

    final mapsQuery = city == 'New Delhi'
        ? '$building, Nehru Place, New Delhi'
        : '$shopNo, $building, Noida';
    final mapsUrl =
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(mapsQuery)}';

    final dealer = Dealer(
      id: widget.existingDealer?.id ?? 'dealer_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      contactPerson: contactPerson.isEmpty ? null : contactPerson,
      mobileNo: mobileNo.isEmpty ? null : mobileNo,
      buildingName: building.isEmpty ? null : building,
      shopNo: shopNo.isEmpty ? null : shopNo,
      address: fullAddress.isEmpty ? '$building, Nehru Place, New Delhi' : fullAddress,
      city: city,
      category: category.isEmpty ? 'General' : category,
      products: products.isEmpty ? null : products,
      googleMapsUrl: mapsUrl,
      notes: notes.isEmpty ? null : notes,
      rating: widget.existingDealer?.rating ?? 5.0,
    );

    await context.read<DealersViewModel>().saveDealer(dealer);

    if (mounted) {
      Navigator.pop(context, dealer);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.existingDealer == null ? 'Dealer added successfully' : 'Dealer updated successfully'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingDealer != null;

    return Dialog(
      backgroundColor: const Color(0xFF0F1524),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 750),
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.store_mall_directory_rounded, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  isEdit ? 'Edit Dealer Details' : 'Add New Dealer',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Colors.white10),
            const SizedBox(height: 16),

            // Form Fields
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Dealer Name
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Dealer / Shop Name *',
                          hintText: 'e.g. Pro Lab, Caviartechnologies',
                          prefixIcon: Icon(Icons.business_rounded, size: 20),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Please enter dealer name' : null,
                      ),
                      const SizedBox(height: 14),

                      // Contact Person & Mobile Row
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _contactPersonController,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'Contact Person',
                                hintText: 'Owner / Executive',
                                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _mobileController,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'Mobile Number',
                                hintText: '10-digit number',
                                prefixIcon: Icon(Icons.phone_android_rounded, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Category Dropdown / Autocomplete
                      Autocomplete<String>(
                        initialValue: TextEditingValue(text: _categoryController.text),
                        optionsBuilder: (textVal) {
                          if (textVal.text.isEmpty) return _DealersViewState.defaultCategories;
                          return _DealersViewState.defaultCategories.where(
                            (c) => c.toLowerCase().contains(textVal.text.toLowerCase()),
                          );
                        },
                        onSelected: (val) => _categoryController.text = val,
                        fieldViewBuilder: (ctx, controller, focus, onSub) {
                          controller.addListener(() => _categoryController.text = controller.text);
                          return TextFormField(
                            controller: controller,
                            focusNode: focus,
                            style: const TextStyle(color: AppTheme.textPrimary),
                            decoration: const InputDecoration(
                              labelText: 'Category *',
                              hintText: 'e.g. Distributor, Laptop Accessories, Motherboards',
                              prefixIcon: Icon(Icons.category_outlined, size: 20),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Please enter or select category' : null,
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // Building & Shop No. Row
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Autocomplete<String>(
                              initialValue: TextEditingValue(text: _buildingController.text),
                              optionsBuilder: (textVal) {
                                if (textVal.text.isEmpty) return _DealersViewState.knownBuildings;
                                return _DealersViewState.knownBuildings.where(
                                  (b) => b.toLowerCase().contains(textVal.text.toLowerCase()),
                                );
                              },
                              onSelected: (val) {
                                _buildingController.text = val;
                                _updateSuggestedAddress();
                              },
                              fieldViewBuilder: (ctx, controller, focus, onSub) {
                                controller.addListener(() {
                                  _buildingController.text = controller.text;
                                });
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focus,
                                  style: const TextStyle(color: AppTheme.textPrimary),
                                  decoration: const InputDecoration(
                                    labelText: 'Building / Area *',
                                    hintText: 'e.g. Meghdoot, Vishal Bhawan',
                                    prefixIcon: Icon(Icons.location_city_rounded, size: 20),
                                  ),
                                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter building' : null,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _shopNoController,
                              style: const TextStyle(color: AppTheme.textPrimary),
                              onChanged: (_) => _updateSuggestedAddress(),
                              decoration: const InputDecoration(
                                labelText: 'Shop / Floor No.',
                                hintText: 'e.g. 115A, 1st Floor',
                                prefixIcon: Icon(Icons.room_rounded, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Full Editable Address
                      TextFormField(
                        controller: _fullAddressController,
                        maxLines: 2,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Full Address *',
                          hintText: 'e.g. 204, Siddharth Building, Nehru Place, New Delhi - 110019',
                          prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Please enter full address' : null,
                      ),
                      const SizedBox(height: 14),

                      // Products & Spares
                      TextFormField(
                        controller: _productsController,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Products & Specialization',
                          hintText: 'e.g. Keyboards, Displays, Chip Level Motherboard, Cables',
                          prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 1-Tap Quick Product Chips
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          'Screens',
                          'Batteries',
                          'Keyboards',
                          'Motherboards',
                          'Adapters',
                          'Hinges',
                          'Fans',
                          'RAM/SSD',
                          'Printers',
                        ].map((tag) {
                          final current = _productsController.text.toLowerCase();
                          final isPresent = current.contains(tag.toLowerCase());
                          return InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () {
                              final text = _productsController.text.trim();
                              if (isPresent) {
                                final updated = text
                                    .split(RegExp(r',\s*'))
                                    .where((s) => !s.toLowerCase().contains(tag.toLowerCase()))
                                    .join(', ');
                                setState(() => _productsController.text = updated);
                              } else {
                                final updated = text.isEmpty ? tag : '$text, $tag';
                                setState(() => _productsController.text = updated);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPresent
                                    ? const Color(0xFF22D3EE).withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isPresent
                                      ? const Color(0xFF22D3EE).withValues(alpha: 0.6)
                                      : Colors.white12,
                                ),
                              ),
                              child: Text(
                                isPresent ? '✓ $tag' : '+ $tag',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isPresent ? FontWeight.bold : FontWeight.normal,
                                  color: isPresent ? const Color(0xFF22D3EE) : AppTheme.textMuted,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      // Notes
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Internal Notes',
                          hintText: 'Credit terms, shop timing, alternate contact',
                          prefixIcon: Icon(Icons.notes_rounded, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, color: Colors.white10),
            const SizedBox(height: 16),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(isEdit ? 'Save Changes' : 'Add Dealer'),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/models/dealer.dart';
import '../../../../data/models/request_order.dart';
import '../../../../data/repositories/shop_repository.dart';
import '../../../../data/services/dealer_inquiry_service.dart';
import '../../../../data/services/dealer_recommendation_service.dart';
import '../../../../data/services/item_category_detector.dart';
import '../../../../data/services/smart_search_utils.dart';
import '../../../core/app_theme.dart';
import '../../../core/motion/motion.dart';
import '../../../shared/components/app_page_header.dart';
import '../view_models/requests_view_model.dart';
import 'requests_view.dart';

class DealerInquiryView extends StatefulWidget {
  final RequestOrder request;

  const DealerInquiryView({super.key, required this.request});

  @override
  State<DealerInquiryView> createState() => _DealerInquiryViewState();
}

class _DealerInquiryViewState extends State<DealerInquiryView> {
  List<DealerRecommendation> _recommendations = const [];
  late ItemClassification _classification;
  late final TextEditingController _messageController;
  final TextEditingController _searchController = TextEditingController();

  final Set<String> _selectedDealerIds = {};
  Map<String, double> _scoreMap = const {};
  Set<String> _matchedDealerIds = const {};
  bool _showAllDealers = false;
  bool _isDispatching = false;
  bool _isUnmatched = false;
  bool _isMessageExpandedOnMobile = true;

  @override
  void initState() {
    super.initState();
    _initData(isInitial: true);
  }

  @override
  void reassemble() {
    super.reassemble();
    _initData(isInitial: false);
  }

  void _initData({bool isInitial = false}) {
    final repo = context.read<ShopRepository>();
    final dealers = repo.getDealers();
    final orders = repo.getPurchaseOrders();

    final itemText = widget.request.item;
    _classification = ItemCategoryDetector.classify(itemText);
    _recommendations = DealerRecommendationService.getRecommendations(
      itemText: itemText,
      allDealers: dealers,
      purchaseOrders: orders,
      getPurchaseItems: (id) => repo.getPurchaseOrderItems(id),
    );

    _scoreMap = {
      for (final r in _recommendations) r.dealer.id: r.score,
    };

    // Matched dealers have positive catalog or transaction scores (> 10.0)
    _matchedDealerIds = _recommendations
        .where((r) => r.score > 10.0)
        .map((r) => r.dealer.id)
        .toSet();

    // If no dealers matched the item, treat as unmatched
    _isUnmatched = _matchedDealerIds.isEmpty;

    if (isInitial) {
      // Only auto-select top scored dealers if we have genuine catalog/history matches
      if (!_isUnmatched) {
        final topMatched = _recommendations
            .where((r) => _matchedDealerIds.contains(r.dealer.id))
            .take(4)
            .map((r) => r.dealer.id);
        _selectedDealerIds.addAll(topMatched);
      } else {
        _selectedDealerIds.clear();
      }

      _messageController = TextEditingController(
        text: widget.request.item.trim(),
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _manualLaunchWhatsApp(Dealer dealer) {
    if (dealer.mobileNo == null || dealer.mobileNo!.trim().isEmpty) return;
    String phone = dealer.mobileNo!.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length == 10) phone = '91$phone';
    final msg = Uri.encodeComponent(_messageController.text.trim());
    launchUrl(
      Uri.parse('https://wa.me/$phone?text=$msg'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _manualLaunchCall(Dealer dealer) async {
    if (dealer.mobileNo == null || dealer.mobileNo!.trim().isEmpty) return;
    final phone = dealer.mobileNo!.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _dispatchInquiries() async {
    if (_selectedDealerIds.isEmpty) return;
    setState(() => _isDispatching = true);

    try {
      final repo = context.read<ShopRepository>();
      final allDealers = repo.getDealers();
      final selectedDealers = allDealers
          .where((d) => _selectedDealerIds.contains(d.id))
          .toList();

      final allPhotos = widget.request.photoList
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      final photoUrlsJoined = allPhotos.isNotEmpty ? allPhotos.join(';') : null;

      final count = await DealerInquiryService.enqueueInquiries(
        requestId: widget.request.id,
        itemText: _messageController.text.trim(),
        photoUrl: photoUrlsJoined,
        targetDealers: selectedDealers,
      );

      if (mounted) {
        setState(() => _isDispatching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚡ Enqueued $count WhatsApp inquiries! Server is dispatching in background.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF065F46),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDispatching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Server queue error ($e). Use individual WhatsApp buttons.',
            ),
            backgroundColor: Colors.deepOrange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _assignToRunner(BuildContext context, {Dealer? dealer}) {
    final reqVm = context.read<RequestsViewModel>();
    RequestsView.showAssignRunnerDialog(
      context,
      widget.request,
      reqVm,
      preselectedDealer: dealer?.name,
      preselectedBuilding: dealer?.buildingName,
      preselectedShopNo: dealer?.shopNo,
    );
  }

  List<Dealer> _getFilteredDealers(List<Dealer> allDealers) {
    final query = _searchController.text.trim();

    final filtered = allDealers.where((d) {
      // If user is searching, allow searching the entire directory
      if (query.isNotEmpty) {
        final combined =
            '${d.name} ${d.mobileNo ?? ""} ${d.shopNo ?? ""} ${d.buildingName ?? ""} ${d.products ?? ""}';
        return SmartSearchUtils.matchesQuery(combined, query);
      }

      // If matched item and user has not toggled "Browse All":
      if (!_isUnmatched && !_showAllDealers) {
        // Show only matched dealers or any dealer user has explicitly selected
        return _matchedDealerIds.contains(d.id) || _selectedDealerIds.contains(d.id);
      }

      // Otherwise (unmatched item OR show all toggled): show all dealers
      return true;
    }).toList();

    // Sorting rule:
    // 1. Selected dealers ALWAYS float to the top
    // 2. Highest recommendation score (top dealers on top)
    // 3. Alphabetical by name
    filtered.sort((a, b) {
      final aSelected = _selectedDealerIds.contains(a.id);
      final bSelected = _selectedDealerIds.contains(b.id);
      if (aSelected && !bSelected) return -1;
      if (!aSelected && bSelected) return 1;

      final aScore = _scoreMap[a.id] ?? 0.0;
      final bScore = _scoreMap[b.id] ?? 0.0;
      final scoreComp = bScore.compareTo(aScore);
      if (scoreComp != 0) return scoreComp;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (_scoreMap.isEmpty && _matchedDealerIds.isEmpty && _recommendations.isEmpty) {
      _initData(isInitial: false);
    }
    final repo = context.watch<ShopRepository>();
    final allDealers = repo.getDealers();
    final filteredDealers = _getFilteredDealers(allDealers);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0B101D),
      body: SafeArea(
        child: Column(
          children: [
            // Standard Page Header
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 6 : 8),
              child: AppPageHeader(
                title: isMobile ? 'Dealer Inquiry' : 'Procure Item & Dealer Inquiries',
                subtitle: isMobile
                    ? '${widget.request.item.length > 28 ? '${widget.request.item.substring(0, 28)}…' : widget.request.item} • ${widget.request.customerName}'
                    : 'Req #${widget.request.id} • ${widget.request.customerName}',
                onBack: () => Navigator.pop(context),
                actions: [
                  BouncyPressable(
                    scaleFactor: 0.94,
                    onTap: () => _assignToRunner(context),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_walk_rounded, size: 16, color: Color(0xFF60A5FA)),
                          SizedBox(width: 6),
                          Text(
                            'Assign Runner',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF60A5FA),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white12, height: 1),

            // Content Area
            Expanded(
              child: isDesktop
                  ? _buildDesktopLayout(filteredDealers)
                  : _buildMobileLayout(filteredDealers),
            ),

            // Bottom Sticky Dispatch Bar
            _buildBottomBar(filteredDealers, isMobile: isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(List<Dealer> filteredDealers) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Item Specifications, WhatsApp Editor & Live Tracker (400px)
        SizedBox(
          width: 400,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildItemSpecCard(),
                const SizedBox(height: 14),
                _buildMessageComposerCard(),
                const SizedBox(height: 14),
                _buildRunnerHandoffCard(),
                const SizedBox(height: 14),
                _buildTrackerSection(),
              ],
            ),
          ),
        ),

        const VerticalDivider(color: Colors.white12, width: 1),

        // Right Column: Filter Toolbar, Unmatched Banner, & Dealer Cards
        Expanded(
          child: Column(
            children: [
              _buildFilterToolbar(filteredDealers),
              if (_isUnmatched) _buildUnmatchedAlertBanner(),
              Expanded(
                child: _buildDealerCardsList(filteredDealers),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(List<Dealer> filteredDealers) {
    final photo = widget.request.photoList.firstOrNull;

    return Column(
      children: [
        // ── Compact Item Header ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF131A2E),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
          child: Row(
            children: [
              if (photo != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      photo,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.request.item,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${widget.request.customerName} • ₹${widget.request.advance.toStringAsFixed(0)} adv • ${_classification.category.name}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Toggle WhatsApp message editor
              IconButton(
                icon: Icon(
                  _isMessageExpandedOnMobile ? Icons.edit_off_rounded : Icons.edit_note_rounded,
                  size: 20,
                  color: _isMessageExpandedOnMobile ? const Color(0xFF25D366) : AppTheme.textMuted,
                ),
                onPressed: () => setState(() => _isMessageExpandedOnMobile = !_isMessageExpandedOnMobile),
                tooltip: 'Edit broadcast message',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),

        // ── Collapsible WhatsApp Message Composer ──
        if (_isMessageExpandedOnMobile)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1524),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.message_rounded, color: Color(0xFF25D366), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Broadcast message...',
                      hintStyle: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFF131A2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF25D366)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Unmatched Alert (compact) ──
        if (_isUnmatched)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No catalog match for "${widget.request.item}". Showing all dealers.',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        // ── Search & Filter Toolbar ──
        _buildFilterToolbar(filteredDealers),

        // ── Dealer Cards List (scrollable, takes remaining space) ──
        Expanded(
          child: _buildDealerCardsList(filteredDealers),
        ),
      ],
    );
  }

  Widget _buildItemSpecCard() {
    final photo = widget.request.photoList.firstOrNull;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.inventory_2_rounded, color: AppTheme.primaryLight, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.request.item,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Customer: ${widget.request.customerName} • Advance: ₹${widget.request.advance.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (photo != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    photo,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Category: ${_classification.category.name.toUpperCase()}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA)),
                ),
              ),
              if (_classification.brand != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Brand: ${_classification.brand}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                  ),
                ),
              for (final spec in _classification.specTokens)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    spec,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnmatchedAlertBanner() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unique / Uncatalogued Item',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFBBF24),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No direct catalog match was found for "${widget.request.item}". Showing full dealer directory with top dealers first. You can search by vendor name, or dispatch a market runner.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.8),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _assignToRunner(context),
                  icon: const Icon(Icons.directions_walk_rounded, size: 14),
                  label: const Text(
                    'Send Market Runner to Search',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA78BFA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageComposerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.message_rounded, color: Color(0xFF25D366), size: 18),
              SizedBox(width: 8),
              Text(
                'WhatsApp Broadcast Message',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            maxLines: 3,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF0F1524),
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF25D366)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunnerHandoffCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.directions_walk_rounded, color: Color(0xFF60A5FA), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Search in Market',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.request.assignedRunnerName != null
                      ? 'Assigned to: ${widget.request.assignedRunnerName}'
                      : 'Dealers out of stock? Hand off to runner.',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _assignToRunner(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Assign', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackerSection() {
    return FutureBuilder<List<DealerInquiryItem>>(
      future: DealerInquiryService.getInquiriesForRequest(widget.request.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final list = snapshot.data!;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF131A2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Realtime Inquiry Tracker',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  Text(
                    '${list.length} Dispatched',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final inq in list.take(5)) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        inq.status == 'sent'
                            ? Icons.done_all_rounded
                            : (inq.status == 'failed' ? Icons.error_outline_rounded : Icons.schedule_rounded),
                        size: 14,
                        color: inq.status == 'sent'
                            ? const Color(0xFF25D366)
                            : (inq.status == 'failed' ? Colors.redAccent : Colors.amber),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          inq.dealerName,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        inq.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: inq.status == 'sent'
                              ? const Color(0xFF25D366)
                              : (inq.status == 'failed' ? Colors.redAccent : Colors.amber),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterToolbar(List<Dealer> filteredDealers) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1524),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Field
          SizedBox(
            height: 38,
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search dealers...',
                hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.textMuted),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 14),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                filled: true,
                fillColor: const Color(0xFF131A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Matched indicator + count + bulk actions in one row
          Row(
            children: [
              if (!_isUnmatched) ...[
                InkWell(
                  onTap: () => setState(() => _showAllDealers = !_showAllDealers),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF34D399)),
                        const SizedBox(width: 3),
                        Text(
                          _showAllDealers
                              ? 'All'
                              : '${_matchedDealerIds.length} matched',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          _showAllDealers ? Icons.filter_list_off_rounded : Icons.filter_list_rounded,
                          size: 11,
                          color: const Color(0xFF34D399),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                '${filteredDealers.length} dealers',
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  setState(() {
                    for (final d in filteredDealers) {
                      _selectedDealerIds.add(d.id);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text('Select All', style: TextStyle(fontSize: 10.5, color: Color(0xFF60A5FA), fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 2),
              InkWell(
                onTap: () => setState(() => _selectedDealerIds.clear()),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text('Clear', style: TextStyle(fontSize: 10.5, color: Colors.redAccent, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDealerCardsList(List<Dealer> dealers, {bool shrinkWrap = false}) {
    if (dealers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 40, color: AppTheme.textMuted),
              SizedBox(height: 10),
              Text('No matching dealers found', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              SizedBox(height: 4),
              Text('Try clearing the search query.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: dealers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final dealer = dealers[index];
        final isSelected = _selectedDealerIds.contains(dealer.id);
        final rec = _recommendations.where((r) => r.dealer.id == dealer.id).firstOrNull;
        final hasValidMobile = dealer.mobileNo != null && dealer.mobileNo!.trim().isNotEmpty;

        return InkWell(
          key: ValueKey(dealer.id),
          onTap: hasValidMobile
              ? () {
                  setState(() {
                    if (isSelected) {
                      _selectedDealerIds.remove(dealer.id);
                    } else {
                      _selectedDealerIds.add(dealer.id);
                    }
                  });
                }
              : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : const Color(0xFF131A2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppTheme.primary.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.06),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Compact checkbox
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Transform.scale(
                    scale: 0.85,
                    child: Checkbox(
                      value: isSelected,
                      activeColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: hasValidMobile
                          ? (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedDealerIds.add(dealer.id);
                                } else {
                                  _selectedDealerIds.remove(dealer.id);
                                }
                              });
                            }
                          : null,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dealer.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: Colors.redAccent),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${dealer.buildingName ?? 'Nehru Place'} ${dealer.shopNo != null && dealer.shopNo!.trim().isNotEmpty ? '(${dealer.shopNo})' : ''}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (rec != null && rec.matchReasons.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 3,
                          runSpacing: 3,
                          children: [
                            for (final reason in rec.matchReasons.take(3))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  reason,
                                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF93C5FD)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Quick action buttons (stacked vertically to save horizontal space)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: hasValidMobile ? () => _manualLaunchWhatsApp(dealer) : null,
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Color(0xFF25D366)),
                      tooltip: 'WhatsApp',
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: hasValidMobile ? () => _manualLaunchCall(dealer) : null,
                      icon: const Icon(Icons.phone_outlined, size: 16, color: AppTheme.primaryLight),
                      tooltip: 'Call',
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: () => _assignToRunner(context, dealer: dealer),
                      icon: const Icon(Icons.directions_walk_rounded, size: 16, color: Color(0xFFA78BFA)),
                      tooltip: 'Send Runner for Pickup',
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
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

  Widget _buildBottomBar(List<Dealer> filteredDealers, {bool isMobile = false}) {
    final count = _selectedDealerIds.length;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1524),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          // Selection count
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count Selected',
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(height: 1),
                const Text(
                  'Background queue via WhatsApp',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ],
          ),
          const Spacer(),
          // Broadcast button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (count > 0 && !_isDispatching) ? _dispatchInquiries : null,
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: isMobile ? 38 : 44,
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20),
                decoration: BoxDecoration(
                  gradient: (count > 0 && !_isDispatching)
                      ? const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: (count > 0 && !_isDispatching)
                      ? null
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (count > 0 && !_isDispatching)
                        ? const Color(0xFF34D399).withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.06),
                    width: 1,
                  ),
                  boxShadow: (count > 0 && !_isDispatching)
                      ? [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isDispatching) ...[
                      const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Broadcasting...',
                        style: TextStyle(
                          fontSize: isMobile ? 12 : 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ] else ...[
                      Icon(
                        Icons.bolt_rounded,
                        size: isMobile ? 18 : 20,
                        color: count > 0 ? Colors.white : Colors.white38,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isMobile
                            ? 'Broadcast ($count)'
                            : 'Broadcast to $count ${count == 1 ? "Dealer" : "Dealers"}',
                        style: TextStyle(
                          fontSize: isMobile ? 12 : 13,
                          fontWeight: FontWeight.w600,
                          color: count > 0 ? Colors.white : Colors.white38,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/models/request_order.dart';
import '../../../../data/services/item_category_detector.dart';
import '../../../../data/services/user_permission_service.dart';
import '../../../../ui/core/app_theme.dart';
import '../../../shared/app_photo_viewer_dialog.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../view_models/requests_view_model.dart';

class RunnerTasksView extends StatefulWidget {
  const RunnerTasksView({super.key});

  @override
  State<RunnerTasksView> createState() => _RunnerTasksViewState();
}

class _RunnerTasksViewState extends State<RunnerTasksView> {
  // 0: All Tasks, 1: Find in Market, 2: Shop Pickups
  int _activeStreamTab = 0;
  String _selectedBuilding = 'All';
  String _statusFilter = 'All'; // Default: 'All', 'Pending', 'Collected'

  Future<void> _launchMaps(String building, String? shopNo) async {
    final query = (shopNo != null && shopNo.trim().isNotEmpty)
        ? '$shopNo, $building, Nehru Place, New Delhi'
        : '$building, Nehru Place, New Delhi';
    final url = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';
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
          SnackBar(content: Text('Could not open map for $building')),
        );
      }
    }
  }

  Future<void> _launchCall(String? mobileNo) async {
    if (mobileNo == null || mobileNo.trim().isEmpty) return;
    final clean = mobileNo.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
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

  Future<void> _launchWhatsApp(String? mobileNo, String itemName) async {
    if (mobileNo == null || mobileNo.trim().isEmpty) return;
    String phone = mobileNo.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length == 10) phone = '91$phone';
    final msg = Uri.encodeComponent(
      'Hi, Perfect Solution runner is arriving at your shop for pickup of: $itemName. Please keep it ready.',
    );
    final url = 'https://wa.me/$phone?text=$msg';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  void _showCollectModal(BuildContext context, RequestsViewModel viewModel, RequestOrder request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1524),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CollectTaskModal(request: request, viewModel: viewModel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = UserPermissionService.getCurrentUserEmail();
    final canMarkCollected = UserPermissionService.canPerformModuleAction('requests', 'canMarkCollected');
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Consumer<RequestsViewModel>(
      builder: (context, viewModel, child) {
        final allTasks = viewModel.getRunnerTasks(
          runnerId: UserPermissionService.isAdmin() ? null : currentEmail,
        );

        // Separate tasks into dual streams:
        // 1. Market Find: dealerName is empty or null (hunting across market)
        // 2. Shop Pickups: dealerName is specified (going to specific shop)
        final marketFindTasks = allTasks.where((t) => t.dealerName == null || t.dealerName!.trim().isEmpty).toList();
        final shopPickupTasks = allTasks.where((t) => t.dealerName != null && t.dealerName!.trim().isNotEmpty).toList();

        final pendingMarketCount = marketFindTasks.where((t) => t.status != RequestOrder.statusCollected).length;
        final pendingPickupCount = shopPickupTasks.where((t) => t.status != RequestOrder.statusCollected).length;
        final totalPendingCount = allTasks.where((t) => t.status != RequestOrder.statusCollected).length;

        // Apply stream tab filter (0: All, 1: Market Find, 2: Shop Pickups)
        List<RequestOrder> streamTasks;
        if (_activeStreamTab == 0) {
          streamTasks = allTasks;
        } else if (_activeStreamTab == 1) {
          streamTasks = marketFindTasks;
        } else {
          streamTasks = shopPickupTasks;
        }

        // Extract buildings for route filter chips
        final Set<String> buildings = {'All'};
        for (final t in streamTasks) {
          final b = (t.targetBuilding != null && t.targetBuilding!.trim().isNotEmpty)
              ? t.targetBuilding!.trim()
              : 'Nehru Place Market';
          buildings.add(b);
        }

        // Apply building and status filter
        final filteredTasks = streamTasks.where((t) {
          // Status filter
          if (_statusFilter == 'Pending' && t.status == RequestOrder.statusCollected) {
            return false;
          }
          if (_statusFilter == 'Collected' && t.status != RequestOrder.statusCollected) {
            return false;
          }

          // Building filter
          if (_selectedBuilding != 'All') {
            final b = (t.targetBuilding != null && t.targetBuilding!.trim().isNotEmpty)
                ? t.targetBuilding!.trim()
                : 'Nehru Place Market';
            if (b != _selectedBuilding) return false;
          }

          return true;
        }).toList();

        // Sort: pending first, then newest date, then newest update
        filteredTasks.sort((a, b) {
          final aCollected = a.status == RequestOrder.statusCollected ? 1 : 0;
          final bCollected = b.status == RequestOrder.statusCollected ? 1 : 0;
          if (aCollected != bCollected) return aCollected.compareTo(bCollected);

          final dateComp = b.date.compareTo(a.date);
          if (dateComp != 0) return dateComp;
          final updateComp = b.updatedAt.compareTo(a.updatedAt);
          if (updateComp != 0) return updateComp;
          return b.id.compareTo(a.id);
        });

        return Scaffold(
          backgroundColor: const Color(0xFF0B101D),
          appBar: Navigator.canPop(context) ? AppBar(
            backgroundColor: const Color(0xFF0F1524),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My Tasks',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$totalPendingCount pending · $pendingMarketCount market · $pendingPickupCount pickup',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ) : null,
          body: SafeArea(
            top: !Navigator.canPop(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Page Title (only when embedded as a nav tab, not pushed) ──
                if (!Navigator.canPop(context))
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 16 : 20, isMobile ? 12 : 16, isMobile ? 16 : 20, 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'My Tasks',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$totalPendingCount pending · $pendingMarketCount market find · $pendingPickupCount shop pickup',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),

                // ── Dual-Stream Primary Tabs (Segmented) ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF131A2E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildStreamTabButton(
                            index: 0,
                            icon: Icons.view_agenda_rounded,
                            label: 'All',
                            badgeCount: totalPendingCount,
                            badgeColor: const Color(0xFFA78BFA),
                            isSelected: _activeStreamTab == 0,
                          ),
                        ),
                        Expanded(
                          child: _buildStreamTabButton(
                            index: 1,
                            icon: Icons.search_rounded,
                            label: isMobile ? 'Market' : 'Find in Market',
                            badgeCount: pendingMarketCount,
                            badgeColor: const Color(0xFF3B82F6),
                            isSelected: _activeStreamTab == 1,
                          ),
                        ),
                        Expanded(
                          child: _buildStreamTabButton(
                            index: 2,
                            icon: Icons.storefront_rounded,
                            label: isMobile ? 'Pickup' : 'Shop Pickups',
                            badgeCount: pendingPickupCount,
                            badgeColor: const Color(0xFF10B981),
                            isSelected: _activeStreamTab == 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Sleek Unified Filter Strip (Status & Building Location) ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
                  child: SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        // Status Filters (All first)
                        _buildStatusFilterChip('All', icon: Icons.clear_all_rounded, activeColor: const Color(0xFFA78BFA)),
                        const SizedBox(width: 6),
                        _buildStatusFilterChip('Pending', icon: Icons.schedule_rounded, activeColor: const Color(0xFFF59E0B)),
                        const SizedBox(width: 6),
                        _buildStatusFilterChip('Collected', icon: Icons.check_circle_outline_rounded, activeColor: const Color(0xFF10B981)),

                        if (buildings.length > 1) ...[
                          const SizedBox(width: 8),
                          Center(
                            child: Container(
                              width: 1,
                              height: 16,
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Buildings
                          ...buildings.map((b) {
                            final isSelected = _selectedBuilding == b;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _buildBuildingChip(b, isSelected),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Task Cards List ──
                Expanded(
                  child: filteredTasks.isEmpty
                      ? AppEmptyState(
                          icon: _activeStreamTab == 0
                              ? Icons.search_off_rounded
                              : (_activeStreamTab == 1 ? Icons.storefront_outlined : Icons.check_circle_outline_rounded),
                          title: _activeStreamTab == 0
                              ? 'No Market Search Tasks'
                              : (_activeStreamTab == 1 ? 'No Shop Pickups' : 'No Tasks Found'),
                          message: _statusFilter == 'Pending'
                              ? 'All assigned tasks for this section are collected or completed!'
                              : 'No matching runner tasks in this view.',
                        )
                      : ListView.separated(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 12 : 16,
                            vertical: 6,
                          ),
                          physics: const BouncingScrollPhysics(),
                          itemCount: filteredTasks.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final task = filteredTasks[index];
                            return _buildTaskCard(
                              context: context,
                              task: task,
                              viewModel: viewModel,
                              canMarkCollected: canMarkCollected,
                              isMobile: isMobile,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStreamTabButton({
    required int index,
    required IconData icon,
    required String label,
    required int badgeCount,
    required Color badgeColor,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () => setState(() {
        _activeStreamTab = index;
        _selectedBuilding = 'All';
      }),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? badgeColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? badgeColor.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? badgeColor : AppTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? badgeColor : Colors.white12,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusFilterChip(String status, {required IconData icon, required Color activeColor}) {
    final isSelected = _statusFilter == status;
    return InkWell(
      onTap: () => setState(() => _statusFilter = status),
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.18) : const Color(0xFF131A2E),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isSelected ? activeColor.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? activeColor : AppTheme.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              status,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuildingChip(String building, bool isSelected) {
    const activeColor = Color(0xFF3B82F6);
    final isAll = building == 'All';
    return InkWell(
      onTap: () => setState(() => _selectedBuilding = building),
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.18) : const Color(0xFF131A2E),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isSelected ? const Color(0xFF60A5FA).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAll ? Icons.location_on_outlined : Icons.apartment_rounded,
              size: 13,
              color: isSelected ? const Color(0xFF60A5FA) : AppTheme.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              isAll ? 'All Locations' : building,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard({
    required BuildContext context,
    required RequestOrder task,
    required RequestsViewModel viewModel,
    required bool canMarkCollected,
    required bool isMobile,
  }) {
    final isCollected = task.status == RequestOrder.statusCollected;
    final isPickup = task.dealerName != null && task.dealerName!.trim().isNotEmpty;
    final building = (task.targetBuilding != null && task.targetBuilding!.trim().isNotEmpty)
        ? task.targetBuilding!.trim()
        : 'Nehru Place Market';
    final shopNo = task.targetShopNo;

    // Classify hardware item to extract specs and category
    final classification = ItemCategoryDetector.classify(task.item);

    return Container(
      decoration: BoxDecoration(
        color: isCollected ? const Color(0x1210B981) : const Color(0xFF131A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCollected
              ? const Color(0x4410B981)
              : (isPickup
                  ? const Color(0xFF10B981).withValues(alpha: 0.25)
                  : const Color(0xFF3B82F6).withValues(alpha: 0.25)),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stream Badge & Order Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stream Tag Chip (Find in Market vs Shop Pickup)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPickup
                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                        : const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isPickup
                          ? const Color(0xFF10B981).withValues(alpha: 0.4)
                          : const Color(0xFF3B82F6).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPickup ? Icons.storefront_rounded : Icons.search_rounded,
                        size: 12,
                        color: isPickup ? const Color(0xFF34D399) : const Color(0xFF60A5FA),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isPickup ? 'SHOP PICKUP' : 'FIND IN MARKET',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isPickup ? const Color(0xFF34D399) : const Color(0xFF60A5FA),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isCollected ? const Color(0x2A10B981) : const Color(0x2AF59E0B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCollected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                  ),
                  child: Text(
                    isCollected ? 'COLLECTED' : 'PENDING',
                    style: TextStyle(
                      color: isCollected ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Item Title & Order Subtitle ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.item,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      'Req #${task.id} • Customer: ${task.customerName}',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                    if (task.advance > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '• Adv: ₹${task.advance.toStringAsFixed(0)}',
                        style: const TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // ── Inline Photo Previews (Full Row with Zoom) ──
          if (task.photoList.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: task.photoList.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final photoUrl = task.photoList[i];
                    return GestureDetector(
                      onTap: () => AppPhotoViewerDialog.show(
                        context,
                        photoUrls: task.photoList,
                        initialIndex: i,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            Image.network(
                              photoUrl,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 72,
                                height: 72,
                                color: Colors.white10,
                                child: const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 22),
                              ),
                            ),
                            Positioned(
                              bottom: 3,
                              right: 3,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],

          // ── Specifications & Staff Notes Container ──
          if ((task.estimate != null && task.estimate!.trim().isNotEmpty) || classification.specTokens.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1524),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.fact_check_outlined, size: 14, color: Color(0xFF93C5FD)),
                        const SizedBox(width: 6),
                        const Text(
                          'Staff Specs & Notes',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF93C5FD),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            classification.category.name.toUpperCase(),
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA)),
                          ),
                        ),
                      ],
                    ),
                    if (task.estimate != null && task.estimate!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.estimate!,
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.textPrimary, height: 1.3),
                      ),
                    ],
                    if (classification.specTokens.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final token in classification.specTokens)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                token,
                                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // ── Location & Target Details ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: isPickup
                ? InkWell(
                    onTap: () => _launchMaps(building, shopNo),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                      ),
                      child: Row(
                      children: [
                        const Icon(Icons.storefront_rounded, color: Color(0xFF34D399), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.dealerName!,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$building ${shopNo != null && shopNo.isNotEmpty ? '• Shop $shopNo' : ''}',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Maps',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                            ),
                            Icon(Icons.directions_outlined, size: 15, color: Color(0xFF34D399)),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
                // Market Sourcing Area Box
                : InkWell(
                    onTap: () => _launchMaps(building, null),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded, color: Color(0xFF60A5FA), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Search in Physical Market',
                                  style: TextStyle(
                                    color: Color(0xFF60A5FA),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  'Target Area: $building',
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Area',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA)),
                              ),
                              Icon(Icons.directions_outlined, size: 15, color: Color(0xFF60A5FA)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 12),

          // ── Action Buttons Footer ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                // Quick Call button if dealer mobile exists
                if (task.mobileNo != null && task.mobileNo!.trim().isNotEmpty) ...[
                  IconButton(
                    onPressed: () => _launchCall(task.mobileNo),
                    icon: const Icon(Icons.phone_rounded, color: Color(0xFF34D399), size: 18),
                    tooltip: 'Call Dealer',
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x2210B981),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _launchWhatsApp(task.mobileNo, task.item),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF22D3EE), size: 18),
                    tooltip: 'WhatsApp Dealer',
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x2206B6D4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                const Spacer(),

                // Mark Collected / Record Found Action
                if (!isCollected && canMarkCollected)
                  ElevatedButton.icon(
                    onPressed: () => _showCollectModal(context, viewModel, task),
                    icon: Icon(
                      isPickup ? Icons.done_all_rounded : Icons.check_circle_outline_rounded,
                      size: 16,
                    ),
                    label: Text(
                      isPickup ? 'Mark Collected' : 'Found & Collect',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPickup ? const Color(0xFF059669) : const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectTaskModal extends StatefulWidget {
  final RequestOrder request;
  final RequestsViewModel viewModel;

  const _CollectTaskModal({required this.request, required this.viewModel});

  @override
  State<_CollectTaskModal> createState() => _CollectTaskModalState();
}

class _CollectTaskModalState extends State<_CollectTaskModal> {
  final _costController = TextEditingController();
  late final TextEditingController _dealerController;
  late final TextEditingController _buildingController;
  late final TextEditingController _shopNoController;
  String? _billPhotoUrl;

  @override
  void initState() {
    super.initState();
    if (widget.request.advance > 0) {
      _costController.text = widget.request.advance.toStringAsFixed(0);
    }
    _dealerController = TextEditingController(text: widget.request.dealerName ?? '');
    _buildingController = TextEditingController(text: widget.request.targetBuilding ?? 'Nehru Place Market');
    _shopNoController = TextEditingController(text: widget.request.targetShopNo ?? '');
  }

  @override
  void dispose() {
    _costController.dispose();
    _dealerController.dispose();
    _buildingController.dispose();
    _shopNoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMarketFind = widget.request.dealerName == null || widget.request.dealerName!.trim().isEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0x2210B981),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMarketFind ? 'Found in Market & Collect' : 'Confirm Part Pickup',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.request.item,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Colors.white10),
            const SizedBox(height: 16),

            // If found in market, allow recording which dealer/shop it was purchased from
            if (isMarketFind) ...[
              TextFormField(
                controller: _dealerController,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Purchased from Dealer / Shop Name',
                  hintText: 'e.g. Caviar Technologies, Pro Lab',
                  prefixIcon: Icon(Icons.storefront_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _buildingController,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Building',
                        hintText: 'e.g. Meghdoot Building',
                        prefixIcon: Icon(Icons.location_city_rounded, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _shopNoController,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Shop No',
                        hintText: 'e.g. 204',
                        prefixIcon: Icon(Icons.room_rounded, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // Actual Purchase Cost Input
            TextFormField(
              controller: _costController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              decoration: const InputDecoration(
                labelText: 'Actual Purchase Cost (₹) *',
                hintText: 'Enter final price paid to dealer',
                prefixIcon: Icon(Icons.currency_rupee_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 16),

            // Bill Photo Attachment Widget
            PhotoAttachmentWidget(
              initialPhotoUrl: _billPhotoUrl,
              onPhotoChanged: (url) => setState(() => _billPhotoUrl = url),
              label: 'Attach Dealer Invoice / Receipt Photo',
            ),
            const SizedBox(height: 20),

            // Confirm Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final cost = double.tryParse(_costController.text.trim()) ?? widget.request.advance;
                  final dealer = _dealerController.text.trim();
                  final bldg = _buildingController.text.trim();
                  final shop = _shopNoController.text.trim();

                  // If dealer info was specified, persist dealer details to request
                  if (dealer.isNotEmpty && dealer != widget.request.dealerName) {
                    await widget.viewModel.assignRunner(
                      requestId: widget.request.id,
                      runnerId: widget.request.assignedRunnerId ?? '',
                      runnerName: widget.request.assignedRunnerName ?? '',
                      dealerName: dealer,
                      building: bldg.isNotEmpty ? bldg : null,
                      shopNo: shop.isNotEmpty ? shop : null,
                    );
                  }

                  await widget.viewModel.markCollected(
                    requestId: widget.request.id,
                    actualCost: cost,
                    billPhoto: _billPhotoUrl,
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Marked "${widget.request.item}" as Collected!'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('Confirm Pickup & Update Shop'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

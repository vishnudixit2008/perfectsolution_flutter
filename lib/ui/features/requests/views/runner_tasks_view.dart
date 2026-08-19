import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/models/request_order.dart';
import '../../../../data/services/user_permission_service.dart';
import '../../../../ui/core/app_theme.dart';
import '../../../../ui/core/motion/motion.dart';
import '../../../shared/app_photo_viewer_dialog.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_page_header.dart';
import '../../../shared/photo_attachment_widget.dart';
import '../view_models/requests_view_model.dart';

class RunnerTasksView extends StatefulWidget {
  const RunnerTasksView({super.key});

  @override
  State<RunnerTasksView> createState() => _RunnerTasksViewState();
}

class _RunnerTasksViewState extends State<RunnerTasksView> {
  String _selectedBuilding = 'All';

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

    return Consumer<RequestsViewModel>(
      builder: (context, viewModel, child) {
        final allTasks = viewModel.getRunnerTasks(
          runnerId: UserPermissionService.isAdmin() ? null : currentEmail,
        );

        // Extract buildings for route tabs
        final Set<String> buildings = {'All'};
        for (final t in allTasks) {
          final b = (t.targetBuilding != null && t.targetBuilding!.trim().isNotEmpty)
              ? t.targetBuilding!.trim()
              : 'Nehru Place Market';
          buildings.add(b);
        }

        final filteredTasks = allTasks.where((t) {
          if (_selectedBuilding == 'All') return true;
          final b = (t.targetBuilding != null && t.targetBuilding!.trim().isNotEmpty)
              ? t.targetBuilding!.trim()
              : 'Nehru Place Market';
          return b == _selectedBuilding;
        }).toList();

        final pendingCount = allTasks.where((t) => t.status == RequestOrder.statusRunnerAssigned).length;
        final collectedCount = allTasks.where((t) => t.status == RequestOrder.statusCollected).length;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: 'Market Runner Route',
                subtitle: '$pendingCount Pending Pickups • $collectedCount Collected',
              ),

              // Building Route Stacks Filter Bar
              if (buildings.length > 1)
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: buildings.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final b = buildings.elementAt(idx);
                      final isSelected = _selectedBuilding == b;
                      final count = b == 'All'
                          ? allTasks.length
                          : allTasks.where((t) => (t.targetBuilding ?? 'Nehru Place Market') == b).length;

                      return FilterChip(
                        selected: isSelected,
                        label: Text('$b ($count)'),
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : AppTheme.textSecondary,
                        ),
                        backgroundColor: const Color(0xFF131A2E),
                        selectedColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? AppTheme.primaryLight : Colors.white10,
                          ),
                        ),
                        onSelected: (_) => setState(() => _selectedBuilding = b),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 10),

              // Task Cards List
              Expanded(
                child: filteredTasks.isEmpty
                    ? const AppEmptyState(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'No Pending Pickups',
                        message: 'All assigned market tasks are collected or completed.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        physics: const BouncingScrollPhysics(),
                        itemCount: filteredTasks.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final task = filteredTasks[index];
                          final isCollected = task.status == RequestOrder.statusCollected;
                          final building = task.targetBuilding ?? 'Nehru Place';
                          final shopNo = task.targetShopNo;

                          return BouncyPressable(
                            onTap: () {
                              if (!isCollected && canMarkCollected) {
                                _showCollectModal(context, viewModel, task);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isCollected
                                    ? const Color(0x1A10B981)
                                    : const Color(0xFF131A2E),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isCollected
                                      ? const Color(0x6610B981)
                                      : const Color(0xFF3B82F6).withValues(alpha: 0.3),
                                  width: 1.2,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top Row: Item Title & Status Badge
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              task.item,
                                              style: const TextStyle(
                                                color: AppTheme.textPrimary,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'Order #${task.id} • For ${task.customerName}',
                                              style: const TextStyle(
                                                color: AppTheme.textMuted,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isCollected
                                              ? const Color(0x3310B981)
                                              : const Color(0x333B82F6),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isCollected
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFF3B82F6),
                                          ),
                                        ),
                                        child: Text(
                                          isCollected ? 'COLLECTED' : 'PICKUP PENDING',
                                          style: TextStyle(
                                            color: isCollected
                                                ? const Color(0xFF34D399)
                                                : const Color(0xFF60A5FA),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 12),

                                  // 1-Tap Building & Location Banner
                                  InkWell(
                                    onTap: () => _launchMaps(building, shopNo),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.white10),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on_rounded,
                                            color: Color(0xFFF87171),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '$building ${shopNo != null && shopNo.isNotEmpty ? '($shopNo)' : ''}',
                                              style: const TextStyle(
                                                color: AppTheme.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          const Text(
                                            'Directions ➔',
                                            style: TextStyle(
                                              color: AppTheme.primaryLight,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  // Dealer Name & Photo Comparison Row
                                  Row(
                                    children: [
                                      if (task.dealerName != null && task.dealerName!.isNotEmpty) ...[
                                        const Icon(Icons.storefront_rounded, size: 15, color: AppTheme.textMuted),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            task.dealerName!,
                                            style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 12.5,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                      if (task.photoList.isNotEmpty)
                                        TextButton.icon(
                                          onPressed: () {
                                            AppPhotoViewerDialog.show(
                                              context,
                                              photoUrls: task.photoList,
                                            );
                                          },
                                          icon: const Icon(Icons.image_search_rounded, size: 16),
                                          label: Text(
                                            'View Photo (${task.photoList.length})',
                                            style: const TextStyle(fontSize: 11.5),
                                          ),
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppTheme.primaryLight,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                          ),
                                        ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),

                                  // Quick Action Buttons
                                  Row(
                                    children: [
                                      if (task.mobileNo != null && task.mobileNo!.isNotEmpty) ...[
                                        IconButton(
                                          onPressed: () => _launchCall(task.mobileNo),
                                          icon: const Icon(Icons.phone_rounded, color: Color(0xFF34D399), size: 20),
                                          tooltip: 'Call Dealer',
                                          style: IconButton.styleFrom(
                                            backgroundColor: const Color(0x2210B981),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          onPressed: () => _launchWhatsApp(task.mobileNo, task.item),
                                          icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF22D3EE), size: 20),
                                          tooltip: 'WhatsApp Dealer',
                                          style: IconButton.styleFrom(
                                            backgroundColor: const Color(0x2206B6D4),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      const Spacer(),
                                      if (!isCollected && canMarkCollected)
                                        ElevatedButton.icon(
                                          onPressed: () => _showCollectModal(context, viewModel, task),
                                          icon: const Icon(Icons.check_rounded, size: 16),
                                          label: const Text('Mark Collected'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.primary,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                      ),
              ),
            ],
          ),
        );
      },
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
  String? _billPhotoUrl;

  @override
  void initState() {
    super.initState();
    if (widget.request.advance > 0) {
      _costController.text = widget.request.advance.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _costController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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
                    const Text(
                      'Confirm Part Collection',
                      style: TextStyle(
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
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

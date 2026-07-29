import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../../data/services/supabase_sync_service.dart';
import '../../../data/repositories/shop_repository.dart';
import '../../navigation/navigation_view_model.dart';
import '../../features/calls/view_models/calls_view_model.dart';
import '../../features/inward_repairs/view_models/inward_repairs_view_model.dart';
import '../../features/replacements/view_models/replacements_view_model.dart';
import '../../features/requests/view_models/requests_view_model.dart';
import '../../features/purchases/view_models/purchases_view_model.dart';
import '../../features/dashboard/view_models/recent_sales_view_model.dart';

class AppPageHeader extends StatefulWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions,
  });

  @override
  State<AppPageHeader> createState() => _AppPageHeaderState();
}

class _AppPageHeaderState extends State<AppPageHeader> {
  bool _isManualSyncing = false;

  Future<void> _triggerManualSync(BuildContext context) async {
    if (_isManualSyncing) return;
    setState(() => _isManualSyncing = true);
    try {
      final localDb = context.read<ShopRepository>().localDb;
      await SupabaseSyncService.instance.manualSync(localDb);
      if (context.mounted) {
        context.read<NavigationViewModel>().notifySync();
        try {
          context.read<CallsViewModel>().loadCalls();
        } catch (_) {}
        try {
          context.read<InwardRepairsViewModel>().loadRepairs();
        } catch (_) {}
        try {
          context.read<ReplacementsViewModel>().loadReplacements();
        } catch (_) {}
        try {
          context.read<RequestsViewModel>().loadRequests();
        } catch (_) {}
        try {
          context.read<PurchasesViewModel>().loadPurchases();
        } catch (_) {}
        try {
          context.read<RecentSalesViewModel>().loadSales();
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _isManualSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.onBack != null) ...[
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppTheme.textPrimary,
                    size: 22,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: -0.5,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 2,
                  softWrap: true,
                ),
              ),
              const SizedBox(width: 8),
              _buildSyncBadge(context),
              if (widget.actions != null && widget.actions!.isNotEmpty) ...[
                const SizedBox(width: 6),
                ...widget.actions!,
              ],
            ],
          ),
          if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.subtitle!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 2,
              softWrap: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncBadge(BuildContext context) {
    return Consumer<SupabaseSyncService>(
      builder: (context, syncService, _) {
        final isSynced = syncService.status == SyncStatus.synced;
        final isSyncing =
            syncService.status == SyncStatus.syncing || _isManualSyncing;
        final statusColor = isSynced
            ? AppTheme.success
            : isSyncing
            ? AppTheme.primaryLight
            : AppTheme.warning;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _triggerManualSync(context),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSyncing)
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: statusColor,
                      ),
                    )
                  else
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    isSynced ? 'Sync' : (isSyncing ? 'Syncing' : 'Sync'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
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

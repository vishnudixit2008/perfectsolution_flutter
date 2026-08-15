import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/repositories/shop_repository.dart';
import '../../../data/services/supabase_sync_service.dart';
import '../../core/app_theme.dart';

class AppHeaderSyncButton extends StatefulWidget {
  final VoidCallback? onSynced;

  const AppHeaderSyncButton({super.key, this.onSynced});

  @override
  State<AppHeaderSyncButton> createState() => _AppHeaderSyncButtonState();
}

class _AppHeaderSyncButtonState extends State<AppHeaderSyncButton> {
  bool _isManualSyncing = false;

  Future<void> _triggerSync(BuildContext context) async {
    if (_isManualSyncing) return;
    final syncService = SupabaseSyncService.instance;

    // If currently in error state, tapping shows detailed error dialog
    if (syncService.status == SyncStatus.error) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F1524),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.3)),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
              SizedBox(width: 8),
              Text(
                'Cloud Sync Details',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Diagnostic details from the latest sync attempt:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  syncService.statusMessage.isEmpty
                      ? 'Unknown sync error occurred.'
                      : syncService.statusMessage,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: AppTheme.danger,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _performManualSync(context);
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry Sync'),
            ),
          ],
        ),
      );
      return;
    }

    await _performManualSync(context, forceFullDownload: false);
  }

  Future<void> _performManualSync(BuildContext context, {bool forceFullDownload = false}) async {
    if (_isManualSyncing) return;
    final syncService = SupabaseSyncService.instance;

    setState(() => _isManualSyncing = true);
    try {
      final localDb = context.read<ShopRepository>().localDb;
      await syncService.manualSync(localDb, forceFullDownload: forceFullDownload);
      if (mounted) {
        if (syncService.status == SyncStatus.synced) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(forceFullDownload
                  ? 'Full database re-synced successfully!'
                  : 'Fast sync & UI refreshed successfully!'),
              backgroundColor: AppTheme.success,
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (syncService.status == SyncStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync Failed: ${syncService.statusMessage}'),
              backgroundColor: AppTheme.danger,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        if (widget.onSynced != null) {
          widget.onSynced!();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync Exception: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isManualSyncing = false);
      }
    }
  }

  void _showSyncOptionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1524),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: const Row(
          children: [
            Icon(Icons.sync_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Cloud Sync Options', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose sync mode:',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bolt_rounded, color: AppTheme.success),
              title: const Text('Quick Delta Sync', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: const Text('Fetches only new changes + refreshes screen (0 cloud bandwidth)', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _performManualSync(context, forceFullDownload: false);
              },
            ),
            const Divider(color: Colors.white12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_download_rounded, color: Colors.orange),
              title: const Text('Force Full Database Re-Sync', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: const Text('Downloads 100% of all tables from cloud from scratch', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _performManualSync(context, forceFullDownload: true);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SupabaseSyncService>(
      builder: (context, syncService, _) {
        final isSynced = syncService.status == SyncStatus.synced;
        final isSyncing =
            syncService.status == SyncStatus.syncing || _isManualSyncing;
        final isError = syncService.status == SyncStatus.error;

        final Color statusColor = isSynced
            ? AppTheme.success
            : isSyncing
            ? AppTheme.primaryLight
            : isError
            ? AppTheme.danger
            : AppTheme.warning;

        final String statusText = isSyncing
            ? 'Syncing...'
            : isSynced
            ? 'Synced'
            : isError
            ? 'Sync Error'
            : 'Offline';

        final IconData statusIcon = isSynced
            ? Icons.cloud_done_rounded
            : isError
            ? Icons.cloud_off_rounded
            : Icons.cloud_sync_rounded;

        final String tooltipMessage = isError
            ? 'Cloud Sync Error: ${syncService.statusMessage}. Tap to retry.'
            : isSynced
            ? 'All changes synced to cloud. Tap to manual sync.'
            : isSyncing
            ? 'Syncing data with cloud...'
            : 'Offline mode. Tap to trigger cloud sync.';

        return Tooltip(
          message: tooltipMessage,
          child: InkWell(
            onTap: () => _triggerSync(context),
            onLongPress: () => _showSyncOptionsDialog(context),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSyncing)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: statusColor,
                      ),
                    )
                  else
                    Icon(
                      statusIcon,
                      size: 14,
                      color: statusColor,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                      letterSpacing: 0.2,
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

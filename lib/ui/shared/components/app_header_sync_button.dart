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

    // If currently in error state, tapping shows detailed error dialog/snackbar
    if (syncService.status == SyncStatus.error && syncService.statusMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync Error: ${syncService.statusMessage}'),
          backgroundColor: AppTheme.danger,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _triggerSync(context),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    setState(() => _isManualSyncing = true);
    try {
      final localDb = context.read<ShopRepository>().localDb;
      await syncService.manualSync(localDb);
      if (mounted) {
        if (syncService.status == SyncStatus.synced) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cloud sync completed successfully!'),
              backgroundColor: AppTheme.success,
              duration: Duration(seconds: 2),
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
      if (mounted) setState(() => _isManualSyncing = false);
    }
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

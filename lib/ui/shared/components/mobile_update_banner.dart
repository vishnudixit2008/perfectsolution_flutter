import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/auto_update_service.dart';
import '../../core/app_theme.dart';
import '../../core/motion/bouncy_pressable.dart';

/// A sleek, non-intrusive mobile bottom banner for OTA app updates.
/// Stays above the bottom navigation bar without blocking app usage.
/// Users can click 'Relaunch & Update' whenever they are ready.
class MobileUpdateBanner extends StatelessWidget {
  const MobileUpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoUpdateService>(
      builder: (context, updateService, _) {
        final status = updateService.status;

        // Hidden when idle or just checking
        if (status == AutoUpdateStatus.idle || status == AutoUpdateStatus.checking) {
          return const SizedBox.shrink();
        }

        final version = updateService.updateInfo?.latestVersion ?? '';
        final progress = updateService.downloadProgress;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: status == AutoUpdateStatus.readyToRelaunch
                ? const Color(0xFF0F1B2E)
                : status == AutoUpdateStatus.error
                    ? AppTheme.danger.withValues(alpha: 0.15)
                    : const Color(0xFF131A2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: status == AutoUpdateStatus.readyToRelaunch
                  ? const Color(0xFF3B82F6).withValues(alpha: 0.5)
                  : status == AutoUpdateStatus.error
                      ? AppTheme.danger.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.1),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: (status == AutoUpdateStatus.readyToRelaunch
                        ? const Color(0xFF3B82F6)
                        : Colors.black)
                    .withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == AutoUpdateStatus.downloading) ...[
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFF60A5FA),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'DOWNLOADING UPDATE v$version',
                                style: const TextStyle(
                                  color: Color(0xFF93C5FD),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                progress != null ? '${progress.percentage}%' : '',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: progress != null && progress.progress > 0
                                  ? progress.progress
                                  : null,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF3B82F6),
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textMuted),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      tooltip: 'Cancel',
                      onPressed: () => updateService.cancelDownload(),
                    ),
                  ],
                ),
              ] else if (status == AutoUpdateStatus.readyToRelaunch) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UPDATE READY',
                            style: TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Version $version ready to apply',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    BouncyPressable(
                      scaleFactor: 0.94,
                      onTap: () => _confirmRelaunch(context, updateService, version),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.restart_alt_rounded, color: Colors.white, size: 15),
                            SizedBox(width: 5),
                            Text(
                              'Relaunch',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (status == AutoUpdateStatus.installing) ...[
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      updateService.installStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ] else if (status == AutoUpdateStatus.error) ...[
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: AppTheme.danger),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Update download failed',
                        style: TextStyle(
                          color: AppTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF60A5FA)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      tooltip: 'Retry',
                      onPressed: () => updateService.retry(),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _confirmRelaunch(BuildContext context, AutoUpdateService updateService, String version) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: const Row(
          children: [
            Icon(Icons.system_update_rounded, color: Color(0xFF60A5FA), size: 22),
            SizedBox(width: 10),
            Text(
              'Relaunch & Update',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Perfect Solution v$version is downloaded and ready to install.\n\nUpdating will take just a few seconds and all your active data is preserved.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              updateService.relaunchAndInstall();
            },
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('Relaunch Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

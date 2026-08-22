import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/auto_update_service.dart';
import '../../core/app_theme.dart';
import '../../core/motion/bouncy_pressable.dart';

class DesktopUpdateProgressWidget extends StatelessWidget {
  const DesktopUpdateProgressWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoUpdateService>(
      builder: (context, updateService, _) {
        final status = updateService.status;

        // Only display if there is active update activity (downloading, ready to relaunch, installing, or error)
        if (status == AutoUpdateStatus.idle || status == AutoUpdateStatus.checking) {
          return const SizedBox.shrink();
        }

        final version = updateService.updateInfo?.latestVersion ?? '';
        final progress = updateService.downloadProgress;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: status == AutoUpdateStatus.readyToRelaunch
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : status == AutoUpdateStatus.error
                      ? AppTheme.danger.withValues(alpha: 0.1)
                      : const Color(0xFF131A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: status == AutoUpdateStatus.readyToRelaunch
                    ? AppTheme.primaryLight.withValues(alpha: 0.4)
                    : status == AutoUpdateStatus.error
                        ? AppTheme.danger.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (status == AutoUpdateStatus.readyToRelaunch
                          ? AppTheme.primary
                          : Colors.black)
                      .withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header / Status
                if (status == AutoUpdateStatus.downloading) ...[
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Downloading Update v$version',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 14, color: AppTheme.textMuted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                        tooltip: 'Cancel Download',
                        onPressed: () => updateService.cancelDownload(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress != null && progress.progress > 0
                          ? progress.progress
                          : null,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        progress != null
                            ? '${progress.percentage}% · ${progress.receivedMb}/${progress.totalMb} MB'
                            : 'Starting...',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                      ),
                      if (progress != null && progress.speedFormatted.isNotEmpty)
                        Text(
                          progress.speedFormatted,
                          style: const TextStyle(
                            color: AppTheme.primaryLight,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ] else if (status == AutoUpdateStatus.readyToRelaunch) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.system_update_rounded,
                          color: AppTheme.primaryLight,
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'UPDATE READY',
                              style: TextStyle(
                                color: AppTheme.primaryLight,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Version $version',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: BouncyPressable(
                      onTap: () => _confirmRelaunch(context, updateService, version),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primary, Color(0xFF6366F1)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(7),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.restart_alt_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text(
                              'Relaunch & Update',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else if (status == AutoUpdateStatus.installing) ...[
                  const Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryLight,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Relaunching application...',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ] else if (status == AutoUpdateStatus.error) ...[
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 14, color: AppTheme.danger),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Update Download Failed',
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 14, color: AppTheme.primaryLight),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                        tooltip: 'Retry Download',
                        onPressed: () => updateService.retry(),
                      ),
                    ],
                  ),
                  if (updateService.errorMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      updateService.errorMessage!,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ],
            ),
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
            Icon(Icons.system_update_rounded, color: AppTheme.primaryLight, size: 22),
            SizedBox(width: 10),
            Text(
              'Relaunch & Update',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Perfect Solution v$version has been downloaded and is ready to install.\n\nThe application will relaunch automatically with the new version.',
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
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/services/update_check_service.dart';
import '../core/app_theme.dart';

class UpdateDialog extends StatelessWidget {
  final AppVersionStatus status;

  const UpdateDialog({super.key, required this.status});

  static Future<void> showIfNeeded(BuildContext context) async {
    final updateStatus = await UpdateCheckService.checkForUpdates();
    if (updateStatus != null && updateStatus.hasUpdate && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: !updateStatus.isMandatory,
        builder: (ctx) => UpdateDialog(status: updateStatus),
      );
    }
  }

  Future<void> _launchDownloadUrl(BuildContext context) async {
    if (status.downloadUrl.isNotEmpty) {
      final uri = Uri.parse(status.downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download link is not available yet. Please check back shortly.'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !status.isMandatory,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF131A2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: status.isMandatory
                    ? Colors.redAccent.withValues(alpha: 0.6)
                    : AppTheme.primaryLight.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (status.isMandatory ? Colors.red : AppTheme.primary)
                      .withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Badge & Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (status.isMandatory ? Colors.redAccent : AppTheme.primary)
                            .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        status.isMandatory
                            ? Icons.system_security_update_warning_rounded
                            : Icons.system_update_rounded,
                        color: status.isMandatory ? Colors.redAccent : AppTheme.primaryLight,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status.isMandatory
                                ? 'MANDATORY UPDATE REQUIRED'
                                : 'NEW UPDATE AVAILABLE',
                            style: TextStyle(
                              color: status.isMandatory
                                  ? Colors.redAccent
                                  : AppTheme.primaryLight,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Version ${status.latestVersion}',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                const SizedBox(height: 12),

                // Version Details & Release Notes
                Row(
                  children: [
                    Text(
                      'Installed: v${status.currentVersion}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Latest: v${status.latestVersion}',
                        style: const TextStyle(
                          color: AppTheme.success,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (status.releaseNotes.isNotEmpty) ...[
                  const Text(
                    'Release Notes:',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        status.releaseNotes,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!status.isMandatory) ...[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Skip for Now',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _launchDownloadUrl(context),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          status.isMandatory ? 'Update Now (Required)' : 'Update Now',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: status.isMandatory
                              ? Colors.redAccent
                              : AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

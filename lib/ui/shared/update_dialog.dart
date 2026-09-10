import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/services/app_update_downloader.dart';
import '../../data/services/update_check_service.dart';
import '../core/app_theme.dart';

enum _UpdateDialogStage {
  info,
  downloading,
  installing,
  error,
}

class UpdateDialog extends StatefulWidget {
  final AppVersionStatus status;

  const UpdateDialog({super.key, required this.status});

  static Future<void> showIfNeeded(
    BuildContext context, {
    bool isAppLaunch = false,
    bool forceCheck = false,
  }) async {
    // Desktop (Windows & macOS) uses silent background download + sidebar "Relaunch & Update" widget
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS)) {
      return;
    }
    final updateStatus = await UpdateCheckService.checkForUpdates(
      isAppLaunch: isAppLaunch,
      forceCheck: forceCheck,
    );
    if (updateStatus != null && updateStatus.hasUpdate && context.mounted) {
      // For non-mandatory updates: Do NOT show a popup dialog.
      // AutoUpdateService automatically downloads the update in the background,
      // and the bottom banner (MobileUpdateBanner) displays the download progress
      // and the 'Relaunch to Update' button when ready.
      // Only show the modal popup dialog if the update is MANDATORY or manually triggered (forceCheck).
      if (!updateStatus.isMandatory && !forceCheck) {
        return;
      }
      showDialog(
        context: context,
        barrierDismissible: !updateStatus.isMandatory,
        builder: (ctx) => UpdateDialog(status: updateStatus),
      );
    }
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdateDialogStage _stage = _UpdateDialogStage.info;
  final AppUpdateDownloader _downloader = AppUpdateDownloader();

  double _progress = 0.0;
  String _receivedMb = '0.0';
  String _totalMb = '??';
  String _speedText = '';
  String _statusText = 'Starting download...';
  String? _errorMessage;

  @override
  void dispose() {
    _downloader.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (widget.status.downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download URL is currently unavailable.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    setState(() {
      _stage = _UpdateDialogStage.downloading;
      _progress = 0.0;
      _errorMessage = null;
      _statusText = 'Connecting to update server...';
    });

    try {
      final downloadedFile = await _downloader.downloadUpdate(
        downloadUrl: widget.status.downloadUrl,
        version: widget.status.latestVersion,
        onProgress: (DownloadProgress p) {
          if (!mounted) return;
          setState(() {
            _progress = p.progress;
            _receivedMb = p.receivedMb;
            _totalMb = p.totalMb;
            _speedText = p.speedFormatted;
            _statusText = p.status;
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _stage = _UpdateDialogStage.installing;
        _statusText = 'Launching installer...';
      });

      await Future.delayed(const Duration(milliseconds: 300));
      final bool launched = await AppUpdateDownloader.launchInstaller(downloadedFile);

      if (!mounted) return;

      if (launched) {
        if (!kIsWeb && Platform.isWindows) {
          // On Windows, gracefully terminate current process after launching setup
          await Future.delayed(const Duration(seconds: 1));
          exit(0);
        } else if (!kIsWeb && Platform.isAndroid) {
          Navigator.of(context, rootNavigator: true).pop();
        } else if (!kIsWeb && Platform.isMacOS) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      } else {
        setState(() {
          _stage = _UpdateDialogStage.error;
          _errorMessage = 'Could not start OS installer automatically. Please use browser fallback.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdateDialogStage.error;
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  Future<void> _fallbackBrowserDownload() async {
    final url = widget.status.downloadUrl;
    if (url.isNotEmpty) {
      final uri = Uri.parse(url);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open browser: $e'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMandatory = widget.status.isMandatory;
    final isDownloading = _stage == _UpdateDialogStage.downloading;

    return PopScope(
      canPop: !isMandatory && !isDownloading,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF131A2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isMandatory
                    ? Colors.redAccent.withValues(alpha: 0.6)
                    : AppTheme.primaryLight.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isMandatory ? Colors.red : AppTheme.primary)
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
                // Header
                _buildHeader(isMandatory),
                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                const SizedBox(height: 12),

                // Content based on stage
                if (_stage == _UpdateDialogStage.info) _buildInfoStage(),
                if (_stage == _UpdateDialogStage.downloading) _buildDownloadingStage(),
                if (_stage == _UpdateDialogStage.installing) _buildInstallingStage(),
                if (_stage == _UpdateDialogStage.error) _buildErrorStage(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMandatory) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isMandatory ? Colors.redAccent : AppTheme.primary)
                .withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isMandatory
                ? Icons.system_security_update_warning_rounded
                : Icons.system_update_rounded,
            color: isMandatory ? Colors.redAccent : AppTheme.primaryLight,
            size: 28,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMandatory
                    ? 'MANDATORY UPDATE REQUIRED'
                    : 'NEW UPDATE AVAILABLE',
                style: TextStyle(
                  color: isMandatory
                      ? Colors.redAccent
                      : AppTheme.primaryLight,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Version ${widget.status.latestVersion}',
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
    );
  }

  Widget _buildInfoStage() {
    final status = widget.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Installed: v${status.currentVersion}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
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
        const SizedBox(height: 14),

        if (status.releaseNotes.isNotEmpty) ...[
          const Text(
            'What\'s New:',
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

        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!status.isMandatory) ...[
              TextButton(
                onPressed: () {
                  UpdateCheckService.recordSkip();
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Skip for Now',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _startDownload,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  status.isMandatory ? 'Update Now (Required)' : 'Download & Install',
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
    );
  }

  Widget _buildDownloadingStage() {
    final int percent = (_progress * 100).clamp(0, 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _statusText,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$percent%',
              style: const TextStyle(
                color: AppTheme.primaryLight,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            minHeight: 10,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryLight),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$_receivedMb MB / $_totalMb MB',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            if (_speedText.isNotEmpty)
              Text(
                _speedText,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!widget.status.isMandatory)
              TextButton(
                onPressed: () {
                  _downloader.cancel();
                  setState(() => _stage = _UpdateDialogStage.info);
                },
                child: const Text('Cancel Download', style: TextStyle(color: AppTheme.danger)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildInstallingStage() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(
              color: AppTheme.primaryLight,
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            const Text(
              'Preparing Installation...',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              !kIsWeb && Platform.isWindows
                  ? 'The app will restart automatically.'
                  : 'Follow the system prompt to complete update.',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorMessage ?? 'An error occurred during update download.',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _fallbackBrowserDownload,
                icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                label: const Text('Browser Download'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _startDownload,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

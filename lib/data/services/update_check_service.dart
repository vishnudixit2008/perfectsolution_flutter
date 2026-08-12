import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ui_preferences_service.dart';

class AppVersionStatus {
  final String currentVersion;
  final String latestVersion;
  final String minRequiredVersion;
  final bool isMandatory;
  final String downloadUrl;
  final String releaseNotes;
  final bool hasUpdate;

  AppVersionStatus({
    required this.currentVersion,
    required this.latestVersion,
    required this.minRequiredVersion,
    required this.isMandatory,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.hasUpdate,
  });
}

class UpdateCheckService {
  static String get currentPlatform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      default:
        return 'other';
    }
  }

  /// Compares semantic versions (e.g. "0.9.0" vs "1.0.0").
  /// Returns < 0 if v1 < v2, 0 if equal, > 0 if v1 > v2.
  static int _compareVersions(String v1, String v2) {
    final v1Parts = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final v2Parts = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final p1 = i < v1Parts.length ? v1Parts[i] : 0;
      final p2 = i < v2Parts.length ? v2Parts[i] : 0;
      if (p1 < p2) return -1;
      if (p1 > p2) return 1;
    }
    return 0;
  }

  static const String _prefKeyLastCheck = 'app_update_last_check_timestamp';
  static const Duration _checkInterval = Duration(hours: 1);
  static const Duration _skipSuppressDuration = Duration(hours: 1);

  static DateTime? _skippedTimestamp;

  /// Records that the user explicitly skipped the update dialog.
  /// Suppresses update popups on manual sync taps for 1 hour.
  static void recordSkip() {
    _skippedTimestamp = DateTime.now();
    if (kDebugMode) {
      print('UpdateCheckService: Update skipped. Popups suppressed for 1 hour during session.');
    }
  }

  /// Returns true if the user skipped an update less than 1 hour ago.
  static bool get isSkippedWithinHour {
    if (_skippedTimestamp == null) return false;
    return DateTime.now().difference(_skippedTimestamp!) < _skipSuppressDuration;
  }

  /// Queries Supabase app_versions table and compares against local PackageInfo.
  ///
  /// Set [isAppLaunch] to true for cold app restarts to bypass the 1-hour skip suppression.
  /// On manual cloud sync taps ([isAppLaunch] = false), if the update was skipped less than 1 hour ago,
  /// the check is suppressed.
  static Future<AppVersionStatus?> checkForUpdates({
    bool isAppLaunch = false,
    bool forceCheck = false,
  }) async {
    try {
      final now = DateTime.now();

      // On manual sync taps (not app launch), respect the 1-hour skip suppression window
      if (!isAppLaunch && isSkippedWithinHour && !forceCheck) {
        if (kDebugMode) {
          final remainingMins = _skipSuppressDuration.inMinutes - now.difference(_skippedTimestamp!).inMinutes;
          print('UpdateCheckService: Update suppressed by user skip. Resumes in $remainingMins mins.');
        }
        return null;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVer = packageInfo.version.isNotEmpty ? packageInfo.version : '0.9.0';
      final platform = currentPlatform;

      final res = await Supabase.instance.client
          .from('app_versions')
          .select()
          .eq('platform', platform)
          .maybeSingle();

      await UiPreferencesService.setValue(_prefKeyLastCheck, now.millisecondsSinceEpoch);

      if (res != null) {
        final latestVer = (res['latest_version'] ?? currentVer).toString();
        final minVer = (res['min_required_version'] ?? currentVer).toString();
        final downloadUrl = (res['download_url'] ?? '').toString();
        final releaseNotes = (res['release_notes'] ?? '').toString();
        final isMandatoryDb = res['is_mandatory'] == true;

        final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
        final latestBuild =
            int.tryParse(res['latest_build_number']?.toString() ?? '') ?? 0;

        final bool versionIsOlder = _compareVersions(currentVer, latestVer) < 0;
        final bool buildIsOlder =
            _compareVersions(currentVer, latestVer) == 0 && currentBuild < latestBuild;
        final bool hasNewerVersion = versionIsOlder || buildIsOlder;
        final bool isBelowMinVersion = _compareVersions(currentVer, minVer) < 0;
        final bool isMandatory = isMandatoryDb || isBelowMinVersion || buildIsOlder;

        if (kDebugMode) {
          print('UpdateCheckService: current=$currentVer+$currentBuild '
              'latest=$latestVer+$latestBuild hasUpdate=$hasNewerVersion');
        }

        return AppVersionStatus(
          currentVersion: currentVer,
          latestVersion: latestVer,
          minRequiredVersion: minVer,
          isMandatory: isMandatory,
          downloadUrl: downloadUrl,
          releaseNotes: releaseNotes,
          hasUpdate: hasNewerVersion,
        );
      }
    } catch (e) {
      if (kDebugMode) print('UpdateCheckService error: $e');
    }
    return null;
  }
}

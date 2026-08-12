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

  /// Queries Supabase app_versions table and compares against local PackageInfo.
  /// Throttles network checks to at most once every 6 hours unless [forceCheck] is true.
  static Future<AppVersionStatus?> checkForUpdates({bool forceCheck = false}) async {
    try {
      final now = DateTime.now();
      final lastCheckMillis = (UiPreferencesService.getValue(_prefKeyLastCheck) as num?)?.toInt() ?? 0;
      final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastCheckMillis);

      final isFirstCheckInSession = (UiPreferencesService.getValue(_prefKeyLastCheck) as num?)?.toInt() == null;

      if (!forceCheck && !isFirstCheckInSession && now.difference(lastCheck) < _checkInterval) {
        if (kDebugMode) {
          final remainingMins = (_checkInterval - now.difference(lastCheck)).inMinutes;
          print('UpdateCheckService: Skipped check. Next check in $remainingMins mins (0 Egress saved!).');
        }
        return null;
      }

      // Record check timestamp
      await UiPreferencesService.setValue(_prefKeyLastCheck, now.millisecondsSinceEpoch);

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVer = packageInfo.version.isNotEmpty ? packageInfo.version : '0.9.0';
      final platform = currentPlatform;

      final res = await Supabase.instance.client
          .from('app_versions')
          .select()
          .eq('platform', platform)
          .maybeSingle();

      if (res != null) {
        final latestVer = (res['latest_version'] ?? currentVer).toString();
        final minVer = (res['min_required_version'] ?? currentVer).toString();
        final downloadUrl = (res['download_url'] ?? '').toString();
        final releaseNotes = (res['release_notes'] ?? '').toString();
        final isMandatoryDb = res['is_mandatory'] == true;

        final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
        final latestBuild = int.tryParse(res['latest_build_number']?.toString() ?? '') ?? 0;

        final bool versionIsOlder = _compareVersions(currentVer, latestVer) < 0;
        final bool buildIsOlder = _compareVersions(currentVer, latestVer) == 0 && currentBuild < latestBuild;
        final bool hasNewerVersion = versionIsOlder || buildIsOlder;
        final bool isBelowMinVersion = _compareVersions(currentVer, minVer) < 0;
        final bool isMandatory = isMandatoryDb || isBelowMinVersion || buildIsOlder;

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

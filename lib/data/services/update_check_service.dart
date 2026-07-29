import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Queries Supabase app_versions table and compares against local PackageInfo.
  static Future<AppVersionStatus?> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVer = packageInfo.version.isNotEmpty ? packageInfo.version : '0.9.0';
      final platform = currentPlatform;

      final res = await Supabase.instance.client
          .from('app_versions')
          .select()
          .eq('platform', platform)
          .maybeSingle();

      if (res != null && res is Map) {
        final latestVer = (res['latest_version'] ?? currentVer).toString();
        final minVer = (res['min_required_version'] ?? currentVer).toString();
        final downloadUrl = (res['download_url'] ?? '').toString();
        final releaseNotes = (res['release_notes'] ?? '').toString();
        final isMandatoryDb = res['is_mandatory'] == true;

        final bool hasNewerVersion = _compareVersions(currentVer, latestVer) < 0;
        final bool isBelowMinVersion = _compareVersions(currentVer, minVer) < 0;
        final bool isMandatory = isMandatoryDb || isBelowMinVersion;

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

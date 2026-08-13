// =============================================================================
// GOOGLE DRIVE UPLOAD SERVICE — PRESERVED FOR FUTURE USE
// =============================================================================
// This service previously handled uploading photos to Google Drive via a
// Google Apps Script Web App and returning public drive.google.com / lh3 URLs.
//
// WHY IT WAS DISABLED (Aug 2026):
//   The Google Apps Script Web App consistently returned:
//     {"status":"error","message":"Exception: Access denied: DriveApp."}
//   even after:
//     - Setting "Execute as: Me" and "Who has access: Anyone"
//     - Adding oauthScopes to appsscript.json
//     - Multiple re-deployments and authorizations
//   The root cause was the web app's server-side OAuth token not being
//   refreshed properly with the drive scope for anonymous external callers.
//
// CURRENT APPROACH:
//   Photos are now uploaded directly to Supabase Storage ('photos' bucket).
//   See: lib/data/services/supabase_photo_service.dart
//
// TO RE-ENABLE GOOGLE DRIVE IN FUTURE:
//   1. Fix the Apps Script authorization (see Code.gs in your Google account)
//   2. Uncomment all the code below
//   3. In photo_attachment_widget.dart, replace SupabasePhotoService calls
//      with GoogleDriveUploadService calls
//   4. The Apps Script URL is stored in defaultAppsScriptUrl below
// =============================================================================

// ignore_for_file: unused_import, unused_field, dead_code

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../../ui/shared/photo_attachment_widget.dart';


class GoogleDriveUploadService {
  // ── Constants (kept for reference / future re-enablement) ──────────────────
  static const String _boxName = 'ui_preferences';
  static const String _appsScriptKey = 'google_drive_apps_script_url';
  static const String _folderIdKey = 'google_drive_folder_id';
  static const String _tokenKey = 'google_drive_service_token';

  /// Latest deployed Apps Script Web App URL (as of Aug 2026).
  /// Deploy settings: Execute as: Me, Who has access: Anyone
  static const String defaultAppsScriptUrl =
      'https://script.google.com/macros/s/AKfycbzSPs57ImbfTLqng5zfWARn192BmbE6RMy8wpi_wj2h5LxqQySQn80pFZfcKNc5soT54A/exec';

  /// Google Drive folder ID where photos were stored.
  static const String defaultDriveFolderId =
      '16Iff7huX3fwK-5Ua36ZfMjMNgK0cXCdR';

  static String? appsScriptUrl;
  static String? driveFolderId;
  static String? serviceAccountToken;

  // ── Stub init (no-op — kept so callers don't break) ───────────────────────
  /// No-op: Google Drive is disabled. Kept so existing callers compile.
  static Future<void> init() async {
    // DISABLED: Google Drive upload disabled. Using Supabase Storage instead.
    // ── Original implementation (preserved for future reference) ──────────
    // try {
    //   final box = await Hive.openBox(_boxName);
    //   await box.put(_appsScriptKey, defaultAppsScriptUrl);
    //   await box.put(_folderIdKey, defaultDriveFolderId);
    //   appsScriptUrl = defaultAppsScriptUrl;
    //   driveFolderId = defaultDriveFolderId;
    //   serviceAccountToken = box.get(_tokenKey);
    // } catch (e) {
    //   if (kDebugMode) print('GoogleDriveUploadService init error: $e');
    //   appsScriptUrl = defaultAppsScriptUrl;
    //   driveFolderId = defaultDriveFolderId;
    // }
  }

  // ── Stub saveSettings (no-op) ──────────────────────────────────────────────
  /// No-op: Google Drive is disabled.
  static Future<void> saveSettings({
    String? scriptUrl,
    String? folderId,
    String? token,
  }) async {
    // DISABLED: Google Drive upload disabled. Using Supabase Storage instead.
    // ── Original implementation ──────────────────────────────────────────────
    // final box = await Hive.openBox(_boxName);
    // appsScriptUrl = scriptUrl?.trim();
    // driveFolderId = folderId?.trim();
    // serviceAccountToken = token?.trim();
    // await box.put(_appsScriptKey, appsScriptUrl ?? defaultAppsScriptUrl);
    // await box.put(_folderIdKey, driveFolderId ?? defaultDriveFolderId);
    // await box.put(_tokenKey, serviceAccountToken ?? '');
  }

  // ── DISABLED: uploadPhotoBytes ─────────────────────────────────────────────
  /// DISABLED — returns null always. Photo upload is now handled by
  /// SupabasePhotoService.uploadPhoto() in photo_attachment_widget.dart.
  ///
  /// Original purpose: Upload compressed image bytes to Google Drive via the
  /// Apps Script web app and return a drive.google.com/thumbnail URL.
  static Future<String?> uploadPhotoBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    // DISABLED: Google Drive upload disabled. Always return null.
    return null;

    // ── Original Google Drive upload implementation (preserved) ─────────────
    // final base64String = base64Encode(bytes);
    // const targetScriptUrl = defaultAppsScriptUrl;
    // const targetFolderId = defaultDriveFolderId;
    // try {
    //   final payload = jsonEncode({
    //     'filename': fileName,
    //     'mimeType': 'image/jpeg',
    //     'bytes': base64String,
    //     'folderId': targetFolderId,
    //   });
    //   final client = http.Client();
    //   final request = http.Request('POST', Uri.parse(targetScriptUrl))
    //     ..headers['Content-Type'] = 'text/plain;charset=utf-8'
    //     ..body = payload;
    //   final streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));
    //   final response = await http.Response.fromStream(streamedResponse);
    //   // Follow 302/307 redirect from Google Apps Script if needed
    //   http.Response finalResponse = response;
    //   if ((response.statusCode == 302 || response.statusCode == 307) &&
    //       response.headers.containsKey('location')) {
    //     final redirectUrl = response.headers['location']!;
    //     finalResponse = await http.get(Uri.parse(redirectUrl)).timeout(const Duration(seconds: 30));
    //   }
    //   if (kDebugMode) {
    //     print('Google Drive upload status: ${finalResponse.statusCode}');
    //     print('Google Drive response: ${finalResponse.body}');
    //   }
    //   if (finalResponse.statusCode == 200 || finalResponse.statusCode == 201) {
    //     final data = jsonDecode(finalResponse.body);
    //     final url = data['url']?.toString() ??
    //         data['fileUrl']?.toString() ?? data['viewUrl']?.toString();
    //     if (url != null && url.isNotEmpty) return _toDriveThumbnailUrl(url);
    //     final fileId = data['id']?.toString() ?? data['fileId']?.toString();
    //     if (fileId != null && fileId.isNotEmpty) {
    //       return 'https://lh3.googleusercontent.com/d/$fileId';
    //     }
    //   }
    // } catch (e) {
    //   if (kDebugMode) print('Apps Script Google Drive upload error: $e');
    // }
    // return null;
  }

  // ── DISABLED: deletePhoto ──────────────────────────────────────────────────
  /// DISABLED — returns false always. Photo deletion is now handled by
  /// SupabasePhotoService.deletePhoto() in photo_attachment_widget.dart.
  ///
  /// Original purpose: Delete a file from Google Drive by calling the Apps
  /// Script doPost() endpoint with action='delete' and the Drive fileId.
  static Future<bool> deletePhoto(String photoUrl) async {
    // DISABLED: Google Drive delete disabled. Always return false.
    return false;

    // ── Original Google Drive delete implementation (preserved) ─────────────
    // if (photoUrl.isEmpty || photoUrl.startsWith('data:image/')) return false;
    // final driveMatch = RegExp(
    //   r'(?:drive\.google\.com/file/d/|drive\.google\.com/thumbnail\?id=|drive\.google\.com/uc\?.*id=|lh3\.googleusercontent\.com/d/)([^/&?]+)',
    // ).firstMatch(photoUrl);
    // if (driveMatch == null) return false;
    // final fileId = driveMatch.group(1);
    // if (fileId == null || fileId.isEmpty) return false;
    // try {
    //   final payload = jsonEncode({'action': 'delete', 'fileId': fileId});
    //   await http.post(
    //     Uri.parse(defaultAppsScriptUrl),
    //     headers: {'Content-Type': 'text/plain;charset=utf-8'},
    //     body: payload,
    //   );
    //   return true;
    // } catch (e) {
    //   if (kDebugMode) print('Apps Script delete error: $e');
    //   return false;
    // }
  }

  // ── DISABLED: syncPendingLocalPhotos ───────────────────────────────────────
  /// DISABLED — no-op. Previously scanned all local records for base64
  /// data:image/ photos, uploaded them to Google Drive, and updated the DB.
  ///
  /// With Supabase Storage, photos are uploaded synchronously before saving
  /// so there is no "pending" state requiring a background sweep.
  /// Base64 photos already in the DB are shown via buildAppImage() as-is.
  static Future<void> syncPendingLocalPhotos(dynamic repo) async {
    // DISABLED: No-op. Supabase Storage uploads happen synchronously.
    // ── Original implementation (all 4 tables: repairs, calls, replacements, purchases) ─
    // preserved in git history — see commit before Aug 2026 refactor.
  }

  // ── DISABLED: _toDriveThumbnailUrl ─────────────────────────────────────────
  /// Converts a Google Drive sharing URL to a thumbnail URL.
  /// e.g. https://drive.google.com/file/d/FILE_ID/view
  ///   -> https://drive.google.com/thumbnail?id=FILE_ID&sz=w800
  // ignore: unused_element
  static String _toDriveThumbnailUrl(String url) {
    if (url.contains('thumbnail?id=')) return url;
    final fileIdMatch = RegExp(r'/file/d/([^/\?]+)').firstMatch(url);
    if (fileIdMatch != null) {
      return 'https://drive.google.com/thumbnail?id=${fileIdMatch.group(1)!}&sz=w800';
    }
    final idParamMatch = RegExp(r'[?&]id=([^&]+)').firstMatch(url);
    if (idParamMatch != null) {
      return 'https://drive.google.com/thumbnail?id=${idParamMatch.group(1)!}&sz=w800';
    }
    if (url.contains('lh3.googleusercontent.com')) return url;
    return url;
  }
}

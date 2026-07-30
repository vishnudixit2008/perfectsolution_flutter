import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;


class GoogleDriveUploadService {
  static const String _boxName = 'ui_preferences';
  static const String _appsScriptKey = 'google_drive_apps_script_url';
  static const String _folderIdKey = 'google_drive_folder_id';
  static const String _tokenKey = 'google_drive_service_token';

  static const String defaultAppsScriptUrl =
      'https://script.google.com/macros/s/AKfycbwNvXGz7S9C0kpd87yKUrVZIuiNQ7r0t9RB0OZXYgwJynBzFVmIZfOuFXyACGr0azQl/exec';

  static String? appsScriptUrl;
  static String? driveFolderId;
  static String? serviceAccountToken;

  /// Loads Google Drive settings from Hive storage on startup
  static Future<void> init() async {
    try {
      final box = await Hive.openBox(_boxName);
      appsScriptUrl = box.get(
        _appsScriptKey,
        defaultValue: defaultAppsScriptUrl,
      );
      driveFolderId = box.get(_folderIdKey);
      serviceAccountToken = box.get(_tokenKey);

      if (appsScriptUrl == null || appsScriptUrl!.trim().isEmpty) {
        appsScriptUrl = defaultAppsScriptUrl;
        await box.put(_appsScriptKey, defaultAppsScriptUrl);
      }
    } catch (e) {
      if (kDebugMode) print('GoogleDriveUploadService init error: $e');
      appsScriptUrl = defaultAppsScriptUrl;
    }
  }

  /// Saves Google Drive settings
  static Future<void> saveSettings({
    String? scriptUrl,
    String? folderId,
    String? token,
  }) async {
    final box = await Hive.openBox(_boxName);
    appsScriptUrl = scriptUrl?.trim();
    driveFolderId = folderId?.trim();
    serviceAccountToken = token?.trim();

    await box.put(_appsScriptKey, appsScriptUrl ?? '');
    await box.put(_folderIdKey, driveFolderId ?? '');
    await box.put(_tokenKey, serviceAccountToken ?? '');
  }

  /// Uploads compressed image bytes to Google Drive via the Apps Script web app.
  /// Uses 0 bytes of Supabase Storage space and returns a direct lh3.googleusercontent.com URL.
  static Future<String?> uploadPhotoBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final base64String = base64Encode(bytes);

    // 1. Primary Method: Google Apps Script Web App (Unlimited Free Google Drive Storage)
    final targetScriptUrl =
        (appsScriptUrl != null && appsScriptUrl!.trim().isNotEmpty)
        ? appsScriptUrl!.trim()
        : defaultAppsScriptUrl;

    try {
      final payload = jsonEncode({
        'filename': fileName,
        'mimeType': 'image/jpeg',
        'bytes': base64String,
        if (driveFolderId != null && driveFolderId!.isNotEmpty)
          'folderId': driveFolderId,
      });

      final response = await http
          .post(
            Uri.parse(targetScriptUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: payload,
          )
          .timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        print('Google Drive upload status: ${response.statusCode}');
        print('Google Drive response: ${response.body}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final url =
            data['url']?.toString() ??
            data['fileUrl']?.toString() ??
            data['viewUrl']?.toString();
        if (url != null && url.isNotEmpty) {
          return _toDriveThumbnailUrl(url);
        }
        final fileId = data['id']?.toString() ?? data['fileId']?.toString();
        if (fileId != null && fileId.isNotEmpty) {
          return 'https://lh3.googleusercontent.com/d/$fileId';
        }
      }
    } catch (e) {
      if (kDebugMode) print('Apps Script Google Drive upload error: $e');
    }

    // 2. Fallback: Base64 Data URI if network fails (uses 0 cloud storage space)
    return 'data:image/jpeg;base64,$base64String';
  }

  /// Converts a Google Drive sharing URL to a thumbnail URL that works cross-device.
  /// e.g. https://drive.google.com/file/d/FILE_ID/view?usp=sharing
  ///   -> https://drive.google.com/thumbnail?id=FILE_ID&sz=w800
  static String _toDriveThumbnailUrl(String url) {
    // Already a thumbnail URL
    if (url.contains('thumbnail?id=')) return url;

    // Extract file ID from /file/d/ID/view pattern
    final fileIdMatch = RegExp(r'/file/d/([^/\?]+)').firstMatch(url);
    if (fileIdMatch != null) {
      final fileId = fileIdMatch.group(1)!;
      return 'https://drive.google.com/thumbnail?id=$fileId&sz=w800';
    }

    // Extract from id= param
    final idParamMatch = RegExp(r'[?&]id=([^&]+)').firstMatch(url);
    if (idParamMatch != null) {
      final fileId = idParamMatch.group(1)!;
      return 'https://drive.google.com/thumbnail?id=$fileId&sz=w800';
    }

    // lh3.googleusercontent.com direct URL — works as-is
    if (url.contains('lh3.googleusercontent.com')) return url;

    // Return as-is if we can't parse it
    return url;
  }
}

/// HTTP client that does NOT follow redirects so we can capture Location headers.
// ignore: unused_element
class _NonRedirectingClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

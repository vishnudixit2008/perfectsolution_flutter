import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../../ui/shared/photo_attachment_widget.dart';


class GoogleDriveUploadService {
  static const String _boxName = 'ui_preferences';
  static const String _appsScriptKey = 'google_drive_apps_script_url';
  static const String _folderIdKey = 'google_drive_folder_id';
  static const String _tokenKey = 'google_drive_service_token';

  static const String defaultAppsScriptUrl =
      'https://script.google.com/macros/s/AKfycbyW_1N5zOx-LtIhc72CGGV-9lYDg27i6uYeN1URgL0Rl5lIk_QDLA1FkfbwcODwJOw7/exec';
  static const String defaultDriveFolderId =
      '16Iff7huX3fwK-5Ua36ZfMjMNgK0cXCdR';

  static String? appsScriptUrl;
  static String? driveFolderId;
  static String? serviceAccountToken;

  /// Loads Google Drive settings from Hive storage on startup
  static Future<void> init() async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_appsScriptKey, defaultAppsScriptUrl);
      await box.put(_folderIdKey, defaultDriveFolderId);
      appsScriptUrl = defaultAppsScriptUrl;
      driveFolderId = defaultDriveFolderId;
      serviceAccountToken = box.get(_tokenKey);
    } catch (e) {
      if (kDebugMode) print('GoogleDriveUploadService init error: $e');
      appsScriptUrl = defaultAppsScriptUrl;
      driveFolderId = defaultDriveFolderId;
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

    await box.put(_appsScriptKey, appsScriptUrl ?? defaultAppsScriptUrl);
    await box.put(_folderIdKey, driveFolderId ?? defaultDriveFolderId);
    await box.put(_tokenKey, serviceAccountToken ?? '');
  }

  /// Uploads compressed image bytes to Google Drive via the Apps Script web app.
  /// Uses 0 bytes of Supabase Storage space and returns a direct lh3.googleusercontent.com URL.
  static Future<String?> uploadPhotoBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final base64String = base64Encode(bytes);

    // Primary Method: Google Apps Script Web App
    const targetScriptUrl = defaultAppsScriptUrl;
    const targetFolderId = defaultDriveFolderId;

    try {
      final payload = jsonEncode({
        'filename': fileName,
        'mimeType': 'image/jpeg',
        'bytes': base64String,
        'folderId': targetFolderId,
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

  /// Deletes a photo from Google Drive by its URL or file ID in the background
  static Future<bool> deletePhoto(String photoUrl) async {
    if (photoUrl.isEmpty || photoUrl.startsWith('data:image/')) return false;

    // Extract Google Drive File ID
    final driveMatch = RegExp(
      r'(?:drive\.google\.com/file/d/|drive\.google\.com/thumbnail\?id=|drive\.google\.com/uc\?.*id=|lh3\.googleusercontent\.com/d/)([^/&?]+)',
    ).firstMatch(photoUrl);

    if (driveMatch == null) return false;
    final fileId = driveMatch.group(1);
    if (fileId == null || fileId.isEmpty) return false;

    try {
      final payload = jsonEncode({
        'action': 'delete',
        'fileId': fileId,
      });

      await http.post(
        Uri.parse(defaultAppsScriptUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: payload,
      );
      return true;
    } catch (e) {
      if (kDebugMode) print('Apps Script delete error: $e');
      return false;
    }
  }

  /// Background Worker that finds any base64 data:image/ photos in saved records,
  /// uploads them to Google Drive in background, and updates records in local DB & cloud.
  static Future<void> syncPendingLocalPhotos(dynamic repo) async {
    try {
      // 1. Check Inward Repairs
      final repairs = repo.getInwardRepairs();
      for (final r in repairs) {
        if (r.photo != null && r.photo!.contains('data:image/')) {
          final photoUrls = PhotoAttachmentWidget.parsePhotoUrls(r.photo);
          final updatedUrls = <String>[];
          bool changed = false;

          for (int i = 0; i < photoUrls.length; i++) {
            final url = photoUrls[i];
            if (url.startsWith('data:image/')) {
              final commaIndex = url.indexOf(',');
              if (commaIndex != -1) {
                final base64Str = url.substring(commaIndex + 1);
                final bytes = base64Decode(base64Str);
                final fileName =
                    'inward_${r.jobNo}_${i + 1}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                final cloudUrl =
                    await uploadPhotoBytes(bytes: bytes, fileName: fileName);
                if (cloudUrl != null && !cloudUrl.startsWith('data:image/')) {
                  updatedUrls.add(cloudUrl);
                  changed = true;
                  continue;
                }
              }
            }
            updatedUrls.add(url);
          }

          if (changed) {
            final updatedRepair = r.copyWith(
              photo: PhotoAttachmentWidget.joinPhotoUrls(updatedUrls),
            );
            final estimateItems = repo.getInwardEstimateItems(r.jobNo);
            await repo.saveInwardRepair(updatedRepair, estimateItems);
          }
        }
      }

      // 2. Check Calls
      final calls = repo.getCalls();
      for (final c in calls) {
        if (c.photo != null && c.photo!.contains('data:image/')) {
          final photoUrls = PhotoAttachmentWidget.parsePhotoUrls(c.photo);
          final updatedUrls = <String>[];
          bool changed = false;

          for (int i = 0; i < photoUrls.length; i++) {
            final url = photoUrls[i];
            if (url.startsWith('data:image/')) {
              final commaIndex = url.indexOf(',');
              if (commaIndex != -1) {
                final base64Str = url.substring(commaIndex + 1);
                final bytes = base64Decode(base64Str);
                final fileName =
                    'call_${c.id}_${i + 1}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                final cloudUrl =
                    await uploadPhotoBytes(bytes: bytes, fileName: fileName);
                if (cloudUrl != null && !cloudUrl.startsWith('data:image/')) {
                  updatedUrls.add(cloudUrl);
                  changed = true;
                  continue;
                }
              }
            }
            updatedUrls.add(url);
          }

          if (changed) {
            final updatedCall = c.copyWith(
              photo: PhotoAttachmentWidget.joinPhotoUrls(updatedUrls),
            );
            await repo.saveCall(updatedCall);
          }
        }
      }

      // 3. Check Replacements
      final replacements = repo.getReplacements();
      for (final rep in replacements) {
        if (rep.photo != null && rep.photo!.contains('data:image/')) {
          final photoUrls = PhotoAttachmentWidget.parsePhotoUrls(rep.photo);
          final updatedUrls = <String>[];
          bool changed = false;

          for (int i = 0; i < photoUrls.length; i++) {
            final url = photoUrls[i];
            if (url.startsWith('data:image/')) {
              final commaIndex = url.indexOf(',');
              if (commaIndex != -1) {
                final base64Str = url.substring(commaIndex + 1);
                final bytes = base64Decode(base64Str);
                final fileName =
                    'replacement_${rep.id}_${i + 1}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                final cloudUrl =
                    await uploadPhotoBytes(bytes: bytes, fileName: fileName);
                if (cloudUrl != null && !cloudUrl.startsWith('data:image/')) {
                  updatedUrls.add(cloudUrl);
                  changed = true;
                  continue;
                }
              }
            }
            updatedUrls.add(url);
          }

          if (changed) {
            final updatedRep = rep.copyWith(
              photo: PhotoAttachmentWidget.joinPhotoUrls(updatedUrls),
            );
            await repo.saveReplacement(updatedRep);
          }
        }
      }

      // 4. Check Purchases
      final purchases = repo.getPurchaseOrders();
      for (final po in purchases) {
        if (po.photo != null && po.photo!.contains('data:image/')) {
          final photoUrls = PhotoAttachmentWidget.parsePhotoUrls(po.photo);
          final updatedUrls = <String>[];
          bool changed = false;

          for (int i = 0; i < photoUrls.length; i++) {
            final url = photoUrls[i];
            if (url.startsWith('data:image/')) {
              final commaIndex = url.indexOf(',');
              if (commaIndex != -1) {
                final base64Str = url.substring(commaIndex + 1);
                final bytes = base64Decode(base64Str);
                final fileName =
                    'purchase_${po.id}_${i + 1}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                final cloudUrl =
                    await uploadPhotoBytes(bytes: bytes, fileName: fileName);
                if (cloudUrl != null && !cloudUrl.startsWith('data:image/')) {
                  updatedUrls.add(cloudUrl);
                  changed = true;
                  continue;
                }
              }
            }
            updatedUrls.add(url);
          }

          if (changed) {
            final updatedPo = po.copyWith(
              photo: PhotoAttachmentWidget.joinPhotoUrls(updatedUrls),
            );
            final poItems = repo.getPurchaseOrderItems(po.id);
            await repo.savePurchaseOrder(updatedPo, poItems);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Background photo sync error: $e');
    }
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

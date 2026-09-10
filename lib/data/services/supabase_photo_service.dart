import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for uploading, deleting, and managing photos in Supabase Storage.
///
/// Photos are stored in the 'photos' bucket (must be created as PUBLIC in
/// Supabase Studio → Storage → New Bucket → public: true).
///
/// Public URLs are stored directly in the `photo` text column of each table
/// (inward_repairs, calls, replacements, purchases, pricelist, requests).
///
/// Existing `data:image/...` base64 photos are still rendered by
/// PhotoAttachmentWidget.buildAppImage() and are NOT touched by this service.
///
/// NOTE: Google Drive upload code has been preserved (commented out) in
/// google_drive_upload_service.dart for future reference.
class SupabasePhotoService {
  static const String _bucketName = 'photos';

  /// Uploads raw image bytes to Supabase Storage at maximum full resolution.
  /// Returns null if the upload fails — caller must NOT store null into DB.
  ///
  /// [bytes]     : Full-resolution raw image bytes.
  /// [fileName]  : Base filename (e.g. 'photo_123456.jpg').
  /// [category]  : Sub-folder within the bucket (e.g. 'inward_repairs', 'calls').
  static Future<String?> uploadPhoto({
    required Uint8List bytes,
    required String fileName,
    String category = 'general',
  }) async {
    try {
      final client = Supabase.instance.client;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Path: {category}/{timestamp}_{filename} — unique per upload
      final path = '$category/${timestamp}_$fileName';

      await client.storage.from(_bucketName).uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );

      final publicUrl = client.storage.from(_bucketName).getPublicUrl(path);

      if (kDebugMode) {
        print('✅ Supabase photo upload success: $publicUrl');
      }

      return publicUrl;
    } catch (e) {
      if (kDebugMode) print('❌ Supabase photo upload error: $e');
      return null;
    }
  }

  /// Deletes a photo from Supabase Storage given its public URL.
  /// Silently returns false for base64 data URIs or non-storage URLs (those
  /// are legacy records and should not be deleted from storage).
  static Future<bool> deletePhoto(String photoUrl) async {
    if (photoUrl.isEmpty || photoUrl.startsWith('data:image/')) return false;

    // Only handle URLs that belong to our Supabase Storage bucket
    final marker = '/storage/v1/object/public/$_bucketName/';
    final markerIndex = photoUrl.indexOf(marker);
    if (markerIndex == -1) {
      // Could be an old Google Drive URL — do not attempt storage deletion
      return false;
    }

    try {
      final client = Supabase.instance.client;
      // Extract the relative path inside the bucket
      final path = Uri.decodeFull(
        photoUrl.substring(markerIndex + marker.length),
      );

      await client.storage.from(_bucketName).remove([path]);

      if (kDebugMode) print('🗑️ Supabase photo deleted: $path');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Supabase photo delete error: $e');
      return false;
    }
  }

  /// Returns true if this URL is a Supabase Storage URL managed by this service.
  static bool isSupabaseStorageUrl(String url) {
    return url.contains('/storage/v1/object/public/$_bucketName/');
  }
}

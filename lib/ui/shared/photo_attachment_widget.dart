import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/google_drive_upload_service.dart';
import '../core/app_theme.dart';

class PhotoAttachmentWidget extends StatefulWidget {
  final String? initialPhotoUrl;
  final List<String>? initialPhotoUrls;
  final ValueChanged<String?> onPhotoChanged;
  final String label;

  const PhotoAttachmentWidget({
    super.key,
    this.initialPhotoUrl,
    this.initialPhotoUrls,
    required this.onPhotoChanged,
    this.label = 'Device / Item Photos',
  });

  /// Helper to safely parse raw photo strings without breaking Base64 data URIs
  static List<String> parsePhotoUrls(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    final trimmed = raw.trim();

    // Check JSON array format
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final List<dynamic> list = jsonDecode(trimmed);
        return list
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
      } catch (_) {}
    }

    // Check pipe delimiter
    if (trimmed.contains('|||')) {
      return trimmed
          .split('|||')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    // If starts with data:image/, it's a single base64 data URI
    if (trimmed.startsWith('data:image/')) {
      return [trimmed];
    }

    // Otherwise standard comma separated HTTP URLs
    return trimmed
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Helper to join photo URLs using pipe delimiter so base64 commas don't break
  static String joinPhotoUrls(List<String> urls) {
    if (urls.isEmpty) return '';
    return urls.where((e) => e.trim().isNotEmpty).join('|||');
  }

  /// Converts standard Google Drive sharing links to direct embeddable CORS-friendly image URLs
  static String? getDirectImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final url = rawUrl.trim();

    // Google Drive share link format: https://drive.google.com/file/d/FILE_ID/view?usp=sharing
    // OR uc?id=FILE_ID OR lh3.googleusercontent.com/d/FILE_ID
    final driveMatch = RegExp(
      r'(?:drive\.google\.com/file/d/|drive\.google\.com/uc\?.*id=|lh3\.googleusercontent\.com/d/)([^/&?]+)',
    ).firstMatch(url);
    if (driveMatch != null) {
      final fileId = driveMatch.group(1);
      return 'https://drive.google.com/thumbnail?id=$fileId&sz=w1000';
    }

    return url;
  }

  /// Renders local device files, base64 Data URIs (data:image/...), and network HTTP URLs seamlessly
  static Widget buildAppImage(
    String url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
  }) {
    final String cleanUrl = url.trim();

    // 1. Base64 Data URI check
    if (cleanUrl.startsWith('data:image/')) {
      try {
        final commaIndex = cleanUrl.indexOf(',');
        if (commaIndex != -1) {
          final base64Str = cleanUrl.substring(commaIndex + 1);
          final bytes = base64Decode(base64Str);
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            errorBuilder:
                errorBuilder ??
                (context, error, stackTrace) => Container(
                  width: width,
                  height: height,
                  color: Colors.white10,
                  child: const Icon(
                    Icons.broken_image_rounded,
                    color: AppTheme.danger,
                  ),
                ),
          );
        }
      } catch (e) {
        if (kDebugMode) print('Error decoding base64 image: $e');
      }
    }

    // 2. Local Device File Path check (e.g. /Users/..., C:\..., file://...)
    if (!kIsWeb &&
        !cleanUrl.startsWith('http://') &&
        !cleanUrl.startsWith('https://')) {
      final path = cleanUrl.startsWith('file://')
          ? cleanUrl.replaceFirst('file://', '')
          : cleanUrl;
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder:
              errorBuilder ??
              (context, error, stackTrace) => Container(
                width: width,
                height: height,
                color: Colors.white10,
                child: const Icon(
                  Icons.photo_rounded,
                  color: AppTheme.textMuted,
                ),
              ),
        );
      }
    }

    // 3. Network URL
    final directUrl = getDirectImageUrl(cleanUrl) ?? cleanUrl;
    return Image.network(
      directUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        // Fallback: If thumbnail URL fails, try direct lh3 URL
        final fallbackUrl = directUrl.contains('drive.google.com/thumbnail')
            ? directUrl
                  .replaceAll(
                    'drive.google.com/thumbnail?id=',
                    'lh3.googleusercontent.com/d/',
                  )
                  .replaceAll('&sz=w1000', '')
            : directUrl;
        if (fallbackUrl != directUrl) {
          return Image.network(
            fallbackUrl,
            width: width,
            height: height,
            fit: fit,
            errorBuilder:
                errorBuilder ??
                (ctx, err, st) => Container(
                  width: width,
                  height: height,
                  color: Colors.white10,
                  child: const Icon(
                    Icons.photo_rounded,
                    color: AppTheme.textMuted,
                  ),
                ),
          );
        }
        return errorBuilder?.call(context, error, stackTrace) ??
            Container(
              width: width,
              height: height,
              color: Colors.white10,
              child: const Icon(Icons.photo_rounded, color: AppTheme.textMuted),
            );
      },
    );
  }

  @override
  State<PhotoAttachmentWidget> createState() => _PhotoAttachmentWidgetState();
}

class _PhotoAttachmentWidgetState extends State<PhotoAttachmentWidget> {
  late List<String> _photoUrls;
  bool _isUploading = false;
  String _uploadStatusText = '';
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _photoUrls = [];
    if (widget.initialPhotoUrls != null &&
        widget.initialPhotoUrls!.isNotEmpty) {
      _photoUrls.addAll(
        widget.initialPhotoUrls!.where((e) => e.trim().isNotEmpty),
      );
    } else if (widget.initialPhotoUrl != null &&
        widget.initialPhotoUrl!.trim().isNotEmpty) {
      _photoUrls.addAll(
        PhotoAttachmentWidget.parsePhotoUrls(widget.initialPhotoUrl),
      );
    }
  }

  void _notifyParent() {
    if (_photoUrls.isEmpty) {
      widget.onPhotoChanged(null);
    } else {
      widget.onPhotoChanged(PhotoAttachmentWidget.joinPhotoUrls(_photoUrls));
    }
  }

  Future<void> _processSelectedFiles(List<XFile> selectedFiles) async {
    if (selectedFiles.isEmpty) return;

    try {
      // 1. Fetch local device file paths for INSTANT zero-delay thumbnail rendering on screen!
      final List<String> localPaths = selectedFiles
          .map((f) => f.path)
          .where((p) => p.trim().isNotEmpty)
          .toList();

      if (mounted) {
        setState(() {
          _isUploading = true;
          _uploadStatusText =
              'Uploading ${selectedFiles.length} photo(s) in background...';
          _photoUrls.addAll(localPaths);
        });
      }
      _notifyParent();

      // 2. Read bytes and upload ALL photos in background concurrently to Google Drive!
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uploadFutures = selectedFiles.asMap().entries.map((entry) async {
        final index = entry.key;
        final file = entry.value;
        final bytes = await file.readAsBytes();
        final fileName = 'photo_${timestamp}_${index + 1}.jpg';
        return GoogleDriveUploadService.uploadPhotoBytes(
          bytes: bytes,
          fileName: fileName,
        );
      });

      final List<String?> cloudUrls = await Future.wait(uploadFutures);

      // 3. Seamlessly replace local device paths with permanent Google Drive URLs for cross-user sync
      for (int i = 0; i < localPaths.length; i++) {
        final localPath = localPaths[i];
        final cloudUrl = cloudUrls[i];
        if (cloudUrl != null && cloudUrl.isNotEmpty) {
          final idx = _photoUrls.indexOf(localPath);
          if (idx != -1) {
            _photoUrls[idx] = cloudUrl;
          }
        }
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatusText = '';
        });
      }
      _notifyParent();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatusText = '';
        });
      }
    }
  }

  void _showPhotoSourcePicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.add_a_photo_rounded,
              color: AppTheme.primaryLight,
              size: 22,
            ),
            SizedBox(width: 10),
            Text(
              'Attach Photo(s)',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppTheme.primaryLight,
                  size: 20,
                ),
              ),
              title: const Text(
                'Take Photo (Camera)',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Capture picture using machine / device camera',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              onTap: () async {
                XFile? photo;
                try {
                  photo = await _picker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 1024,
                    maxHeight: 1024,
                    imageQuality: 70,
                  );
                } catch (e) {
                  if (kDebugMode) print('Camera pick error: $e');
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (photo != null) {
                  _processSelectedFiles([photo]);
                }
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.folder_open_rounded,
                  color: AppTheme.textPrimary,
                  size: 20,
                ),
              ),
              title: const Text(
                'Upload from Finder / Gallery',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Browse file system / Finder & select one or multiple images',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              onTap: () async {
                List<XFile> files = [];
                try {
                  files = await _picker.pickMultiImage(
                    maxWidth: 1024,
                    maxHeight: 1024,
                    imageQuality: 70,
                  );
                } catch (_) {
                  try {
                    final single = await _picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1024,
                      maxHeight: 1024,
                      imageQuality: 70,
                    );
                    if (single != null) files.add(single);
                  } catch (e) {
                    if (kDebugMode) print('Gallery pick error: $e');
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (files.isNotEmpty) {
                  _processSelectedFiles(files);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  void _showImagePreviewDialog(int initialIndex) {
    showDialog(
      context: context,
      builder: (ctx) {
        int currentIndex = initialIndex;
        return StatefulBuilder(
          builder: (context, setPreviewState) {
            final rawUrl = _photoUrls[currentIndex];

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 850,
                  maxHeight: 650,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF131A2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Photo ${currentIndex + 1} of ${_photoUrls.length}',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white10),
                        // Image Body
                        Expanded(
                          child: Center(
                            child: PhotoAttachmentWidget.buildAppImage(
                              rawUrl,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Navigation Arrows if multiple photos
                    if (_photoUrls.length > 1) ...[
                      if (currentIndex > 0)
                        Positioned(
                          left: 12,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                              ),
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setPreviewState(() => currentIndex--);
                              },
                            ),
                          ),
                        ),
                      if (currentIndex < _photoUrls.length - 1)
                        Positioned(
                          right: 12,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                              ),
                              icon: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setPreviewState(() => currentIndex++);
                              },
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_photoUrls.isNotEmpty)
              Text(
                '${_photoUrls.length} Photo${_photoUrls.length > 1 ? 's' : ''} Attached',
                style: const TextStyle(
                  color: AppTheme.primaryLight,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (_isUploading)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryLight.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primaryLight,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _uploadStatusText,
                  style: const TextStyle(
                    color: AppTheme.primaryLight,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else ...[
          if (_photoUrls.isNotEmpty) ...[
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photoUrls.length + 1,
                separatorBuilder: (_, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  if (index == _photoUrls.length) {
                    // Add More Button
                    return InkWell(
                      onTap: _showPhotoSourcePicker,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 80,
                        height: 90,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primaryLight.withValues(alpha: 0.4),
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo_rounded,
                              color: AppTheme.primaryLight,
                              size: 22,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Add More',
                              style: TextStyle(
                                color: AppTheme.primaryLight,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final rawUrl = _photoUrls[index];

                  return Stack(
                    children: [
                      GestureDetector(
                        onTap: () => _showImagePreviewDialog(index),
                        child: Container(
                          width: 80,
                          height: 90,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: PhotoAttachmentWidget.buildAppImage(
                              rawUrl,
                              width: 80,
                              height: 90,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () {
                            final removedUrl = _photoUrls[index];
                            setState(() {
                              _photoUrls.removeAt(index);
                            });
                            _notifyParent();
                            GoogleDriveUploadService.deletePhoto(removedUrl);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: AppTheme.danger,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showPhotoSourcePicker,
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                label: const Text(
                  'Add Photo(s)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryLight,
                  side: BorderSide(
                    color: AppTheme.primaryLight.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Reusable Photo Gallery display section for Entry Detail Dialogs across all modules
class PhotoGallerySection extends StatelessWidget {
  final List<String> photoUrls;
  final String label;

  const PhotoGallerySection({
    super.key,
    required this.photoUrls,
    this.label = 'Attached Photo(s)',
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(
              Icons.photo_library_rounded,
              size: 16,
              color: AppTheme.primaryLight,
            ),
            const SizedBox(width: 6),
            Text(
              '$label (${photoUrls.length})',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photoUrls.length,
            separatorBuilder: (_, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final rawUrl = photoUrls[index];
              return GestureDetector(
                onTap: () => _showPreviewDialog(context, photoUrls, index),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: PhotoAttachmentWidget.buildAppImage(
                      rawUrl,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showPreviewDialog(
    BuildContext context,
    List<String> urls,
    int initialIndex,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        int currentIndex = initialIndex;
        return StatefulBuilder(
          builder: (context, setPreviewState) {
            final rawUrl = urls[currentIndex];
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 850,
                  maxHeight: 650,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF131A2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Photo ${currentIndex + 1} of ${urls.length}',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white10),
                        Expanded(
                          child: Center(
                            child: PhotoAttachmentWidget.buildAppImage(
                              rawUrl,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (urls.length > 1) ...[
                      if (currentIndex > 0)
                        Positioned(
                          left: 12,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                              ),
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  setPreviewState(() => currentIndex--),
                            ),
                          ),
                        ),
                      if (currentIndex < urls.length - 1)
                        Positioned(
                          right: 12,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                              ),
                              icon: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  setPreviewState(() => currentIndex++),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

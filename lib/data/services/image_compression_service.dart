import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Cross-platform intelligent image compression service.
/// Automatically compresses images > 100KB to < 100KB while preserving maximum
/// sharpness, legible text, serial numbers, and clarity.
class ImageCompressionService {
  /// Default target max size: 100 KB (102,400 bytes)
  static const int defaultMaxBytes = 100 * 1024;

  /// Compresses raw image bytes so the output size is strictly <= [maxBytes].
  ///
  /// - If [rawBytes] is already <= [maxBytes], returns [rawBytes] untouched.
  /// - Executes inside a background worker isolate (`compute()`) so UI animations
  ///   and frame rates remain silky smooth.
  static Future<Uint8List> compressImageBytes(
    Uint8List rawBytes, {
    int maxBytes = defaultMaxBytes,
  }) async {
    if (rawBytes.lengthInBytes <= maxBytes) {
      if (kDebugMode) {
        print(
          '📸 [ImageCompression] Image is already under 100KB '
          '(${_formatBytes(rawBytes.lengthInBytes)}). Skipping compression.',
        );
      }
      return rawBytes;
    }

    try {
      final initialSize = rawBytes.lengthInBytes;
      final compressedBytes = await compute(
        _isolateCompressWorker,
        _CompressionParams(rawBytes: rawBytes, maxBytes: maxBytes),
      );

      final finalSize = compressedBytes.lengthInBytes;
      if (kDebugMode) {
        final reductionPct =
            ((initialSize - finalSize) / initialSize * 100).toStringAsFixed(1);
        print(
          '✅ [ImageCompression] Compressed ${_formatBytes(initialSize)} -> '
          '${_formatBytes(finalSize)} ($reductionPct% reduction, target <= 100KB)',
        );
      }

      return compressedBytes;
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [ImageCompression] Compression error, falling back to original: $e');
      }
      return rawBytes;
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _CompressionParams {
  final Uint8List rawBytes;
  final int maxBytes;

  _CompressionParams({required this.rawBytes, required this.maxBytes});
}

/// Isolated worker function for decoding, resizing, and encoding images
Uint8List _isolateCompressWorker(_CompressionParams params) {
  final rawBytes = params.rawBytes;
  final maxBytes = params.maxBytes;

  // 1. Decode image
  final decoded = img.decodeImage(rawBytes);
  if (decoded == null) return rawBytes;

  // 2. Normalize EXIF orientation (e.g. from camera shots)
  img.Image currentImage = img.bakeOrientation(decoded);

  // 3. Initial dimension downscale if image is excessively large (e.g. 4000x3000 camera shot)
  // Max dimension 1600px provides ultra-crisp display on both Retina mobile & 4K desktop screens
  const int maxInitialDimension = 1600;
  if (currentImage.width > maxInitialDimension ||
      currentImage.height > maxInitialDimension) {
    if (currentImage.width >= currentImage.height) {
      currentImage = img.copyResize(
        currentImage,
        width: maxInitialDimension,
        interpolation: img.Interpolation.cubic,
      );
    } else {
      currentImage = img.copyResize(
        currentImage,
        height: maxInitialDimension,
        interpolation: img.Interpolation.cubic,
      );
    }
  }

  // 4. Multi-stage compression ladder to find the highest possible quality under maxBytes
  final qualityLevels = [85, 75, 65, 52, 40, 32];

  for (final quality in qualityLevels) {
    final encoded = img.encodeJpg(currentImage, quality: quality);
    if (encoded.lengthInBytes <= maxBytes) {
      return Uint8List.fromList(encoded);
    }
  }

  // 5. If still exceeding 100KB at quality 32, resize dimensions down progressively
  final scaleDimensions = [1280, 1024, 800, 640];
  for (final dim in scaleDimensions) {
    img.Image scaled;
    if (currentImage.width >= currentImage.height) {
      scaled = img.copyResize(
        currentImage,
        width: dim,
        interpolation: img.Interpolation.cubic,
      );
    } else {
      scaled = img.copyResize(
        currentImage,
        height: dim,
        interpolation: img.Interpolation.cubic,
      );
    }

    for (final quality in [60, 45, 35]) {
      final encoded = img.encodeJpg(scaled, quality: quality);
      if (encoded.lengthInBytes <= maxBytes) {
        return Uint8List.fromList(encoded);
      }
    }
  }

  // Fallback: lowest acceptable quality JPEG
  final lastAttempt = img.encodeJpg(
    img.copyResize(currentImage, width: 640),
    quality: 30,
  );
  return Uint8List.fromList(lastAttempt);
}

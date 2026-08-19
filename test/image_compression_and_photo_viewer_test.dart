import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shop_management_flutter/data/services/image_compression_service.dart';
import 'package:shop_management_flutter/ui/shared/app_photo_viewer_dialog.dart';
import 'package:shop_management_flutter/ui/shared/photo_attachment_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageCompressionService Tests', () {
    test('Images already <= 100KB are not re-compressed', () async {
      final smallBytes = Uint8List.fromList(List.generate(50 * 1024, (i) => i % 256));
      final result = await ImageCompressionService.compressImageBytes(smallBytes);
      expect(result.lengthInBytes, equals(50 * 1024));
    });

    test('Large images (> 500KB) are compressed to strictly <= 100KB', () async {
      // Create a high-resolution 1920x1080 synthetic image with complex gradient patterns
      final canvas = img.Image(width: 1920, height: 1080);
      for (int y = 0; y < 1080; y++) {
        for (int x = 0; x < 1920; x++) {
          final r = (x * 255 / 1920).round();
          final g = (y * 255 / 1080).round();
          final b = ((x + y) % 256).round();
          canvas.setPixelRgb(x, y, r, g, b);
        }
      }

      // Encode at 100% quality to generate a large payload (~600KB - 1.5MB)
      final largeBytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 100));
      expect(largeBytes.lengthInBytes, greaterThan(100 * 1024));

      // Run through our ImageCompressionService
      final compressed = await ImageCompressionService.compressImageBytes(largeBytes);

      // Verify final payload is strictly <= 100 KB
      expect(compressed.lengthInBytes, lessThanOrEqualTo(100 * 1024));

      // Verify the compressed image is valid and decodable
      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.width, greaterThan(0));
      expect(decoded.height, greaterThan(0));
    });
  });

  group('Photo Parsing & Viewer Widget Tests', () {
    test('PhotoAttachmentWidget correctly parses and joins multiple photo URLs', () {
      final urls = [
        'https://example.com/photo1.jpg',
        'https://example.com/photo2.jpg',
      ];
      final joined = PhotoAttachmentWidget.joinPhotoUrls(urls);
      expect(joined, contains('https://example.com/photo1.jpg'));
      expect(joined, contains('https://example.com/photo2.jpg'));

      final parsed = PhotoAttachmentWidget.parsePhotoUrls(joined);
      expect(parsed.length, equals(2));
      expect(parsed[0], equals('https://example.com/photo1.jpg'));
      expect(parsed[1], equals('https://example.com/photo2.jpg'));
    });

    testWidgets('AppPhotoViewerDialog mounts and renders page counter and close button', (tester) async {
      final dummyUrls = [
        'https://example.com/photo_a.jpg',
        'https://example.com/photo_b.jpg',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPhotoViewerDialog(
              photoUrls: dummyUrls,
              initialIndex: 0,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Photo 1 of 2'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });
}

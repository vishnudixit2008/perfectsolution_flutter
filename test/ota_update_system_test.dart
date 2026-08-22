import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shop_management_flutter/data/models/sale_item.dart';
import 'package:shop_management_flutter/data/services/app_update_downloader.dart';
import 'package:shop_management_flutter/data/services/auto_update_service.dart';
import 'package:shop_management_flutter/data/services/update_check_service.dart';
import 'package:shop_management_flutter/ui/shared/components/desktop_update_progress_widget.dart';
import 'package:shop_management_flutter/ui/shared/update_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OTA Update System - Downloader & Progress Logic', () {
    test('DownloadProgress calculates MBs, percentages, and speed strings accurately', () {
      const p1 = DownloadProgress(
        receivedBytes: 15 * 1024 * 1024,
        totalBytes: 30 * 1024 * 1024,
        progress: 0.5,
        speedBytesPerSec: 2.5 * 1024 * 1024,
        status: 'Downloading...',
      );

      expect(p1.percentage, equals(50));
      expect(p1.receivedMb, equals('15.0'));
      expect(p1.totalMb, equals('30.0'));
      expect(p1.speedFormatted, equals('2.5 MB/s'));

      const p2 = DownloadProgress(
        receivedBytes: 512 * 1024,
        totalBytes: 1024 * 1024,
        progress: 0.5,
        speedBytesPerSec: 512 * 1024,
        status: 'Downloading...',
      );

      expect(p2.speedFormatted, equals('512.0 KB/s'));
    });

    test('AppVersionStatus correctly identifies mandatory updates', () {
      final mandatoryStatus = AppVersionStatus(
        currentVersion: '1.2.0',
        latestVersion: '1.3.0',
        minRequiredVersion: '1.2.5',
        isMandatory: true,
        downloadUrl: 'https://example.com/app.apk',
        releaseNotes: 'Security patch',
        hasUpdate: true,
      );

      expect(mandatoryStatus.isMandatory, isTrue);
      expect(mandatoryStatus.hasUpdate, isTrue);

      final optionalStatus = AppVersionStatus(
        currentVersion: '1.2.5',
        latestVersion: '1.2.6',
        minRequiredVersion: '1.2.0',
        isMandatory: false,
        downloadUrl: 'https://example.com/app.apk',
        releaseNotes: 'Minor tweaks',
        hasUpdate: true,
      );

      expect(optionalStatus.isMandatory, isFalse);
      expect(optionalStatus.hasUpdate, isTrue);
    });
  });

  group('OTA Update System - Widget & Dialog UI States', () {
    testWidgets('UpdateDialog renders version info and release notes in info stage', (tester) async {
      final status = AppVersionStatus(
        currentVersion: '1.2.5',
        latestVersion: '1.2.6',
        minRequiredVersion: '1.0.0',
        isMandatory: false,
        downloadUrl: 'https://example.com/PerfectSolution-Setup.exe',
        releaseNotes: 'Faster invoice processing and in-app updates',
        hasUpdate: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateDialog(status: status),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('NEW UPDATE AVAILABLE'), findsOneWidget);
      expect(find.text('Version 1.2.6'), findsOneWidget);
      expect(find.text('Installed: v1.2.5'), findsOneWidget);
      expect(find.text('Latest: v1.2.6'), findsOneWidget);
      expect(find.text('Faster invoice processing and in-app updates'), findsOneWidget);
      expect(find.text('Download & Install'), findsOneWidget);
      expect(find.text('Skip for Now'), findsOneWidget);
    });

    testWidgets('UpdateDialog mandatory mode blocks skip button', (tester) async {
      final status = AppVersionStatus(
        currentVersion: '1.0.0',
        latestVersion: '1.2.6',
        minRequiredVersion: '1.2.0',
        isMandatory: true,
        downloadUrl: 'https://example.com/PerfectSolution-Setup.exe',
        releaseNotes: 'Critical security update',
        hasUpdate: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateDialog(status: status),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('MANDATORY UPDATE REQUIRED'), findsOneWidget);
      expect(find.text('Update Now (Required)'), findsOneWidget);
      expect(find.text('Skip for Now'), findsNothing);
    });

    testWidgets('DesktopUpdateProgressWidget does not render when idle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AutoUpdateService>.value(
            value: AutoUpdateService.instance,
            child: const Scaffold(
              body: DesktopUpdateProgressWidget(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining('Downloading Update'), findsNothing);
      expect(find.textContaining('UPDATE READY'), findsNothing);
    });
  });

  group('Invoice Fixes & Price Override Regression Tests', () {
    test('SaleItem accurately computes activePrice and line total with override', () {
      final item = SaleItem(
        id: 'test_prod_1',
        invoiceNo: 105,
        lineType: 'Product',
        itemDescription: 'SSD 512GB Kingston',
        quantity: 2,
        itemPrice: 2800.0, // catalog price
        customPrice: 2500.0, // overridden price
        totalAmount: 5000.0,
      );

      expect(item.itemPrice, equals(2800.0));
      expect(item.customPrice, equals(2500.0));
      expect(item.activePrice, equals(2500.0));
      expect(item.totalAmount, equals(5000.0));

      final cleared = item.copyWith(clearCustomPrice: true, totalAmount: 2 * 2800.0);
      expect(cleared.customPrice, isNull);
      expect(cleared.activePrice, equals(2800.0));
      expect(cleared.totalAmount, equals(5600.0));
    });

    test('SaleItem fromJson preserves overridden customPrice when unit_price differs', () {
      final json = {
        'id': 'line_101',
        'invoice_no': 550,
        'line_type': 'Product',
        'item_description': 'RAM 8GB DDR4',
        'quantity': 1,
        'item_price': 1600.0,
        'unit_price': 1400.0,
        'custom_price': 1400.0,
        'total_amount': 1400.0,
      };

      final parsed = SaleItem.fromJson(json);
      expect(parsed.itemPrice, equals(1600.0));
      expect(parsed.customPrice, equals(1400.0));
      expect(parsed.activePrice, equals(1400.0));
      expect(parsed.totalAmount, equals(1400.0));
    });
  });
}

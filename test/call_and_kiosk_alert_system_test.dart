import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shop_management_flutter/data/models/app_user.dart';
import 'package:shop_management_flutter/data/models/call_model.dart';
import 'package:shop_management_flutter/data/services/app_permissions_service.dart';
import 'package:shop_management_flutter/data/services/call_alert_audio_service.dart';
import 'package:shop_management_flutter/data/services/kiosk_broadcast_service.dart';
import 'package:shop_management_flutter/data/services/ui_preferences_service.dart';
import 'package:shop_management_flutter/data/services/user_permission_service.dart';
import 'package:shop_management_flutter/ui/shared/dialogs/call_alert_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('call_kiosk_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('ui_preferences');
    await Hive.openBox('user_preferences');
    await UiPreferencesService.init();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Call Alert Popup & Sound Lifecycle Tests', () {
    testWidgets('CallAlertDialog renders with single green Okay button and customer details', (tester) async {
      final call = CallModel(
        id: 101,
        date: DateTime.now(),
        name: 'Vikas Sharma',
        mobileNo: '9876543210',
        address: 'Sector 62, Noida',
        query: 'iPhone 13 screen flickering and battery drain',
        status: 'Pending',
        assignedTo: 'Asim',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => CallAlertDialog.show(context, call),
                child: const Text('Trigger Alert'),
              ),
            ),
          ),
        ),
      );

      // Trigger the alert dialog
      await tester.tap(find.text('Trigger Alert'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify UI elements
      expect(find.text('NEW CALL ASSIGNED'), findsOneWidget);
      expect(find.text('Vikas Sharma'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Sector 62, Noida'), findsOneWidget);
      expect(find.text('iPhone 13 screen flickering and battery drain'), findsOneWidget);
      expect(find.text('Job #101'), findsOneWidget);

      // Verify only ONE single green "Okay" button exists
      final okayBtnFinder = find.text('Okay');
      expect(okayBtnFinder, findsOneWidget);

      // Tap the Okay button
      await tester.tap(okayBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Dialog is dismissed
      expect(find.text('NEW CALL ASSIGNED'), findsNothing);
      expect(CallAlertAudioService.instance.isPlaying, isFalse);
    });

    test('Staff assignment matching accurately maps direct technician assignments', () {
      final staffUser = AppUser(
        email: 'ashimkumar0006@gmail.com',
        name: 'Asim Kumar',
        role: 'technician',
        pageAccess: {},
        actionAccess: {},
        isActive: true,
      );

      // Direct exact matches
      expect(UserPermissionService.isEntryDirectlyAssignedToUser('Asim', staffUser), isTrue);
      expect(UserPermissionService.isEntryDirectlyAssignedToUser('asim', staffUser), isTrue);
      expect(UserPermissionService.isEntryDirectlyAssignedToUser('Asim Kumar', staffUser), isTrue);
      expect(UserPermissionService.isEntryDirectlyAssignedToUser('ashimkumar0006@gmail.com', staffUser), isTrue);

      // Negative matches (assigned to someone else)
      expect(UserPermissionService.isEntryDirectlyAssignedToUser('Harsh', staffUser), isFalse);
      expect(UserPermissionService.isEntryDirectlyAssignedToUser('Mohan', staffUser), isFalse);
      expect(UserPermissionService.isEntryDirectlyAssignedToUser(null, staffUser), isFalse);
    });

    test('Admin and Kiosk accounts are safely excluded from call popup spam', () {
      final adminUser = AppUser(
        email: 'perfectsolutionnoida@gmail.com',
        name: 'Admin',
        role: 'admin',
        pageAccess: {},
        actionAccess: {},
        isActive: true,
      );

      final saleUser = AppUser(
        email: 'sale.perfectsolutionnoida@gmail.com',
        name: 'Sale Display',
        role: 'sale',
        pageAccess: {},
        actionAccess: {},
        isActive: true,
      );

      final technicianUser = AppUser(
        email: 'ashimkumar0006@gmail.com',
        name: 'Asim',
        role: 'technician',
        pageAccess: {},
        actionAccess: {},
        isActive: true,
      );

      expect(UserPermissionService.shouldReceiveCallAlertPopup(adminUser), isFalse);
      expect(UserPermissionService.shouldReceiveCallAlertPopup(saleUser), isFalse);
      expect(UserPermissionService.shouldReceiveCallAlertPopup(technicianUser), isTrue);
    });
  });

  group('Customer QR Display (Kiosk Mode) Dynamic Filtering Tests', () {
    test('Turning Kiosk Mode ON and OFF strictly updates local state and prevents false display', () async {
      // Default is OFF
      expect(UiPreferencesService.isKioskMode(), isFalse);

      // Turn ON
      await UiPreferencesService.setKioskMode(true);
      expect(UiPreferencesService.isKioskMode(), isTrue);

      // Turn OFF
      await UiPreferencesService.setKioskMode(false);
      expect(UiPreferencesService.isKioskMode(), isFalse);
    });

    test('KioskBroadcastPayload correctly encodes and decodes payment payload', () {
      final payload = KioskBroadcastPayload(
        amount: 1550.00,
        invoiceNo: 'INV-9021',
        customerName: 'Amit Saxena',
        upiId: 'perfectsolution@upi',
        upiName: 'Perfect Solution',
        isDirectPush: true,
      );

      final json = payload.toJson();
      expect(json['amount'], equals(1550.00));
      expect(json['invoiceNo'], equals('INV-9021'));
      expect(json['customerName'], equals('Amit Saxena'));

      final parsed = KioskBroadcastPayload.fromJson(json);
      expect(parsed.amount, equals(1550.00));
      expect(parsed.invoiceNo, equals('INV-9021'));
      expect(parsed.customerName, equals('Amit Saxena'));
    });
  });

  group('OEM Permissions & Brand Setup Matrix Tests', () {
    test('AppPermissionsService recognizes brand names and checks essential permissions correctly', () async {
      final brand = await AppPermissionsService.instance.getDeviceBrand();
      expect(brand, isA<String>());

      final status = await AppPermissionsService.instance.checkPermissions();
      expect(status.isAllEssentialGranted, isA<bool>());

      // Camera is optional, while core 4 permissions determine isAllEssentialGrantedForAndroid
      final modelWithCameraMissing = PermissionStatusModel(
        notificationsGranted: true,
        overlayGranted: true,
        batteryOptimizationIgnored: true,
        installPackagesGranted: true,
        cameraGranted: false, // Optional
        storageGranted: false,
      );
      expect(modelWithCameraMissing.isAllEssentialGrantedForAndroid, isTrue);

      final modelWithOverlayMissing = PermissionStatusModel(
        notificationsGranted: true,
        overlayGranted: false, // Mandatory
        batteryOptimizationIgnored: true,
        installPackagesGranted: true,
        cameraGranted: true,
        storageGranted: true,
      );
      expect(modelWithOverlayMissing.isAllEssentialGrantedForAndroid, isFalse);
    });
  });
}

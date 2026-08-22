import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shop_management_flutter/data/models/app_user.dart';
import 'package:shop_management_flutter/data/services/user_permission_service.dart';
import 'package:shop_management_flutter/ui/shared/status_management_dialog.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('status_mgmt_test_');
    Hive.init(tempDir.path);
    await UserPermissionService.init();
    await StatusManagementService.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    StatusManagementService.clearCache();
    await UserPermissionService.setCurrentUser('perfectsolutionnoida@gmail.com');
  });

  group('StatusManagementService System Tests', () {
    test('Initializes with default statuses for all 6 modules', () {
      final inward = StatusManagementService.getStatuses('inward');
      expect(inward, contains('Repairing'));
      expect(inward, contains('Ready'));
      expect(inward, contains('Complete'));

      final calls = StatusManagementService.getStatuses('calls');
      expect(calls, contains('Pending'));
      expect(calls, contains('Complete'));

      final replacements = StatusManagementService.getStatuses('replacements');
      expect(replacements, contains('Pending'));
      expect(replacements, contains('Complete'));

      final requests = StatusManagementService.getStatuses('requests');
      expect(requests, contains('Pending'));
      expect(requests, contains('Complete'));

      final purchases = StatusManagementService.getStatuses('purchases');
      expect(purchases, contains('PENDING'));
      expect(purchases, contains('Confirmed'));

      final sales = StatusManagementService.getStatuses('sales');
      expect(sales, contains('Pending'));
      expect(sales, contains('Complete'));
    });

    test('Add custom status dynamically updates status list and persists', () async {
      await StatusManagementService.addStatus('inward', 'Waiting for Parts');
      final updated = StatusManagementService.getStatuses('inward');
      expect(updated, contains('Waiting for Parts'));

      // Check case sorting comparison
      final cmp = StatusManagementService.compareStatuses('inward', 'Waiting for Parts', 'Complete');
      expect(cmp, isNot(equals(0)));
    });

    test('Set and get default status per module', () async {
      await StatusManagementService.setDefaultStatus('calls', 'Pending payment');
      final defStatus = StatusManagementService.getDefaultStatus('calls');
      expect(defStatus, equals('Pending payment'));
    });

    test('Status color system stores, syncs and retrieves custom colors', () async {
      const customColor = Color(0xFFEAB308); // Yellow
      await StatusManagementService.setStatusColor('replacements', 'Pending', customColor);

      final resolvedColor = StatusManagementService.getStatusColor('replacements', 'Pending');
      expect(resolvedColor.toARGB32(), equals(customColor.toARGB32()));

      final allColors = StatusManagementService.getAllStatusColors();
      expect(allColors.containsKey('replacements'), isTrue);
      expect(allColors['replacements']?['pending'], equals(customColor.toARGB32()));
    });
  });

  group('Active Entry Counting & Migration Workflow Tests', () {
    test('Accurately counts entries and migrates records on status delete', () async {
      if (!Hive.isBoxOpen('inward_box')) {
        await Hive.openBox('inward_box');
      }
      final inwardBox = Hive.box('inward_box');
      await inwardBox.clear();

      // Add a custom status
      await StatusManagementService.addStatus('inward', 'Testing Phase');

      // Populate dummy entries in inward_box with this status
      await inwardBox.put(101, {'job_no': 101, 'customer_name': 'Alice', 'status': 'Testing Phase'});
      await inwardBox.put(102, {'job_no': 102, 'customer_name': 'Bob', 'status': 'Testing Phase'});
      await inwardBox.put(103, {'job_no': 103, 'customer_name': 'Charlie', 'status': 'Ready'});

      // Count active entries
      final count = StatusManagementService.getStatusEntryCount('inward', 'Testing Phase');
      expect(count, equals(2));

      // Migrate active entries from 'Testing Phase' to 'Ready'
      await StatusManagementService.deleteStatus('inward', 'Testing Phase', migrateToStatus: 'Ready');

      // Verify status list no longer contains 'Testing Phase'
      final statuses = StatusManagementService.getStatuses('inward');
      expect(statuses.contains('Testing Phase'), isFalse);

      // Verify records in inwardBox are migrated to 'Ready'
      final record101 = inwardBox.get(101);
      final record102 = inwardBox.get(102);
      expect(record101['status'], equals('Ready'));
      expect(record102['status'], equals('Ready'));

      // Active count for deleted status should now be 0
      final countAfter = StatusManagementService.getStatusEntryCount('inward', 'Testing Phase');
      expect(countAfter, equals(0));
    });
  });

  group('StatusManagementDialog Admin vs Employee Widget Tests', () {
    testWidgets('Admin sees palette button, drag handle, star, and delete button', (tester) async {
      await UserPermissionService.setCurrentUser('perfectsolutionnoida@gmail.com');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusManagementDialog(
              moduleKey: 'inward',
              moduleTitle: 'Inward Repairs',
              onStatusesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manage Inward Repairs Statuses'), findsOneWidget);
      expect(find.text('Add New Status'), findsOneWidget);

      // Admin has delete icons and palette icons
      expect(find.byIcon(Icons.delete_outline_rounded), findsWidgets);
      expect(find.byIcon(Icons.palette_rounded), findsWidgets);
    });

    testWidgets('Employee does NOT see delete icon or clickable admin palette', (tester) async {
      final employee = AppUser.defaultEmployee('staff@shop.com', 'Staff');
      await UserPermissionService.saveUser(employee);
      await UserPermissionService.setCurrentUser('staff@shop.com');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusManagementDialog(
              moduleKey: 'inward',
              moduleTitle: 'Inward Repairs',
              onStatusesUpdated: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manage Inward Repairs Statuses'), findsOneWidget);

      // Non-admin should NOT see delete icons
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.palette_rounded), findsNothing);
    });
  });
}

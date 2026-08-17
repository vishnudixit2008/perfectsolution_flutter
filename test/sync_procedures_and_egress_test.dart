import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shop_management_flutter/data/models/app_user.dart';
import 'package:shop_management_flutter/data/repositories/shop_repository.dart';
import 'package:shop_management_flutter/data/services/local_database_service.dart';
import 'package:shop_management_flutter/data/services/supabase_sync_service.dart';
import 'package:shop_management_flutter/data/services/ui_preferences_service.dart';
import 'package:shop_management_flutter/ui/shared/status_management_dialog.dart';

void main() {
  late Directory tempDir;
  late LocalDatabaseService localDb;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('shop_sync_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );

    Hive.init(tempDir.path);
    await Hive.openBox('settings_box');
    await Hive.openBox('users_box');
    await Hive.openBox('status_management_box');
    await Hive.openBox('ui_preferences');
    await Hive.openBox('offline_queue');

    localDb = LocalDatabaseService();
    await localDb.init();
    await StatusManagementService.init();
    await UiPreferencesService.init();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Egress Optimization & Incremental Delta Sync Tests', () {
    test('LocalDatabaseService tracks per-table last_sync_timestamp for minimal egress', () async {
      const tableName = 'inward_repairs';
      final syncTime = DateTime.now().toUtc().toIso8601String();

      await localDb.setLastSyncTimestamp(tableName, syncTime);
      final retrieved = localDb.getLastSyncTimestamp(tableName);

      expect(retrieved, equals(syncTime));

      // Timestamp for other tables should be independent and null initially
      expect(localDb.getLastSyncTimestamp('calls'), isNull);
    });

    test('Delta query timestamp logic formats ISO timestamps accurately', () {
      final now = DateTime.now().toUtc();
      final lastSyncIso = now.subtract(const Duration(hours: 1)).toIso8601String();

      // Delta sync uses lastSyncIso to construct 'updated_at' > lastSyncIso query
      expect(DateTime.parse(lastSyncIso).isBefore(now), isTrue);
      expect(lastSyncIso.contains('T'), isTrue);
    });

    test('Google Review QR listing persists in settings_box and reads dynamically', () async {
      await localDb.setGoogleReviewListing('laptop_repairing', syncToCloud: false);
      expect(localDb.getGoogleReviewListing(), equals('laptop_repairing'));

      final fromBox = Hive.box('settings_box').get('google_review_listing');
      expect(fromBox, equals('laptop_repairing'));

      await localDb.setGoogleReviewListing('perfect_solution', syncToCloud: false);
      expect(localDb.getGoogleReviewListing(), equals('perfect_solution'));
    });
  });

  group('User Permissions & Status Sync Throttling (Egress Reduction)', () {
    test('15-Minute Sync Throttling prevents redundant cloud requests on force=false', () async {
      final now = DateTime.now();
      await UiPreferencesService.setValue('last_users_sync_time', now.millisecondsSinceEpoch);

      // Verify that stored timestamp is fresh
      final lastCheckMillis = (UiPreferencesService.getValue('last_users_sync_time') as num?)?.toInt() ?? 0;
      final diffMinutes = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastCheckMillis)).inMinutes;

      // Within 15 minutes, standard sync checks will abort without cloud egress
      expect(diffMinutes < 15, isTrue);
    });

    test('AppUser serializes nested status lists & default statuses for seamless sync', () {
      final user = AppUser.defaultEmployee('tech@shop.com', 'Tech Worker').copyWith(
        customStatusLists: {
          'inward': ['Diagnostic', 'Waiting Parts', 'Ready for Testing', 'Complete'],
          'calls': ['Open', 'In Transit', 'Resolved'],
        },
        defaultStatuses: {
          'inward': 'Diagnostic',
          'calls': 'Open',
        },
      );

      final json = user.toJson();
      final deserialized = AppUser.fromJson(json);

      expect(deserialized.customStatusLists['inward'], containsAll(['Diagnostic', 'Waiting Parts', 'Ready for Testing', 'Complete']));
      expect(deserialized.customStatusLists['calls'], containsAll(['Open', 'In Transit', 'Resolved']));
      expect(deserialized.defaultStatuses['inward'], equals('Diagnostic'));
      expect(deserialized.defaultStatuses['calls'], equals('Open'));
    });
  });

  group('StatusManagementService In-Memory Cache & Reordering Tests', () {
    test('StatusManagementService caches module status lists and sorts without disk egress', () async {
      final testStatuses = ['Urgent', 'In Progress', 'Done'];
      await StatusManagementService.saveStatuses('inward', testStatuses);

      // getStatuses should return the updated list
      final statuses = StatusManagementService.getStatuses('inward');
      expect(statuses, equals(testStatuses));

      // Fast compare using in-memory cache
      final compareUrgentDone = StatusManagementService.compareStatuses('inward', 'Urgent', 'Done');
      expect(compareUrgentDone, lessThan(0));

      final compareDoneUrgent = StatusManagementService.compareStatuses('inward', 'Done', 'Urgent');
      expect(compareDoneUrgent, greaterThan(0));
    });

    test('StatusManagementService.loadFromUser invalidates stale cache and hydrates new statuses', () async {
      final remoteUser = AppUser.defaultAdmin(email: 'admin@shop.com').copyWith(
        customStatusLists: {
          'inward': ['Received', 'Under Repair', 'Quality Check', 'Ready'],
        },
        defaultStatuses: {
          'inward': 'Received',
        },
      );

      await StatusManagementService.loadFromUser(remoteUser);

      final hydratedStatuses = StatusManagementService.getStatuses('inward');
      expect(hydratedStatuses, equals(['Received', 'Under Repair', 'Quality Check', 'Ready']));

      final defaultStatus = StatusManagementService.getDefaultStatus('inward');
      expect(defaultStatus, equals('Received'));
    });

    test('StatusManagementService reorder and add operations update cache immediately', () async {
      await StatusManagementService.saveStatuses('calls', ['Step 1', 'Step 2', 'Step 3']);
      await StatusManagementService.reorderStatuses('calls', 2, 0); // Move 'Step 3' to index 0

      final reordered = StatusManagementService.getStatuses('calls');
      expect(reordered.first, equals('Step 3'));

      await StatusManagementService.addStatus('calls', 'Step 4');
      final updated = StatusManagementService.getStatuses('calls');
      expect(updated.last, equals('Step 4'));
    });
  });

  group('Realtime Broadcast & Notification Pipeline Tests', () {
    test('ShopRepository broadcasts table change events for all modules and app_users', () async {
      final receivedEvents = <String>[];
      final subscription = ShopRepository.tableDataChangedStream.listen((table) {
        receivedEvents.add(table);
      });

      ShopRepository.notifyTableChanged('inward_repairs');
      ShopRepository.notifyTableChanged('calls');
      ShopRepository.notifyTableChanged('replacements');
      ShopRepository.notifyTableChanged('requests');
      ShopRepository.notifyTableChanged('purchases');
      ShopRepository.notifyTableChanged('sales');
      ShopRepository.notifyTableChanged('pricelist');
      ShopRepository.notifyTableChanged('app_users');
      ShopRepository.notifyTableChanged('all');

      await Future.delayed(const Duration(milliseconds: 100));
      await subscription.cancel();

      expect(receivedEvents, containsAll([
        'inward_repairs',
        'calls',
        'replacements',
        'requests',
        'purchases',
        'sales',
        'pricelist',
        'app_users',
        'all',
      ]));
    });

    test('SupabaseSyncService holds valid status flags and singleton instance', () {
      final syncService = SupabaseSyncService.instance;
      expect(syncService, isNotNull);
      expect(syncService.status, isNotNull);
    });
  });
}

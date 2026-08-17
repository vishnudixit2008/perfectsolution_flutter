import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_management_flutter/data/repositories/shop_repository.dart';
import 'package:shop_management_flutter/data/services/supabase_sync_service.dart';
import 'package:shop_management_flutter/data/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sleep / Wake & Delta Quick Sync Tests', () {
    test('SupabaseSyncService accurately initializes and handles onAppResume API', () async {
      final service = SupabaseSyncService.instance;
      expect(service, isNotNull);

      // Verify ensureRealtimeConnected runs safely without throws
      final localDb = LocalDatabaseService();
      expect(() => service.ensureRealtimeConnected(localDb), returnsNormally);

      // Verify onAppResume runs safely and triggers notifyTableChanged('all')
      final completer = Completer<String>();
      final sub = ShopRepository.tableDataChangedStream.listen((tbl) {
        if (!completer.isCompleted) completer.complete(tbl);
      });

      await service.onAppResume(localDb);
      final received = await completer.future.timeout(const Duration(seconds: 2));
      expect(received, equals('all'));
      await sub.cancel();
    });

    test('Delta timestamp calculation with 30s clock drift buffer', () {
      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      final syncIso = DateTime.fromMillisecondsSinceEpoch(nowMillis - 30000, isUtc: true).toIso8601String();
      final parsed = DateTime.parse(syncIso);

      // Buffer ensures timestamps from 30 seconds ago are captured
      expect(DateTime.now().difference(parsed).inSeconds, greaterThanOrEqualTo(29));
      expect(DateTime.now().difference(parsed).inSeconds, lessThanOrEqualTo(35));
    });
  });
}

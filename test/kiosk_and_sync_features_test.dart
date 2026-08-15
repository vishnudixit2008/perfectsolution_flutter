import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_management_flutter/data/services/kiosk_broadcast_service.dart';
import 'package:shop_management_flutter/data/services/kiosk_overlay_helper.dart';
import 'package:shop_management_flutter/data/services/supabase_sync_service.dart';
import 'package:shop_management_flutter/data/repositories/shop_repository.dart';

void main() {
  group('Kiosk Broadcast & UPI Real-time Payload Tests', () {
    test('KioskBroadcastPayload correctly serializes and deserializes upiId and upiName', () {
      final payload = KioskBroadcastPayload(
        amount: 2499.50,
        invoiceNo: '#1042',
        customerName: 'Rahul Verma',
        upiId: 'perfectsolution@upi',
        upiName: 'Perfect Solution Noida',
      );

      final json = payload.toJson();
      expect(json['amount'], equals(2499.50));
      expect(json['invoiceNo'], equals('#1042'));
      expect(json['customerName'], equals('Rahul Verma'));
      expect(json['upiId'], equals('perfectsolution@upi'));
      expect(json['upiName'], equals('Perfect Solution Noida'));

      final parsed = KioskBroadcastPayload.fromJson(json);
      expect(parsed.amount, equals(2499.50));
      expect(parsed.invoiceNo, equals('#1042'));
      expect(parsed.customerName, equals('Rahul Verma'));
      expect(parsed.upiId, equals('perfectsolution@upi'));
      expect(parsed.upiName, equals('Perfect Solution Noida'));
    });

    test('KioskOverlayHelper runs safely without crashing in test/desktop environments', () async {
      final isGranted = await KioskOverlayHelper.isOverlayPermissionGranted();
      expect(isGranted, isTrue);

      final isBatteryIgnored = await KioskOverlayHelper.isBatteryOptimizationIgnored();
      expect(isBatteryIgnored, isTrue);

      // Should not throw
      expect(() async => await KioskOverlayHelper.requestOverlayPermission(), returnsNormally);
      expect(() async => await KioskOverlayHelper.requestIgnoreBatteryOptimization(), returnsNormally);
      expect(() async => await KioskOverlayHelper.bringAppToFront(), returnsNormally);
    });

    test('SupabaseSyncService accurately holds SyncStatus states', () {
      final service = SupabaseSyncService.instance;
      expect(service.status, isNotNull);
      expect(service.statusMessage, isNotEmpty);
    });

    test('ShopRepository onTableDataChanged emits event when notifyTableChanged is called', () async {
      final completer = Completer<String>();
      final testSub = ShopRepository.tableDataChangedStream.listen((table) {
        if (!completer.isCompleted) completer.complete(table);
      });

      ShopRepository.notifyTableChanged('inward_repairs');
      final received = await completer.future.timeout(const Duration(seconds: 2));
      expect(received, equals('inward_repairs'));
      await testSub.cancel();
    });
  });
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class KioskBroadcastPayload {
  final double amount;
  final String? invoiceNo;
  final String? customerName;
  final String? upiId;
  final String? upiName;

  KioskBroadcastPayload({
    required this.amount,
    this.invoiceNo,
    this.customerName,
    this.upiId,
    this.upiName,
  });

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'invoiceNo': invoiceNo,
      'customerName': customerName,
      'upiId': upiId,
      'upiName': upiName,
    };
  }

  factory KioskBroadcastPayload.fromJson(Map<String, dynamic> json) {
    return KioskBroadcastPayload(
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      invoiceNo: json['invoiceNo'] as String?,
      customerName: json['customerName'] as String?,
      upiId: json['upiId'] as String?,
      upiName: json['upiName'] as String?,
    );
  }
}

class KioskBroadcastService {
  static final KioskBroadcastService instance = KioskBroadcastService._internal();

  KioskBroadcastService._internal();

  RealtimeChannel? _channel;
  final StreamController<KioskBroadcastPayload> _showQrController = StreamController<KioskBroadcastPayload>.broadcast();
  final StreamController<void> _dismissQrController = StreamController<void>.broadcast();

  Stream<KioskBroadcastPayload> get onShowQr => _showQrController.stream;
  Stream<void> get onDismissQr => _dismissQrController.stream;

  bool _isSubscribed = false;

  /// Initialize and subscribe to the real-time Supabase WebSocket broadcast channel
  void init() {
    if (_isSubscribed) return;

    try {
      final supabase = Supabase.instance.client;
      _channel = supabase.channel('kiosk_payment_broadcast');

      _channel!.onBroadcast(
        event: 'SHOW_QR',
        callback: (payload) {
          debugPrint('KioskBroadcastService: Received SHOW_QR broadcast -> $payload');
          try {
            final data = KioskBroadcastPayload.fromJson(payload);
            _showQrController.add(data);
          } catch (e) {
            debugPrint('Error parsing KioskBroadcastPayload: $e');
          }
        },
      );

      _channel!.onBroadcast(
        event: 'DISMISS_QR',
        callback: (payload) {
          debugPrint('KioskBroadcastService: Received DISMISS_QR broadcast');
          _dismissQrController.add(null);
        },
      );

      _channel!.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _isSubscribed = true;
          debugPrint('KioskBroadcastService: Subscribed to kiosk_payment_broadcast channel');
        } else {
          debugPrint('KioskBroadcastService: Subscription status: $status, error: $error');
        }
      });
    } catch (e) {
      debugPrint('KioskBroadcastService init error (Supabase might not be initialized): $e');
    }
  }

  /// Broadcast a payment QR display event to all listening Kiosk display devices
  Future<bool> sendQrToKiosk({
    required double amount,
    String? invoiceNo,
    String? customerName,
    String? upiId,
    String? upiName,
  }) async {
    init(); // Ensure subscribed
    if (_channel == null) return false;

    final payload = KioskBroadcastPayload(
      amount: amount,
      invoiceNo: invoiceNo,
      customerName: customerName,
      upiId: upiId,
      upiName: upiName,
    );

    try {
      await _channel!.sendBroadcastMessage(
        event: 'SHOW_QR',
        payload: payload.toJson(),
      );
      debugPrint('KioskBroadcastService: Sent SHOW_QR payload for amount ₹$amount');
      return true;
    } catch (e) {
      debugPrint('KioskBroadcastService: Failed to broadcast SHOW_QR: $e');
      return false;
    }
  }

  /// Broadcast a command to dismiss the active QR screen from all Kiosk display devices
  Future<bool> dismissKioskQr() async {
    init(); // Ensure subscribed
    if (_channel == null) return false;

    try {
      await _channel!.sendBroadcastMessage(
        event: 'DISMISS_QR',
        payload: {},
      );
      debugPrint('KioskBroadcastService: Sent DISMISS_QR broadcast');
      return true;
    } catch (e) {
      debugPrint('KioskBroadcastService: Failed to broadcast DISMISS_QR: $e');
      return false;
    }
  }
}

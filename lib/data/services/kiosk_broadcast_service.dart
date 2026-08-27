import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fcm_push_sender_service.dart';

class KioskBroadcastPayload {
  final double amount;
  final String? invoiceNo;
  final String? customerName;
  final String? upiId;
  final String? upiName;
  final bool isDirectPush;

  KioskBroadcastPayload({
    required this.amount,
    this.invoiceNo,
    this.customerName,
    this.upiId,
    this.upiName,
    this.isDirectPush = false,
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
      isDirectPush: false,
    );
  }
}

class KioskBroadcastService {
  static final KioskBroadcastService instance = KioskBroadcastService._internal();

  KioskBroadcastService._internal();

  RealtimeChannel? _channel;
  final StreamController<KioskBroadcastPayload> _showQrController = StreamController<KioskBroadcastPayload>.broadcast();
  final StreamController<void> _dismissQrController = StreamController<void>.broadcast();
  final StreamController<Map<String, String>> _activeUpiChangedController =
      StreamController<Map<String, String>>.broadcast();

  Stream<KioskBroadcastPayload> get onShowQr => _showQrController.stream;
  Stream<void> get onDismissQr => _dismissQrController.stream;
  Stream<Map<String, String>> get onActiveUpiChanged =>
      _activeUpiChangedController.stream;

  bool _isSubscribed = false;
  bool _isInitializing = false;
  KioskBroadcastPayload? latestPendingQrPayload;

  /// Displays the QR code locally on this kiosk device without rebroadcasting
  void showLocalQr({
    required double amount,
    String? invoiceNo,
    String? customerName,
    String? upiId,
    String? upiName,
    bool isDirectPush = true,
  }) {
    final payload = KioskBroadcastPayload(
      amount: amount,
      invoiceNo: invoiceNo,
      customerName: customerName,
      upiId: upiId,
      upiName: upiName,
      isDirectPush: isDirectPush,
    );
    latestPendingQrPayload = payload;
    _showQrController.add(payload);
    debugPrint('KioskBroadcastService: Displaying local QR for amount ₹$amount, upi: $upiId');
  }

  void clearPendingQr() {
    latestPendingQrPayload = null;
  }

  /// Initialize and subscribe to the real-time Supabase WebSocket broadcast channel
  void init() {
    if (_isSubscribed || _isInitializing) return;
    _isInitializing = true;

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

      _channel!.onBroadcast(
        event: 'ACTIVE_UPI_CHANGED',
        callback: (payload) {
          debugPrint('KioskBroadcastService: Received ACTIVE_UPI_CHANGED -> $payload');
          try {
            final upiId = payload['upiId']?.toString() ?? '';
            final upiName = payload['upiName']?.toString() ?? '';
            if (upiId.isNotEmpty) {
              _activeUpiChangedController.add({'upiId': upiId, 'upiName': upiName});
            }
          } catch (e) {
            debugPrint('Error parsing ACTIVE_UPI_CHANGED: $e');
          }
        },
      );

      _channel!.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _isSubscribed = true;
          _isInitializing = false;
          debugPrint('KioskBroadcastService: Subscribed to kiosk_payment_broadcast channel');
        } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.closed) {
          _isSubscribed = false;
          _isInitializing = false;
          debugPrint('KioskBroadcastService: Subscription status: $status');
        }
      });
    } catch (e) {
      _isInitializing = false;
      debugPrint('KioskBroadcastService init error: $e');
    }
  }

  /// Broadcast active UPI ID change in real time to all connected devices
  Future<bool> broadcastActiveUpiChanged({
    required String upiId,
    String? upiName,
  }) async {
    init(); // Ensure subscribed
    if (_channel == null) return false;

    try {
      await _channel!.sendBroadcastMessage(
        event: 'ACTIVE_UPI_CHANGED',
        payload: {
          'upiId': upiId,
          'upiName': upiName ?? '',
        },
      );
      debugPrint('KioskBroadcastService: Sent ACTIVE_UPI_CHANGED -> $upiId');
      return true;
    } catch (e) {
      debugPrint('KioskBroadcastService: Failed to broadcast ACTIVE_UPI_CHANGED: $e');
      return false;
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

      // Also send high-priority FCM push to wake sleeping / locked kiosk devices
      unawaited(FcmPushSenderService.instance.sendKioskQrPush(
        upiId: upiId ?? '',
        amount: amount,
        customerName: customerName,
        note: invoiceNo,
      ));

      debugPrint('KioskBroadcastService: Sent SHOW_QR payload for amount ₹$amount, upi: $upiId');
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

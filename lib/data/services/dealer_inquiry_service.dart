// ==============================================================================
// Dealer Inquiry Queue Service
// Purpose: Manages background WhatsApp dispatch jobs via Supabase dealer_inquiry_queue
// Handles enqueuing, status tracking, and realtime delivery updates
// ==============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dealer.dart';

class DealerInquiryItem {
  final String id;
  final String requestId;
  final String? dealerId;
  final String dealerName;
  final String dealerPhone;
  final String itemText;
  final String? photoUrl;
  final String status; // pending, sending, sent, failed
  final double? quoteAmount;
  final String? quoteNotes;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? sentAt;

  const DealerInquiryItem({
    required this.id,
    required this.requestId,
    this.dealerId,
    required this.dealerName,
    required this.dealerPhone,
    required this.itemText,
    this.photoUrl,
    this.status = 'pending',
    this.quoteAmount,
    this.quoteNotes,
    this.errorMessage,
    required this.createdAt,
    this.sentAt,
  });

  factory DealerInquiryItem.fromJson(Map<String, dynamic> json) {
    return DealerInquiryItem(
      id: json['id']?.toString() ?? '',
      requestId: json['request_id']?.toString() ?? '',
      dealerId: json['dealer_id']?.toString(),
      dealerName: json['dealer_name']?.toString() ?? '',
      dealerPhone: json['dealer_phone']?.toString() ?? '',
      itemText: json['item_text']?.toString() ?? '',
      photoUrl: json['photo_url']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      quoteAmount: json['quote_amount'] is num
          ? (json['quote_amount'] as num).toDouble()
          : double.tryParse(json['quote_amount']?.toString() ?? ''),
      quoteNotes: json['quote_notes']?.toString(),
      errorMessage: json['error_message']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      sentAt: json['sent_at'] != null
          ? DateTime.tryParse(json['sent_at'].toString())
          : null,
    );
  }
}

class DealerInquiryService {
  /// Checks whether Supabase is initialized and reachable
  static bool get isConfigured {
    try {
      return Supabase.instance.client.auth.currentSession != null || 
             Supabase.instance.client.rest.headers.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Enqueues inquiry requests for multiple dealers into the server queue.
  /// Returns count of successfully enqueued jobs.
  static Future<int> enqueueInquiries({
    required String requestId,
    required String itemText,
    String? photoUrl,
    required List<Dealer> targetDealers,
  }) async {
    if (targetDealers.isEmpty) return 0;

    try {
      final client = Supabase.instance.client;
      final rows = <Map<String, dynamic>>[];

      for (final dealer in targetDealers) {
        if (dealer.mobileNo == null || dealer.mobileNo!.trim().isEmpty) continue;
        rows.add({
          'request_id': requestId,
          'dealer_id': dealer.id,
          'dealer_name': dealer.name,
          'dealer_phone': dealer.mobileNo!.trim(),
          'item_text': itemText.trim(),
          'photo_url': (photoUrl != null && photoUrl.trim().isNotEmpty) ? photoUrl.trim() : null,
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      if (rows.isEmpty) return 0;

      await client.from('dealer_inquiry_queue').insert(rows);
      return rows.length;
    } catch (e) {
      if (kDebugMode) {
        print('Error enqueuing dealer inquiries: $e');
      }
      rethrow;
    }
  }

  /// Fetches all inquiries associated with a specific request ID
  static Future<List<DealerInquiryItem>> getInquiriesForRequest(String requestId) async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('dealer_inquiry_queue')
          .select()
          .eq('request_id', requestId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => DealerInquiryItem.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching inquiries for request $requestId: $e');
      }
      return const [];
    }
  }

  /// Subscribes to realtime status updates on dealer inquiries for a request
  static RealtimeChannel? subscribeToRequestInquiries({
    required String requestId,
    required Function(DealerInquiryItem item) onStatusUpdate,
  }) {
    try {
      final client = Supabase.instance.client;
      final channel = client.channel('public:dealer_inquiry_queue:$requestId');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'dealer_inquiry_queue',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'request_id',
          value: requestId,
        ),
        callback: (payload) {
          final newRecord = payload.newRecord;
          if (newRecord.isNotEmpty) {
            final item = DealerInquiryItem.fromJson(newRecord);
            onStatusUpdate(item);
          }
        },
      ).subscribe();

      return channel;
    } catch (e) {
      if (kDebugMode) {
        print('Realtime subscription error for inquiries: $e');
      }
      return null;
    }
  }
}

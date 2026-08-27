import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../models/call_model.dart';

class FcmPushSenderService {
  static final FcmPushSenderService instance = FcmPushSenderService._internal();
  FcmPushSenderService._internal();

  static const String _projectId = 'perfect-solution-b4d6e';

  // Firebase Service Account Credentials provided by the user
  static const Map<String, dynamic> _serviceAccountJson = {
    "type": "service_account",
    "project_id": "perfect-solution-b4d6e",
    "private_key_id": "be9bd4addb88b8b5f37831091ddcc8781f0754aa",
    "private_key":
        "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDjJ0a155WHRCkc\nIixlT5GvjvjV9dYO57LiwQKREe/7QFWPkG6fWjQbEJp8zkqH5xJqjgAWKTuoYajo\n62GruXAVa/i1Loe2IC9sLjkS0CE+LBYTz4fnBe5OncBXfL/cwTPP0Wmwyxr+Sh1g\nrD3RAQr80dIrocuvNCKNsQr1nG5SrrRziSsyz18jQ+uryK5pzd3xcIM5PgWGn0q+\nno7Z22N7lmLA8X6yr7p2nbDql7Qdt5OV+Vd0oMEEF6cOBEyzZyojhWx0f4am/3aA\nLORmWVlmi7UZP1kj6sfPVZOTld2+MffbvXA7L6Cx4/WrWFp9BYpHd/6dpDHSYybh\ncLNsZAHDAgMBAAECggEAAS/woUsPL/sUuNnqs+gat6TBNFIIhUa5bX16HNgusGqG\n2CFztAedx+DdG1rkAgeRpcF/s1Zh43hVyP5ODANvROkt6Su0K4J8v+RBSmypaNn1\nOX81PW2C+dBxbXbnhEqzBSC/B8ayOjZ3vfhkMqUqimbEsgb847WwPPRrBQEd+IBi\nc283f/Sw68qbsZDrTNtJzhc6AECY6VUvEb1PANgqORx0BftXq9NMB733hwVjVzlx\nprBm5RaPl7RApWLsj10X08sHxKN5GRUhhpGJvYd8O6FzLu646cW3EuMQL90w5VrM\nSKhAt4n387PF6s4Rac85mE/fT27eYAwWk4El3kiuOQKBgQD6cuODxTU6+Zwb+bf7\ntKZpVRp4iobxvnQfrQumOR8B6MMocbqVqCNFmF/bRO7B2j9s7ypB0vi6HD3X3cvZ\n+AiI6zUy+LUaMH2iCWNBEc64SLnDr2zgdoxPfFt36eC8rWnF10iejg65bXA8/tIo\nLTMv/6N+j1jz0ZFDV7HBNr6FuQKBgQDoMDQdH51FWTkbIdezsu0gLI4pQVoBjFVY\npFzq/yVk06P960EJs+p0FWQW8N00GmfIPcMrKdX/qPXEJLmMBO37h5c90TwFZ0XC\nk0zUGlc1LJYUuikeZ4Y8HkEvDEfF+63ardc1uld9rs411k1zoLrINL2mmPNYwPX0\naaziP6rBWwKBgBcklrGOf6S7fBl5se6oetgw7QlGg8HC/6gNrY3mqV7by2zpVXyO\n1PORaQoyDH4NVN8UGquKe0F3ap+P905lBSTh10CmitWotXNLushAhQGydrgGdeEo\nEz8lFq62BfZpb+TASA2ewu2Pl1eLlI/x3VEKJmmDhYzCSNIYQGzCSkjBAoGBAOK/\nGFWMpyivPm55uU2bIak2+cneMUirxDkhokA31UvGxzLUiJoyInck4K7qoAse8lUB\nw9QmMf9PAFuBRdYwhjwKKS/MYqIgPWcMNI45/wpFtXceacNwdA3Huf55Lqpw41JY\nTIACryhlCqpW0yJlR6L2pnLIkXUOU+NRQ+1bIaVbAoGAG1u5vtRFRxDQRSgZ53cp\nYX8xWpWhfmkSf+hg4OrSdT28OXQa+trm5WI2BAUYxxDmU+oGb40N4PmViwkDWjUe\nmYvA12SYIvyNAVdWKDHQjdfOEVGqbGDY6pabOtcPozN/w7KXfTPkvbcQQ0Ooaje1\nKMs7Ijo6OlQz/CA2RbevUUU=\n-----END PRIVATE KEY-----\n",
    "client_email":
        "firebase-adminsdk-fbsvc@perfect-solution-b4d6e.iam.gserviceaccount.com",
    "client_id": "115651132583597455240",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
  };

  AutoRefreshingAuthClient? _cachedClient;
  DateTime? _tokenExpiry;

  /// Get or refresh Google OAuth2 authenticated client
  Future<AutoRefreshingAuthClient?> _getAuthClient() async {
    try {
      if (_cachedClient != null &&
          _tokenExpiry != null &&
          DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
        return _cachedClient;
      }

      final accountCredentials = ServiceAccountCredentials.fromJson(_serviceAccountJson);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await clientViaServiceAccount(accountCredentials, scopes);
      _cachedClient = client;
      _tokenExpiry = client.credentials.accessToken.expiry;
      return client;
    } catch (e) {
      debugPrint('FcmPushSenderService: Failed to authenticate Google Service Account: $e');
      return null;
    }
  }

  /// Sends a high-priority Call Assignment Push to the assigned user's device(s)
  Future<void> sendCallAssignmentPush(CallModel call) async {
    final assignedStaff = call.assignedTo.trim();
    if (assignedStaff.isEmpty || assignedStaff == 'N/A') return;

    final lower = assignedStaff.toLowerCase();
    if (AppUser.isPermanentAdmin(lower) ||
        lower == 'sale.perfectsolutionnoida@gmail.com' ||
        lower == 'perfect solution (admin)') {
      debugPrint('FcmPushSenderService: Skipping call push for admin/sale user: $assignedStaff');
      return;
    }

    try {
      final tokens = await _getTargetTokens(assignedStaff);
      if (tokens.isEmpty) {
        debugPrint('FcmPushSenderService: No registered device tokens found for assigned user: $assignedStaff');
        return;
      }

      final client = await _getAuthClient();
      if (client == null) return;

      final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$_projectId/messages:send');

      for (final token in tokens) {
        final payload = {
          "message": {
            "token": token,
            "data": {
              "type": "call_assignment",
              "call_id": call.id.toString(),
              "name": call.name,
              "mobile": call.mobileNo ?? "",
              "address": call.address ?? "",
              "query": call.query ?? "",
              "assigned_to": call.assignedTo,
              "status": call.status,
              "date": call.date.toIso8601String(),
            },
            "android": {
              "priority": "high",
              "direct_boot_ok": true
            }
          }
        };

        final response = await client.post(
          url,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          debugPrint('FcmPushSenderService: Successfully sent call push to token (${token.substring(0, 10)}...)');
        } else {
          debugPrint('FcmPushSenderService: Failed to send call push: ${response.statusCode} - ${response.body}');
          // Auto-cleanup stale/unregistered tokens
          if (response.statusCode == 404) {
            final body = jsonDecode(response.body);
            final errorCode = body['error']?['details']?[0]?['errorCode']?.toString() ?? '';
            if (errorCode == 'UNREGISTERED') {
              debugPrint('FcmPushSenderService: Removing UNREGISTERED token from Supabase');
              await _removeStaleToken(token);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('FcmPushSenderService: Error sending call push: $e');
    }
  }

  /// Removes a stale/unregistered FCM token from Supabase shop_settings
  Future<void> _removeStaleToken(String staleToken) async {
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('shop_settings')
          .select('value')
          .eq('key', 'user_fcm_tokens')
          .maybeSingle();

      if (res == null || res['value'] == null) return;

      final map = Map<String, dynamic>.from(res['value'] as Map);
      bool changed = false;
      for (final key in map.keys.toList()) {
        if (map[key] is List) {
          final before = (map[key] as List).length;
          map[key] = (map[key] as List).where((t) => t.toString() != staleToken).toList();
          if ((map[key] as List).length != before) changed = true;
        }
      }
      if (changed) {
        await supabase.from('shop_settings').update({'value': map}).eq('key', 'user_fcm_tokens');
        debugPrint('FcmPushSenderService: Stale token removed from Supabase');
      }
    } catch (e) {
      debugPrint('FcmPushSenderService: Error removing stale token: $e');
    }
  }

  /// Sends a high-priority Kiosk Payment QR Push to wake up Kiosk display devices
  Future<void> sendKioskQrPush({
    required String upiId,
    required double amount,
    String? customerName,
    String? note,
  }) async {
    try {
      final tokens = await _getKioskTokens();
      if (tokens.isEmpty) {
        debugPrint('FcmPushSenderService: No registered kiosk device tokens found');
        return;
      }

      final client = await _getAuthClient();
      if (client == null) return;

      final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$_projectId/messages:send');

      for (final token in tokens) {
        final payload = {
          "message": {
            "token": token,
            "data": {
              "type": "kiosk_qr",
              "upi_id": upiId,
              "amount": amount.toStringAsFixed(2),
              "customer_name": customerName ?? "",
              "note": note ?? "",
            },
            "android": {
              "priority": "high",
              "direct_boot_ok": true
            }
          }
        };

        final response = await client.post(
          url,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          debugPrint('FcmPushSenderService: Successfully sent kiosk QR push to token');
        } else {
          debugPrint('FcmPushSenderService: Failed to send kiosk QR push: ${response.statusCode} - ${response.body}');
          if (response.statusCode == 404) {
            await _removeStaleToken(token);
          }
        }
      }
    } catch (e) {
      debugPrint('FcmPushSenderService: Error sending kiosk QR push: $e');
    }
  }

  /// Retrieves target user device tokens from Supabase `shop_settings`
  Future<List<String>> _getTargetTokens(String userIdentifier) async {
    try {
      final supabase = Supabase.instance.client;

      final res = await supabase
          .from('shop_settings')
          .select('value')
          .eq('key', 'user_fcm_tokens')
          .maybeSingle();

      if (res == null || res['value'] == null) {
        debugPrint('FcmPushSenderService: No "user_fcm_tokens" key in shop_settings yet');
        return [];
      }

      final map = Map<String, dynamic>.from(res['value'] as Map);
      final keyClean = userIdentifier.trim().toLowerCase();

      final List<String> matchingTokens = [];
      for (final entry in map.entries) {
        final entryKey = entry.key.trim().toLowerCase();
        if (entryKey == keyClean || entryKey.contains(keyClean) || keyClean.contains(entryKey)) {
          if (entry.value is List) {
            matchingTokens.addAll((entry.value as List).map((e) => e.toString()));
          } else if (entry.value is String) {
            matchingTokens.add(entry.value.toString());
          }
        }
      }

      final uniqueTokens = matchingTokens.toSet().toList();
      debugPrint('FcmPushSenderService: Lookup for "$userIdentifier" matched ${uniqueTokens.length} token(s) (Registered keys: ${map.keys.toList()})');
      return uniqueTokens;
    } catch (e) {
      debugPrint('FcmPushSenderService: Error retrieving target user tokens: $e');
      return [];
    }
  }

  /// Retrieves all kiosk device tokens from Supabase
  Future<List<String>> _getKioskTokens() async {
    try {
      final supabase = Supabase.instance.client;

      final res = await supabase
          .from('shop_settings')
          .select('value')
          .eq('key', 'kiosk_fcm_tokens')
          .maybeSingle();

      if (res == null || res['value'] == null) return [];

      final val = res['value'];
      if (val is List) {
        return val.map((e) => e.toString()).toSet().toList();
      } else if (val is Map && val['tokens'] is List) {
        return (val['tokens'] as List).map((e) => e.toString()).toSet().toList();
      }
      return [];
    } catch (e) {
      debugPrint('FcmPushSenderService: Error retrieving kiosk tokens: $e');
      return [];
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/call_model.dart';
import 'call_alert_audio_service.dart';
import 'kiosk_broadcast_service.dart';
import 'kiosk_overlay_helper.dart';
import 'user_permission_service.dart';
import 'ui_preferences_service.dart';
import '../../ui/shared/dialogs/call_alert_dialog.dart';

/// Top-level background message handler for FCM
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FcmService [Background]: Received message data: ${message.data}');
}

class FcmService {
  static final FcmService instance = FcmService._internal();
  FcmService._internal();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static GlobalKey<NavigatorState>? navigatorKey;
  bool _isInitialized = false;

  /// Android Notification Channel for Call Assignment Alerts (Silent background channel in tray)
  static const AndroidNotificationChannel _callAlertChannel =
      AndroidNotificationChannel(
    'call_alerts_v3',
    'Call Assignment Alerts',
    description: 'Silent notification for full screen call alerts',
    importance: Importance.defaultImportance,
    playSound: false,
    sound: null,
    enableVibration: false,
  );

  /// Android Notification Channel for Kiosk Payment QR Display
  static const AndroidNotificationChannel _kioskQrChannel =
      AndroidNotificationChannel(
    'kiosk_qr',
    'Kiosk Payment QR',
    description: 'Wakeup notifications for Kiosk display',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Initialize Firebase Messaging & Local Notifications
  Future<void> init({GlobalKey<NavigatorState>? key}) async {
    if (_isInitialized) return;
    if (key != null) navigatorKey = key;

    try {
      final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

      // On Desktop (Windows, macOS, Linux), real-time alerts are handled via Supabase Realtime
      if (!isMobile && !kIsWeb) {
        _isInitialized = true;
        return;
      }

      // Initialize Firebase if not already initialized
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      // Initialize Flutter Local Notifications
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestSoundPermission: true,
        requestBadgePermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.actionId == 'dismiss_alert') {
            CallAlertAudioService.instance.stopAlert();
            return;
          }
          _handleNotificationTap(response.payload);
        },
      );

      // Create Android Notification Channels
      if (!kIsWeb && Platform.isAndroid) {
        final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          // Delete old stale channel (sound can't be changed after first creation)
          await androidPlugin.deleteNotificationChannel('call_alerts');
          // Create fresh channel with correct custom sound
          await androidPlugin.createNotificationChannel(_callAlertChannel);
          await androidPlugin.createNotificationChannel(_kioskQrChannel);
          await androidPlugin.requestNotificationsPermission();
          await androidPlugin.requestFullScreenIntentPermission();
        }
      }

      // Request FCM Permissions
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      // Set foreground presentation options
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Listen for foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _handleForegroundMessage(message);
      });

      // Listen for notification taps when app was in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleMessageOpenedApp(message);
      });

      // Check if launched from terminated state via notification
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      // Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) {
        _syncCurrentDeviceToken(newToken);
      });

      // Listen for call alert payload sent from native MainActivity.onNewIntent
      // This fires when fullScreenIntent brings app to front from background/lockscreen
      if (!kIsWeb && Platform.isAndroid) {
        const methodChannel = MethodChannel('com.perfectsolution.kiosk/overlay');
        methodChannel.setMethodCallHandler((call) async {
          if (call.method == 'onCallAlertPayload') {
            final payload = call.arguments?.toString();
            if (payload != null && payload.isNotEmpty) {
              try {
                final data = jsonDecode(payload);
                if (data is Map) {
                  final callData = Map<String, dynamic>.from(data);
                  final call = _parseCallFromData(callData);
                  if (call != null) {
                    Future.delayed(const Duration(milliseconds: 600), () {
                      _triggerCallAlertModal(call);
                    });
                  }
                }
              } catch (e) {
                debugPrint('FcmService: Error handling native call alert payload: $e');
              }
            }
          } else if (call.method == 'onKioskQrPayload') {
            if (!_isCurrentDeviceSaleKiosk()) {
              debugPrint('FcmService: Ignoring onKioskQrPayload - device is not sale display');
              return;
            }
            final payload = call.arguments?.toString();
            if (payload != null && payload.isNotEmpty) {
              try {
                final data = jsonDecode(payload);
                if (data is Map) {
                  final upiId = data['upi_id']?.toString() ?? '';
                  final amount = double.tryParse(data['amount']?.toString() ?? '0') ?? 0.0;
                  final customerName = data['customer_name']?.toString();
                  final note = data['note']?.toString();

                  if (amount > 0) {
                    KioskBroadcastService.instance.showLocalQr(
                      upiId: upiId,
                      amount: amount,
                      customerName: customerName,
                      invoiceNo: note,
                    );
                    KioskOverlayHelper.bringAppToFront();
                  }
                }
              } catch (e) {
                debugPrint('FcmService: Error handling native kiosk QR payload: $e');
              }
            }
          }
        });

        // Check if there was an initial pending call or kiosk QR when activity launched
        try {
          final initialCall = await methodChannel.invokeMethod<String>('getInitialCallPayload');
          if (initialCall != null && initialCall.isNotEmpty) {
            final data = jsonDecode(initialCall);
            if (data is Map) {
              final call = _parseCallFromData(Map<String, dynamic>.from(data));
              if (call != null) {
                Future.delayed(const Duration(milliseconds: 800), () {
                  _triggerCallAlertModal(call);
                });
              }
            }
          }
        } catch (_) {}

        try {
          if (_isCurrentDeviceSaleKiosk()) {
            final initialKiosk = await methodChannel.invokeMethod<String>('getInitialKioskPayload');
            if (initialKiosk != null && initialKiosk.isNotEmpty) {
              final data = jsonDecode(initialKiosk);
              if (data is Map) {
                final upiId = data['upi_id']?.toString() ?? '';
                final amount = double.tryParse(data['amount']?.toString() ?? '0') ?? 0.0;
                final customerName = data['customer_name']?.toString();
                final note = data['note']?.toString();

                if (amount > 0) {
                  KioskBroadcastService.instance.showLocalQr(
                    upiId: upiId,
                    amount: amount,
                    customerName: customerName,
                    invoiceNo: note,
                    isDirectPush: true,
                  );
                  Future.delayed(const Duration(milliseconds: 1000), () {
                    KioskBroadcastService.instance.showLocalQr(
                      upiId: upiId,
                      amount: amount,
                      customerName: customerName,
                      invoiceNo: note,
                      isDirectPush: true,
                    );
                  });
                }
              }
            }
          }
        } catch (_) {}
      }

      _isInitialized = true;
      debugPrint('FcmService: Successfully initialized Firebase Cloud Messaging');

      // Get initial token in background without blocking startup
      unawaited(() async {
        try {
          final token = await messaging.getToken();
          if (token != null) {
            debugPrint('FcmService: Device FCM Token: $token');
            await _syncCurrentDeviceToken(token);
            await syncCurrentUserTokens();
          }
        } catch (e) {
          debugPrint('FcmService: Error fetching initial token: $e');
        }
      }());
    } catch (e) {
      debugPrint('FcmService: Error initializing Firebase: $e');
    }
  }



  /// Verifies if the currently logged-in user or active device mode is the sale display
  static bool _isCurrentDeviceSaleKiosk() {
    final email = UserPermissionService.getCurrentUserEmail().toLowerCase().trim();
    return email == 'sale.perfectsolutionnoida@gmail.com' ||
        email == 'sale' ||
        UiPreferencesService.isKioskMode();
  }

  /// Handle incoming foreground push message
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FcmService [Foreground]: ${message.data}');
    final data = message.data;
    final type = data['type']?.toString();

    if (type == 'call_assignment') {
      final call = _parseCallFromData(data);
      if (call != null) {
        _triggerCallAlertModal(call);
      }
    } else if (type == 'kiosk_qr') {
      if (!_isCurrentDeviceSaleKiosk()) {
        debugPrint('FcmService: Suppressing kiosk QR push for non-sale device');
        return;
      }
      final upiId = data['upi_id']?.toString() ?? '';
      final amount = double.tryParse(data['amount']?.toString() ?? '0') ?? 0.0;
      final customerName = data['customer_name']?.toString();
      final note = data['note']?.toString();

      if (amount > 0) {
        KioskBroadcastService.instance.showLocalQr(
          upiId: upiId,
          amount: amount,
          customerName: customerName,
          invoiceNo: note,
        );
        KioskOverlayHelper.bringAppToFront();
      }
    }
  }

  /// Handle when user taps notification to open app
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('FcmService [OpenedApp]: ${message.data}');
    final data = message.data;
    final type = data['type']?.toString();

    if (type == 'call_assignment') {
      final call = _parseCallFromData(data);
      if (call != null) {
        // Wait a short moment for widget tree to mount if just launched
        Future.delayed(const Duration(milliseconds: 600), () {
          _triggerCallAlertModal(call);
        });
      }
    }
  }

  void _handleNotificationTap(String? payload) {
    debugPrint('FcmService: Local notification tapped with payload: $payload');
    if (payload != null && payload.isNotEmpty) {
      try {
        final data = jsonDecode(payload);
        if (data is Map) {
          final call = _parseCallFromData(Map<String, dynamic>.from(data));
          if (call != null) {
            // Delay to allow the MainActivity to fully come to foreground
            Future.delayed(const Duration(milliseconds: 800), () {
              _triggerCallAlertModal(call);
            });
          }
        }
      } catch (e) {
        debugPrint('FcmService: Error handling notification tap: $e');
      }
    }
  }

  /// Displays the full-screen alert dialog on top of the UI with guaranteed context mount polling
  void _triggerCallAlertModal(CallModel call) {
    if (!UserPermissionService.shouldReceiveCallAlertPopup()) {
      debugPrint('FcmService: Suppressing call alert modal for admin/sale user: ${UserPermissionService.getCurrentUser().email}');
      return;
    }

    if (!UserPermissionService.isEntryDirectlyAssignedToUser(call.assignedTo)) {
      debugPrint('FcmService: Suppressing call alert modal - call is assigned to "${call.assignedTo}", not logged-in user "${UserPermissionService.getCurrentUser().email}"');
      return;
    }

    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      attempts++;
      final context = navigatorKey?.currentContext;
      if (context != null && context.mounted) {
        timer.cancel();
        CallAlertDialog.show(context, call);
      } else if (attempts >= 50) {
        timer.cancel();
        debugPrint('FcmService: Timeout waiting to mount CallAlertDialog (10s elapsed)');
      }
    });
  }

  CallModel? _parseCallFromData(Map<String, dynamic> data) {
    try {
      final id = int.tryParse(data['call_id']?.toString() ?? '0') ?? DateTime.now().millisecondsSinceEpoch;
      final name = data['name']?.toString() ?? '';
      final mobile = data['mobile']?.toString();
      final address = data['address']?.toString();
      final query = data['query']?.toString();
      final assignedTo = data['assigned_to']?.toString() ?? '';
      final status = data['status']?.toString() ?? 'Pending';
      final dateStr = data['date']?.toString();
      final date = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();

      return CallModel(
        id: id,
        date: date,
        name: name,
        mobileNo: mobile,
        address: address,
        query: query,
        status: status,
        assignedTo: assignedTo,
      );
    } catch (e) {
      debugPrint('FcmService: Error parsing call from data: $e');
      return null;
    }
  }

  /// Syncs all identifiers for the currently active user (email, name, formatted name)
  Future<void> syncCurrentUserTokens() async {
    try {
      final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      if (!isMobile && !kIsWeb) return;

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      final email = UserPermissionService.getCurrentUserEmail().trim();
      final user = UserPermissionService.getCurrentUser();

      if (email.isNotEmpty) {
        await _registerTokenInSupabase(email, token);
      }
      if (user.email.isNotEmpty && user.email.toLowerCase() != email.toLowerCase()) {
        await _registerTokenInSupabase(user.email, token);
      }
      if (user.name.isNotEmpty) {
        await _registerTokenInSupabase(user.name, token);
        final formatted = UserPermissionService.formatStaffName(user.name);
        if (formatted.isNotEmpty && formatted.toLowerCase() != user.name.toLowerCase()) {
          await _registerTokenInSupabase(formatted, token);
        }
      }
    } catch (e) {
      debugPrint('FcmService: Error syncing current user tokens: $e');
    }
  }

  /// Syncs device FCM token to Supabase for the current user and/or kiosk
  Future<void> syncUserToken(String userIdentifier) async {
    try {
      final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      if (!isMobile && !kIsWeb) return;

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _registerTokenInSupabase(userIdentifier, token);
      }
    } catch (e) {
      debugPrint('FcmService: Error syncing user token: $e');
    }
  }

  Future<void> _syncCurrentDeviceToken(String token) async {
    try {
      final isKiosk = UiPreferencesService.isKioskMode();
      if (isKiosk) {
        await _registerKioskTokenInSupabase(token);
      }
    } catch (_) {}
  }

  /// Registers user token in Supabase `shop_settings`
  Future<void> _registerTokenInSupabase(String userIdentifier, String token) async {
    try {
      final supabase = Supabase.instance.client;

      final res = await supabase
          .from('shop_settings')
          .select('value')
          .eq('key', 'user_fcm_tokens')
          .maybeSingle();

      Map<String, dynamic> currentMap = {};
      if (res != null && res['value'] != null) {
        dynamic rawVal = res['value'];
        if (rawVal is String) {
          try {
            rawVal = jsonDecode(rawVal);
          } catch (_) {}
        }
        if (rawVal is Map) {
          currentMap = Map<String, dynamic>.from(rawVal);
        }
      }

      final keyClean = userIdentifier.trim().toLowerCase();
      final List<dynamic> tokenList = List.from(currentMap[keyClean] ?? []);
      if (tokenList.contains(token)) {
        return; // Already registered, do not spam DB & realtime listeners
      }
      tokenList.add(token);
      currentMap[keyClean] = tokenList;

      await supabase.from('shop_settings').upsert({
        'key': 'user_fcm_tokens',
        'value': currentMap,
        'updated_at': DateTime.now().toIso8601String(),
      });

      debugPrint('FcmService: Successfully registered device token for $userIdentifier');
    } catch (e) {
      debugPrint('FcmService: Error registering user token in Supabase: $e');
    }
  }

  /// Registers kiosk token in Supabase `shop_settings`
  Future<void> _registerKioskTokenInSupabase(String token) async {
    try {
      final supabase = Supabase.instance.client;

      final res = await supabase
          .from('shop_settings')
          .select('value')
          .eq('key', 'kiosk_fcm_tokens')
          .maybeSingle();

      List<dynamic> tokenList = [];
      if (res != null && res['value'] is List) {
        tokenList = List.from(res['value'] as List);
      }
      if (tokenList.contains(token)) {
        return; // Already registered
      }
      tokenList.add(token);

      await supabase.from('shop_settings').upsert({
        'key': 'kiosk_fcm_tokens',
        'value': tokenList,
        'updated_at': DateTime.now().toIso8601String(),
      });

      debugPrint('FcmService: Successfully registered Kiosk device token');
    } catch (e) {
      debugPrint('FcmService: Error registering kiosk token: $e');
    }
  }

  /// Cancels all active notifications and alerts
  static Future<void> clearAllNotifications() async {
    try {
      await _localNotifications.cancelAll();
    } catch (_) {}
  }
}

import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/repositories/shop_repository.dart';
import 'data/services/google_drive_upload_service.dart';
import 'data/services/supabase_sync_service.dart';
import 'data/services/local_database_service.dart';
import 'data/services/ui_preferences_service.dart';
import 'data/services/user_permission_service.dart';
import 'data/services/kiosk_overlay_helper.dart';
import 'data/services/auto_update_service.dart';
import 'ui/shared/status_management_dialog.dart';
import 'ui/core/app_theme.dart';
import 'ui/core/icon_registry.dart';
import 'ui/features/pricelist/view_models/pricelist_view_model.dart';

import 'ui/features/settings/view_models/settings_view_model.dart';
import 'ui/features/sales/view_models/sales_view_model.dart';
import 'ui/features/dashboard/view_models/recent_sales_view_model.dart';
import 'ui/navigation/main_navigation_container.dart';
import 'ui/features/calls/view_models/calls_view_model.dart';
import 'ui/features/inward_repairs/view_models/inward_repairs_view_model.dart';
import 'ui/features/replacements/view_models/replacements_view_model.dart';
import 'ui/features/requests/view_models/requests_view_model.dart';
import 'ui/features/purchases/view_models/purchases_view_model.dart';
import 'ui/features/auth/view_models/auth_view_model.dart';
import 'ui/features/auth/views/login_view.dart';
import 'ui/navigation/navigation_view_model.dart';
import 'data/services/fcm_service.dart';
import 'ui/features/permissions/views/permissions_gate_view.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) print('IconRegistry loaded: ${IconRegistry.icons.length}');

  // Register Windows URL Scheme Protocol under HKCU (No Admin elevation required)
  await _registerWindowsProtocolHandler();

  // Initialize Database Service
  final localDb = LocalDatabaseService();
  await localDb.init();
  await UiPreferencesService.init();
  await StatusManagementService.init();
  await UserPermissionService.init();
  await GoogleDriveUploadService.init();
  // This also calls Supabase.initialize() internally
  await SupabaseSyncService.instance.init(localDb);

  // Initialize Firebase Cloud Messaging & Full Screen Alerts
  await FcmService.instance.init(key: rootNavigatorKey);

  // If Kiosk Mode is active on Android, keep WebSocket alive with foreground service
  if (UiPreferencesService.isKioskMode()) {
    KioskOverlayHelper.startKioskForegroundService();
  }

  // Check if launched with command-line deep link argument on Windows/Desktop
  if (args.isNotEmpty && args.first.contains('://')) {
    final link = args.first;
    if (kDebugMode) print('App launched with command line deep link: $link');
    try {
      final uri = Uri.parse(link);
      if (Supabase.instance.client.auth.currentSession == null) {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
      }
    } catch (e) {
      if (kDebugMode) print('Error parsing command line deep link: $e');
    }
  }

  // Initialize Repository
  final repository = ShopRepository(localDb: localDb);

  runApp(
    MultiProvider(
      providers: [
        Provider<ShopRepository>.value(value: repository),
        ChangeNotifierProvider.value(value: SupabaseSyncService.instance),
        ChangeNotifierProvider.value(value: AutoUpdateService.instance),
        ChangeNotifierProvider(create: (context) => AuthViewModel()),
        ChangeNotifierProvider(
          create: (context) => PricelistViewModel(repository: repository),
        ),
        ChangeNotifierProvider(
          create: (context) => SettingsViewModel(repository: repository),
        ),
        ChangeNotifierProvider(
          create: (context) => SalesViewModel(repository: repository),
        ),
        ChangeNotifierProvider(
          create: (context) => RecentSalesViewModel(repository: repository),
        ),
        ChangeNotifierProvider(
          create: (context) => CallsViewModel(repository: repository),
        ),
        ChangeNotifierProvider(
          create: (context) => InwardRepairsViewModel(repository: repository),
        ),
        ChangeNotifierProvider(
          create: (context) => ReplacementsViewModel(repository: repository),
        ),
        ChangeNotifierProvider(
          create: (context) => RequestsViewModel(repository: repository),
        ),
        ChangeNotifierProvider(
          create: (context) => PurchasesViewModel(repository: repository),
        ),
        ChangeNotifierProvider(create: (context) => NavigationViewModel()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Only wire up deep link listener on native platforms (not web)
    if (!kIsWeb) {
      _initDeepLinkHandling();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (kDebugMode) {
        print(
          '[Lifecycle] App resumed / screen unlocked — triggering quick delta catchup sync',
        );
      }
      try {
        final repo = Provider.of<ShopRepository>(context, listen: false);
        SupabaseSyncService.instance.onAppResume(repo.localDb);
      } catch (e) {
        if (kDebugMode) print('[Lifecycle] Resume sync trigger error: $e');
      }
    }
  }

  /// Listens for the OAuth deep link callback (io.supabase.shopmanagement://login-callback)
  /// and hands it to Supabase so it can exchange the code for a session.
  void _initDeepLinkHandling() async {
    _appLinks = AppLinks();

    // Check cold start initial deep link (Windows/Android app launched via protocol link)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        if (kDebugMode) print('Initial cold start deep link: $initialUri');
        if (Supabase.instance.client.auth.currentSession == null) {
          await Supabase.instance.client.auth.getSessionFromUrl(initialUri);
        }
      }
    } catch (e) {
      if (kDebugMode) print('Initial deep link error: $e');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) async {
        if (kDebugMode) print('Deep link received: $uri');
        try {
          // Only attempt url session extraction if user is not already authenticated
          if (Supabase.instance.client.auth.currentSession == null) {
            await Supabase.instance.client.auth.getSessionFromUrl(uri);
          }
        } on AuthException catch (e) {
          // Ignores flow_state_not_found (404) duplicate exchange error
          if (kDebugMode) {
            print('Supabase deep link AuthException handled: ${e.message}');
          }
        } catch (err) {
          if (kDebugMode) print('Deep link error: $err');
        }
      },
      onError: (err) {
        if (kDebugMode) print('Deep link stream error: $err');
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Perfect Solution',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      home: PermissionsGateView(
        child: Consumer<AuthViewModel>(
          builder: (context, authViewModel, _) {
            if (!authViewModel.isAuthenticated) {
              return const LoginView();
            }

            // Secondary Security Gate: Ensure user is authorized in active permissions
            final userEmail = authViewModel.currentUser.email;
            if (!UserPermissionService.isAuthorizedUser(userEmail)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                authViewModel.logout();
              });
              return const LoginView();
            }

            return const MainNavigationContainer();
          },
        ),
      ),
    );
  }
}

Future<void> _registerWindowsProtocolHandler() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    try {
      final exePath = Platform.resolvedExecutable;
      const key = r'HKCU\Software\Classes\io.supabase.shopmanagement';
      await Process.run('reg', [
        'add',
        key,
        '/ve',
        '/d',
        'URL:Shop Management Protocol',
        '/f',
      ]);
      await Process.run('reg', [
        'add',
        '$key\\shell\\open\\command',
        '/ve',
        '/d',
        '"$exePath" "%1"',
        '/f',
      ]);
      await Process.run('reg', [
        'add',
        key,
        '/v',
        'URL Protocol',
        '/d',
        '',
        '/f',
      ]);
    } catch (e) {
      if (kDebugMode) print('Error registering Windows protocol handler: $e');
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
import 'data/services/customer_directory_service.dart';
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
import 'data/services/multi_window_sync_service.dart';
import 'ui/features/permissions/views/permissions_gate_view.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) print('IconRegistry loaded: ${IconRegistry.icons.length}');

  // ── Handle --new-window from Windows taskbar jump list ───────────────────
  // The jump list item launches a NEW process with --new-window. We detect it
  // here and ask the native side (via _nativeChannel) to open a sub-window in
  // the EXISTING process. The existing process already has the handler registered
  // via MultiWindowSyncService and will call createNewWindow() on our behalf.
  if (!kIsWeb &&
      Platform.isWindows &&
      args.isNotEmpty &&
      args.first == '--new-window') {
    const MethodChannel nativeChannel = MethodChannel(
      'com.perfectsolution/desktop_window_manager',
    );
    try {
      await nativeChannel.invokeMethod('new_window_request');
    } catch (_) {}
    // This process is just a messenger; exit naturally after delivering the signal.
    return;
  }

  int? windowId;
  Map<String, dynamic> windowArgs = {};
  if (args.isNotEmpty && args.first == 'multi_window') {
    windowId = int.tryParse(args[1]);
    if (args.length > 2 && args[2].isNotEmpty) {
      try {
        windowArgs = jsonDecode(args[2]);
      } catch (_) {}
    }
  }

  final bool isSubWindow = windowId != null && windowId != 0;

  // Register Windows URL Scheme Protocol in background on desktop
  if (!isSubWindow && !kIsWeb && Platform.isWindows) {
    unawaited(_registerWindowsProtocolHandler());
  }

  // 1. Initialize Hive engine and open database boxes in parallel
  final localDb = LocalDatabaseService();
  await localDb.init(subWindowId: windowId);

  // ── Sub-window auth pre-seeding ─────────────────────────────────────────
  // CRITICAL: Before service init boxes are opened, get the current user's
  // auth state from windowArgs (passed synchronously by main window on creation)
  // or via IPC fallback, and seed this window's local Hive with the auth email
  // and user record. This ensures:
  //   • AuthViewModel finds auth_remember_me=true → skips LoginView immediately
  //   • UserPermissionService finds the current user → permissions work
  //   • Both happen synchronously before any Widget tree is built
  String? subWindowSessionJson;
  if (isSubWindow) {
    String? email = windowArgs['auth_email'] as String?;
    dynamic userData = windowArgs['auth_user_data'];
    subWindowSessionJson = windowArgs['auth_session_json'] as String?;

    // If not passed via windowArgs, fall back to querying main window via IPC
    if (email == null || email.isEmpty) {
      try {
        final authResponseJson = await DesktopMultiWindow.invokeMethod(
          0,
          'get_auth_state',
          null,
        ).timeout(const Duration(seconds: 2));

        if (authResponseJson != null) {
          final authState =
              jsonDecode(authResponseJson.toString()) as Map<String, dynamic>;
          email = (authState['email'] as String?) ?? '';
          userData = authState['user_data'];
          subWindowSessionJson = authState['session_json'] as String?;
        }
      } catch (e) {
        debugPrint(
          'main [SubWindow #$windowId]: Auth pre-seeding IPC fallback failed: $e',
        );
      }
    }

    if (email != null && email.isNotEmpty) {
      try {
        // Seed ui_preferences box so AuthViewModel auto-authenticates
        final prefBox = await Hive.openBox('ui_preferences');
        await prefBox.put('auth_remember_me', true);
        await prefBox.put('auth_remembered_email', email.toLowerCase().trim());

        // Seed app_users_box so UserPermissionService has current user data
        if (userData != null) {
          final usersBox = await Hive.openBox('app_users_box');
          await usersBox.put(email.toLowerCase().trim(), userData);
          await usersBox.put('current_user_email', email.toLowerCase().trim());
        }
        debugPrint(
          'main [SubWindow #$windowId]: Seeded auth for $email successfully',
        );
      } catch (e) {
        debugPrint('main [SubWindow #$windowId]: Error saving auth seeds: $e');
      }
    }
  }

  // 2. Open preference and service boxes in parallel
  await Future.wait([
    UiPreferencesService.init(),
    StatusManagementService.init(),
    UserPermissionService.init(),
  ]);

  if (!isSubWindow) {
    unawaited(GoogleDriveUploadService.init());
    await SupabaseSyncService.instance.init(localDb);
  } else {
    // Sub-window: initialize Supabase client and recover session concurrently
    // so runApp() executes immediately without waiting for Supabase init.
    unawaited(() async {
      try {
        await Supabase.initialize(
          url: SupabaseSyncService.defaultUrl,
          publishableKey: SupabaseSyncService.defaultAnonKey,
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.pkce,
          ),
        );
      } catch (_) {
        // Supabase already initialized — safe to ignore
      }

      if (subWindowSessionJson != null && subWindowSessionJson.isNotEmpty) {
        try {
          await Supabase.instance.client.auth.recoverSession(
            subWindowSessionJson,
          );
          debugPrint(
            'main [SubWindow #$windowId]: Supabase session recovered successfully',
          );
        } catch (e) {
          debugPrint(
            'main [SubWindow #$windowId]: Session recovery failed: $e',
          );
        }
      }

      SupabaseSyncService.instance.markInitialized();
    }());
  }

  // Initialize Desktop Multi-Window Service with localDb reference
  await MultiWindowSyncService.instance.init(
    windowId: windowId,
    windowArgs: windowArgs,
    localDb: localDb,
  );

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

  // Initialize Customer Directory Service
  CustomerDirectoryService.instance.init(repository);

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

  // Defer non-critical background push notifications and kiosk service after first frame
  if (!isSubWindow) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FcmService.instance.init(key: rootNavigatorKey);
      if (UiPreferencesService.isKioskMode()) {
        KioskOverlayHelper.startKioskForegroundService();
      }
    });
  }
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
    final bool isSubWindow = MultiWindowSyncService.instance.isSubWindow;
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      WidgetsBinding.instance.addObserver(this);
    }
    // Only wire up deep link listener on main window
    if (!kIsWeb && !isSubWindow) {
      _initDeepLinkHandling();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
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
    if (MultiWindowSyncService.instance.isSubWindow) return;
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
    final bool isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

    Widget app = MaterialApp(
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

    if (isDesktop) {
      final shortcutActivator = SingleActivator(
        LogicalKeyboardKey.keyN,
        meta: Platform.isMacOS,
        control: !Platform.isMacOS,
      );

      return CallbackShortcuts(
        bindings: {
          shortcutActivator: () {
            MultiWindowSyncService.instance.createNewWindow();
          },
        },
        child: Focus(autofocus: true, child: app),
      );
    }

    return app;
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

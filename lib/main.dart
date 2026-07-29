import 'dart:async';
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
import 'ui/shared/status_management_dialog.dart';
import 'ui/core/app_theme.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Database Service
  final localDb = LocalDatabaseService();
  await localDb.init();
  await UiPreferencesService.init();
  await StatusManagementService.init();
  await UserPermissionService.init();
  await GoogleDriveUploadService.init();
  // This also calls Supabase.initialize() internally
  await SupabaseSyncService.instance.init(localDb);

  // Initialize Repository
  final repository = ShopRepository(localDb: localDb);

  runApp(
    MultiProvider(
      providers: [
        Provider<ShopRepository>.value(value: repository),
        ChangeNotifierProvider.value(value: SupabaseSyncService.instance),
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

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // Only wire up deep link listener on native platforms (not web)
    if (!kIsWeb) {
      _initDeepLinkHandling();
    }
  }

  /// Listens for the OAuth deep link callback (io.supabase.shopmanagement://login-callback)
  /// and hands it to Supabase so it can exchange the code for a session.
  void _initDeepLinkHandling() {
    _appLinks = AppLinks();
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
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Perfect Solution',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      home: Consumer<AuthViewModel>(
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
    );
  }
}

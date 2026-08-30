import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../data/models/app_user.dart';
import '../../../../data/services/user_permission_service.dart';
import '../../../../data/services/windows_oauth_service.dart';
import '../../../../data/services/fcm_service.dart';




class AuthViewModel extends ChangeNotifier {
  static const String _prefBoxName = 'ui_preferences';
  static const String _rememberMeKey = 'auth_remember_me';
  static const String _rememberedEmailKey = 'auth_remembered_email';

  bool _isAuthenticated = false;
  bool _isLoading = false;
  bool _rememberMe = false;
  String? _errorMessage;
  StreamSubscription<AuthState>? _authSubscription;

  AuthViewModel() {
    _listenToSupabaseAuth();
    _checkInitialAuth();
  }

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get rememberMe => _rememberMe;
  String? get errorMessage => _errorMessage;
  AppUser get currentUser => UserPermissionService.getCurrentUser();

  void setRememberMe(bool value) {
    _rememberMe = value;
    notifyListeners();
  }

  void notifyPermissionChanged() {
    notifyListeners();
  }

  /// Listen for Supabase OAuth Callback events (Handles deep links automatically)
  void _listenToSupabaseAuth() {
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
        (data) async {
          final event = data.event;
          final session = data.session;

          if (session != null && session.user.email != null) {
            final userEmail = session.user.email!.trim().toLowerCase();

            // Strict Whitelist Authorization Check (Live Cloud DB + Local)
            final isAuthorized = await UserPermissionService.isAuthorizedUserAsync(userEmail);
            if (isAuthorized) {
              await UserPermissionService.setCurrentUser(userEmail);
              await _updateRememberMeSession(userEmail, _rememberMe);
              _isAuthenticated = true;
              _isLoading = false;
              _errorMessage = null;
              unawaited(FcmService.instance.syncUserToken(userEmail));
              unawaited(FcmService.instance.syncUserToken(currentUser.name));
              notifyListeners();
            } else {
              // Unauthorized User — immediately sign out & block
              await Supabase.instance.client.auth.signOut();
              await _updateRememberMeSession('', false);
              _isAuthenticated = false;
              _isLoading = false;
              _errorMessage =
                  'Access Denied: Your account ($userEmail) is not permitted to use this app. Access is restricted by the Administrator.';
              notifyListeners();
            }
          } else if (event == AuthChangeEvent.signedOut ||
              event == AuthChangeEvent.tokenRefreshed && session == null) {
            // Session cleared — reset loading state so UI doesn't stay stuck
            if (_isLoading) {
              _isLoading = false;
              notifyListeners();
            }
          }
        },
        onError: (error) {
          if (kDebugMode) print('Auth state error (non-critical): $error');
          if (_isLoading && !_isAuthenticated) {
            _isLoading = false;
            notifyListeners();
          }
        },
      );
    } catch (_) {}
  }

  Future<void> _checkInitialAuth() async {
    try {
      if (Hive.isBoxOpen(_prefBoxName)) {
        final box = Hive.box(_prefBoxName);
        final isRemembered = box.get(_rememberMeKey, defaultValue: false) as bool;
        final rememberedEmail = box.get(_rememberedEmailKey) as String?;

        if (isRemembered &&
            rememberedEmail != null &&
            rememberedEmail.isNotEmpty &&
            await UserPermissionService.isAuthorizedUserAsync(rememberedEmail)) {
          _rememberMe = true;
          await UserPermissionService.setCurrentUser(rememberedEmail);
          _isAuthenticated = true;
          unawaited(FcmService.instance.syncUserToken(rememberedEmail));
          unawaited(FcmService.instance.syncUserToken(currentUser.name));
        } else {
          _rememberMe = false;
          _isAuthenticated = false;
          await _updateRememberMeSession('', false);
        }
      } else {
        _isAuthenticated = false;
      }
    } catch (_) {
      _isAuthenticated = false;
    }
    notifyListeners();
  }

  /// Save or clear persistent login session in Hive
  Future<void> _updateRememberMeSession(String email, bool remember) async {
    try {
      if (!Hive.isBoxOpen(_prefBoxName)) {
        await Hive.openBox(_prefBoxName);
      }
      final box = Hive.box(_prefBoxName);
      await box.put(_rememberMeKey, remember);
      if (remember) {
        await box.put(_rememberedEmailKey, email.toLowerCase().trim());
      } else {
        await box.delete(_rememberedEmailKey);
      }
    } catch (_) {}
  }

  /// Sign in with Email & Password (Strict Password Verification + Whitelist Check)
  Future<bool> loginWithEmailAndPassword(
    String email,
    String password, {
    bool rememberMe = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _rememberMe = rememberMe;
    notifyListeners();

    try {
      final cleanEmail = email.trim().toLowerCase();
      final cleanPass = password.trim();

      if (cleanEmail.isEmpty) {
        _errorMessage = 'Please enter an email address.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (cleanPass.isEmpty) {
        _errorMessage = 'Password is required to sign in. Access denied.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 1. Strict Whitelist Check (Live Cloud DB + Local)
      final isAuthorized = await UserPermissionService.isAuthorizedUserAsync(cleanEmail);
      if (!isAuthorized) {
        _errorMessage =
            'Access Denied: The account ($cleanEmail) is not permitted to use this app. Access is restricted by the Administrator.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 2. Authenticate Password against Supabase Auth
      bool supabaseAuthSuccess = false;
      try {
        if (Supabase.instance.client.auth.currentSession != null) {
          await Supabase.instance.client.auth.signOut();
        }
        final res = await Supabase.instance.client.auth.signInWithPassword(
          email: cleanEmail,
          password: cleanPass,
        );
        if (res.user != null) {
          supabaseAuthSuccess = true;
        }
      } catch (e) {
        if (kDebugMode) print('Supabase auth sign in exception: $e');
      }

      // 3. Check UserPermissionService password verification if Supabase Auth isn't populated
      final bool localAuthSuccess =
          supabaseAuthSuccess || await UserPermissionService.verifyUserPassword(cleanEmail, cleanPass);

      if (!localAuthSuccess) {
        _errorMessage = 'Invalid Password. Sign in attempt blocked for security.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Password Verification PASSED -> Grant Session
      await UserPermissionService.setCurrentUser(cleanEmail);
      await _updateRememberMeSession(cleanEmail, rememberMe);
      _isAuthenticated = true;
      _isLoading = false;
      _errorMessage = null;
      unawaited(FcmService.instance.syncUserToken(cleanEmail));
      unawaited(FcmService.instance.syncUserToken(currentUser.name));
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Authentication Error: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginWithGoogle({bool rememberMe = false}) async {
    _isLoading = true;
    _errorMessage = null;
    _rememberMe = rememberMe;
    notifyListeners();

    try {
      // ── Web: Google Identity Services (GIS) Popup / signInWithIdToken ─────────
      if (kIsWeb) {
        try {
          final GoogleSignIn googleSignIn = GoogleSignIn(
            clientId:
                '277669825525-190ehfo8er1ncq76tugtpuih0u1kue3c.apps.googleusercontent.com',
            scopes: ['email', 'profile'],
          );

          try {
            await googleSignIn.signOut();
          } catch (_) {}

          final googleUser = await googleSignIn.signIn();

          if (googleUser != null) {
            final googleAuth = await googleUser.authentication;
            final idToken = googleAuth.idToken;
            final accessToken = googleAuth.accessToken;

            if (idToken != null) {
              final res = await Supabase.instance.client.auth.signInWithIdToken(
                provider: OAuthProvider.google,
                idToken: idToken,
                accessToken: accessToken,
              );

              if (res.user != null && res.user!.email != null) {
                final userEmail = res.user!.email!.toLowerCase().trim();
                final isAuth =
                    await UserPermissionService.isAuthorizedUserAsync(userEmail);
                if (isAuth) {
                  await UserPermissionService.setCurrentUser(userEmail);
                  await _updateRememberMeSession(userEmail, rememberMe);
                  _isAuthenticated = true;
                  _isLoading = false;
                  _errorMessage = null;
                  notifyListeners();
                  return true;
                } else {
                  await Supabase.instance.client.auth.signOut();
                  _errorMessage =
                      'Access Denied: Your account ($userEmail) is not permitted to use this app.';
                  _isLoading = false;
                  notifyListeners();
                  return false;
                }
              }
            }
          }
        } catch (e) {
          if (kDebugMode) print('Web GIS attempt exception: $e');
        }

        // Web Fallback: If popup was closed or GIS fallback required,
        // use whitelisted localhost:54321 callback or origin
        final String webOrigin = Uri.base.origin;
        final String webRedirectTo = webOrigin.contains('localhost') || webOrigin.contains('127.0.0.1')
            ? 'http://localhost:54321/auth/v1/callback'
            : '$webOrigin/';

        final success = await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: webRedirectTo,
          authScreenLaunchMode: LaunchMode.platformDefault,
        );

        Future.delayed(const Duration(seconds: 40), () {
          if (_isLoading && !_isAuthenticated) {
            _isLoading = false;
            _errorMessage = 'Google Sign-In canceled or timed out. Please try again.';
            notifyListeners();
          }
        });

        return success;
      }

      // ── Desktop (macOS & Windows): HTTP Loopback Handshake ───────────────────
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        try {
          final redirectUrl = await WindowsOAuthService.startLocalServer();

          final success = await Supabase.instance.client.auth.signInWithOAuth(
            OAuthProvider.google,
            redirectTo: redirectUrl,
            authScreenLaunchMode: LaunchMode.externalApplication,
          );

          if (!success) {
            await WindowsOAuthService.stopLocalServer();
            _errorMessage = 'Failed to launch Google authentication browser.';
            _isLoading = false;
            notifyListeners();
            return false;
          }

          final callbackUri = await WindowsOAuthService.waitForCallback(
            timeout: const Duration(seconds: 45),
          );

          if (callbackUri != null && Supabase.instance.client.auth.currentSession == null) {
            try {
              await Supabase.instance.client.auth.getSessionFromUrl(callbackUri);
            } catch (e) {
              if (kDebugMode) print('getSessionFromUrl exception (safe handling): $e');
              await Future.delayed(const Duration(milliseconds: 500));
            }
          }

          final session = Supabase.instance.client.auth.currentSession;
          if (session != null && session.user.email != null) {
            final userEmail = session.user.email!.trim().toLowerCase();
            final isAuth =
                await UserPermissionService.isAuthorizedUserAsync(userEmail);
            if (isAuth) {
              await UserPermissionService.setCurrentUser(userEmail);
              await _updateRememberMeSession(userEmail, rememberMe);
              _isAuthenticated = true;
              _isLoading = false;
              _errorMessage = null;
              notifyListeners();
              return true;
            } else {
              await Supabase.instance.client.auth.signOut();
              _errorMessage =
                  'Access Denied: Your account ($userEmail) is not permitted to use this app.';
              _isLoading = false;
              notifyListeners();
              return false;
            }
          } else {
            _errorMessage =
                'Google Sign-In canceled or timed out. Please try again.';
            _isLoading = false;
            notifyListeners();
            return false;
          }
        } catch (e) {
          await WindowsOAuthService.stopLocalServer();
          if (kDebugMode) print('Desktop OAuth error: $e');
        }
      }





      // ── Mobile / iOS / Android: Try native GoogleSignIn SDK first ─────────────
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
        try {
          final GoogleSignIn googleSignIn = GoogleSignIn(
            serverClientId:
                '277669825525-190ehfo8er1ncq76tugtpuih0u1kue3c.apps.googleusercontent.com',
            clientId: defaultTargetPlatform == TargetPlatform.iOS
                ? '277669825525-190ehfo8er1ncq76tugtpuih0u1kue3c.apps.googleusercontent.com'
                : null,
            scopes: ['email', 'profile'],
          );

          try {
            await googleSignIn.signOut();
          } catch (_) {}

          final googleUser = await googleSignIn.signIn();

          if (googleUser == null) {
            // User dismissed/canceled the native Google account picker
            _isLoading = false;
            notifyListeners();
            return false;
          }

          final googleAuth = await googleUser.authentication;
          final idToken = googleAuth.idToken;
          final accessToken = googleAuth.accessToken;

          if (idToken != null) {
            final res = await Supabase.instance.client.auth.signInWithIdToken(
              provider: OAuthProvider.google,
              idToken: idToken,
              accessToken: accessToken,
            );

            if (res.user != null && res.user!.email != null) {
              final userEmail = res.user!.email!.toLowerCase().trim();
              final isAuth =
                  await UserPermissionService.isAuthorizedUserAsync(userEmail);
              if (isAuth) {
                await UserPermissionService.setCurrentUser(userEmail);
                await _updateRememberMeSession(userEmail, rememberMe);
                _isAuthenticated = true;
                _isLoading = false;
                _errorMessage = null;
                notifyListeners();
                return true;
              } else {
                await Supabase.instance.client.auth.signOut();
                _errorMessage =
                    'Access Denied: Your account ($userEmail) is not permitted to use this app.';
                _isLoading = false;
                notifyListeners();
                return false;
              }
            }
          }
        } catch (e) {
          if (kDebugMode) print('GoogleSignIn native attempt exception: $e');
        }
      }

      // ── Mobile / macOS fallback: Supabase OAuth with deep-link scheme ─────────
      const String nativeRedirectTo =
          'io.supabase.shopmanagement://login-callback';

      final success = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: nativeRedirectTo,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      Future.delayed(const Duration(seconds: 25), () {
        if (_isLoading && !_isAuthenticated) {
          _isLoading = false;
          _errorMessage =
              'Google Sign-In canceled or timed out. Please try again or sign in with Email.';
          notifyListeners();
        }
      });

      return success;
    } catch (e) {
      _errorMessage = 'Google Sign-In Error: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Log out back to Login View
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    await _updateRememberMeSession('', false);
    _rememberMe = false;
    _isAuthenticated = false;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

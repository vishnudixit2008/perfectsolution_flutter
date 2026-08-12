import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Local HTTP loopback server for desktop OAuth authentication on Windows & Desktop.
/// Eliminates custom URI scheme dependency and browser protocol prompt errors on Windows.
class WindowsOAuthService {
  static HttpServer? _server;
  static Completer<Uri>? _completer;

  /// Starts a temporary local HTTP loopback server on localhost:54321
  static Future<String> startLocalServer() async {
    await stopLocalServer();
    _completer = Completer<Uri>();

    try {
      // Use dedicated fixed loopback port 43211 (avoid 54321 which is used by local Supabase)
      const int primaryPort = 43211;
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, primaryPort);
      } catch (_) {
        try {
          _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 43212);
        } catch (_) {
          _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        }
      }

      final port = _server?.port ?? primaryPort;
      final redirectUrl = 'http://localhost:$port/auth/v1/callback';

      _server?.listen((HttpRequest request) async {
        final uri = request.uri;
        final path = uri.path;

        // Handle callback hash handler (access_token in hash fragment)
        if (path.contains('callback_hash')) {
          final queryParams = uri.query;
          final fullUri = Uri.parse('http://localhost:$port/auth/v1/callback#$queryParams');
          if (_completer != null && !_completer!.isCompleted) {
            _completer!.complete(fullUri);
          }
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.text
            ..write('OK');
          await request.response.close();
          return;
        }


        // Standard callback HTML response for '/', '/auth/v1/callback', etc.
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Perfect Solution - Authentication Successful</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background: #0B0F19; color: #FFFFFF; }
    .card { background: #131A2E; padding: 40px 48px; border-radius: 20px; text-align: center; box-shadow: 0 20px 40px rgba(0,0,0,0.6); border: 1px solid #1E293B; max-width: 420px; }
    .icon { width: 64px; height: 64px; background: #10B9811A; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 20px; color: #10B981; font-size: 32px; font-weight: bold; }
    h1 { color: #F8FAFC; margin: 0 0 10px; font-size: 22px; font-weight: 700; }
    p { color: #94A3B8; margin: 0 0 24px; font-size: 14px; line-height: 1.5; }
    .btn { background: #3B82F6; color: #FFFFFF; border: none; padding: 10px 24px; border-radius: 8px; font-weight: 600; font-size: 14px; cursor: pointer; text-decoration: none; display: inline-block; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">&#10003;</div>
    <h1>Authentication Successful!</h1>
    <p>You have signed in to <strong>Perfect Solution</strong>. You can safely close this browser window and return to the app.</p>
    <button class="btn" onclick="window.close()">Close Window</button>
  </div>
  <script>
    if (window.location.hash && window.location.hash.length > 1) {
      var hash = window.location.hash.substring(1);
      fetch('/callback_hash?' + hash).catch(function(){});
    }
  </script>
</body>
</html>
''');
        await request.response.close();

        // Extract code or access token parameter if present in GET query
        if (uri.queryParameters.containsKey('code') || uri.queryParameters.containsKey('access_token')) {
          if (_completer != null && !_completer!.isCompleted) {
            _completer!.complete(uri);
          }
        }
      });

      return redirectUrl;
    } catch (e) {
      if (kDebugMode) print('Error starting Windows OAuth local server: $e');
      return 'io.supabase.shopmanagement://login-callback';
    }
  }

  /// Waits for incoming OAuth callback from local HTTP server
  static Future<Uri?> waitForCallback({Duration timeout = const Duration(seconds: 40)}) async {
    if (_completer == null) return null;
    try {
      return await _completer!.future.timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      await stopLocalServer();
    }
  }

  /// Stops local server
  static Future<void> stopLocalServer() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _completer = null;
  }
}

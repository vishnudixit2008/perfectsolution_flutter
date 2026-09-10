import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class DownloadProgress {
  final int receivedBytes;
  final int totalBytes;
  final double progress; // 0.0 to 1.0
  final double speedBytesPerSec;
  final String status;

  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.progress,
    required this.speedBytesPerSec,
    required this.status,
  });

  String get receivedMb => (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
  String get totalMb => totalBytes > 0
      ? (totalBytes / (1024 * 1024)).toStringAsFixed(1)
      : '??';
  int get percentage => (progress * 100).clamp(0, 100).toInt();

  String get speedFormatted {
    if (speedBytesPerSec < 1024) {
      return '${speedBytesPerSec.toStringAsFixed(0)} B/s';
    } else if (speedBytesPerSec < 1024 * 1024) {
      return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }
}

class AppUpdateDownloader {
  HttpClient? _ioClient;
  bool _isCancelled = false;

  /// Creates an HttpClient configured for high-resilience TLS handshakes across Windows, macOS and Android
  HttpClient _createHttpClient() {
    final client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Automatically accept certificates from release distribution and shop domains
        // even on Windows systems with outdated Root CA stores or corporate SSL proxies
        final lower = host.toLowerCase();
        if (lower.contains('github.com') ||
            lower.contains('githubusercontent.com') ||
            lower.contains('amazonaws.com') ||
            lower.contains('cloudfront.net') ||
            lower.contains('perfectsolution') ||
            lower.contains('duckdns.org') ||
            lower.contains('supabase') ||
            lower.contains('ngrok') ||
            kDebugMode) {
          return true;
        }
        return false;
      }
      ..connectionTimeout = const Duration(seconds: 45)
      ..idleTimeout = const Duration(seconds: 45)
      ..autoUncompress = true;
    return client;
  }

  /// Cancels the ongoing download if active.
  void cancel() {
    _isCancelled = true;
    _ioClient?.close(force: true);
    _ioClient = null;
  }

  /// Downloads the update file from [downloadUrl] and emits live [DownloadProgress].
  /// Automatically follows redirects (e.g. GitHub 302 -> AWS S3 / objects.githubusercontent.com)
  /// and retries on transient connection / OS Handshake glitches.
  /// Returns the completed [File] on success, or throws on failure.
  Future<File> downloadUpdate({
    required String downloadUrl,
    required String version,
    required void Function(DownloadProgress) onProgress,
    int maxRetries = 3,
  }) async {
    _isCancelled = false;

    // Determine target local filename and directory
    final String extension = _getFileExtension(downloadUrl);
    final Directory targetDir = await _getTargetDirectory();
    final String localFileName = 'PerfectSolution_v${version}_update$extension';
    final File localFile = File('${targetDir.path}/$localFileName');

    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      _ioClient = _createHttpClient();

      try {
        Uri currentUri = Uri.parse(downloadUrl);
        HttpClientResponse? response;
        int redirectCount = 0;

        // Follow HTTP redirects explicitly to ensure TLS bypass/handshake callback applies to redirected hosts
        while (redirectCount < 8) {
          final request = await _ioClient!.getUrl(currentUri);
          request.headers.set('User-Agent', 'PerfectSolutionApp/1.0 (Windows; macOS; Android)');
          request.followRedirects = false;

          response = await request.close();

          if (response.isRedirect) {
            final location = response.headers.value(HttpHeaders.locationHeader);
            if (location != null && location.isNotEmpty) {
              currentUri = Uri.parse(location);
              redirectCount++;
              continue;
            }
          }
          break;
        }

        if (response == null || response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'Server returned HTTP status ${response?.statusCode ?? 'No response'} for update URL.',
            uri: currentUri,
          );
        }

        final int contentLength = response.contentLength;

        if (await localFile.exists()) {
          try {
            await localFile.delete();
          } catch (_) {}
        }

        final IOSink fileSink = localFile.openWrite();

        int receivedBytes = 0;
        int lastReceivedCheckpoint = 0;
        final stopwatch = Stopwatch()..start();
        double currentSpeed = 0.0;
        DateTime lastSpeedCheck = DateTime.now();

        try {
          await for (final List<int> chunk in response) {
            if (_isCancelled) {
              await fileSink.flush();
              await fileSink.close();
              if (await localFile.exists()) {
                await localFile.delete();
              }
              throw Exception('Download was cancelled by user.');
            }

            fileSink.add(chunk);
            receivedBytes += chunk.length;

            // Calculate speed every 500ms
            final now = DateTime.now();
            final elapsedSinceSpeed = now.difference(lastSpeedCheck).inMilliseconds;
            if (elapsedSinceSpeed >= 500) {
              final bytesDiff = receivedBytes - lastReceivedCheckpoint;
              currentSpeed = (bytesDiff / elapsedSinceSpeed) * 1000;
              lastReceivedCheckpoint = receivedBytes;
              lastSpeedCheck = now;
            }

            final double progress = contentLength > 0
                ? (receivedBytes / contentLength).clamp(0.0, 1.0)
                : 0.0;

            onProgress(
              DownloadProgress(
                receivedBytes: receivedBytes,
                totalBytes: contentLength,
                progress: progress,
                speedBytesPerSec: currentSpeed,
                status: 'Downloading...',
              ),
            );
          }

          await fileSink.flush();
          await fileSink.close();

          // Verify downloaded file is not truncated
          if (contentLength > 0 && receivedBytes < contentLength) {
            throw HttpException('Download incomplete: received $receivedBytes of $contentLength bytes');
          }

          onProgress(
            DownloadProgress(
              receivedBytes: receivedBytes,
              totalBytes: receivedBytes,
              progress: 1.0,
              speedBytesPerSec: 0,
              status: 'Verifying & preparing installer...',
            ),
          );

          return localFile;
        } catch (e) {
          await fileSink.flush();
          await fileSink.close();
          if (await localFile.exists()) {
            try {
              await localFile.delete();
            } catch (_) {}
          }
          rethrow;
        } finally {
          stopwatch.stop();
        }
      } catch (e) {
        if (_isCancelled) rethrow;
        if (kDebugMode) print('AppUpdateDownloader attempt $attempt/$maxRetries error: $e');
        if (attempt >= maxRetries) {
          rethrow;
        }
        // Exponential backoff before retry
        await Future.delayed(Duration(milliseconds: 600 * attempt));
      } finally {
        _ioClient?.close(force: true);
        _ioClient = null;
      }
    }

    throw HttpException('Failed to download update after $maxRetries attempts.');
  }

  /// Launches the native OS installer / package manager for the downloaded [file].
  static Future<bool> launchInstaller(File file) async {
    final String path = file.path;

    if (!kIsWeb && Platform.isAndroid) {
      // 1. Try native PackageInstaller session (silent background update on Android 12+)
      try {
        const nativeChannel = MethodChannel('com.perfectsolution.kiosk/overlay');
        final bool? success = await nativeChannel.invokeMethod<bool>(
          'installApkSilently',
          {'apkPath': path},
        );
        if (success == true) {
          return true;
        }
      } catch (e) {
        if (kDebugMode) print('PackageInstaller silent install error: $e');
      }

      // 2. Fallback to OpenFilex standard package installer prompt
      try {
        final result = await OpenFilex.open(
          path,
          type: 'application/vnd.android.package-archive',
        );
        if (result.type == ResultType.done) {
          return true;
        }
      } catch (e) {
        if (kDebugMode) print('Android OpenFilex error: $e');
      }

      // Universal fallback
      try {
        final result = await OpenFilex.open(path);
        return result.type == ResultType.done;
      } catch (_) {
        return false;
      }
    }

    if (!kIsWeb && Platform.isWindows) {
      try {
        // Run setup executable
        await Process.start(path, [], mode: ProcessStartMode.detached);
        return true;
      } catch (e) {
        if (kDebugMode) print('Windows installer launch error: $e');
        try {
          final result = await OpenFilex.open(path);
          return result.type == ResultType.done;
        } catch (_) {
          return false;
        }
      }
    }

    if (!kIsWeb && Platform.isMacOS) {
      try {
        // Mount and open DMG on macOS
        final res = await Process.run('/usr/bin/open', [path]);
        if (res.exitCode == 0) return true;
      } catch (e) {
        if (kDebugMode) print('macOS open DMG error: $e');
      }

      try {
        final result = await OpenFilex.open(path);
        return result.type == ResultType.done;
      } catch (_) {
        return false;
      }
    }

    // Fallback for Linux / Web
    try {
      final result = await OpenFilex.open(path);
      return result.type == ResultType.done;
    } catch (_) {
      final uri = Uri.file(path);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    }
  }

  static String _getFileExtension(String url) {
    final cleanUrl = url.split('?').first.toLowerCase();
    if (cleanUrl.endsWith('.apk')) return '.apk';
    if (cleanUrl.endsWith('.exe')) return '.exe';
    if (cleanUrl.endsWith('.dmg')) return '.dmg';
    if (cleanUrl.endsWith('.pkg')) return '.pkg';
    if (cleanUrl.endsWith('.zip')) return '.zip';
    if (cleanUrl.endsWith('.tar.gz')) return '.tar.gz';

    if (!kIsWeb && Platform.isAndroid) return '.apk';
    if (!kIsWeb && Platform.isWindows) return '.exe';
    if (!kIsWeb && Platform.isMacOS) return '.dmg';
    return '.bin';
  }

  static Future<Directory> _getTargetDirectory() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) return extDir;
      } catch (_) {}
      return await getTemporaryDirectory();
    }

    if (!kIsWeb && Platform.isWindows) {
      try {
        final tempDir = await getTemporaryDirectory();
        return tempDir;
      } catch (_) {}
    }

    if (!kIsWeb && Platform.isMacOS) {
      try {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) return downloadsDir;
      } catch (_) {}
      return await getTemporaryDirectory();
    }

    return await getTemporaryDirectory();
  }

  /// Returns the expected local [File] for a given [version] and [downloadUrl].
  /// Use this to check if a previous session already downloaded the update,
  /// so we can skip re-downloading and go straight to readyToRelaunch.
  static Future<File> resolveLocalFile({
    required String version,
    required String downloadUrl,
  }) async {
    final extension = _getFileExtension(downloadUrl);
    final targetDir = await _getTargetDirectory();
    final localFileName = 'PerfectSolution_v${version}_update$extension';
    return File('${targetDir.path}/$localFileName');
  }
}

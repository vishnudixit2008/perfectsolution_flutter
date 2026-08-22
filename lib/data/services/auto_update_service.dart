import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'app_update_downloader.dart';
import 'update_check_service.dart';

enum AutoUpdateStatus {
  idle,
  checking,
  downloading,
  readyToRelaunch,
  installing,
  error,
}

class AutoUpdateService extends ChangeNotifier {
  static final AutoUpdateService instance = AutoUpdateService._internal();
  AutoUpdateService._internal();

  final AppUpdateDownloader _downloader = AppUpdateDownloader();
  Timer? _periodicCheckTimer;

  AutoUpdateStatus _status = AutoUpdateStatus.idle;
  AutoUpdateStatus get status => _status;

  AppVersionStatus? _updateInfo;
  AppVersionStatus? get updateInfo => _updateInfo;

  DownloadProgress? _downloadProgress;
  DownloadProgress? get downloadProgress => _downloadProgress;

  File? _downloadedFile;
  File? get downloadedFile => _downloadedFile;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isInitialized = false;
  bool _isDownloading = false;

  /// Initializes the auto-update engine on app startup
  void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    // Periodic check every 15 minutes
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      checkForUpdates();
    });

    // Check shortly after launch
    Future.delayed(const Duration(seconds: 4), () {
      checkForUpdates();
    });
  }

  /// Cancels any ongoing timers and downloads
  void disposeService() {
    _periodicCheckTimer?.cancel();
    _downloader.cancel();
  }

  /// Queries Supabase for the latest version.
  /// If a new version is found on Desktop (Windows / macOS), automatically starts background download.
  Future<void> checkForUpdates({bool force = false}) async {
    if (_status == AutoUpdateStatus.downloading || _status == AutoUpdateStatus.installing) {
      return;
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isAndroid)) {
      _setStatus(AutoUpdateStatus.checking);
      try {
        final versionStatus = await UpdateCheckService.checkForUpdates(
          isAppLaunch: true,
          forceCheck: force,
        );

        if (versionStatus != null && versionStatus.hasUpdate) {
          _updateInfo = versionStatus;
          _errorMessage = null;

          // On Desktop (Windows / macOS), automatically download in the background
          if (Platform.isWindows || Platform.isMacOS) {
            _startBackgroundDownload(versionStatus);
          } else {
            _setStatus(AutoUpdateStatus.idle);
          }
        } else {
          _updateInfo = null;
          _setStatus(AutoUpdateStatus.idle);
        }
      } catch (e) {
        if (kDebugMode) print('AutoUpdateService check error: $e');
        _setStatus(AutoUpdateStatus.idle);
      }
    } else {
      _setStatus(AutoUpdateStatus.idle);
    }
  }

  /// Initiates automatic background download for the available update
  Future<void> _startBackgroundDownload(AppVersionStatus versionStatus) async {
    if (_isDownloading) return;
    if (versionStatus.downloadUrl.trim().isEmpty) {
      _errorMessage = 'Download URL is empty in update configuration.';
      _setStatus(AutoUpdateStatus.error);
      return;
    }

    _isDownloading = true;
    _errorMessage = null;
    _downloadProgress = const DownloadProgress(
      receivedBytes: 0,
      totalBytes: 0,
      progress: 0.0,
      speedBytesPerSec: 0,
      status: 'Starting background download...',
    );
    _setStatus(AutoUpdateStatus.downloading);

    try {
      final file = await _downloader.downloadUpdate(
        downloadUrl: versionStatus.downloadUrl,
        version: versionStatus.latestVersion,
        onProgress: (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );

      _downloadedFile = file;
      _isDownloading = false;
      _setStatus(AutoUpdateStatus.readyToRelaunch);
      if (kDebugMode) {
        print('AutoUpdateService: Download completed successfully. Ready to relaunch: ${file.path}');
      }
    } catch (e) {
      _isDownloading = false;
      _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      _setStatus(AutoUpdateStatus.error);
      if (kDebugMode) print('AutoUpdateService background download error: $e');
    }
  }

  /// Cancels the current download
  void cancelDownload() {
    if (_status == AutoUpdateStatus.downloading) {
      _downloader.cancel();
      _isDownloading = false;
      _setStatus(AutoUpdateStatus.idle);
    }
  }

  /// Retries download if in error state
  void retry() {
    if (_updateInfo != null) {
      _startBackgroundDownload(_updateInfo!);
    } else {
      checkForUpdates(force: true);
    }
  }

  /// Automatically replaces the old application files in-place and launches the new version.
  /// Seamless zero-effort update for users across macOS and Windows.
  Future<bool> relaunchAndInstall() async {
    if (_downloadedFile == null || !await _downloadedFile!.exists()) {
      _errorMessage = 'Downloaded update file was not found.';
      _setStatus(AutoUpdateStatus.error);
      return false;
    }

    _setStatus(AutoUpdateStatus.installing);
    final file = _downloadedFile!;
    final filePath = file.path;
    final int currentPid = pid;

    if (!kIsWeb && Platform.isMacOS) {
      try {
        final script = await _createMacosRelaunchScript(filePath, currentPid);
        if (script != null) {
          // Launch detached helper script
          await Process.start('/bin/bash', [script.path], mode: ProcessStartMode.detached);
          await Future.delayed(const Duration(milliseconds: 400));
          exit(0);
        }
      } catch (e) {
        if (kDebugMode) print('macOS in-place relaunch failed: $e');
      }

      // Fallback: open DMG / package via OS
      return await AppUpdateDownloader.launchInstaller(file);
    }

    if (!kIsWeb && Platform.isWindows) {
      try {
        final script = await _createWindowsRelaunchScript(filePath, currentPid);
        if (script != null) {
          // Launch detached helper script
          await Process.start('cmd.exe', ['/c', script.path], mode: ProcessStartMode.detached);
          await Future.delayed(const Duration(milliseconds: 400));
          exit(0);
        }
      } catch (e) {
        if (kDebugMode) print('Windows in-place relaunch failed: $e');
      }

      // Fallback: open exe installer
      return await AppUpdateDownloader.launchInstaller(file);
    }

    // Android / Other
    return await AppUpdateDownloader.launchInstaller(file);
  }

  /// Creates a detached bash script on macOS to replace the .app bundle in-place and relaunch
  Future<File?> _createMacosRelaunchScript(String downloadedFilePath, int currentPid) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final scriptFile = File('${tempDir.path}/perfect_solution_updater.sh');

      // Resolve current running .app bundle path (e.g. /Applications/Perfect Solution.app)
      String targetAppPath = '/Applications/Perfect Solution.app';
      try {
        final execPath = Platform.resolvedExecutable;
        if (execPath.contains('.app/Contents/MacOS/')) {
          targetAppPath = '${execPath.split('.app/Contents/MacOS/').first}.app';
        }
      } catch (_) {}

      final scriptContent = '''#!/bin/bash
PID=$currentPid
TARGET_APP="$targetAppPath"
DOWNLOAD_FILE="$downloadedFilePath"

# 1. Wait for current app process to fully exit
for i in {1..30}; do
  if ! kill -0 \$PID 2>/dev/null; then
    break
  fi
  sleep 0.2
done

# 2. Extract / Mount & Replace
if [[ "\$DOWNLOAD_FILE" == *.dmg ]]; then
  # Mount DMG silently to temporary mountpoint
  MOUNT_OUTPUT=\$(hdiutil attach "\$DOWNLOAD_FILE" -nobrowse -noautoopen -mountrandom /tmp 2>/dev/null)
  MOUNT_DIR=\$(echo "\$MOUNT_OUTPUT" | awk -F'\t' '{print \$NF}' | grep -E '^/tmp' | head -n 1)
  
  if [ -n "\$MOUNT_DIR" ] && [ -d "\$MOUNT_DIR" ]; then
    APP_IN_DMG=\$(find "\$MOUNT_DIR" -maxdepth 2 -name "*.app" | head -n 1)
    if [ -n "\$APP_IN_DMG" ]; then
      rm -rf "\$TARGET_APP" 2>/dev/null || true
      cp -R "\$APP_IN_DMG" "\$TARGET_APP" 2>/dev/null || cp -R "\$APP_IN_DMG" "/Applications/"
      xattr -cr "\$TARGET_APP" 2>/dev/null || true
      hdiutil detach "\$MOUNT_DIR" -force 2>/dev/null || true
      open -n "\$TARGET_APP" 2>/dev/null || open -a "Perfect Solution"
      rm -f "\$DOWNLOAD_FILE" 2>/dev/null || true
      exit 0
    fi
    hdiutil detach "\$MOUNT_DIR" -force 2>/dev/null || true
  fi
elif [[ "\$DOWNLOAD_FILE" == *.zip ]]; then
  PARENT_DIR=\$(dirname "\$TARGET_APP")
  rm -rf "\$TARGET_APP" 2>/dev/null || true
  unzip -o -q "\$DOWNLOAD_FILE" -d "\$PARENT_DIR"
  xattr -cr "\$TARGET_APP" 2>/dev/null || true
  open -n "\$TARGET_APP" 2>/dev/null || open -a "Perfect Solution"
  rm -f "\$DOWNLOAD_FILE" 2>/dev/null || true
  exit 0
fi

# Fallback: Open installer natively if automated copy could not proceed
open "\$DOWNLOAD_FILE"
''';

      await scriptFile.writeAsString(scriptContent);
      await Process.run('/bin/chmod', ['+x', scriptFile.path]);
      return scriptFile;
    } catch (e) {
      if (kDebugMode) print('Error creating macOS updater script: $e');
      return null;
    }
  }

  /// Creates a detached batch script on Windows to run silent installer and relaunch
  Future<File?> _createWindowsRelaunchScript(String downloadedFilePath, int currentPid) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final scriptFile = File('${tempDir.path}\\perfect_solution_updater.bat');
      final currentExe = Platform.resolvedExecutable;

      final scriptContent = '''@echo off
set PID=$currentPid
set DOWNLOAD_FILE=$downloadedFilePath
set EXE_PATH=$currentExe

:: 1. Wait for process to exit
timeout /t 1 /nobreak > NUL
taskkill /F /PID %PID% > NUL 2>&1
timeout /t 1 /nobreak > NUL

:: 2. Execute installer silently or run update
if "%DOWNLOAD_FILE:~-4%"==".exe" (
  start "" "%DOWNLOAD_FILE%" /SILENT /VERYSILENT /SP- /NORESTART /CLOSEAPPLICATIONS
) else (
  start "" "%DOWNLOAD_FILE%"
)

exit
''';

      await scriptFile.writeAsString(scriptContent);
      return scriptFile;
    } catch (e) {
      if (kDebugMode) print('Error creating Windows updater script: $e');
      return null;
    }
  }

  void _setStatus(AutoUpdateStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }
}

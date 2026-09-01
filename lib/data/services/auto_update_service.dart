import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// Step-by-step status text shown during installation (e.g. "Installing update...")
  String _installStatus = 'Installing...';
  String get installStatus => _installStatus;

  bool _isInitialized = false;
  bool _isDownloading = false;

  /// Initializes the auto-update engine on app startup
  void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    // Listen for native installation failure events (Android PackageInstaller)
    if (!kIsWeb && Platform.isAndroid) {
      const nativeChannel = MethodChannel('com.perfectsolution.kiosk/overlay');
      nativeChannel.setMethodCallHandler((call) async {
        if (call.method == 'onInstallError') {
          _errorMessage = call.arguments as String?;
          _setStatus(AutoUpdateStatus.error);
        }
      });
    }

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

    // In debug mode (VS Code / flutter run), skip automatic background downloads to avoid interrupting development
    if (kDebugMode && !force) {
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

          // Automatically download in the background on Desktop and Android
          if (Platform.isWindows || Platform.isMacOS || Platform.isAndroid) {
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

  /// Initiates automatic background download for the available update.
  /// If the file was already downloaded in a previous session (user closed app
  /// without updating), skips the download entirely and goes straight to
  /// readyToRelaunch — no wasted bandwidth.
  Future<void> _startBackgroundDownload(AppVersionStatus versionStatus) async {
    if (_isDownloading) return;
    if (versionStatus.downloadUrl.trim().isEmpty) {
      _errorMessage = 'Download URL is empty in update configuration.';
      _setStatus(AutoUpdateStatus.error);
      return;
    }

    // Check if this version was already fully downloaded in a previous session
    try {
      final existingFile = await AppUpdateDownloader.resolveLocalFile(
        version: versionStatus.latestVersion,
        downloadUrl: versionStatus.downloadUrl,
      );
      if (await existingFile.exists() && await existingFile.length() > 0) {
        // File is already on disk — skip download, go straight to ready state
        _downloadedFile = existingFile;
        _errorMessage = null;
        _setStatus(AutoUpdateStatus.readyToRelaunch);
        if (kDebugMode) {
          print('AutoUpdateService: Found existing download, skipping re-download: ${existingFile.path}');
        }
        return;
      }
    } catch (_) {
      // If file check fails for any reason, proceed with normal download
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
        print('AutoUpdateService: Download completed. Ready to relaunch: ${file.path}');
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
  /// Does everything directly in Dart using Process.run – no bash scripts, no fallback to Finder.
  Future<bool> relaunchAndInstall() async {
    if (_downloadedFile == null || !await _downloadedFile!.exists()) {
      _errorMessage = 'Downloaded update file was not found.';
      _setStatus(AutoUpdateStatus.error);
      return false;
    }

    _installStatus = 'Preparing...';
    _setStatus(AutoUpdateStatus.installing);
    final file = _downloadedFile!;
    final filePath = file.path;

    if (!kIsWeb && Platform.isMacOS) {
      return await _performMacosUpdate(filePath);
    }

    if (!kIsWeb && Platform.isWindows) {
      return await _performWindowsUpdate(filePath);
    }

    if (!kIsWeb && Platform.isAndroid) {
      _installStatus = 'Applying update in background...';
      notifyListeners();
      return await AppUpdateDownloader.launchInstaller(file);
    }

    // Other – use system installer
    return await AppUpdateDownloader.launchInstaller(file);
  }

  String _resolveTargetAppPath() {
    final exePath = Platform.resolvedExecutable;
    final appIdx = exePath.indexOf('.app');
    if (appIdx != -1) {
      final runningAppPath = exePath.substring(0, appIdx + 4);
      // If not running directly from a read-only DMG volume, replace the running bundle
      if (!runningAppPath.startsWith('/Volumes/')) {
        return runningAppPath;
      }
    }
    return '/Applications/Perfect Solution.app';
  }

  // ---------------------------------------------------------------------------
  // macOS: detached background shell script handles replacement after process exit
  // ---------------------------------------------------------------------------
  Future<bool> _performMacosUpdate(String dmgPath) async {
    try {
      final mountDir = '/tmp/ps_updater_mnt_${DateTime.now().millisecondsSinceEpoch}';

      // Step 1: Silently detach any stale DMG mounts from previous attempts
      _installStatus = 'Preparing...';
      notifyListeners();
      await Future.wait([
        Process.run('/usr/bin/hdiutil',
            ['detach', '/Volumes/Perfect Solution', '-force', '-quiet'],
            runInShell: false),
        Process.run('/usr/bin/hdiutil',
            ['detach', '/Volumes/Perfect Solution 1', '-force', '-quiet'],
            runInShell: false),
        Process.run('/usr/bin/hdiutil',
            ['detach', '/Volumes/Perfect Solution 2', '-force', '-quiet'],
            runInShell: false),
      ]);

      // Step 2: Create dedicated mountpoint and attach DMG silently.
      _installStatus = 'Mounting update package...';
      notifyListeners();
      await Directory(mountDir).create(recursive: true);
      final attachResult = await Process.run(
        '/usr/bin/hdiutil',
        ['attach', dmgPath, '-nobrowse', '-noautoopen', '-noverify', '-mountpoint', mountDir],
        runInShell: false,
      );
      if (kDebugMode) {
        print('hdiutil attach exit: ${attachResult.exitCode}');
        print('hdiutil attach stdout: ${attachResult.stdout}');
        print('hdiutil attach stderr: ${attachResult.stderr}');
      }

      // Step 3: Find the .app bundle inside the mounted DMG.
      // CRITICAL: We MUST use followLinks: false and recursive: false so it does NOT follow
      // the "Applications -> /Applications" symlink created by create-dmg into the system's /Applications folder.
      String? appInDmg;
      final directAppPath = '$mountDir/Perfect Solution.app';
      if (Directory(directAppPath).existsSync() && !FileSystemEntity.isLinkSync(directAppPath)) {
        appInDmg = directAppPath;
      } else {
        try {
          await for (final entity in Directory(mountDir).list(recursive: false, followLinks: false)) {
            if (entity is Directory && entity.path.endsWith('.app') && !FileSystemEntity.isLinkSync(entity.path)) {
              appInDmg = entity.path;
              break;
            }
          }
        } catch (e) {
          if (kDebugMode) print('Error finding .app in DMG: $e');
        }
      }

      if (appInDmg == null || !Directory(appInDmg).existsSync()) {
        if (kDebugMode) print('Could not find .app in mounted DMG at $mountDir');
        await Process.run('/usr/bin/hdiutil', ['detach', mountDir, '-force', '-quiet'],
            runInShell: false);
        await Directory(mountDir).delete(recursive: true).catchError((_) => Directory(mountDir));
        _errorMessage = 'Could not find app inside update package.';
        _setStatus(AutoUpdateStatus.error);
        return false;
      }
      if (kDebugMode) print('Found app in DMG: $appInDmg');

      final destApp = _resolveTargetAppPath();
      if (kDebugMode) print('Target macOS app path for update: $destApp');

      // Step 4: Write a detached updater script that executes immediately once this app process exits.
      // Doing the replacement outside the running app process guarantees no file-lock errors.
      _installStatus = 'Installing & Relaunching...';
      notifyListeners();

      final scriptPath = '/tmp/ps_updater_${DateTime.now().millisecondsSinceEpoch}.sh';
      final scriptFile = File(scriptPath);
      final currentPid = pid;

      final scriptContent = '''#!/bin/bash
PID=$currentPid
MOUNT_DIR="$mountDir"
DMG_PATH="$dmgPath"
APP_IN_DMG="$appInDmg"
DEST_APP="$destApp"

# 1. Wait for old Flutter process to fully terminate
while kill -0 \$PID 2>/dev/null; do
  sleep 0.15
done
sleep 0.2

# 2. Replace the application bundle
rm -rf "\$DEST_APP"
/usr/bin/ditto "\$APP_IN_DMG" "\$DEST_APP"

# 3. Strip quarantine so Gatekeeper permits execution
/usr/bin/xattr -cr "\$DEST_APP" 2>/dev/null

# 4. Detach DMG & remove temp mount
/usr/bin/hdiutil detach "\$MOUNT_DIR" -force -quiet 2>/dev/null
rm -rf "\$MOUNT_DIR"
rm -f "\$DMG_PATH"

# 5. Relaunch the new application and bring to foreground
/usr/bin/open -n "\$DEST_APP" 2>/dev/null || /usr/bin/open "\$DEST_APP"

# 6. Self cleanup
rm -f "\$0"
''';

      await scriptFile.writeAsString(scriptContent);
      await Process.run('/bin/chmod', ['+x', scriptPath], runInShell: false);

      // Launch the script completely detached
      await Process.start(
        '/bin/bash',
        [scriptPath],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      await Future.delayed(const Duration(milliseconds: 200));
      exit(0);
    } catch (e) {
      if (kDebugMode) print('macOS in-place update error: $e');
      _errorMessage = 'Update failed: ${e.toString().replaceAll('Exception:', '').trim()}';
      _setStatus(AutoUpdateStatus.error);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Windows: silent update via a detached batch script for universal reliability.
  // ---------------------------------------------------------------------------
  Future<bool> _performWindowsUpdate(String installerPath) async {
    try {
      _installStatus = 'Installing & Relaunching...';
      notifyListeners();
      final tempDir = await getTemporaryDirectory();
      final scriptFile = File('${tempDir.path}\\ps_win_updater_${DateTime.now().millisecondsSinceEpoch}.bat');
      final currentExe = Platform.resolvedExecutable;
      final currentPid = pid;

      final String relaunchExe;
      if (currentExe.toLowerCase().contains('flutter_tools') ||
          currentExe.toLowerCase().endsWith('dart.exe')) {
        relaunchExe = r'%ProgramFiles%\Perfect Solution\Perfect Solution.exe';
      } else {
        relaunchExe = currentExe;
      }

      final scriptContent = '''@echo off
setlocal enabledelayedexpansion
taskkill /F /PID $currentPid >nul 2>&1
start /wait "" "$installerPath" /VERYSILENT /SUPPRESSMSGBOXES /SP- /NORESTART /CLOSEAPPLICATIONS /FORCECLOSEAPPLICATIONS
if exist "$relaunchExe" (
    start "" "$relaunchExe"
) else if exist "%LOCALAPPDATA%\\Programs\\Perfect Solution\\Perfect Solution.exe" (
    start "" "%LOCALAPPDATA%\\Programs\\Perfect Solution\\Perfect Solution.exe"
) else if exist "%ProgramFiles%\\Perfect Solution\\Perfect Solution.exe" (
    start "" "%ProgramFiles%\\Perfect Solution\\Perfect Solution.exe"
) else if exist "%ProgramFiles(x86)%\\Perfect Solution\\Perfect Solution.exe" (
    start "" "%ProgramFiles(x86)%\\Perfect Solution\\Perfect Solution.exe"
)
del /f /q "$installerPath" >nul 2>&1
del /f /q "%~f0" >nul 2>&1
''';

      await scriptFile.writeAsString(scriptContent);

      // Launch batch file completely detached with cmd /c
      await Process.start(
        'cmd.exe',
        ['/c', scriptFile.path],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      await Future.delayed(const Duration(milliseconds: 200));
      exit(0);
    } catch (e) {
      if (kDebugMode) print('Windows in-place update error: $e');
      _errorMessage = 'Update failed: ${e.toString().replaceAll('Exception:', '').trim()}';
      _setStatus(AutoUpdateStatus.error);
      return false;
    }
  }

  void _setStatus(AutoUpdateStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }
}

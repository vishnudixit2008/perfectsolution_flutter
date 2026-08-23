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

  /// Step-by-step status text shown during installation (e.g. "Installing update...")
  String _installStatus = 'Installing...';
  String get installStatus => _installStatus;

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

    // Android / Other – use system installer
    return await AppUpdateDownloader.launchInstaller(file);
  }

  // ---------------------------------------------------------------------------
  // macOS: in-place update entirely from Dart – no bash script, no Finder.
  // ---------------------------------------------------------------------------
  Future<bool> _performMacosUpdate(String dmgPath) async {
    try {
      final mountDir = '/tmp/ps_updater_mnt_${DateTime.now().millisecondsSinceEpoch}';

      // Step 1: Silently detach any stale DMG mounts from previous attempts (run in parallel)
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
      // -noverify skips the slow CRC checksum (~5–8 s) — the file was already
      // verified at download time, so skipping it is safe and fast.
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

      // Step 3: Find the .app bundle inside the mounted DMG
      String? appInDmg;
      try {
        await for (final entity in Directory(mountDir).list(recursive: true)) {
          if (entity is Directory && entity.path.endsWith('.app')) {
            appInDmg = entity.path;
            break;
          }
        }
      } catch (e) {
        if (kDebugMode) print('Error finding .app in DMG: $e');
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

      // Step 4: Remove old bundle and copy new one using ditto (preserves code signing)
      _installStatus = 'Installing update...';
      notifyListeners();
      const destApp = '/Applications/Perfect Solution.app';
      await Process.run('/bin/rm', ['-rf', destApp], runInShell: false);
      final dittoResult = await Process.run(
        '/usr/bin/ditto',
        [appInDmg, destApp],
        runInShell: false,
      );
      if (kDebugMode) {
        print('ditto exit: ${dittoResult.exitCode}');
        print('ditto stderr: ${dittoResult.stderr}');
      }

      // Step 5: Strip quarantine so Gatekeeper doesn't block the new build
      await Process.run('/usr/bin/xattr', ['-cr', destApp], runInShell: false);

      // Step 6: Detach DMG, delete mount dir, delete downloaded file (in parallel)
      _installStatus = 'Relaunching...';
      notifyListeners();
      await Future.wait([
        Process.run('/usr/bin/hdiutil', ['detach', mountDir, '-force', '-quiet'],
            runInShell: false),
        Directory(mountDir).delete(recursive: true).catchError((_) => Directory(mountDir)),
        File(dmgPath).delete().catchError((_) => File(dmgPath)),
      ]);

      // Step 7: Launch updated app, then exit this process
      await Process.start('/usr/bin/open', ['-n', destApp],
          mode: ProcessStartMode.detached, runInShell: false);
      await Future.delayed(const Duration(milliseconds: 300));
      exit(0);
    } catch (e) {
      if (kDebugMode) print('macOS in-place update error: $e');
      _errorMessage = 'Update failed: ${e.toString().replaceAll('Exception:', '').trim()}';
      _setStatus(AutoUpdateStatus.error);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Windows: silent update via a minimal detached PowerShell script.
  // PowerShell is used (not cmd) because it can be started completely hidden
  // with -WindowStyle Hidden, ensuring no console window ever flashes for users.
  // ---------------------------------------------------------------------------
  Future<bool> _performWindowsUpdate(String installerPath) async {
    try {
      _installStatus = 'Installing update...';
      notifyListeners();
      final tempDir = await getTemporaryDirectory();
      final scriptFile = File('${tempDir.path}\\ps_updater.ps1');
      final currentExe = Platform.resolvedExecutable;
      final currentPid = pid;

      // Build the exe path to relaunch after the installer finishes.
      // In production, the Inno Setup installer overwrites the exe in-place,
      // so we relaunch from the same path. In debug mode (dart.exe / flutter),
      // we fall back to the registered %ProgramFiles% install location.
      final String relaunchExe;
      if (currentExe.toLowerCase().contains('flutter_tools') ||
          currentExe.toLowerCase().endsWith('dart.exe')) {
        relaunchExe = r'$env:ProgramFiles\Perfect Solution\Perfect Solution.exe';
      } else {
        relaunchExe = currentExe.replaceAll(r'\', r'\\');
      }

      // PowerShell script – runs entirely in the background, no window shown.
      // Timeouts are kept minimal:
      //   1s before kill  – Flutter exit(0) needs ~400ms, 1s is comfortable
      //   1s after kill   – OS needs time to release file handles on the exe
      //   1s after install – registry writes / shortcuts settle before relaunch
      final scriptContent = '''
Start-Sleep -Seconds 1
Stop-Process -Id $currentPid -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process -FilePath "$installerPath" -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/SP-", "/NORESTART", "/CLOSEAPPLICATIONS", "/FORCECLOSEAPPLICATIONS" -Wait -WindowStyle Hidden
Start-Sleep -Seconds 1
\$exe = "$relaunchExe"
if (Test-Path \$exe) { Start-Process -FilePath \$exe }
Remove-Item -Path "$installerPath" -Force -ErrorAction SilentlyContinue
''';

      await scriptFile.writeAsString(scriptContent);

      // Launch PowerShell completely hidden – no window, no flicker
      await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle', 'Hidden',
          '-ExecutionPolicy', 'Bypass',
          '-File', scriptFile.path,
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      await Future.delayed(const Duration(milliseconds: 400));
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

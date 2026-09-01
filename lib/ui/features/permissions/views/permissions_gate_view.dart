import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../data/services/app_permissions_service.dart';
import '../../../../data/services/fcm_service.dart';
import '../../../core/app_theme.dart';
import '../../../core/motion/bouncy_pressable.dart';

class PermissionsGateView extends StatefulWidget {
  final Widget child;

  const PermissionsGateView({super.key, required this.child});

  @override
  State<PermissionsGateView> createState() => _PermissionsGateViewState();
}

class _PermissionsGateViewState extends State<PermissionsGateView>
    with WidgetsBindingObserver {
  PermissionStatusModel? _status;
  bool _isLoading = true;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    if (kIsWeb || !Platform.isAndroid) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _status = PermissionStatusModel(
            notificationsGranted: true,
            overlayGranted: true,
            batteryOptimizationIgnored: true,
            installPackagesGranted: true,
            cameraGranted: true,
            storageGranted: true,
          );
        });
      }
      return;
    }

    final status = await AppPermissionsService.instance.checkPermissions();
    if (mounted) {
      setState(() {
        _status = status;
        _isLoading = false;
      });
      if (status.isAllEssentialGranted) {
        unawaited(FcmService.instance.syncCurrentUserTokens());
      }
    }
  }

  Future<void> _grantAllMissing() async {
    if (_status == null || _isRequesting) return;
    setState(() => _isRequesting = true);

    try {
      if (!_status!.notificationsGranted) {
        await AppPermissionsService.instance.requestNotificationPermission();
      }
      if (!_status!.overlayGranted) {
        await AppPermissionsService.instance.requestOverlayPermission();
      }
      if (!_status!.batteryOptimizationIgnored) {
        await AppPermissionsService.instance.requestBatteryOptimization();
      }
      if (!_status!.installPackagesGranted) {
        await AppPermissionsService.instance.requestInstallPackagesPermission();
      }
      await _checkPermissions();
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isAndroid) {
      return widget.child;
    }

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF10B981),
          ),
        ),
      );
    }

    if (_status != null && _status!.isAllEssentialGranted) {
      return widget.child;
    }

    final status = _status;
    final notifOk = status?.notificationsGranted ?? false;
    final overlayOk = status?.overlayGranted ?? false;
    final batteryOk = status?.batteryOptimizationIgnored ?? false;
    final installOk = status?.installPackagesGranted ?? false;
    final cameraOk = status?.cameraGranted ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shield Icon & Title
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.3),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.security_rounded,
                          color: Color(0xFF34D399),
                          size: 44,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'Permissions Required',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'To ensure you receive instant full-screen call alerts, sound chimes, and prevent background silencing, please grant the following permissions:',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Permission Items List
                    _buildPermissionItem(
                      icon: Icons.notifications_active_rounded,
                      iconColor: const Color(0xFF38BDF8),
                      title: 'Notification Alerts & Sound',
                      subtitle:
                          'Enables loud soothing alarm sounds and instant push alerts for assigned calls & orders.',
                      isGranted: notifOk,
                      isRequired: true,
                      onTap: () async {
                        await AppPermissionsService.instance
                            .requestNotificationPermission();
                        await _checkPermissions();
                      },
                    ),
                    const SizedBox(height: 14),

                    _buildPermissionItem(
                      icon: Icons.picture_in_picture_alt_rounded,
                      iconColor: const Color(0xFFA78BFA),
                      title: 'Display Over Other Apps',
                      subtitle:
                          'Allows full-screen call popups to display instantly even when using other apps or on the home screen.',
                      isGranted: overlayOk,
                      isRequired: true,
                      onTap: () async {
                        await AppPermissionsService.instance
                            .requestOverlayPermission();
                        await _checkPermissions();
                      },
                    ),
                    const SizedBox(height: 14),

                    _buildPermissionItem(
                      icon: Icons.battery_saver_rounded,
                      iconColor: const Color(0xFFFBBF24),
                      title: 'Unrestricted Background Battery',
                      subtitle:
                          'Prevents Android battery saver from killing or delaying alert services when the phone is locked.',
                      isGranted: batteryOk,
                      isRequired: true,
                      onTap: () async {
                        await AppPermissionsService.instance
                            .requestBatteryOptimization();
                        await _checkPermissions();
                      },
                    ),
                    const SizedBox(height: 14),

                    _buildPermissionItem(
                      icon: Icons.system_update_rounded,
                      iconColor: const Color(0xFF60A5FA),
                      title: 'Automatic App Updates',
                      subtitle:
                          'Allows the app to seamlessly receive background bug fixes, performance improvements, and feature updates.',
                      isGranted: installOk,
                      isRequired: true,
                      onTap: () async {
                        await AppPermissionsService.instance
                            .requestInstallPackagesPermission();
                        await _checkPermissions();
                      },
                    ),
                    const SizedBox(height: 14),

                    _buildPermissionItem(
                      icon: Icons.camera_alt_rounded,
                      iconColor: const Color(0xFF34D399),
                      title: 'Camera & Device Photos',
                      subtitle:
                          'Allows attaching device condition photos in Inward repairs and customer calls.',
                      isGranted: cameraOk,
                      isRequired: false,
                      onTap: () async {
                        await AppPermissionsService.instance
                            .requestCameraPermission();
                        await AppPermissionsService.instance
                            .requestStoragePermission();
                        await _checkPermissions();
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Action Area
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.8),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BouncyPressable(
                    scaleFactor: 0.96,
                    onTap: _grantAllMissing,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isRequesting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline_rounded,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Grant Required Permissions',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  BouncyPressable(
                    scaleFactor: 0.96,
                    onTap: () =>
                        AppPermissionsService.instance.openAppSystemSettings(),
                    child: const Text(
                      'Open Full App Settings',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isGranted,
    required bool isRequired,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
          width: isGranted ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isRequired && !isGranted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Required',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isGranted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, color: Color(0xFF34D399), size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Active',
                    style: TextStyle(
                      color: Color(0xFF34D399),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            BouncyPressable(
              onTap: onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Allow',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

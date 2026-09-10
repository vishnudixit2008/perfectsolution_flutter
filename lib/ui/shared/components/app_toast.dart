import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

enum AppToastType {
  error,
  warning,
  success,
  info,
}

/// A luxury dark-themed floating notification banner for errors, warnings, and feedback.
class AppToast {
  static void show(
    BuildContext context, {
    required String title,
    required String message,
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    final (accentColor, iconData) = switch (type) {
      AppToastType.error => (AppTheme.danger, Icons.error_outline_rounded),
      AppToastType.warning => (AppTheme.warning, Icons.wifi_off_rounded),
      AppToastType.success => (AppTheme.success, Icons.check_circle_outline_rounded),
      AppToastType.info => (AppTheme.primaryLight, Icons.info_outline_rounded),
    };

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;
    final horizontalMargin = isWide
        ? math.max(24.0, (screenWidth - 460) / 2)
        : 16.0;

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: 24,
          left: horizontalMargin,
          right: horizontalMargin,
        ),
        padding: EdgeInsets.zero,
        duration: duration,
        content: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: accentColor.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.28),
                    width: 1,
                  ),
                ),
                child: Icon(
                  iconData,
                  color: accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppTheme.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => messenger.hideCurrentSnackBar(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    color: AppTheme.textMuted.withValues(alpha: 0.7),
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void showWarning(
    BuildContext context, {
    required String title,
    required String message,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    show(
      context,
      title: title,
      message: message,
      type: AppToastType.warning,
      duration: duration,
    );
  }

  static void showError(
    BuildContext context, {
    required String title,
    required String message,
    Duration duration = const Duration(milliseconds: 4000),
  }) {
    show(
      context,
      title: title,
      message: message,
      type: AppToastType.error,
      duration: duration,
    );
  }

  static void showSuccess(
    BuildContext context, {
    required String title,
    required String message,
    Duration duration = const Duration(milliseconds: 3000),
  }) {
    show(
      context,
      title: title,
      message: message,
      type: AppToastType.success,
      duration: duration,
    );
  }

  static void showInfo(
    BuildContext context, {
    required String title,
    required String message,
    Duration duration = const Duration(milliseconds: 3000),
  }) {
    show(
      context,
      title: title,
      message: message,
      type: AppToastType.info,
      duration: duration,
    );
  }
}

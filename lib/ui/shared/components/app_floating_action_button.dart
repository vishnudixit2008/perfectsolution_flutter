import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/motion/motion.dart';
import '../../features/settings/views/upi_qr_screen.dart';

class AppFloatingActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  final IconData icon;
  final bool showQr;
  final bool showAdd;

  const AppFloatingActionButton({
    super.key,
    this.onPressed,
    this.tooltip = 'Add New',
    this.icon = Icons.add_rounded,
    this.showQr = true,
    this.showAdd = true,
  });

  const AppFloatingActionButton.qrOnly({
    super.key,
  })  : onPressed = null,
        tooltip = '',
        icon = Icons.add_rounded,
        showQr = true,
        showAdd = false;

  @override
  Widget build(BuildContext context) {
    final bool hasAdd = showAdd && onPressed != null;

    Widget buildQrButton() {
      return BouncyPressable(
        scaleFactor: 0.88,
        onTap: () {
          showDialog(
            context: context,
            useSafeArea: false,
            builder: (_) => Dialog.fullscreen(
              backgroundColor: const Color(0xFF080D1A),
              child: const UpiQrScreen(),
            ),
          );
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppTheme.secondary, Color(0xFF2DD4BF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.secondary.withValues(alpha: 0.45),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.qr_code_2_rounded, size: 24, color: Colors.white),
        ),
      );
    }

    Widget buildAddButton() {
      return BouncyPressable(
        scaleFactor: 0.88,
        onTap: onPressed,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppTheme.primary, AppTheme.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.5),
                blurRadius: 14,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 28, color: Colors.white),
        ),
      );
    }

    if (!showQr && hasAdd) {
      return buildAddButton();
    }

    if (showQr && !hasAdd) {
      return buildQrButton();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        buildQrButton(),
        const SizedBox(height: 12),
        buildAddButton(),
      ],
    );
  }
}

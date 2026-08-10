import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
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
      return Container(
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
        child: FloatingActionButton(
          heroTag: null,
          onPressed: () {
            showDialog(
              context: context,
              useSafeArea: false,
              builder: (_) => Dialog.fullscreen(
                backgroundColor: const Color(0xFF080D1A),
                child: const UpiQrScreen(),
              ),
            );
          },
          tooltip: 'UPI QR Pay',
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          highlightElevation: 0,
          shape: const CircleBorder(),
          child: const Icon(Icons.qr_code_2_rounded, size: 24),
        ),
      );
    }

    Widget buildAddButton() {
      return Container(
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
              color: AppTheme.primary.withValues(alpha: 0.45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          heroTag: null,
          onPressed: onPressed,
          tooltip: tooltip,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          highlightElevation: 0,
          shape: const CircleBorder(),
          child: Icon(icon, size: 28),
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

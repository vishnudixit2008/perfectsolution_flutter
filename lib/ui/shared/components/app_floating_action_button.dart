import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

class AppFloatingActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;

  const AppFloatingActionButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Add New',
    this.icon = Icons.add_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FloatingActionButton(
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
}

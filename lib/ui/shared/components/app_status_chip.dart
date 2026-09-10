import 'package:flutter/material.dart';
import '../status_management_dialog.dart';

/// A shared badge widget that renders any module's status with the exact
/// color configured by admins in the Status Manager.
class AppStatusChip extends StatelessWidget {
  final String status;
  final String moduleKey;
  final double scaleFactor;

  const AppStatusChip({
    super.key,
    required this.status,
    required this.moduleKey,
    this.scaleFactor = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = StatusManagementService.getStatusColor(moduleKey, status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 8 * scaleFactor,
        vertical: 3 * scaleFactor,
      ),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6 * scaleFactor),
        border: Border.all(
          color: chipColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: chipColor,
          fontSize: 11 * scaleFactor,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_theme.dart';

class DateTimePickerField extends StatelessWidget {
  final String label;
  final DateTime selectedDateTime;
  final ValueChanged<DateTime> onDateTimeChanged;
  final bool isVisible;
  final bool canEdit;

  const DateTimePickerField({
    super.key,
    required this.label,
    required this.selectedDateTime,
    required this.onDateTimeChanged,
    this.isVisible = true,
    this.canEdit = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    final formattedDate =
        DateFormat('dd MMM yyyy, hh:mm a').format(selectedDateTime);

    return InkWell(
      onTap: canEdit
          ? () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: selectedDateTime,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: AppTheme.primary,
                        onPrimary: Colors.white,
                        surface: Color(0xFF161A23),
                        onSurface: AppTheme.textPrimary,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (pickedDate == null || !context.mounted) return;

              final pickedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: AppTheme.primary,
                        onPrimary: Colors.white,
                        surface: Color(0xFF161A23),
                        onSurface: AppTheme.textPrimary,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (pickedTime == null) return;

              onDateTimeChanged(
                DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  pickedTime.hour,
                  pickedTime.minute,
                ),
              );
            }
          : null,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(
            Icons.calendar_today_rounded,
            size: 18,
            color: AppTheme.primaryLight,
          ),
          suffixIcon: canEdit
              ? const Icon(
                  Icons.edit_calendar_rounded,
                  size: 18,
                  color: AppTheme.primaryLight,
                )
              : const Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: AppTheme.textMuted,
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        child: Text(
          formattedDate,
          style: TextStyle(
            color: canEdit ? AppTheme.textPrimary : AppTheme.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

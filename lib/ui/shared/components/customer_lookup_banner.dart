import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/models/customer_profile.dart';
import '../../core/app_theme.dart';
import '../../core/motion/motion.dart';
import '../dialogs/customer_history_dialog.dart';

class CustomerLookupBanner extends StatelessWidget {
  final CustomerProfile? profile;
  final VoidCallback? onHistoryTap;

  const CustomerLookupBanner({
    super.key,
    required this.profile,
    this.onHistoryTap,
  });

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const SizedBox.shrink();
    }

    final currencyFormat = NumberFormat.currency(
      symbol: '₹',
      decimalDigits: 0,
      locale: 'en_IN',
    );

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: BouncyPressable(
        scaleFactor: 0.98,
        onTap: onHistoryTap ??
            () {
              CustomerHistoryDialog.show(context, profile: profile);
            },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 15,
                  color: Color(0xFF818CF8),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFCBD5E1),
                    ),
                    children: [
                      TextSpan(
                        text: profile!.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' • ${profile!.visitCount} ${profile!.visitCount == 1 ? "visit" : "visits"}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (profile!.totalSpent > 0)
                        TextSpan(
                          text: ' • ${currencyFormat.format(profile!.totalSpent)}',
                          style: const TextStyle(
                            color: Color(0xFF34D399),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppTheme.primaryLight.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View History',
                      style: TextStyle(
                        color: AppTheme.primaryLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 11,
                      color: AppTheme.primaryLight,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

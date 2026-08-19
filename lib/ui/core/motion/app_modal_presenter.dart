import 'dart:ui';
import 'package:flutter/material.dart';
import 'motion_tokens.dart';

/// Presents a modal dialog with an Apple iOS/macOS spring scale-and-slide
/// entry and an ultra-snappy, professional closing animation with zero lag.
Future<T?> showAppModalDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  Color? barrierColor,
  Duration transitionDuration = AppleMotion.quick,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss Modal',
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.65),
    transitionDuration: transitionDuration,
    pageBuilder: (ctx, anim1, anim2) => builder(ctx),
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      final curvedAnim = CurvedAnimation(
        parent: anim,
        curve: AppleMotion.spring,
        reverseCurve: AppleMotion.modalExitCurve,
      );

      final slideAnim = Tween<Offset>(
        begin: const Offset(0.0, 0.035),
        end: Offset.zero,
      ).animate(curvedAnim);

      final scaleAnim = Tween<double>(
        begin: 0.94,
        end: 1.0,
      ).animate(curvedAnim);

      final fadeAnim = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(
        CurvedAnimation(
          parent: anim,
          curve: Curves.easeOut,
          reverseCurve: AppleMotion.modalExitCurve,
        ),
      );

      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 8.0 * anim.value,
          sigmaY: 8.0 * anim.value,
        ),
        child: FadeTransition(
          opacity: fadeAnim,
          child: SlideTransition(
            position: slideAnim,
            child: ScaleTransition(
              scale: scaleAnim,
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

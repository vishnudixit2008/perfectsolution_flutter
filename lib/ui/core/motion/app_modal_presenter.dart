import 'dart:ui';
import 'package:flutter/material.dart';
import 'motion_tokens.dart';

/// Presents a modal dialog with platform-adaptive animation:
///
/// **Desktop (Windows/macOS)**: Crisp 200ms ScaleTransition (0.97→1.0) + FadeTransition.
///   No BackdropFilter blur — eliminates the most expensive GPU compositor op on
///   integrated Intel/AMD graphics, giving buttery 60/120 FPS modal openings.
///
/// **Mobile (Android)**: Full 420ms liquid spring bloom (Telegram-grade):
///   BackdropFilter 10px blur, ScaleTransition (0.88→1.0), SlideTransition + FadeTransition.
Future<T?> showAppModalDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  Color? barrierColor,
  Duration? transitionDuration,
}) {
  final isDesktop = AppleMotion.isDesktop;
  final duration = transitionDuration ?? AppleMotion.modalDuration;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss Modal',
    barrierColor: barrierColor ??
        Colors.black.withValues(alpha: isDesktop ? 0.55 : 0.70),
    transitionDuration: duration,
    pageBuilder: (ctx, anim1, anim2) => builder(ctx),
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      if (isDesktop) {
        // ── Desktop: GPU-lean crisp entry ─────────────────────────────────
        final curvedAnim = CurvedAnimation(
          parent: anim,
          curve: const Cubic(0.25, 1.0, 0.5, 1.0),
          reverseCurve: Curves.easeInCubic,
        );

        final scaleAnim = Tween<double>(
          begin: AppleMotion.modalEntryScaleDesktop,
          end: 1.0,
        ).animate(curvedAnim);

        final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: anim,
            curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
            reverseCurve: Curves.easeInCubic,
          ),
        );

        return FadeTransition(
          opacity: fadeAnim,
          child: ScaleTransition(
            scale: scaleAnim,
            child: child,
          ),
        );
      }

      // ── Mobile: full liquid spring bloom with backdrop blur ──────────────
      final curvedAnim = CurvedAnimation(
        parent: anim,
        curve: const Cubic(0.175, 0.885, 0.32, 1.22),
        reverseCurve: Curves.easeInCubic,
      );

      final slideAnim = Tween<Offset>(
        begin: const Offset(0.0, 0.06),
        end: Offset.zero,
      ).animate(curvedAnim);

      final scaleAnim = Tween<double>(
        begin: 0.88,
        end: 1.0,
      ).animate(curvedAnim);

      final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: anim,
          curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
          reverseCurve: Curves.easeInCubic,
        ),
      );

      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 10.0 * anim.value,
          sigmaY: 10.0 * anim.value,
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

import 'package:flutter/material.dart';
import 'motion_tokens.dart';

/// An Apple & Telegram-grade tactile bounce wrapper — platform-adaptive.
///
/// **Mobile (Android)**: Full ScaleTransition elastic press feedback with haptics.
/// **Desktop (Windows/macOS)**: Scale-free hover highlight mode —
///   hover shows a subtle white-tint overlay, press deepens it.
///   GPU-free: no compositing layer transform so 500+ row lists stay 120 FPS.
class BouncyPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final double scaleFactor;
  final Duration duration;
  final Curve curve;
  final MouseCursor cursor;
  final HitTestBehavior behavior;
  final bool enableHaptics;
  final BorderRadius? hoverBorderRadius;

  const BouncyPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.scaleFactor = AppleMotion.pressScale,
    this.duration = AppleMotion.instant,
    this.curve = AppleMotion.spring,
    this.cursor = SystemMouseCursors.click,
    this.behavior = HitTestBehavior.opaque,
    this.enableHaptics = true,
    this.hoverBorderRadius,
  });

  @override
  State<BouncyPressable> createState() => _BouncyPressableState();
}

class _BouncyPressableState extends State<BouncyPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleFactor,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutQuad,
        reverseCurve: widget.curve,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap != null || widget.onLongPress != null) {
      if (widget.enableHaptics) {
        AppleMotion.triggerHapticFeedback(light: true);
      }
      if (!AppleMotion.isDesktop) {
        _controller.forward();
      } else {
        setState(() => _isPressed = true);
      }
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.onTap != null || widget.onLongPress != null) {
      if (!AppleMotion.isDesktop) {
        _controller.reverse();
      } else {
        setState(() => _isPressed = false);
      }
    }
  }

  void _handleTapCancel() {
    if (widget.onTap != null || widget.onLongPress != null) {
      if (!AppleMotion.isDesktop) {
        _controller.reverse();
      } else {
        setState(() => _isPressed = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null &&
        widget.onLongPress == null &&
        widget.onSecondaryTap == null) {
      return widget.child;
    }

    if (AppleMotion.isDesktop) {
      // ── Desktop: GPU-free hover highlight, no scale transform ──────────────
      final overlayColor = _isPressed
          ? AppleMotion.pressOverlay
          : _isHovered
              ? AppleMotion.hoverOverlay
              : Colors.transparent;

      return MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: GestureDetector(
          behavior: widget.behavior,
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTap: widget.onSecondaryTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: overlayColor,
              borderRadius: widget.hoverBorderRadius,
            ),
            child: widget.child,
          ),
        ),
      );
    }

    // ── Mobile: full elastic scale transform ──────────────────────────────
    return MouseRegion(
      cursor: widget.cursor,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onSecondaryTap,
        child: RepaintBoundary(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

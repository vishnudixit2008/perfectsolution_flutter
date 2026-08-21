import 'package:flutter/material.dart';
import 'motion_tokens.dart';

/// An Apple & Telegram-grade tactile bounce wrapper.
///
/// Performance Optimizations:
/// - Uses [ScaleTransition] directly to update the RenderTransform matrix layer without widget tree rebuilds.
/// - Encloses animating widget in a [RepaintBoundary] to isolate layer repainting from parent containers.
/// - Zero allocations in paint cycles.
/// - Lightweight non-blocking haptic tick on tap down.
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
  });

  @override
  State<BouncyPressable> createState() => _BouncyPressableState();
}

class _BouncyPressableState extends State<BouncyPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

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
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.reverse();
    }
  }

  void _handleTapCancel() {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null &&
        widget.onLongPress == null &&
        widget.onSecondaryTap == null) {
      return widget.child;
    }

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

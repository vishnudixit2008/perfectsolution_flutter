import 'package:flutter/material.dart';
import 'motion_tokens.dart';

/// An Apple-inspired tactile bounce wrapper that smoothly depresses on touch/click
/// and springs back elastically on release.
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
  });

  @override
  State<BouncyPressable> createState() => _BouncyPressableState();
}

class _BouncyPressableState extends State<BouncyPressable>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

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
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

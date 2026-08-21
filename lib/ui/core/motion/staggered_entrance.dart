import 'package:flutter/material.dart';
import 'motion_tokens.dart';

/// Ultra-performant staggered entrance animation designed specifically for high-density lists.
///
/// Performance Optimizations:
/// 1. Viewport Capping: Only items with [index] < [maxAnimatedIndex] (default 8) instantiate
///    an [AnimationController]. Items beyond 8 render instantly with zero animation overhead.
/// 2. Layer-Level Transforms: Uses [FadeTransition] and [SlideTransition] directly, manipulating
///    [RenderAnimatedOpacity] and [RenderTransform] without triggering widget tree rebuilds.
/// 3. Paint Isolation: Enclosed in [RepaintBoundary] to isolate animating rows from adjacent list nodes.
class StaggeredSlideFade extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration baseDuration;
  final Duration itemDelay;
  final double slideOffset;
  final Curve curve;
  final int maxAnimatedIndex;

  const StaggeredSlideFade({
    super.key,
    required this.child,
    this.index = 0,
    this.baseDuration = AppleMotion.medium,
    this.itemDelay = const Duration(milliseconds: 20),
    this.slideOffset = 12.0,
    this.curve = AppleMotion.easeOut,
    this.maxAnimatedIndex = 8,
  });

  @override
  State<StaggeredSlideFade> createState() => _StaggeredSlideFadeState();
}

class _StaggeredSlideFadeState extends State<StaggeredSlideFade>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _fadeAnimation;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();

    // If beyond the initial viewport threshold, skip animation completely to conserve CPU/GPU
    if (widget.index >= widget.maxAnimatedIndex) {
      return;
    }

    _controller = AnimationController(
      vsync: this,
      duration: widget.baseDuration,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller!,
      curve: widget.curve,
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, widget.slideOffset / 100),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller!,
        curve: widget.curve,
      ),
    );

    final delay = widget.itemDelay * widget.index;
    if (delay == Duration.zero) {
      _controller!.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted && _controller != null) {
          _controller!.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Zero-overhead fast path for non-initial items
    if (widget.index >= widget.maxAnimatedIndex || _controller == null) {
      return widget.child;
    }

    return RepaintBoundary(
      child: FadeTransition(
        opacity: _fadeAnimation!,
        child: SlideTransition(
          position: _slideAnimation!,
          child: widget.child,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'motion_tokens.dart';

/// Ultra-performant staggered entrance animation — platform-adaptive.
///
/// **Desktop**: 8ms delay, 4 items max, 160ms duration → near-instant reveal,
///   professional feel on big screens where all items are visible simultaneously.
/// **Mobile**: 20ms delay, 8 items max, 420ms duration → expressive cascade.
///
/// Items beyond [maxAnimatedIndex] render instantly with zero animation overhead.
/// Uses [FadeTransition] + [SlideTransition] at the layer level — zero rebuilds.
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
    Duration? baseDuration,
    Duration? itemDelay,
    this.slideOffset = 10.0,
    this.curve = AppleMotion.easeOut,
    int? maxAnimatedIndex,
  })  : baseDuration = baseDuration ?? AppleMotion.medium,
        itemDelay = itemDelay ?? const Duration(milliseconds: 20),
        maxAnimatedIndex = maxAnimatedIndex ?? 8;

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

    // Platform-aware thresholds
    final maxIndex = AppleMotion.staggerMaxIndex;

    // Beyond viewport threshold → skip animation entirely to save CPU/GPU
    if (widget.index >= maxIndex) return;

    final duration = AppleMotion.staggerBaseDuration;

    _controller = AnimationController(
      vsync: this,
      duration: duration,
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

    final delay = AppleMotion.staggerDelay * widget.index;
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
    final maxIndex = AppleMotion.staggerMaxIndex;
    if (widget.index >= maxIndex || _controller == null) {
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

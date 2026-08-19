import 'package:flutter/material.dart';
import 'motion_tokens.dart';

/// Staggered entrance animation for list items, cards, and grid tiles.
/// Animates sequentially with a subtle slide-up and fade-in to eliminate visual popping.
class StaggeredSlideFade extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration baseDuration;
  final Duration itemDelay;
  final double slideOffset;
  final Curve curve;

  const StaggeredSlideFade({
    super.key,
    required this.child,
    this.index = 0,
    this.baseDuration = AppleMotion.medium,
    this.itemDelay = const Duration(milliseconds: 25),
    this.slideOffset = 14.0,
    this.curve = AppleMotion.easeOut,
  });

  @override
  State<StaggeredSlideFade> createState() => _StaggeredSlideFadeState();
}

class _StaggeredSlideFadeState extends State<StaggeredSlideFade>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.baseDuration,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );

    _slideAnimation = Tween<double>(
      begin: widget.slideOffset,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: widget.curve,
      ),
    );

    // Stagger delay capped at max 12 items (300ms) to ensure fast overall perception
    final cappedIndex = widget.index.clamp(0, 12);
    final delay = widget.itemDelay * cappedIndex;

    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnimation.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

import 'package:flutter/material.dart';
import '../app_theme.dart';

/// An elegant dark-mode shimmer effect for placeholder skeletons during loading.
class ShimmerSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Widget? child;

  const ShimmerSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.child,
  });

  /// Factory helper for a standard card skeleton
  factory ShimmerSkeleton.card({
    Key? key,
    double? width,
    double height = 76.0,
    double borderRadius = 12.0,
  }) {
    return ShimmerSkeleton(
      key: key,
      width: width ?? double.infinity,
      height: height,
      borderRadius: BorderRadius.circular(borderRadius),
    );
  }

  /// Factory helper for text lines
  factory ShimmerSkeleton.line({
    Key? key,
    double width = 100.0,
    double height = 12.0,
    double borderRadius = 4.0,
  }) {
    return ShimmerSkeleton(
      key: key,
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(borderRadius),
    );
  }

  /// Factory helper for avatar circles
  factory ShimmerSkeleton.avatar({
    Key? key,
    double size = 40.0,
  }) {
    return ShimmerSkeleton(
      key: key,
      width: size,
      height: size,
      borderRadius: BorderRadius.circular(size / 2),
    );
  }

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final br = widget.borderRadius ?? BorderRadius.circular(8);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: br,
              gradient: LinearGradient(
                begin: Alignment(-1.5 + (progress * 3.0), -0.3),
                end: Alignment(-0.5 + (progress * 3.0), 0.3),
                colors: [
                  AppTheme.cardBg,
                  const Color(0xFF1F293D),
                  AppTheme.cardBg,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
                width: 1,
              ),
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

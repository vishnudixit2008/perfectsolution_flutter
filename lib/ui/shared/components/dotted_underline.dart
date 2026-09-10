import 'package:flutter/material.dart';

/// Renders a crisp, highly visible dotted underline beneath its child widget.
/// Used to subtly indicate interactive/clickable text (e.g. mobile numbers opening customer history)
/// without relying on OS/Skia font decoration which is often invisible or dropped on Windows.
class DottedUnderline extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double dotRadius;
  final double spacing;
  final double gap;
  final double scaleFactor;

  const DottedUnderline({
    super.key,
    required this.child,
    this.color,
    this.dotRadius = 1.1,
    this.spacing = 3.0,
    this.gap = 2.0,
    this.scaleFactor = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveDotRadius = dotRadius * scaleFactor;
    final effectiveSpacing = spacing * scaleFactor;
    final effectiveGap = gap * scaleFactor;
    final effectiveColor = color ?? const Color(0xFFCBD5E1);

    return CustomPaint(
      painter: _DottedUnderlinePainter(
        color: effectiveColor,
        dotRadius: effectiveDotRadius,
        spacing: effectiveSpacing,
        gap: effectiveGap,
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: (effectiveDotRadius * 2) + effectiveGap),
        child: child,
      ),
    );
  }
}

class _DottedUnderlinePainter extends CustomPainter {
  final Color color;
  final double dotRadius;
  final double spacing;
  final double gap;

  _DottedUnderlinePainter({
    required this.color,
    required this.dotRadius,
    required this.spacing,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || dotRadius <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Center of dots in the allocated bottom padding region
    final y = size.height - dotRadius;

    final availableWidth = size.width - (dotRadius * 2);
    if (availableWidth <= 0) {
      canvas.drawCircle(Offset(size.width / 2, y), dotRadius, paint);
      return;
    }

    final nominalStep = (dotRadius * 2) + spacing;
    final numGaps = (availableWidth / nominalStep).round();

    if (numGaps <= 0) {
      canvas.drawCircle(Offset(size.width / 2, y), dotRadius, paint);
      return;
    }

    final step = availableWidth / numGaps;
    for (int i = 0; i <= numGaps; i++) {
      final x = dotRadius + (i * step);
      canvas.drawCircle(Offset(x, y), dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedUnderlinePainter oldDelegate) =>
      color != oldDelegate.color ||
      dotRadius != oldDelegate.dotRadius ||
      spacing != oldDelegate.spacing ||
      gap != oldDelegate.gap;
}

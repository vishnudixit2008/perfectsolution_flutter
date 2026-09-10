import 'package:flutter/material.dart';

class WhatsAppIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const WhatsAppIcon({super.key, this.size = 18, this.color});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? const Color(0xFF25D366);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _WhatsAppGlyphPainter(color: effectiveColor),
      ),
    );
  }
}

class _WhatsAppGlyphPainter extends CustomPainter {
  final Color color;

  _WhatsAppGlyphPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    if (w <= 0 || h <= 0) return;

    final double s = w / 24.0;
    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Visual center of the speech bubble circle
    final double cx = 12.04 * s;
    final double cy = 11.85 * s;

    // 1. Speech Bubble with Tail & hollow cutout
    final Path bubblePath = Path();
    bubblePath.fillType = PathFillType.evenOdd;

    // Outer Bubble
    bubblePath.moveTo(12.04 * s, 2.0 * s);
    bubblePath.cubicTo(6.58 * s, 2.0 * s, 2.13 * s, 6.45 * s, 2.13 * s, 11.91 * s);
    bubblePath.cubicTo(2.13 * s, 13.66 * s, 2.59 * s, 15.36 * s, 3.45 * s, 16.86 * s);
    bubblePath.lineTo(2.05 * s, 22.0 * s);
    bubblePath.lineTo(7.30 * s, 20.62 * s);
    bubblePath.cubicTo(8.75 * s, 21.41 * s, 10.38 * s, 21.83 * s, 12.04 * s, 21.83 * s);
    bubblePath.cubicTo(17.50 * s, 21.83 * s, 21.95 * s, 17.38 * s, 21.95 * s, 11.91 * s);
    bubblePath.cubicTo(21.95 * s, 9.26 * s, 20.92 * s, 6.77 * s, 19.05 * s, 4.90 * s);
    bubblePath.cubicTo(17.18 * s, 3.03 * s, 14.69 * s, 2.0 * s, 12.04 * s, 2.0 * s);
    bubblePath.close();

    // Inner Hollow Cutout
    bubblePath.moveTo(12.04 * s, 3.65 * s);
    bubblePath.cubicTo(14.25 * s, 3.65 * s, 16.31 * s, 4.51 * s, 17.87 * s, 6.07 * s);
    bubblePath.cubicTo(19.43 * s, 7.63 * s, 20.28 * s, 9.69 * s, 20.28 * s, 11.91 * s);
    bubblePath.cubicTo(20.28 * s, 16.45 * s, 16.58 * s, 20.15 * s, 12.04 * s, 20.15 * s);
    bubblePath.cubicTo(10.56 * s, 20.15 * s, 9.11 * s, 19.75 * s, 7.84 * s, 19.00 * s);
    bubblePath.lineTo(7.54 * s, 18.82 * s);
    bubblePath.lineTo(4.42 * s, 19.64 * s);
    bubblePath.lineTo(5.25 * s, 16.60 * s);
    bubblePath.lineTo(5.05 * s, 16.29 * s);
    bubblePath.cubicTo(4.25 * s, 15.02 * s, 3.79 * s, 13.51 * s, 3.79 * s, 11.91 * s);
    bubblePath.cubicTo(3.79 * s, 7.37 * s, 7.49 * s, 3.65 * s, 12.04 * s, 3.65 * s);
    bubblePath.close();

    canvas.drawPath(bubblePath, fillPaint);

    // 2. Handset Receiver Path (mathematically centered inside bubble)
    Path phonePath = Path();
    phonePath.moveTo(7.42 * s, 7.81 * s);
    phonePath.cubicTo(7.22 * s, 7.80 * s, 6.99 * s, 7.88 * s, 6.84 * s, 8.14 * s);
    phonePath.cubicTo(6.64 * s, 8.49 * s, 6.06 * s, 9.27 * s, 6.06 * s, 10.51 * s);
    phonePath.cubicTo(6.06 * s, 11.75 * s, 6.86 * s, 13.01 * s, 7.07 * s, 13.27 * s);
    phonePath.cubicTo(7.27 * s, 13.54 * s, 8.90 * s, 16.07 * s, 11.50 * s, 17.19 * s);
    phonePath.cubicTo(12.12 * s, 17.46 * s, 12.60 * s, 17.62 * s, 12.98 * s, 17.74 * s);
    phonePath.cubicTo(13.60 * s, 17.94 * s, 14.17 * s, 17.91 * s, 14.62 * s, 17.84 * s);
    phonePath.cubicTo(15.12 * s, 17.77 * s, 16.16 * s, 17.21 * s, 16.38 * s, 16.60 * s);
    phonePath.cubicTo(16.60 * s, 15.99 * s, 16.60 * s, 15.47 * s, 16.53 * s, 15.36 * s);
    phonePath.cubicTo(16.46 * s, 15.25 * s, 16.28 * s, 15.19 * s, 16.01 * s, 15.06 * s);
    phonePath.cubicTo(15.74 * s, 14.92 * s, 14.40 * s, 14.27 * s, 14.15 * s, 14.18 * s);
    phonePath.cubicTo(13.90 * s, 14.09 * s, 13.72 * s, 14.04 * s, 13.54 * s, 14.32 * s);
    phonePath.cubicTo(13.36 * s, 14.59 * s, 12.84 * s, 15.20 * s, 12.68 * s, 15.38 * s);
    phonePath.cubicTo(12.52 * s, 15.56 * s, 12.36 * s, 15.58 * s, 12.09 * s, 15.45 * s);
    phonePath.cubicTo(11.82 * s, 15.31 * s, 10.95 * s, 15.03 * s, 9.92 * s, 14.11 * s);
    phonePath.cubicTo(9.12 * s, 13.40 * s, 8.58 * s, 12.52 * s, 8.42 * s, 12.25 * s);
    phonePath.cubicTo(8.26 * s, 11.98 * s, 8.40 * s, 11.83 * s, 8.54 * s, 11.70 * s);
    phonePath.cubicTo(8.66 * s, 11.58 * s, 8.81 * s, 11.38 * s, 8.95 * s, 11.23 * s);
    phonePath.cubicTo(9.09 * s, 11.07 * s, 9.13 * s, 10.96 * s, 9.22 * s, 10.78 * s);
    phonePath.cubicTo(9.31 * s, 10.60 * s, 9.27 * s, 10.44 * s, 9.20 * s, 10.30 * s);
    phonePath.cubicTo(9.13 * s, 10.16 * s, 8.59 * s, 8.83 * s, 8.36 * s, 8.29 * s);
    phonePath.cubicTo(8.14 * s, 7.76 * s, 7.91 * s, 7.83 * s, 7.74 * s, 7.82 * s);
    phonePath.close();

    final Rect phoneBounds = phonePath.getBounds();
    final double shiftX = cx - phoneBounds.center.dx;
    final double shiftY = cy - phoneBounds.center.dy;
    phonePath = phonePath.shift(Offset(shiftX, shiftY));

    canvas.drawPath(phonePath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

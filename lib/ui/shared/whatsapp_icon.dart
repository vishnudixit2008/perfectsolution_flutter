import 'package:flutter/material.dart';

class WhatsAppIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const WhatsAppIcon({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _WhatsAppLogoPainter(color: color ?? const Color(0xFF25D366)),
    );
  }
}

class _WhatsAppLogoPainter extends CustomPainter {
  final Color color;

  _WhatsAppLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final Paint whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final double w = size.width;
    final double radius = w / 2;

    // Draw background green circle
    canvas.drawCircle(Offset(radius, radius), radius, fillPaint);

    // Draw white chat bubble with tail
    final Path bubblePath = Path();
    bubblePath.addOval(
      Rect.fromCircle(
        center: Offset(radius, radius * 0.95),
        radius: radius * 0.72,
      ),
    );

    // Tail
    final Path tailPath = Path()
      ..moveTo(radius * 0.45, radius * 1.4)
      ..lineTo(radius * 0.3, radius * 1.65)
      ..lineTo(radius * 0.75, radius * 1.5)
      ..close();

    canvas.drawPath(bubblePath, whitePaint);
    canvas.drawPath(tailPath, whitePaint);

    // Draw inner green phone receiver
    final Paint phonePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final Path phonePath = Path();
    final double scale = w / 24;

    phonePath.moveTo(9 * scale, 7.5 * scale);
    phonePath.cubicTo(
      8.7 * scale,
      7.5 * scale,
      8.3 * scale,
      7.6 * scale,
      8.1 * scale,
      8.1 * scale,
    );
    phonePath.cubicTo(
      7.8 * scale,
      8.5 * scale,
      7.1 * scale,
      9.4 * scale,
      7.1 * scale,
      10.7 * scale,
    );
    phonePath.cubicTo(
      7.1 * scale,
      12 * scale,
      8 * scale,
      13.2 * scale,
      8.2 * scale,
      13.4 * scale,
    );
    phonePath.cubicTo(
      8.3 * scale,
      13.6 * scale,
      10 * scale,
      16.3 * scale,
      12.6 * scale,
      17.4 * scale,
    );
    phonePath.cubicTo(
      14.7 * scale,
      18.3 * scale,
      14.7 * scale,
      17.7 * scale,
      15.3 * scale,
      17.6 * scale,
    );
    phonePath.cubicTo(
      15.9 * scale,
      17.5 * scale,
      17.1 * scale,
      16.8 * scale,
      17.4 * scale,
      16 * scale,
    );
    phonePath.cubicTo(
      17.7 * scale,
      15.2 * scale,
      17.7 * scale,
      14.6 * scale,
      17.6 * scale,
      14.4 * scale,
    );
    phonePath.cubicTo(
      17.5 * scale,
      14.2 * scale,
      17.2 * scale,
      14.1 * scale,
      16.7 * scale,
      13.8 * scale,
    );
    phonePath.cubicTo(
      16.2 * scale,
      13.5 * scale,
      13.8 * scale,
      12.3 * scale,
      13.4 * scale,
      12.1 * scale,
    );
    phonePath.cubicTo(
      13 * scale,
      11.9 * scale,
      12.7 * scale,
      11.9 * scale,
      12.4 * scale,
      12.3 * scale,
    );
    phonePath.cubicTo(
      12.1 * scale,
      12.7 * scale,
      11.3 * scale,
      13.7 * scale,
      11.1 * scale,
      13.9 * scale,
    );
    phonePath.cubicTo(
      10.9 * scale,
      14.1 * scale,
      10.6 * scale,
      14.1 * scale,
      10.1 * scale,
      13.8 * scale,
    );
    phonePath.cubicTo(
      9.6 * scale,
      13.5 * scale,
      8 * scale,
      13 * scale,
      6.9 * scale,
      12 * scale,
    );
    phonePath.close();

    canvas.drawPath(phonePath, phonePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

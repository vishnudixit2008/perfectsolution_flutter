import 'package:flutter/material.dart';

class WhatsAppIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const WhatsAppIcon({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/whatsapp_icon.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return CustomPaint(
            size: Size(size, size),
            painter: _WhatsAppLogoPainter(color: color ?? const Color(0xFF25D366)),
          );
        },
      ),
    );
  }
}

class _WhatsAppLogoPainter extends CustomPainter {
  final Color color;

  _WhatsAppLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    if (w <= 0 || h <= 0) return;

    final double scale = w / 24.0;

    // 1. Green Circular Background (#25D366)
    final Paint bgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);

    // 2. Pure White Speech Bubble + Tail
    final Paint whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final Path bubblePath = Path();
    bubblePath.addOval(
      Rect.fromCircle(
        center: Offset(12.1 * scale, 11.4 * scale),
        radius: 7.0 * scale,
      ),
    );

    final Path tailPath = Path()
      ..moveTo(6.2 * scale, 14.6 * scale)
      ..lineTo(4.6 * scale, 18.2 * scale)
      ..lineTo(9.0 * scale, 17.0 * scale)
      ..close();

    canvas.drawPath(bubblePath, whitePaint);
    canvas.drawPath(tailPath, whitePaint);

    // 3. Inner WhatsApp Green Phone Handset Receiver (#25D366)
    final Paint phonePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final Path phonePath = Path();
    phonePath.moveTo(14.8 * scale, 13.8 * scale);
    phonePath.cubicTo(14.5 * scale, 13.7 * scale, 14.1 * scale, 13.5 * scale, 13.7 * scale, 13.8 * scale);
    phonePath.cubicTo(13.3 * scale, 14.1 * scale, 12.9 * scale, 14.6 * scale, 12.6 * scale, 14.5 * scale);
    phonePath.cubicTo(12.3 * scale, 14.4 * scale, 11.8 * scale, 14.2 * scale, 11.1 * scale, 13.6 * scale);
    phonePath.cubicTo(10.3 * scale, 12.9 * scale, 9.7 * scale, 12.1 * scale, 9.5 * scale, 11.7 * scale);
    phonePath.cubicTo(9.3 * scale, 11.4 * scale, 9.5 * scale, 11.1 * scale, 9.7 * scale, 10.9 * scale);
    phonePath.cubicTo(9.9 * scale, 10.7 * scale, 10.1 * scale, 10.4 * scale, 10.3 * scale, 10.2 * scale);
    phonePath.cubicTo(10.5 * scale, 10.0 * scale, 10.5 * scale, 9.7 * scale, 10.4 * scale, 9.5 * scale);
    phonePath.cubicTo(10.3 * scale, 9.2 * scale, 9.7 * scale, 7.8 * scale, 9.4 * scale, 7.2 * scale);
    phonePath.cubicTo(9.1 * scale, 6.6 * scale, 8.9 * scale, 6.7 * scale, 8.7 * scale, 6.7 * scale);
    phonePath.cubicTo(8.5 * scale, 6.7 * scale, 8.2 * scale, 6.7 * scale, 8.0 * scale, 6.7 * scale);
    phonePath.cubicTo(7.7 * scale, 6.7 * scale, 7.3 * scale, 6.8 * scale, 7.0 * scale, 7.2 * scale);
    phonePath.cubicTo(6.7 * scale, 7.5 * scale, 5.9 * scale, 8.3 * scale, 5.9 * scale, 9.9 * scale);
    phonePath.cubicTo(5.9 * scale, 11.5 * scale, 7.1 * scale, 13.1 * scale, 7.3 * scale, 13.3 * scale);
    phonePath.cubicTo(7.4 * scale, 13.5 * scale, 9.6 * scale, 16.9 * scale, 13.0 * scale, 18.3 * scale);
    phonePath.cubicTo(13.8 * scale, 18.7 * scale, 14.5 * scale, 18.9 * scale, 15.0 * scale, 19.1 * scale);
    phonePath.cubicTo(15.8 * scale, 19.3 * scale, 16.6 * scale, 19.3 * scale, 17.2 * scale, 19.2 * scale);
    phonePath.cubicTo(17.9 * scale, 19.1 * scale, 19.3 * scale, 18.3 * scale, 19.6 * scale, 17.5 * scale);
    phonePath.cubicTo(19.9 * scale, 16.7 * scale, 19.9 * scale, 16.0 * scale, 19.8 * scale, 15.9 * scale);
    phonePath.cubicTo(19.7 * scale, 15.7 * scale, 19.4 * scale, 15.6 * scale, 19.0 * scale, 15.4 * scale);
    phonePath.cubicTo(18.6 * scale, 15.2 * scale, 16.7 * scale, 14.2 * scale, 16.3 * scale, 14.1 * scale);
    phonePath.cubicTo(16.0 * scale, 14.0 * scale, 15.8 * scale, 13.9 * scale, 15.5 * scale, 14.3 * scale);
    phonePath.cubicTo(15.2 * scale, 14.7 * scale, 14.6 * scale, 15.4 * scale, 14.4 * scale, 15.6 * scale);
    phonePath.cubicTo(14.2 * scale, 15.8 * scale, 14.0 * scale, 15.8 * scale, 13.6 * scale, 15.6 * scale);
    phonePath.cubicTo(13.2 * scale, 15.4 * scale, 11.9 * scale, 15.0 * scale, 10.4 * scale, 13.6 * scale);
    phonePath.cubicTo(9.2 * scale, 12.5 * scale, 8.4 * scale, 11.1 * scale, 8.2 * scale, 10.7 * scale);
    phonePath.cubicTo(8.0 * scale, 10.3 * scale, 8.2 * scale, 10.1 * scale, 8.4 * scale, 9.9 * scale);
    phonePath.close();

    canvas.drawPath(phonePath, phonePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

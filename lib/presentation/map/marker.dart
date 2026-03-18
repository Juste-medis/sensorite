import 'package:flutter/material.dart';

class RealtimeUserMarker extends StatelessWidget {
  const RealtimeUserMarker({super.key, required this.heading, this.size = 56});

  final double heading;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: heading / 360.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: CustomPaint(
        size: Size(size * 0.5, size * 0.5),
        painter: _ArrowPainter(),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width / 2, 0); // Pointe en haut
    path.lineTo(size.width * 0.9, size.height * 0.7); // Bas droit
    path.lineTo(size.width / 2, size.height * 0.4); // Milieu
    path.lineTo(size.width * 0.1, size.height * 0.7); // Bas gauche
    path.close();

    // Ombre
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Flèche blanche
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:math' as math;
import 'package:flutter/material.dart';

class RealtimeUserMarker extends StatefulWidget {
  const RealtimeUserMarker({
    super.key,
    required this.heading,
    this.size = 56,
    this.accuracy = 0.0, // 0.0 = pas d'anneau de précision
  });

  final double heading;
  final double size;
  final double accuracy;

  @override
  State<RealtimeUserMarker> createState() => _RealtimeUserMarkerState();
}

class _RealtimeUserMarkerState extends State<RealtimeUserMarker>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _headingController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _headingAnimation;
  double _currentHeading = 0;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: false);

    _pulseAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    _headingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _headingAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _headingController, curve: Curves.easeOut),
    );

    _currentHeading = widget.heading;
  }

  @override
  void didUpdateWidget(RealtimeUserMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heading != widget.heading) {
      final from = _currentHeading;
      double to = widget.heading;

      // Shortest rotation path
      double delta = (to - from + 540) % 360 - 180;
      final target = from + delta;

      _headingAnimation = Tween<double>(begin: from, end: target).animate(
        CurvedAnimation(parent: _headingController, curve: Curves.easeOut),
      );
      _headingController
        ..reset()
        ..forward();
      _currentHeading = target;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _headingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;

    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anneau de précision GPS (optionnel)
          if (widget.accuracy > 0)
            Container(
              width: s * (0.4 + widget.accuracy.clamp(0, 1) * 0.6),
              height: s * (0.4 + widget.accuracy.clamp(0, 1) * 0.6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                border: Border.all(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
            ),

          // Pulse ring
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, _) {
              final scale = 1.0 + _pulseAnimation.value * 1.2;
              final opacity = (1.0 - _pulseAnimation.value).clamp(0.0, 1.0);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: s * 0.3,
                  height: s * 0.3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(
                      0xFF007AFF,
                    ).withValues(alpha: opacity * 0.35),
                  ),
                ),
              );
            },
          ),

          // Cône directionnel
          AnimatedBuilder(
            animation: _headingAnimation,
            builder: (context, _) {
              final angle = _headingAnimation.value * math.pi / 180;
              return Transform.rotate(
                angle: angle,
                child: CustomPaint(
                  size: Size(s, s),
                  painter: _DirectionalConePainter(),
                ),
              );
            },
          ),

          // Dot central (halo + bordure + remplissage)
          Container(
            width: s * 0.32,
            height: s * 0.32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.45),
                  blurRadius: s * 0.2,
                  spreadRadius: s * 0.03,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: s * 0.12,
                  offset: Offset(0, s * 0.04),
                ),
              ],
            ),
            padding: EdgeInsets.all(s * 0.035),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF007AFF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionalConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width * 0.46;

    // Angle d'ouverture du cône (~55°)
    const halfAngle = 27.5 * math.pi / 180;

    // Direction: vers le haut (- pi/2)
    const dir = -math.pi / 2;

    final tipX = cx;
    final tipY = cy;

    final leftX = cx + radius * math.cos(dir - halfAngle);
    final leftY = cy + radius * math.sin(dir - halfAngle);

    final rightX = cx + radius * math.cos(dir + halfAngle);
    final rightY = cy + radius * math.sin(dir + halfAngle);

    final path = Path()
      ..moveTo(tipX, tipY)
      ..lineTo(leftX, leftY)
      ..arcToPoint(
        Offset(rightX, rightY),
        radius: Radius.circular(radius),
        largeArc: false,
      )
      ..close();

    // Dégradé radial bleu → transparent
    final shader = RadialGradient(
      center: Alignment.center,
      radius: 0.5,
      colors: [
        const Color(0xFF007AFF).withValues(alpha: 0.55),
        const Color(0xFF007AFF).withValues(alpha: 0.0),
      ],
      stops: const [0.0, 1.0],
    ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));

    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

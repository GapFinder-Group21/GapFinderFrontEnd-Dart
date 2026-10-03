import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_fonts.dart';

class AnimatedMatchButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool isEnabled;

  const AnimatedMatchButton({
    super.key,
    this.onTap,
    this.isEnabled = true,
  });

  @override
  State<AnimatedMatchButton> createState() => _AnimatedMatchButtonState();
}

class _AnimatedMatchButtonState extends State<AnimatedMatchButton>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Controlador de rotación continua
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    // Controlador de pulso (latido)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isEnabled) {
      _rotationController.repeat();
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(AnimatedMatchButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEnabled != oldWidget.isEnabled) {
      if (widget.isEnabled) {
        _rotationController.repeat();
        _pulseController.repeat(reverse: true);
      } else {
        _rotationController.stop();
        _pulseController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isEnabled ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([_rotationController, _pulseAnimation]),
        builder: (context, child) {
          return Transform.scale(
            scale: widget.isEnabled ? _pulseAnimation.value : 1.0,
            child: Opacity(
              opacity: widget.isEnabled ? 1.0 : 0.4,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // El borde de 3 colores rotando
                  RotationTransition(
                    turns: _rotationController,
                    child: CustomPaint(
                      size: const Size(160, 160),
                      painter: _TricolorBorderPainter(),
                    ),
                  ),
                  // El círculo interior oscuro con el logo y texto
                  Container(
                    width: 148, // Un poco más pequeño que el borde
                    height: 148,
                    decoration: const BoxDecoration(
                      color: AppColors.contrast,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/logo_sin_fondo.png',
                            width: 80,
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                          Text(
                            'MATCH',
                            style: AppFonts.display(weight: FontWeight.w900).copyWith(
                              fontSize: 13,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TricolorBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double strokeWidth = 6.0;
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round; // Puntas redondeadas para suavidad

    // Dibujamos 3 arcos de 120 grados cada uno (360/3)
    const double sweepAngle = 2 * math.pi / 3;

    // Arco Azul (accent3)
    paint.color = AppColors.accent3;
    canvas.drawArc(rect, 0, sweepAngle, false, paint);

    // Arco Verde (accent2)
    paint.color = AppColors.accent2;
    canvas.drawArc(rect, sweepAngle, sweepAngle, false, paint);

    // Arco Rojo/Rosa (accent1)
    paint.color = AppColors.accent1;
    canvas.drawArc(rect, 2 * sweepAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/matix_colors.dart';

/// El robot Matix v1: simple, dibujado a mano (sin assets), con algo de vida
/// (parpadeo sutil + un brinco al celebrar). El arte es reemplazable después por
/// un diseño custom: basta cambiar este widget. Se usa en la presencia flotante
/// y en las burbujas.
class AvatarMatix extends StatefulWidget {
  const AvatarMatix({
    super.key,
    this.size = 44,
    this.animar = true,
    this.celebrando = false,
  });

  final double size;

  /// Si `false`, no corre el parpadeo (para tests o listas largas).
  final bool animar;

  /// Cuando pasa a `true`, da un brinco corto (reacción al cerrar un hito).
  final bool celebrando;

  @override
  State<AvatarMatix> createState() => _AvatarMatixState();
}

class _AvatarMatixState extends State<AvatarMatix>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final AnimationController _brinco;

  @override
  void initState() {
    super.initState();
    // Ciclo de ~3.6 s: ojo abierto casi todo el rato, parpadeo rápido al final.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    _brinco = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    if (widget.animar) _ctrl.repeat();
    if (widget.celebrando) _brinco.forward(from: 0);
  }

  @override
  void didUpdateWidget(AvatarMatix old) {
    super.didUpdateWidget(old);
    if (widget.celebrando && !old.celebrando) _brinco.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _brinco.dispose();
    super.dispose();
  }

  /// Apertura del ojo 0..1 a partir del progreso del ciclo: abierto (1) casi
  /// todo el tiempo, con un parpadeo corto cerca del 90% del ciclo.
  double _apertura(double t) {
    if (t < 0.88 || t > 0.96) return 1;
    // Entre 0.88 y 0.96: baja a 0 y vuelve (un parpadeo).
    final p = (t - 0.88) / 0.08; // 0..1
    return (1 - (1 - (2 * p - 1).abs())).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ctrl, _brinco]),
        builder: (context, _) {
          // Brinco: sube y baja una vez (sin(pi·t)) con una pizca de giro.
          final b = _brinco.isAnimating || _brinco.value > 0
              ? math.sin(math.pi * _brinco.value)
              : 0.0;
          return Transform.translate(
            offset: Offset(0, -widget.size * 0.12 * b),
            child: Transform.rotate(
              angle: 0.12 * b,
              child: CustomPaint(
                painter: _RobotPainter(
                  apertura: widget.animar ? _apertura(_ctrl.value) : 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RobotPainter extends CustomPainter {
  _RobotPainter({required this.apertura});

  /// 1 = ojos abiertos, 0 = cerrados.
  final double apertura;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cuerpo = Paint()..color = MatixColors.cardHi;
    final borde = Paint()
      ..color = MatixColors.accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045;
    final acento = Paint()..color = MatixColors.accent;
    final ojo = Paint()..color = MatixColors.accent;

    // Antena: línea + bolita arriba al centro.
    final cx = w / 2;
    canvas.drawLine(
      Offset(cx, h * 0.02),
      Offset(cx, h * 0.16),
      Paint()
        ..color = MatixColors.accent.withValues(alpha: 0.7)
        ..strokeWidth = w * 0.045
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(cx, h * 0.05), w * 0.05, acento);

    // Cabeza: rectángulo redondeado.
    final cabeza = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.14, h * 0.18, w * 0.72, h * 0.66),
      Radius.circular(w * 0.2),
    );
    canvas.drawRRect(cabeza, cuerpo);
    canvas.drawRRect(cabeza, borde);

    // Ojos: dos pastillas que se achican al parpadear (alto * apertura).
    final ojoW = w * 0.16;
    final ojoHMax = h * 0.18;
    final ojoH = (ojoHMax * apertura).clamp(w * 0.04, ojoHMax);
    final ojoY = h * 0.46;
    for (final ox in [w * 0.36, w * 0.64]) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(ox, ojoY), width: ojoW, height: ojoH),
        Radius.circular(w * 0.04),
      );
      canvas.drawRRect(r, ojo);
    }

    // Boca: una línea corta y amable.
    canvas.drawLine(
      Offset(w * 0.40, h * 0.68),
      Offset(w * 0.60, h * 0.68),
      Paint()
        ..color = MatixColors.muted
        ..strokeWidth = w * 0.05
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RobotPainter old) => old.apertura != apertura;
}

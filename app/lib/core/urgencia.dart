import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/matix_colors.dart';

/// Urgencia visible (Capa 7 · Urgencia-1).
///
/// La presión se VE, no se grita: una cuenta regresiva viva y una escala
/// de color por cercanía a la fecha/hora límite. Sirve igual para tareas
/// (vence_en) y eventos (inicia_en). Acá vive la lógica pura (testeable)
/// y el widget [ContadorUrgencia] que la pinta y la mantiene viva.

/// Escala de cercanía a una fecha/hora límite.
enum NivelUrgencia { tranquilo, proximo, urgente, vencido }

/// Umbrales por defecto: rojo si falta <= 24 h (o ya venció); ámbar si
/// falta <= 72 h; tranquilo si falta más. La presión sube al acercarse.
const Duration kUrgenciaUrgente = Duration(hours: 24);
const Duration kUrgenciaProximo = Duration(hours: 72);

/// Nivel de urgencia de [objetivo] respecto a [ahora].
///
/// `ahora` se pasa explícito (en vez de leer `DateTime.now()` adentro)
/// para que sea determinística en tests.
NivelUrgencia nivelUrgencia(
  DateTime objetivo,
  DateTime ahora, {
  Duration urgente = kUrgenciaUrgente,
  Duration proximo = kUrgenciaProximo,
}) {
  final restante = objetivo.difference(ahora);
  if (restante.isNegative) return NivelUrgencia.vencido;
  if (restante <= urgente) return NivelUrgencia.urgente;
  if (restante <= proximo) return NivelUrgencia.proximo;
  return NivelUrgencia.tranquilo;
}

/// Color de cada nivel, con los tokens de Matix. Tranquilo = muted (sin
/// grito); ámbar al acercarse; rojo cuando está encima o ya venció.
Color colorUrgencia(NivelUrgencia n) => switch (n) {
      NivelUrgencia.tranquilo => MatixColors.muted,
      NivelUrgencia.proximo => MatixColors.amber,
      NivelUrgencia.urgente => MatixColors.red,
      NivelUrgencia.vencido => MatixColors.red,
    };

/// Cuenta regresiva compacta, en tú y sin reproche:
///
/// - Futuro: "En 2 días" / "En 5 h" / "En 12 min" / "Justo ahora".
/// - Pasado: "Hace 2 días" / "Hace 5 h" / "Recién".
///
/// Días cuando falta mucho; horas o minutos cuando está cerca.
String textoUrgencia(DateTime objetivo, DateTime ahora) {
  final d = objetivo.difference(ahora);
  final futuro = !d.isNegative;
  final abs = d.abs();
  if (abs.inMinutes < 1) return futuro ? 'Justo ahora' : 'Recién';
  final mag = _magnitud(abs);
  return futuro ? 'En $mag' : 'Hace $mag';
}

String _magnitud(Duration d) {
  if (d.inHours >= 24) {
    final n = d.inDays;
    return '$n ${n == 1 ? "día" : "días"}';
  }
  if (d.inMinutes >= 60) {
    return '${d.inHours} h';
  }
  return '${d.inMinutes} min';
}

/// Chip con cuenta regresiva VIVA y coloreada por cercanía. Se
/// reconstruye cada minuto para que el contador avance y el color escale
/// solos, sin que el usuario tenga que recargar. Úsalo donde ya mira:
/// el bloque "Hoy" y el detalle de tarea/evento.
class ContadorUrgencia extends StatefulWidget {
  const ContadorUrgencia({
    super.key,
    required this.objetivo,
    this.conIcono = true,
    this.fondo = false,
  });

  /// Fecha/hora límite. Se compara contra `DateTime.now()` en cada tic.
  final DateTime objetivo;

  /// Muestra el icono (reloj, o alerta si está vencido) a la izquierda.
  final bool conIcono;

  /// Si true, pinta un fondo tenue del color (estilo badge).
  final bool fondo;

  @override
  State<ContadorUrgencia> createState() => _ContadorUrgenciaState();
}

class _ContadorUrgenciaState extends State<ContadorUrgencia> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Un tic por minuto basta: el contador se mueve en minutos y el
    // color escala al cruzar los umbrales. Barato y suficiente.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final nivel = nivelUrgencia(widget.objetivo, ahora);
    final color = colorUrgencia(nivel);
    final texto = textoUrgencia(widget.objetivo, ahora);
    final fuerte =
        nivel == NivelUrgencia.urgente || nivel == NivelUrgencia.vencido;

    final fila = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.conIcono) ...[
          Icon(
            nivel == NivelUrgencia.vencido
                ? Icons.error_outline
                : Icons.schedule,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
        ],
        Text(
          texto,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: fuerte ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );

    if (!widget.fondo) return fila;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: fila,
    );
  }
}

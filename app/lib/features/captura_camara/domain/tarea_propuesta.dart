import 'package:flutter/foundation.dart';

/// Una tarea candidata que el cerebro extrajo del texto (Capa 7-B).
///
/// Es editable en la hoja de revisión antes de crearse: el usuario
/// ajusta el título, mueve o quita la fecha y le asigna un proyecto.
/// Nada se crea hasta que confirma. Por eso vive como modelo de la
/// app, separado de [Tarea] (la entidad ya persistida).
///
/// `venceEn` es una fecha local (medianoche) o `null`. El cerebro la
/// devuelve como `YYYY-MM-DD` tras resolver fechas relativas ("el
/// viernes"); acá la guardamos como `DateTime` para el date picker y
/// se convierte a UTC al crear, como el resto de tareas.
@immutable
class TareaPropuesta {
  const TareaPropuesta({
    required this.titulo,
    this.venceEn,
    this.proyectoId,
  });

  final String titulo;
  final DateTime? venceEn;
  final String? proyectoId;

  /// Parse del JSON del cerebro (`{titulo, vence_en}`). `vence_en`
  /// llega como `YYYY-MM-DD` o `null`. Si la fecha es inválida la
  /// descartamos en vez de reventar — la tarea sigue siendo útil.
  factory TareaPropuesta.fromCerebro(Map<String, dynamic> j) {
    final crudo = j['vence_en'] as String?;
    DateTime? vence;
    if (crudo != null && crudo.trim().isNotEmpty) {
      vence = DateTime.tryParse(crudo.trim());
    }
    return TareaPropuesta(
      titulo: (j['titulo'] as String? ?? '').trim(),
      venceEn: vence,
    );
  }

  TareaPropuesta copyWith({
    String? titulo,
    Object? venceEn = _kSentinel,
    Object? proyectoId = _kSentinel,
  }) {
    return TareaPropuesta(
      titulo: titulo ?? this.titulo,
      venceEn:
          identical(venceEn, _kSentinel) ? this.venceEn : venceEn as DateTime?,
      proyectoId: identical(proyectoId, _kSentinel)
          ? this.proyectoId
          : proyectoId as String?,
    );
  }

  static const _kSentinel = Object();
}

import '../../tareas/domain/tarea.dart';

/// Horizonte temporal de un paso del desglose (Capa 7 · Desglose):
/// ordena un objetivo grande en el tiempo.
enum Horizonte {
  ahora,
  pronto,
  masAdelante;

  static Horizonte fromJson(String? s) => switch (s) {
        'ahora' => Horizonte.ahora,
        'mas_adelante' => Horizonte.masAdelante,
        _ => Horizonte.pronto,
      };

  String get label => switch (this) {
        Horizonte.ahora => 'Ahora',
        Horizonte.pronto => 'Pronto',
        Horizonte.masAdelante => 'Más adelante',
      };

  /// Mapeo a prioridad de tarea: así el horizonte viaja con el paso
  /// creado (sin columna nueva) y los pasos "ahora" salen primero al
  /// usar "Planifica mi día" (que ordena por prioridad).
  Prioridad get prioridad => switch (this) {
        Horizonte.ahora => Prioridad.alta,
        Horizonte.pronto => Prioridad.media,
        Horizonte.masAdelante => Prioridad.baja,
      };
}

/// Un paso propuesto por Matix. Mutable para que la hoja de revisión
/// permita editar el título y el horizonte antes de crear.
class PasoPropuesto {
  PasoPropuesto({required this.titulo, this.horizonte = Horizonte.pronto});

  String titulo;
  Horizonte horizonte;

  factory PasoPropuesto.fromCerebro(Map<String, dynamic> j) => PasoPropuesto(
        titulo: (j['titulo'] as String?)?.trim() ?? '',
        horizonte: Horizonte.fromJson(j['horizonte'] as String?),
      );

  PasoPropuesto copyWith({String? titulo, Horizonte? horizonte}) =>
      PasoPropuesto(
        titulo: titulo ?? this.titulo,
        horizonte: horizonte ?? this.horizonte,
      );
}

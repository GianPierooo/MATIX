/// Cuán proactivo es Matix. El dial arranca en EXIGENTE (proactivo y encima),
/// pero los frenos (tope diario, silencio, dedup, anti-fatiga) viven firmes en
/// el cerebro: subir o bajar este nivel nunca apaga la contención.
enum NivelProactividad {
  suave,
  equilibrado,
  exigente;

  static NivelProactividad fromJson(String? s) => switch (s) {
        'suave' => NivelProactividad.suave,
        'equilibrado' => NivelProactividad.equilibrado,
        _ => NivelProactividad.exigente,
      };

  String toJson() => name;

  String get etiqueta => switch (this) {
        NivelProactividad.suave => 'Suave',
        NivelProactividad.equilibrado => 'Equilibrado',
        NivelProactividad.exigente => 'Exigente',
      };

  String get descripcion => switch (this) {
        NivelProactividad.suave =>
          'Pocos avisos. Solo lo más oportuno, sin encimarte.',
        NivelProactividad.equilibrado =>
          'Avisos medidos: ratos libres, reposición y plazos cercanos.',
        NivelProactividad.exigente =>
          'Proactivo y encima: se adelanta a todo, con frenos firmes.',
      };
}

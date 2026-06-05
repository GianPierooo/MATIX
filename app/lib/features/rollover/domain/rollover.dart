// Modelos del ROLLOVER de tareas no cumplidas (Capa 8). El cerebro detecta lo
// que no se hizo a su hora o al cierre del día y propone moverlo al siguiente
// hueco libre; la app lo muestra TOCABLE por el robot (acepto / otro día / lo
// suelto). Nada se mueve en silencio. Parsing PURO y testeable.

/// La decisión del usuario sobre una tarea no cumplida.
enum DecisionRollover { aceptar, otroDia, soltar }

extension DecisionRolloverX on DecisionRollover {
  /// Lo que entiende el cerebro (POST /rollover/decidir).
  String get id => switch (this) {
        DecisionRollover.aceptar => 'aceptar',
        DecisionRollover.otroDia => 'otro_dia',
        DecisionRollover.soltar => 'soltar',
      };
}

/// El hueco propuesto para retomar una tarea.
class PropuestaHueco {
  const PropuestaHueco({
    required this.fecha,
    required this.inicio,
    required this.fin,
    required this.cuando,
  });

  final String fecha; // ISO date
  final String inicio; // HH:MM (Lima)
  final String fin; // HH:MM (Lima)
  final String cuando; // "hoy 15:30" / "mañana 09:00" / "el mié 10:00"

  static PropuestaHueco? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return PropuestaHueco(
      fecha: (j['fecha'] as String?) ?? '',
      inicio: (j['inicio'] as String?) ?? '',
      fin: (j['fin'] as String?) ?? '',
      cuando: (j['cuando'] as String?) ?? '',
    );
  }
}

/// Una tarea no cumplida con su propuesta de reprogramación.
class RolloverItem {
  const RolloverItem({
    required this.tareaId,
    required this.titulo,
    required this.vecesReprogramada,
    this.vencioEn,
    this.propuesta,
  });

  final String tareaId;
  final String titulo;
  final int vecesReprogramada;
  final String? vencioEn;
  final PropuestaHueco? propuesta;

  static RolloverItem fromJson(Map<String, dynamic> j) => RolloverItem(
        tareaId: (j['tarea_id'] as String?) ?? '',
        titulo: (j['titulo'] as String?) ?? 'Tarea',
        vecesReprogramada: (j['veces_reprogramada'] as num?)?.toInt() ?? 0,
        vencioEn: j['vencio_en'] as String?,
        propuesta:
            PropuestaHueco.fromJson(j['propuesta'] as Map<String, dynamic>?),
      );
}

/// El guardrail honesto: cuánto se arrastra y si ya es de re-escopar/bajar carga.
class Sobrecarga {
  const Sobrecarga({
    required this.sobrecargado,
    required this.n,
    this.peorTitulo,
    this.peorVeces = 0,
    this.mensaje,
    this.recomendacion,
  });

  final bool sobrecargado;
  final int n;
  final String? peorTitulo;
  final int peorVeces;
  final String? mensaje;
  final String? recomendacion; // 'reescopar' | 'bajar_carga'

  static const vacia = Sobrecarga(sobrecargado: false, n: 0);

  static Sobrecarga fromJson(Map<String, dynamic>? j) {
    if (j == null) return vacia;
    return Sobrecarga(
      sobrecargado: (j['sobrecargado'] as bool?) ?? false,
      n: (j['n'] as num?)?.toInt() ?? 0,
      peorTitulo: j['peor_titulo'] as String?,
      peorVeces: (j['peor_veces'] as num?)?.toInt() ?? 0,
      mensaje: j['mensaje'] as String?,
      recomendacion: j['recomendacion'] as String?,
    );
  }
}

/// La respuesta completa de GET /rollover.
class RolloverData {
  const RolloverData({required this.proposals, required this.sobrecarga});

  final List<RolloverItem> proposals;
  final Sobrecarga sobrecarga;

  bool get hayAlgo => proposals.isNotEmpty || sobrecarga.sobrecargado;

  static const vacio =
      RolloverData(proposals: [], sobrecarga: Sobrecarga.vacia);

  static RolloverData fromJson(Map<String, dynamic> j) {
    final raw = (j['proposals'] as List?) ?? const [];
    return RolloverData(
      proposals: [
        for (final p in raw)
          if (p is Map<String, dynamic>) RolloverItem.fromJson(p),
      ],
      sobrecarga: Sobrecarga.fromJson(j['sobrecarga'] as Map<String, dynamic>?),
    );
  }
}

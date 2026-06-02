/// Guion de grabación para entrenar "oye matix" con la voz del usuario.
///
/// Define qué decir en cada clip y de qué tipo es:
/// - `positivo`: la palabra real, "oye matix". Variamos tono/distancia/ritmo
///   para que el modelo generalice a cómo la dirás en la vida real.
/// - `negativo` ("duros"): frases parecidas o cotidianas que NO deben
///   dispararla. Afinan la frontera para que no salte con cualquier cosa.
///
/// El total (positivos + negativos) alimenta el reentrenamiento; con
/// aumentación, ~60 positivos se multiplican a miles de ejemplos.
library;

/// Un ítem del guion: el tipo, la frase a decir y una pista de cómo decirla.
class MuestraGuion {
  const MuestraGuion({
    required this.tipo,
    required this.frase,
    required this.pista,
  });

  /// `positivo` | `negativo`.
  final String tipo;

  /// Lo que el usuario debe decir.
  final String frase;

  /// Cómo decirlo (distancia, tono, ritmo) — guía en pantalla.
  final String pista;

  bool get esPositivo => tipo == 'positivo';
}

/// Construye el guion completo. Orden: primero los positivos (con variación),
/// luego los negativos duros. El índice dentro de cada tipo lo asigna el
/// provider al subir (1..N por tipo).
List<MuestraGuion> construirGuion() {
  final items = <MuestraGuion>[];

  // 60 positivos "oye matix" con variación guiada (5 bloques de 12).
  const bloquesPositivos = <(String, int)>[
    ('Normal, a 30 cm, tono natural.', 16),
    ('Más suave, casi en voz baja.', 11),
    ('Un poco más lejos, a un brazo de distancia.', 11),
    ('Rápido y pegado: "oyematix".', 11),
    ('Con algo de ruido de fondo (tele, ventilador).', 11),
  ];
  for (final (pista, n) in bloquesPositivos) {
    for (var i = 0; i < n; i++) {
      items.add(MuestraGuion(tipo: 'positivo', frase: 'oye matix', pista: pista));
    }
  }

  // 25 negativos duros: parecidas y cotidianas que NO deben disparar.
  const negativos = <String>[
    'oye',
    'matix',
    'oye mati',
    'oye matías',
    'oye marcos',
    'oye amigo',
    'oye ven acá',
    'oye una cosa',
    'oye perdona',
    'oye escucha',
    'oye dime',
    'oiga',
    'matías',
    'mati ven',
    'hola qué tal',
    'buenos días',
    'qué hora es',
    'ya voy',
    'no sé',
    'espera un momento',
    'gracias',
    'dale pues',
    'a ver',
    'todo bien',
    'nos vemos',
  ];
  for (final frase in negativos) {
    items.add(MuestraGuion(
      tipo: 'negativo',
      frase: frase,
      pista: 'Dilo natural. Esto NO debe despertar a Matix.',
    ));
  }

  return items;
}

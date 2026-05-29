/// Mapea un `uuid` (string) a un id de notificación Android (int 32
/// bits). Usamos los primeros 7 caracteres hex del uuid (28 bits)
/// para garantizar que cabe en `Integer.MAX_VALUE` sin overflow.
///
/// Colisión: 1 entre 268M, prácticamente nula a la escala de tareas
/// de un usuario. Estable entre runs.
int notifIdDe(String uuid) {
  final hex = uuid.replaceAll('-', '');
  if (hex.length < 7) {
    return uuid.hashCode.abs() & 0x0FFFFFFF;
  }
  return int.parse(hex.substring(0, 7), radix: 16);
}

/// Id de notificación estable para UNA ocurrencia de un evento recurrente,
/// derivado de `(uuid, fecha de la ocurrencia)`. Distinto de [notifIdDe],
/// que ignora cualquier sufijo (toma solo los primeros 7 hex del uuid) y
/// por tanto colisiona entre ocurrencias de la misma serie.
///
/// Usamos FNV-1a de 32 bits sobre `'$uuid@aaaa-mm-dd'` y enmascaramos a 31
/// bits para que quepa positivo en `Integer.MAX_VALUE`. Determinista entre
/// runs: la misma ocurrencia siempre cae en el mismo id, lo que permite
/// recalcular y cancelar la ventana móvil sin guardar estado.
int notifIdDeOcurrencia(String uuid, DateTime dia) {
  final d = DateTime(dia.year, dia.month, dia.day);
  final clave =
      '$uuid@${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  var hash = 0x811c9dc5;
  for (final code in clave.codeUnits) {
    hash ^= code;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Id de notificación estable para el N-ésimo nudge escalado de una
/// tarea (Capa 7 · Urgencia-2). Una tarea tiene varios nudges (uno por
/// punto del calendario), así que derivamos un id distinto por índice
/// con FNV-1a sobre `'$uuid#nudge$indice'`. Determinista entre runs:
/// permite cancelar/reprogramar el rango fijo 0..kMaxNudges-1 sin
/// guardar estado. No choca con [notifIdDe] (el del recordatorio único).
int notifIdDeNudge(String uuid, int indice) {
  final clave = '$uuid#nudge$indice';
  var hash = 0x811c9dc5;
  for (final code in clave.codeUnits) {
    hash ^= code;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

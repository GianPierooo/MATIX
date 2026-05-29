/// Recordatorio de un evento, modelado como un offset en minutos antes
/// del inicio. Capa Calendario · Paso 2.
///
/// `null` = sin recordatorio · `0` = a la hora · `10`/`60`/`1440` = los
/// presets de la app. Mantener la lógica como funciones puras permite
/// testearla sin tocar la UI ni el plugin de notificaciones.
class PresetRecordatorio {
  const PresetRecordatorio(this.offsetMin, this.etiqueta);

  /// Minutos antes del inicio. `null` = sin recordatorio.
  final int? offsetMin;
  final String etiqueta;
}

/// Presets ofrecidos en el selector, en orden de cercanía al inicio.
const presetsRecordatorio = <PresetRecordatorio>[
  PresetRecordatorio(null, 'Sin recordatorio'),
  PresetRecordatorio(0, 'A la hora'),
  PresetRecordatorio(10, '10 minutos antes'),
  PresetRecordatorio(60, '1 hora antes'),
  PresetRecordatorio(1440, '1 día antes'),
];

/// Texto legible del recordatorio para el detalle del evento. Cae a una
/// descripción en claro si el offset no es uno de los presets.
String etiquetaRecordatorio(int? offsetMin) {
  for (final p in presetsRecordatorio) {
    if (p.offsetMin == offsetMin) return p.etiqueta;
  }
  if (offsetMin == null || offsetMin < 0) return 'Sin recordatorio';
  if (offsetMin == 0) return 'A la hora';
  if (offsetMin % 1440 == 0) return '${offsetMin ~/ 1440} días antes';
  if (offsetMin % 60 == 0) return '${offsetMin ~/ 60} horas antes';
  return '$offsetMin minutos antes';
}

/// Instante en que debe dispararse el recordatorio (`inicia − offset`),
/// o `null` si no hay recordatorio.
DateTime? momentoRecordatorio(DateTime inicia, int? offsetMin) {
  if (offsetMin == null || offsetMin < 0) return null;
  return inicia.subtract(Duration(minutes: offsetMin));
}

/// `true` si hay que agendar: existe offset y el instante es futuro.
/// Un evento ya pasado (o cuyo recordatorio ya pasó) no agenda nada.
bool agendaRecordatorio({
  required DateTime inicia,
  required int? offsetMin,
  required DateTime ahora,
}) {
  final cuando = momentoRecordatorio(inicia, offsetMin);
  return cuando != null && cuando.isAfter(ahora);
}

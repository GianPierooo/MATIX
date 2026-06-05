// Anti-fastidio de la mascota (la lección del búho): dosificada igual que la
// proactividad. No aparece a cada rato, respeta horas de silencio, y BAJA si la
// ignoras. Todo PURO y testeable.

/// Cuán seguido aparece. Discreta = el doble de espaciado que normal.
enum FrecuenciaMascota { discreta, normal }

FrecuenciaMascota frecuenciaDe(String? s) =>
    s == 'discreta' ? FrecuenciaMascota.discreta : FrecuenciaMascota.normal;

extension FrecuenciaMascotaX on FrecuenciaMascota {
  String get id => name;
  String get etiqueta =>
      this == FrecuenciaMascota.discreta ? 'Discreta' : 'Normal';
}

/// ¿La hora local cae en el silencio [inicio, fin)? Cruza medianoche si
/// inicio > fin (p. ej. 22→8). PURO.
bool enSilencio(int hora, int inicio, int fin) {
  if (inicio == fin) return false;
  if (inicio < fin) return inicio <= hora && hora < fin;
  return hora >= inicio || hora < fin;
}

/// Multiplicador anti-fatiga: si la ignoras seguido, espaciamos más (sin
/// apagarla). Mismo espíritu que la proactividad del cerebro. PURO.
int factorIgnoradas(int ignoradasSeguidas) {
  if (ignoradasSeguidas <= 1) return 1;
  if (ignoradasSeguidas <= 3) return 2;
  return 4;
}

/// Cada cuánto, como mínimo, puede APARECER (no el saludo). Normal = 4 h base;
/// discreta = 8 h. Escala con el anti-fatiga. PURO.
Duration intervaloAparicion(FrecuenciaMascota f, int ignoradasSeguidas) {
  final base = f == FrecuenciaMascota.discreta ? 8 : 4;
  return Duration(hours: base * factorIgnoradas(ignoradasSeguidas));
}

/// ¿Puede aparecer AHORA? Respeta on/off, silencio, intervalo y anti-fatiga.
/// PURO (recibe `ahora` y `ultima`, no toca el reloj).
bool puedeAparecer({
  required bool habilitado,
  required DateTime ahora,
  DateTime? ultima,
  required int ignoradasSeguidas,
  required int silencioInicio,
  required int silencioFin,
  required FrecuenciaMascota frecuencia,
}) {
  if (!habilitado) return false;
  if (enSilencio(ahora.hour, silencioInicio, silencioFin)) return false;
  if (ultima == null) return true;
  return ahora.difference(ultima) >= intervaloAparicion(frecuencia, ignoradasSeguidas);
}

/// La despedida también se dosifica: no en cada salida ni en silencio. PURO.
bool puedeDespedir({
  required bool habilitado,
  required DateTime ahora,
  DateTime? ultimaDespedida,
  required int silencioInicio,
  required int silencioFin,
  int minHorasEntreDespedidas = 4,
}) {
  if (!habilitado) return false;
  if (enSilencio(ahora.hour, silencioInicio, silencioFin)) return false;
  if (ultimaDespedida == null) return true;
  return ahora.difference(ultimaDespedida) >=
      Duration(hours: minHorasEntreDespedidas);
}

/// Cálculo de choques de horario.
///
/// Un "choque" ocurre cuando dos bloques de tiempo se solapan en el
/// mismo día. Útil para advertir al usuario:
/// - Evento nuevo que pisa una clase recurrente.
/// - Dos eventos que se solapan.
///
/// La función `seSolapan` es pura — sin Flutter, fácil de testear.
bool seSolapan(
  DateTime aIni,
  DateTime aFin,
  DateTime bIni,
  DateTime bFin,
) {
  // Solapamiento estricto: comparten algún instante interior.
  // Tocar punta con punta (aFin == bIni) NO cuenta como choque.
  return aIni.isBefore(bFin) && bIni.isBefore(aFin);
}

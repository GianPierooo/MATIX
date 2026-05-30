// Helpers de semana para la vista de calendario (presentación).
// Semana de lunes a domingo (como el resto del calendario).

/// El lunes (a las 00:00) de la semana que contiene [d].
DateTime lunesDe(DateTime d) {
  final base = DateTime(d.year, d.month, d.day);
  return base.subtract(Duration(days: base.weekday - 1));
}

/// Los 7 días (lunes → domingo) de la semana que contiene [d].
List<DateTime> diasDeSemana(DateTime d) {
  final lunes = lunesDe(d);
  return [for (var i = 0; i < 7; i++) lunes.add(Duration(days: i))];
}

import 'package:shared_preferences/shared_preferences.dart';

/// `yyyy-MM-dd` de una fecha LOCAL (sin hora). PURO y testeable.
String fechaIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// ¿La fecha guardada corresponde a HOY? Si no hay fecha guardada (o es de otro
/// día), el botón "Me acabo de levantar" debe mostrarse. PURO y testeable.
bool despertarRegistradoHoy(String? guardada, DateTime ahora) =>
    guardada != null && guardada == fechaIso(ahora);

/// Persiste la fecha del último "Me acabo de levantar" para no repetir el botón
/// el mismo día. Reaparece solo al día siguiente (fecha nueva). Local, sin red.
class DespertarPrefs {
  static const _kFecha = 'despertar_fecha';

  Future<String?> leerFecha() async =>
      (await SharedPreferences.getInstance()).getString(_kFecha);

  Future<void> marcar(DateTime fecha) async =>
      (await SharedPreferences.getInstance())
          .setString(_kFecha, fechaIso(fecha));

  Future<void> limpiar() async =>
      (await SharedPreferences.getInstance()).remove(_kFecha);
}

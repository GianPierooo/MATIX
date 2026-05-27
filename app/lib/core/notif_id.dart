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

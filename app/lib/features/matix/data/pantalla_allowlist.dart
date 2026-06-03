import 'package:shared_preferences/shared_preferences.dart';

/// Allowlist de paquetes que Matix puede LEER de la pantalla (Tier C).
///
/// ESCAFOLDADO para C.0: por defecto es PERMISIVO (lee cualquier app). La
/// estructura (modo restringido + lista local) queda lista para C.1, donde se
/// limitará a apps elegidas por el usuario. Se guarda LOCAL en el dispositivo
/// (SharedPreferences), nunca en la BD: es preferencia del device.
class PantallaAllowlist {
  PantallaAllowlist();

  static const _claveModo = 'pantalla_allowlist_restringida';
  static const _claveLista = 'pantalla_allowlist_paquetes';

  /// ¿Matix puede leer este paquete? En C.0 (modo no restringido), siempre sí.
  Future<bool> permitido(String paquete) async {
    final prefs = await SharedPreferences.getInstance();
    final restringida = prefs.getBool(_claveModo) ?? false; // C.0: permisivo
    if (!restringida) return true;
    final lista = prefs.getStringList(_claveLista) ?? const [];
    return lista.contains(paquete);
  }

  // ── Scaffolding para C.1 (aún no se usa en la UI) ──────────────────

  Future<bool> esRestringida() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_claveModo) ?? false;
  }

  Future<void> setRestringida(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveModo, valor);
  }

  Future<List<String>> paquetes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_claveLista) ?? const [];
  }

  Future<void> agregar(String paquete) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList(_claveLista)?.toList() ?? <String>[];
    if (!lista.contains(paquete)) {
      lista.add(paquete);
      await prefs.setStringList(_claveLista, lista);
    }
  }

  Future<void> quitar(String paquete) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList(_claveLista)?.toList() ?? <String>[];
    lista.remove(paquete);
    await prefs.setStringList(_claveLista, lista);
  }
}

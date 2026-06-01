import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Migajas de la activación del wake word, persistidas a disco para
/// diagnosticar un CRASH NATIVO (SIGSEGV/abort) sin USB ni logcat.
///
/// Antes de cada paso riesgoso se escribe — de forma SÍNCRONA y con flush — la
/// migaja del paso. La escritura termina (y el dato queda en el SO) antes de la
/// llamada nativa siguiente, así que aunque el proceso muera de golpe, la
/// migaja sobrevive. Al reabrir la app leemos la última: si NO es un estado
/// "seguro", la última activación murió ahí y lo mostramos.
///
/// Nunca se escriben datos personales — solo el nombre del paso.
class WakeWordCrumbs {
  WakeWordCrumbs({File? archivo}) : _f = archivo;

  File? _f;

  /// Estados que indican que la activación pasó el tramo peligroso o terminó
  /// limpia. Cualquier otra migaja = murió en ese paso.
  static const Set<String> seguros = {'apagado', 'escuchando-ok', 'inferencia-ok'};

  Future<void> preparar() async {
    if (_f != null) return;
    final dir = await getApplicationSupportDirectory();
    _f = File('${dir.path}${Platform.pathSeparator}wakeword_crumb.txt');
  }

  /// Escribe la migaja YA (síncrono + flush). Requiere [preparar] antes.
  void marca(String paso) {
    final f = _f;
    if (f == null) return;
    try {
      f.writeAsStringSync(paso, flush: true);
    } catch (_) {
      // Si no se puede escribir, seguimos: las migajas son best-effort.
    }
  }

  /// Última migaja escrita (o null si no hay).
  Future<String?> leer() async {
    try {
      await preparar();
      final f = _f!;
      if (await f.exists()) {
        final s = (await f.readAsString()).trim();
        return s.isEmpty ? null : s;
      }
    } catch (_) {}
    return null;
  }

  /// Paso en el que murió la última activación, o null si terminó bien / no hay
  /// rastro.
  Future<String?> muerteDeActivacion() async {
    final c = await leer();
    if (c == null) return null;
    return seguros.contains(c) ? null : c;
  }

  Future<void> limpiar() async {
    try {
      await preparar();
      final f = _f!;
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

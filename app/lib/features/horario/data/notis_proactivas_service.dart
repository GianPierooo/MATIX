import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notificaciones_service.dart';
import 'horario_repository.dart';

/// Servicio que pide al cerebro la LISTA de notis proactivas del día (resumen
/// matutino + pre-actividad + nudges) y las programa localmente con
/// `NotificacionesService.programar` (que ya usa `zonedSchedule` de
/// `flutter_local_notifications`).
///
/// Por qué local-scheduling y NO un tick de servidor:
/// - Una vez programadas, el AlarmManager nativo las dispara aunque la app
///   esté dormida. En MagicOS, donde el `ActionBroadcastReceiver` del plugin
///   a veces no arranca, esto es lo más robusto: el sistema operativo entrega
///   la noti directo, sin proceso de Matix vivo. Cero dependencia de FCM/red
///   en el momento del disparo. Cero coste por día.
///
/// Idempotencia: cada noti del cerebro trae un `dedup_key` estable
/// (`tipo|fecha|HH:MM|ref`). Nosotros generamos un ID INT determinista por
/// `dedup_key` y guardamos los IDs programados en SharedPreferences. Al
/// `refrescar()`: cancelamos los IDs viejos, programamos los nuevos, guardamos
/// los IDs nuevos. Re-llamar no duplica.
///
/// Se llama desde tres puntos:
/// - tras `POST /horario/despertar` (al levantarse: el día arrancó);
/// - tras `POST /horario/agendar` (cambió el plan);
/// - on-resume si pasó tiempo (los plazos pueden haberse movido).
class NotisProactivasService {
  NotisProactivasService(this._repo, this._notif);

  final HorarioRepository _repo;
  final NotificacionesService _notif;

  /// Clave en `SharedPreferences` donde guardamos los IDs ya programados, para
  /// poder cancelarlos antes de la próxima ronda. Si el storage se pierde, las
  /// alarmas viejas se quedan hasta vencer — no es fatal (igual eran del día).
  static const String _kPrefIds = 'notis_proactivas_ids_programados';

  /// Offset reservado para IDs de notis proactivas (evita colisión con otros
  /// usos del scheduler en la app). 31 bits efectivos por el hash.
  static const int _idOffset = 0x40000000;

  /// Pide al cerebro las notis del día y las programa. Devuelve un resumen
  /// para logs/diagnóstico: `{programadas, canceladas, total_servidor}`.
  /// Tolerante a fallos: si la red cae, no rompe — solo loggea.
  Future<Map<String, int>> refrescar() async {
    Map<String, dynamic> payload;
    try {
      payload = await _repo.traerNotisProgramadas();
    } catch (e) {
      debugPrint('NotisProactivas: no pude traer del cerebro ($e)');
      return const {'programadas': 0, 'canceladas': 0, 'total_servidor': 0};
    }
    final notis = (payload['notis'] as List?) ?? const [];

    // Cancelar las anteriores: si el storage perdió la lista, igual seguimos
    // (las viejas mueren solas tras su disparo o el reinicio del teléfono).
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefIds);
    final viejos = _parseIds(raw);
    var cancelados = 0;
    for (final id in viejos) {
      try {
        await _notif.cancelar(id);
        cancelados++;
      } catch (_) {
        // Ignoramos: el plugin a veces falla por estado interno.
      }
    }

    final nuevosIds = <int>[];
    var programados = 0;
    for (final raw in notis) {
      final n = (raw as Map).cast<String, dynamic>();
      final dedup = (n['dedup_key'] as String?) ?? '';
      final iso = (n['disparar_en'] as String?) ?? '';
      final titulo = (n['titulo'] as String?) ?? '';
      final cuerpo = (n['cuerpo'] as String?) ?? '';
      final payloadAccion = (n['payload'] as String?) ?? '';
      if (dedup.isEmpty || iso.isEmpty) continue;
      final cuando = DateTime.tryParse(iso);
      if (cuando == null) continue;
      final id = idDe(dedup);
      // Pre-actividad ganaría con alarma exacta (la diferencia entre llegar a
      // las 10:45:00 y 10:47:30 importa para "en 15 min"). El resto no necesita
      // precisión al segundo. Detección barata por dedup_key.
      final exacto = dedup.startsWith('pre_actividad|');
      final ok = await _notif.programar(
        id: id,
        titulo: titulo,
        cuerpo: cuerpo,
        cuando: cuando,
        exacto: exacto,
        payload: payloadAccion,
      );
      if (ok) {
        nuevosIds.add(id);
        programados++;
      }
    }

    await prefs.setString(_kPrefIds, jsonEncode(nuevosIds));
    debugPrint(
      'NotisProactivas: ok '
      'programadas=$programados canceladas=$cancelados total_servidor=${notis.length}',
    );
    return {
      'programadas': programados,
      'canceladas': cancelados,
      'total_servidor': notis.length,
    };
  }

  /// Cancela TODAS las notis proactivas programadas (útil al cerrar sesión o
  /// al desactivar el módulo). No toca el resto de notis de la app.
  Future<int> cancelarTodas() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = _parseIds(prefs.getString(_kPrefIds));
    var canceladas = 0;
    for (final id in ids) {
      try {
        await _notif.cancelar(id);
        canceladas++;
      } catch (_) {}
    }
    await prefs.remove(_kPrefIds);
    return canceladas;
  }

  /// ID INT determinista a partir del `dedup_key` (string estable del cerebro).
  /// Mismo dedup_key → mismo ID. Si la app re-pide y un mismo bloque sigue ahí,
  /// `programar()` lo SUSTITUYE en vez de duplicarlo (el plugin re-programa por
  /// id). Hash de 31 bits + offset para reservar rango y evitar choques con
  /// otros usos del scheduler.
  ///
  /// Visible para tests.
  static int idDe(String dedupKey) {
    // FNV-1a 32-bit: hash estable, sin dependencias, buena distribución.
    var hash = 0x811c9dc5;
    for (final code in dedupKey.codeUnits) {
      hash ^= code;
      // Multiplicación en 32-bit ignorando overflow (& 0xFFFFFFFF).
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    // 30 bits efectivos + offset para no chocar con otros bloques del scheduler.
    return _idOffset + (hash & 0x3FFFFFFF);
  }

  static List<int> _parseIds(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [for (final v in decoded) if (v is int) v];
      }
    } catch (_) {}
    return const [];
  }
}

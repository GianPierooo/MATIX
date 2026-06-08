import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config.dart';

/// Servicio ÚNICO para aplicar la confirmación de tareas (rendición de cuentas)
/// y de asistencia a eventos. Lo usan TRES rutas:
///   - el handler de background de la noti (`manejarTapRendicionCuentas`,
///     `manejarTapAsistencia`), que sigue siendo top-level y simple;
///   - la UI in-app (Tu día + Cierre del día), que confirma con un toque
///     cuando el usuario VE el ítem pasado, sin esperar la noti;
///   - la pantalla de Diagnóstico, que dispara un "ping" y verifica que el
///     POST llegó al cerebro.
///
/// INSTRUMENTACIÓN: cada intento guarda un registro local con timestamp + ok/
/// error en `SharedPreferences`. La pantalla de Diagnóstico lo lee para que el
/// usuario vea evidencia ("último 'hecho': hace 12s, OK 200") en vez de
/// adivinar dónde se rompió la cadena. Es liviano (~30 entradas con rotación).
///
/// Acciones válidas:
///   - tareas: hecho | mas_tarde | manana
///   - asistencia: si_fui | no_fui | reprogramar

const Set<String> _accionesTarea = {'hecho', 'mas_tarde', 'manana'};
const Set<String> _accionesAsistencia = {'si_fui', 'no_fui', 'reprogramar'};

/// Tipo de evento confirmado, para diferenciar en el log de diagnóstico.
enum TipoConfirmacion { tarea, asistencia, diagnostico }

/// Una entrada del log local (instrumentación de la cadena).
class EntradaConfirmacion {
  const EntradaConfirmacion({
    required this.cuando,
    required this.tipo,
    required this.ref,
    required this.accion,
    required this.ok,
    this.statusCode,
    this.error,
  });

  final DateTime cuando;
  final TipoConfirmacion tipo;

  /// Id del ítem o etiqueta breve (tarea_id / evento_id / `diag:<accion>`).
  final String ref;
  final String accion;
  final bool ok;
  final int? statusCode;
  final String? error;

  Map<String, dynamic> toJson() => {
        'cuando': cuando.toIso8601String(),
        'tipo': tipo.name,
        'ref': ref,
        'accion': accion,
        'ok': ok,
        if (statusCode != null) 'status': statusCode,
        if (error != null) 'error': error,
      };

  static EntradaConfirmacion? fromJson(Map<String, dynamic> j) {
    try {
      return EntradaConfirmacion(
        cuando: DateTime.parse(j['cuando'] as String),
        tipo: TipoConfirmacion.values.byName(j['tipo'] as String),
        ref: j['ref'] as String,
        accion: j['accion'] as String,
        ok: j['ok'] as bool,
        statusCode: (j['status'] as num?)?.toInt(),
        error: j['error'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Resultado simple de un intento.
class ResultadoConfirmacion {
  const ResultadoConfirmacion({
    required this.ok,
    this.statusCode,
    this.mensaje,
  });
  final bool ok;
  final int? statusCode;
  final String? mensaje;
}

const String _kLogPrefs = 'confirmaciones_log_v1';
const int _topeLog = 30;

class ConfirmacionService {
  ConfirmacionService({http.Client? cliente})
      : _cliente = cliente ?? http.Client();

  final http.Client _cliente;

  Future<ResultadoConfirmacion> confirmarTarea({
    required String tareaId,
    required String accion,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (tareaId.isEmpty || !_accionesTarea.contains(accion)) {
      return const ResultadoConfirmacion(ok: false, mensaje: 'argumentos inválidos');
    }
    return _post(
      path: '/api/v1/push/rendicion-cuentas/accion',
      body: {'tarea_id': tareaId, 'accion': accion},
      tipo: TipoConfirmacion.tarea,
      ref: tareaId,
      accion: accion,
      timeout: timeout,
    );
  }

  Future<ResultadoConfirmacion> confirmarAsistencia({
    required String eventoId,
    required String accion,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (eventoId.isEmpty || !_accionesAsistencia.contains(accion)) {
      return const ResultadoConfirmacion(ok: false, mensaje: 'argumentos inválidos');
    }
    return _post(
      path: '/api/v1/push/asistencia/accion',
      body: {'evento_id': eventoId, 'accion': accion},
      tipo: TipoConfirmacion.asistencia,
      ref: eventoId,
      accion: accion,
      timeout: timeout,
    );
  }

  /// Para la pantalla de Diagnóstico: aplica una acción de prueba contra una
  /// `tareaId` real (la app la elige) o no hace POST si no la pasa — solo
  /// queremos comprobar la cadena handler→POST→cerebro. Loguea el intento.
  Future<ResultadoConfirmacion> diagnosticoPing({
    required String etiqueta,
  }) async {
    final ahora = DateTime.now();
    final res = const ResultadoConfirmacion(ok: true, mensaje: 'diagnóstico local');
    await _registrar(EntradaConfirmacion(
      cuando: ahora,
      tipo: TipoConfirmacion.diagnostico,
      ref: 'diag',
      accion: etiqueta,
      ok: res.ok,
    ));
    return res;
  }

  Future<ResultadoConfirmacion> _post({
    required String path,
    required Map<String, dynamic> body,
    required TipoConfirmacion tipo,
    required String ref,
    required String accion,
    required Duration timeout,
  }) async {
    if (MatixConfig.apiUrl.isEmpty) {
      await _registrar(EntradaConfirmacion(
        cuando: DateTime.now(), tipo: tipo, ref: ref, accion: accion,
        ok: false, error: 'API URL vacía',
      ));
      return const ResultadoConfirmacion(ok: false, mensaje: 'API URL vacía');
    }
    final uri = Uri.parse('${MatixConfig.apiUrl}$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (MatixConfig.hasApiKey) 'X-Matix-Key': MatixConfig.apiKey,
    };
    final ahora = DateTime.now();
    try {
      final resp = await _cliente
          .post(uri, headers: headers, body: json.encode(body))
          .timeout(timeout);
      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      await _registrar(EntradaConfirmacion(
        cuando: ahora, tipo: tipo, ref: ref, accion: accion,
        ok: ok, statusCode: resp.statusCode,
        error: ok ? null : _resumenError(resp.body),
      ));
      return ResultadoConfirmacion(
        ok: ok,
        statusCode: resp.statusCode,
        mensaje: ok ? null : 'HTTP ${resp.statusCode}',
      );
    } catch (e) {
      debugPrint('Confirmacion: $tipo $accion fallo ($e).');
      await _registrar(EntradaConfirmacion(
        cuando: ahora, tipo: tipo, ref: ref, accion: accion,
        ok: false, error: '${e.runtimeType}',
      ));
      return ResultadoConfirmacion(ok: false, mensaje: '${e.runtimeType}');
    }
  }

  String _resumenError(String body) {
    if (body.length > 160) return body.substring(0, 160);
    return body;
  }

  /// Persistencia LOCAL del log de intentos (los últimos [_topeLog]).
  Future<void> _registrar(EntradaConfirmacion e) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getStringList(_kLogPrefs) ?? const [];
      final nuevas = <String>[json.encode(e.toJson()), ...crudo];
      if (nuevas.length > _topeLog) {
        nuevas.removeRange(_topeLog, nuevas.length);
      }
      await prefs.setStringList(_kLogPrefs, nuevas);
    } catch (_) {
      // Logging es best-effort: jamás romper el flujo del usuario.
    }
  }

  Future<List<EntradaConfirmacion>> leerLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getStringList(_kLogPrefs) ?? const [];
      return crudo
          .map((s) {
            try {
              return EntradaConfirmacion.fromJson(
                  json.decode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<EntradaConfirmacion>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> limpiarLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLogPrefs);
    } catch (_) {}
  }

  void cerrar() => _cliente.close();
}

final confirmacionServiceProvider = Provider<ConfirmacionService>(
  (ref) => ConfirmacionService(),
);

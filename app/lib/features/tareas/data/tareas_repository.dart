// Mantenemos `if (x != null) 'k': x` por claridad — la sintaxis
// null-aware `?'k': x` (Dart 3.7+) hace lo mismo pero menos legible
// en este patrón de "construcción de payload sin nulls".
// ignore_for_file: use_null_aware_elements

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../api/matix_client.dart';
import '../../../core/notif_id.dart';
import '../../../core/notificaciones_service.dart';
import '../../nudges/domain/nudges.dart' show kMaxNudges;
import '../domain/tarea.dart';

/// Wrapper sobre `MatixClient` para las rutas `/api/v1/tareas` y
/// `/api/v1/subtareas`. Convierte JSON ↔ entities.
///
/// Además, mantiene sincronizadas las notificaciones locales con el
/// campo `recordar_en` de cada tarea: programa al crear, cancela al
/// borrar/completar, reprograma al editar. El `id` de notificación
/// se deriva del uuid de la tarea (ver `notif_id.dart`), así es
/// estable entre runs sin necesidad de persistir nada.
class TareasRepository {
  TareasRepository(this._client, this._notif);
  final MatixClient _client;
  final NotificacionesService _notif;

  // ─── Tareas ───────────────────────────────────────────────────────────

  Future<List<Tarea>> listar() async {
    final raw = await _client.getList('/api/v1/tareas');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Tarea.fromJson)
        .toList(growable: false);
  }

  /// Lista las tareas eliminadas (papelera). El cerebro filtra del
  /// lado servidor con `?papelera=true`, así no traemos toda la
  /// tabla al cliente.
  Future<List<Tarea>> listarPapelera() async {
    final raw = await _client.getList('/api/v1/tareas?papelera=true');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Tarea.fromJson)
        .toList(growable: false);
  }

  Future<Tarea> obtener(String id) async {
    final j = await _client.getOne('/api/v1/tareas/$id');
    return Tarea.fromJson(j);
  }

  Future<Tarea> crear({
    required String titulo,
    String? nota,
    DateTime? venceEn,
    Prioridad prioridad = Prioridad.media,
    String? categoriaId,
    String? cursoId,
    String? proyectoId,
    Repeticion? repeticion,
    DateTime? recordarEn,
  }) async {
    final body = <String, dynamic>{
      'titulo': titulo,
      'prioridad': prioridad.toJson(),
      if (nota != null && nota.isNotEmpty) 'nota': nota,
      if (venceEn != null) 'vence_en': venceEn.toUtc().toIso8601String(),
      if (categoriaId != null) 'categoria_id': categoriaId,
      if (cursoId != null) 'curso_id': cursoId,
      if (proyectoId != null) 'proyecto_id': proyectoId,
      if (repeticion != null) 'repeticion': repeticion.toJson(),
      if (recordarEn != null) 'recordar_en': recordarEn.toUtc().toIso8601String(),
    };
    final j = await _client.post('/api/v1/tareas', body);
    final t = Tarea.fromJson(j);
    await _reprogramarRecordatorio(t);
    await _reprogramarNudges(t);
    return t;
  }

  Future<Tarea> actualizar(String id, Map<String, dynamic> cambios) async {
    final j = await _client.patch('/api/v1/tareas/$id', cambios);
    final t = Tarea.fromJson(j);
    await _reprogramarRecordatorio(t);
    await _reprogramarNudges(t);
    return t;
  }

  Future<Tarea> marcarCompletada(String id, {required bool completada}) async {
    return actualizar(id, {
      'completada': completada,
      'completada_en':
          completada ? DateTime.now().toUtc().toIso8601String() : null,
    });
  }

  Future<void> borrar(String id) async {
    // DELETE en el cerebro es SOFT desde Capa 2 Paso 5: la fila se
    // marca con `eliminado_en` pero no se destruye. La notificación
    // local sí la cancelamos — una tarea en papelera no debería
    // dispararla.
    await _client.delete('/api/v1/tareas/$id');
    await _notifSeguro(() async {
      await _notif.cancelar(notifIdDe(id));
      await _cancelarNudges(id);
    });
  }

  /// Saca una tarea de la papelera. Devuelve la tarea restaurada
  /// para que el caller reprograme su recordatorio si tenía uno.
  Future<Tarea> restaurar(String id) async {
    final j = await _client.post('/api/v1/tareas/$id/restaurar', const {});
    final t = Tarea.fromJson(j);
    await _reprogramarRecordatorio(t);
    await _reprogramarNudges(t);
    return t;
  }

  /// Destruye la tarea permanentemente. Solo se llama al "vaciar
  /// papelera" en la UI — nunca como deshacer un borrado.
  Future<void> borrarPermanente(String id) async {
    await _client.delete('/api/v1/tareas/$id/permanente');
    // notif ya cancelada en `borrar`, pero por si acaso:
    await _notifSeguro(() async {
      await _notif.cancelar(notifIdDe(id));
      await _cancelarNudges(id);
    });
  }

  /// Cancela la notificación previa (si la había) y programa una
  /// nueva si la tarea tiene `recordar_en` futuro y no está
  /// completada. Idempotente: se puede llamar tantas veces como
  /// haga falta sin generar duplicados.
  ///
  /// Si es la primera vez que se programa algo en esta sesión y el
  /// usuario aún no ha dado permiso (Android 13+), se pide
  /// silenciosamente. Si lo niega, la notif simplemente no llega —
  /// la app sigue funcionando.
  Future<void> _reprogramarRecordatorio(Tarea t) async {
    // El recordatorio de la tarea ahora lo manda el CEREBRO por push (FCM,
    // Push Capa 2): las alarmas locales no disparan en los OEM que matan el
    // segundo plano. Acá solo cancelamos cualquier alarma local previa (de
    // versiones viejas de la app) para no dejar basura. Los nudges
    // escalados (Urgencia-2) siguen locales por ahora — su migración a push
    // es Capa 3.
    await _notifSeguro(() => _notif.cancelar(notifIdDe(t.id)));
  }

  /// Corre un efecto de notificaciones sin dejar que su error escale.
  /// El servicio ya traga las `PlatformException`; esto es la red por si
  /// algo más inesperado revienta — el flujo que llamó (crear/editar/
  /// aplicar plan) debe completarse igual.
  Future<void> _notifSeguro(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      debugPrint('Notif (tareas): efecto ignorado por error: $e');
    }
  }

  // ─── Nudges de urgencia (Push Capa 3b) ────────────────────────────────

  /// Los nudges de urgencia ahora los manda el CEREBRO por push (FCM):
  /// las alarmas locales no disparan en los OEM que matan el segundo
  /// plano (Honor/Magic UI). Acá solo cancelamos cualquier nudge local
  /// previo (de versiones viejas de la app) al crear/editar/restaurar,
  /// para no dejar alarmas huérfanas en el dispositivo. El interruptor
  /// por tarea vive en `tareas.nudges_silenciada` (lo respeta el
  /// scheduler), y el maestro + silencio + disponibilidad en el cerebro.
  Future<void> _reprogramarNudges(Tarea t) async {
    await _notifSeguro(() => _cancelarNudges(t.id));
  }

  Future<void> _cancelarNudges(String tareaId) async {
    for (var i = 0; i < kMaxNudges; i++) {
      await _notif.cancelar(notifIdDeNudge(tareaId, i));
    }
  }

  // ─── Subtareas ───────────────────────────────────────────────────────

  /// Subtareas de una tarea concreta. El filtro se aplica en el
  /// cerebro vía query param — el cliente NO baja toda la tabla.
  Future<List<Subtarea>> listarSubtareasDe(String tareaId) async {
    final raw = await _client.getList('/api/v1/subtareas?tarea_id=$tareaId');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Subtarea.fromJson)
        .toList(growable: false);
  }

  Future<Subtarea> crearSubtarea({
    required String tareaId,
    required String titulo,
    int orden = 0,
  }) async {
    final j = await _client.post('/api/v1/subtareas', {
      'tarea_id': tareaId,
      'titulo': titulo,
      'orden': orden,
    });
    return Subtarea.fromJson(j);
  }

  Future<Subtarea> actualizarSubtarea(
    String id,
    Map<String, dynamic> cambios,
  ) async {
    final j = await _client.patch('/api/v1/subtareas/$id', cambios);
    return Subtarea.fromJson(j);
  }

  Future<void> borrarSubtarea(String id) async {
    await _client.delete('/api/v1/subtareas/$id');
  }
}

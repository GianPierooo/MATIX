// ignore_for_file: use_null_aware_elements

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../api/matix_client.dart';
import '../../../core/notificaciones_service.dart';
import '../domain/evento.dart';
import '../domain/recordatorio_evento.dart';
import '../domain/recurrencia.dart';

/// Wrapper sobre `/api/v1/eventos`. Mantiene sincronizadas las
/// notificaciones locales con `recordar_en` (mismo patrón que
/// `TareasRepository`).
class EventosRepository {
  EventosRepository(this._client, this._notif);
  final MatixClient _client;
  final NotificacionesService _notif;

  Future<List<Evento>> listar() async {
    final raw = await _client.getList('/api/v1/eventos');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Evento.fromJson)
        .toList(growable: false);
  }

  Future<List<Evento>> listarPapelera() async {
    final raw = await _client.getList('/api/v1/eventos?papelera=true');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Evento.fromJson)
        .toList(growable: false);
  }

  Future<Evento> obtener(String id) async {
    final j = await _client.getOne('/api/v1/eventos/$id');
    return Evento.fromJson(j);
  }

  Future<Evento> crear({
    required String titulo,
    String? descripcion,
    required DateTime iniciaEn,
    DateTime? terminaEn,
    bool todoElDia = false,
    String? ubicacion,
    String? cursoId,
    String? proyectoId,
    String? color,
    int? recordatorioOffsetMin,
    ReglaRecurrencia? regla,
  }) async {
    // El offset es la fuente de verdad; `recordar_en` se deriva como
    // espejo absoluto (inicia − offset) para lectores legados.
    final recordarEn = momentoRecordatorio(iniciaEn, recordatorioOffsetMin);
    final body = <String, dynamic>{
      'titulo': titulo,
      'inicia_en': iniciaEn.toUtc().toIso8601String(),
      'todo_el_dia': todoElDia,
      if (descripcion != null && descripcion.isNotEmpty)
        'descripcion': descripcion,
      if (terminaEn != null)
        'termina_en': terminaEn.toUtc().toIso8601String(),
      if (ubicacion != null && ubicacion.isNotEmpty) 'ubicacion': ubicacion,
      if (cursoId != null) 'curso_id': cursoId,
      if (proyectoId != null) 'proyecto_id': proyectoId,
      if (color != null) 'color': color,
      if (recordatorioOffsetMin != null)
        'recordatorio_offset_min': recordatorioOffsetMin,
      if (recordarEn != null)
        'recordar_en': recordarEn.toUtc().toIso8601String(),
      if (regla != null) ...regla.toJson(),
    };
    final j = await _client.post('/api/v1/eventos', body);
    final e = Evento.fromJson(j);
    await _sincronizarRecordatorios(e);
    return e;
  }

  Future<Evento> actualizar(String id, Map<String, dynamic> cambios) async {
    final j = await _client.patch('/api/v1/eventos/$id', cambios);
    final e = Evento.fromJson(j);
    await _sincronizarRecordatorios(e);
    return e;
  }

  Future<void> borrar(String id) async {
    // Soft delete (Capa 2 Paso 5).
    await _client.delete('/api/v1/eventos/$id');
    await _cancelarRecordatorios(id);
  }

  Future<Evento> restaurar(String id) async {
    final j = await _client.post('/api/v1/eventos/$id/restaurar', const {});
    final e = Evento.fromJson(j);
    await _sincronizarRecordatorios(e);
    return e;
  }

  Future<void> borrarPermanente(String id) async {
    await _client.delete('/api/v1/eventos/$id/permanente');
    await _cancelarRecordatorios(id);
  }

  /// Reagenda la ventana móvil de recordatorios de toda la app: una pasada
  /// por cada evento. Best-effort — un fallo en uno no corta a los demás ni
  /// propaga. Se llama al arrancar para refrescar la ventana de las series
  /// recurrentes (no se pueden agendar notificaciones infinitas).
  Future<void> refrescarVentanaRecordatorios() async {
    try {
      final todos = await listar();
      for (final e in todos) {
        try {
          await _sincronizarRecordatorios(e);
        } catch (_) {
          // Un evento problemático no debe impedir refrescar el resto.
        }
      }
    } catch (_) {
      // Sin red / sin sesión: la próxima apertura reintenta.
    }
  }

  /// Cancela y reagenda los recordatorios de un evento. Primero limpia la
  /// ventana completa (cubre reglas previas que cambiaron — p. ej. una serie
  /// acortada o vuelta única) y luego agenda los de la ventana actual.
  ///
  /// Todo va dentro de `_notifSeguro`: las notificaciones son un efecto
  /// secundario; si el plugin falla (caché ilegible, OEM raro) NO debe
  /// tumbar el CRUD de eventos — el evento ya quedó guardado en el cerebro.
  Future<void> _sincronizarRecordatorios(Evento e) async {
    await _notifSeguro(() async {
      await _cancelarRecordatorios(e.id);
      final recordatorios = recordatoriosVentana(
        eventoId: e.id,
        regla: e.regla,
        inicioSerie: e.iniciaEn.toLocal(),
        offsetMin: e.recordatorioOffsetMin,
        ahora: DateTime.now(),
      );
      if (recordatorios.isEmpty) return;
      await _notif.pedirPermisos();
      final cuerpo = e.ubicacion?.isNotEmpty == true
          ? e.ubicacion!
          : 'Tu evento está por empezar.';
      for (final r in recordatorios) {
        await _notif.programar(
          id: r.notifId,
          titulo: e.titulo,
          cuerpo: cuerpo,
          cuando: r.cuando,
          exacto: true,
          payload: 'evento:${e.id}',
        );
      }
    });
  }

  /// Cancela todos los ids que el evento pudo agendar en la ventana (id base
  /// del evento + un id por día). Determinista por `(id, día)`, así que
  /// limpia ocurrencias de cualquier regla previa sin guardar estado.
  Future<void> _cancelarRecordatorios(String id) async {
    await _notifSeguro(() async {
      final ids = idsCancelacionVentana(eventoId: id, ahora: DateTime.now());
      for (final nid in ids) {
        await _notif.cancelar(nid);
      }
    });
  }

  /// Corre un efecto de notificaciones sin dejar que su error escale. El
  /// servicio ya traga los fallos del plugin; esto es la red por si algo
  /// inesperado revienta — crear/editar/borrar un evento debe completarse
  /// igual. (Anidar `_notifSeguro` es inofensivo: idempotente.)
  Future<void> _notifSeguro(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      debugPrint('Notif (eventos): efecto ignorado por error: $e');
    }
  }
}

// Mantenemos `if (x != null) 'k': x` por claridad — la sintaxis
// null-aware `?'k': x` (Dart 3.7+) hace lo mismo pero menos legible
// en este patrón de "construcción de payload sin nulls".
// ignore_for_file: use_null_aware_elements

import '../../../api/matix_client.dart';
import '../../../core/notif_id.dart';
import '../../../core/notificaciones_service.dart';
import '../../nudges/data/nudges_prefs.dart';
import '../../nudges/domain/nudges.dart';
import '../domain/selectores.dart';
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
  TareasRepository(this._client, this._notif, this._nudgesPrefs);
  final MatixClient _client;
  final NotificacionesService _notif;
  final NudgesPrefs _nudgesPrefs;

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
    await _notif.cancelar(notifIdDe(id));
    await _cancelarNudges(id);
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
    await _notif.cancelar(notifIdDe(id));
    await _cancelarNudges(id);
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
    final nid = notifIdDe(t.id);
    await _notif.cancelar(nid);
    if (t.completada) return;
    final r = t.recordarEn;
    if (r == null) return;
    await _notif.pedirPermisos();
    await _notif.programar(
      id: nid,
      titulo: t.titulo,
      cuerpo: _cuerpoRecordatorio(t),
      cuando: r.toLocal(),
      payload: 'tarea:${t.id}',
    );
  }

  // ─── Nudges escalados (Urgencia-2) ────────────────────────────────────

  /// Cancela TODOS los posibles nudges de una tarea (rango fijo de ids,
  /// sin guardar estado) y, si corresponde, agenda el calendario nuevo.
  /// No agenda nada para tareas completadas, sin plazo, o con los nudges
  /// apagados — y `programar` ignora puntos en el pasado.
  Future<void> _reprogramarNudges(Tarea t) async {
    await _cancelarNudges(t.id);
    if (t.completada || t.venceEn == null) return;
    final cfg = await _nudgesPrefs.leerConfig();
    final silenciada = await _nudgesPrefs.estaSilenciada(t.id);
    final plan = planNudges(
      t,
      DateTime.now(),
      intensidad: cfg.intensidad,
      silencio: cfg.silencio,
      silenciada: silenciada,
    );
    if (plan.isEmpty) return;
    await _notif.pedirPermisos();
    for (final n in plan) {
      await _notif.programar(
        id: n.id,
        titulo: t.titulo,
        cuerpo: n.cuerpo,
        cuando: n.cuando,
        payload: 'tarea:${t.id}',
      );
    }
  }

  Future<void> _cancelarNudges(String tareaId) async {
    for (var i = 0; i < kMaxNudges; i++) {
      await _notif.cancelar(notifIdDeNudge(tareaId, i));
    }
  }

  /// Reprograma los nudges de TODAS las tareas. Lo llama el ajuste
  /// global de nudges (intensidad / horas de silencio) para que el
  /// cambio aplique de inmediato sin tener que editar tarea por tarea.
  Future<void> reprogramarNudgesDeTodas() async {
    final tareas = await listar();
    for (final t in tareas) {
      await _reprogramarNudges(t);
    }
  }

  String _cuerpoRecordatorio(Tarea t) {
    final cuando = _cuandoLegible(t.venceEn);
    final ctx = _contextoLegible(t);
    if (ctx == null) return cuando;
    return '$ctx · $cuando';
  }

  String _cuandoLegible(DateTime? venceEn) {
    if (venceEn == null) return 'Recordatorio';
    final v = venceEn.toLocal();
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(v.year, v.month, v.day);
    final diff = dia.difference(hoy).inDays;
    final hora =
        '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'Vence hoy a las $hora';
    if (diff == 1) return 'Vence mañana a las $hora';
    if (diff > 1) return 'Vence en $diff días';
    return 'Estaba para hace ${-diff} días';
  }

  /// Si la tarea cuelga de un proyecto / curso / categoría, devuelve
  /// el nombre para meterlo en el cuerpo de la notif. Se calcula
  /// barato: consulta los selectores cacheados. Si no hay nada
  /// asociado, devuelve `null`.
  String? _contextoLegible(Tarea t) {
    // Usamos los selectores que ya están cargados por el
    // SelectoresRepository — si no, hacemos best-effort y dejamos
    // el cuerpo sin prefijo.
    final ctx = _ultimoSelectoresCache;
    if (ctx == null) return null;
    if (t.proyectoId != null) {
      final p = ctx.proyectos.firstWhere(
        (x) => x.id == t.proyectoId,
        orElse: () => const ProyectoRef(
            id: '', nombre: '', estado: 'activo'),
      );
      if (p.nombre.isNotEmpty) return p.nombre;
    }
    if (t.cursoId != null) {
      final c = ctx.cursos.firstWhere(
        (x) => x.id == t.cursoId,
        orElse: () => const CursoRef(id: '', nombre: ''),
      );
      if (c.nombre.isNotEmpty) return c.nombre;
    }
    if (t.categoriaId != null) {
      final c = ctx.categorias.firstWhere(
        (x) => x.id == t.categoriaId,
        orElse: () => const CategoriaRef(id: '', nombre: ''),
      );
      if (c.nombre.isNotEmpty) return c.nombre;
    }
    return null;
  }

  /// Snapshot de selectores que el provider rellena. Nullable; si no
  /// está cargado el contexto, la notif simplemente sale sin prefijo.
  static _SelectoresSnapshot? _ultimoSelectoresCache;

  /// Llamado por `tareas_providers.dart` para inyectar el snapshot
  /// actualizado de selectores. Es estático para evitar circular
  /// dependency entre repo y providers.
  static void actualizarSelectoresCache({
    required List<CategoriaRef> categorias,
    required List<CursoRef> cursos,
    required List<ProyectoRef> proyectos,
  }) {
    _ultimoSelectoresCache = _SelectoresSnapshot(
      categorias: categorias,
      cursos: cursos,
      proyectos: proyectos,
    );
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

class _SelectoresSnapshot {
  _SelectoresSnapshot({
    required this.categorias,
    required this.cursos,
    required this.proyectos,
  });
  final List<CategoriaRef> categorias;
  final List<CursoRef> cursos;
  final List<ProyectoRef> proyectos;
}
